import 'dart:async';

import 'package:anime_tv/core/config/app_config.dart';
import 'package:anime_tv/features/watch_together/data/watch_party_client.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final watchPartyClientProvider = Provider<WatchPartyClient>(
  (_) => WatchPartyClient(baseUrl: AppConfig.watchTogetherBaseUrl),
);

final watchPartyControllerProvider =
    StateNotifierProvider<WatchPartyController, WatchPartyState>((ref) {
      return WatchPartyController(ref.watch(watchPartyClientProvider));
    });

enum WatchPartyConnection { disconnected, connecting, connected, reconnecting }

class WatchPartyState {
  const WatchPartyState({
    this.connection = WatchPartyConnection.disconnected,
    this.session,
    this.snapshot,
    this.attachedMedia,
    this.timelineMismatch = false,
    this.message,
  });

  final WatchPartyConnection connection;
  final WatchPartySession? session;
  final WatchPartySnapshot? snapshot;
  final WatchPartyMedia? attachedMedia;
  final bool timelineMismatch;
  final String? message;

  bool get isBusy => connection == WatchPartyConnection.connecting;
  bool get isActive => session != null;
  bool get isHost => session?.role == WatchPartyRole.host;

  /// Guests hand playback authority to the host only while a concrete player
  /// is attached. Browsing the lobby before choosing matching media remains
  /// fully interactive.
  bool get guestPlaybackControlsLocked =>
      session?.role == WatchPartyRole.guest && attachedMedia != null;

  WatchPartyState copyWith({
    WatchPartyConnection? connection,
    Object? session = _unset,
    Object? snapshot = _unset,
    Object? attachedMedia = _unset,
    bool? timelineMismatch,
    Object? message = _unset,
  }) => WatchPartyState(
    connection: connection ?? this.connection,
    session: identical(session, _unset)
        ? this.session
        : session as WatchPartySession?,
    snapshot: identical(snapshot, _unset)
        ? this.snapshot
        : snapshot as WatchPartySnapshot?,
    attachedMedia: identical(attachedMedia, _unset)
        ? this.attachedMedia
        : attachedMedia as WatchPartyMedia?,
    timelineMismatch: timelineMismatch ?? this.timelineMismatch,
    message: identical(message, _unset) ? this.message : message as String?,
  );
}

const _unset = Object();

class WatchPartyController extends StateNotifier<WatchPartyState> {
  WatchPartyController(this._client) : super(const WatchPartyState());

  final WatchPartyClient _client;
  Timer? _pollTimer;
  StreamSubscription<WatchPartyPlaybackSample>? _playbackSubscription;
  WatchPartyPlaybackPort? _playbackPort;
  WatchPartyPlaybackPort? _pendingPlaybackPort;
  WatchPartyPlaybackSample? _lastSample;
  DateTime? _lastPublishedAt;
  int _generation = 0;
  bool _publishing = false;
  bool _publishAgain = false;
  bool _guestReady = false;
  WatchPartySession? _guestReadySession;
  Future<void> _guestReadyTail = Future<void>.value();
  bool _guestReconciliationInFlight = false;
  bool _guestReconcileAgain = false;
  WatchPartySnapshot? _pendingGuestSnapshot;
  int _lastGuestCommandRevision = -1;
  DateTime? _lastGuestCommandAt;
  int _playbackAttachmentGeneration = 0;
  bool _disposed = false;

  Future<bool> create() async {
    if (state.isBusy) return false;
    await _leaveCurrent(send: true);
    final generation = ++_generation;
    state = const WatchPartyState(connection: WatchPartyConnection.connecting);
    try {
      final created = await _client.create();
      if (generation != _generation) return false;
      final snapshot = await _client.snapshot(created.session);
      if (generation != _generation) return false;
      state = state.copyWith(
        connection: WatchPartyConnection.connected,
        session: created.session,
        snapshot: snapshot,
        message: 'Room created. Share the code, then start an episode.',
      );
      _schedulePoll(generation, immediate: false);
      if (_lastSample != null) unawaited(_publishHostSample(force: true));
      return true;
    } on WatchPartyClientException catch (error) {
      if (generation == _generation) {
        state = WatchPartyState(message: watchPartyFriendlyError(error));
      }
      return false;
    }
  }

  Future<bool> join(String code) async {
    if (state.isBusy) return false;
    await _leaveCurrent(send: true);
    final generation = ++_generation;
    state = const WatchPartyState(connection: WatchPartyConnection.connecting);
    try {
      final joined = await _client.join(code);
      if (generation != _generation) return false;
      state = state.copyWith(
        connection: WatchPartyConnection.connected,
        session: joined.session,
        snapshot: joined.snapshot,
        message: joined.snapshot.media == null
            ? 'Joined. Waiting for the host to choose an episode.'
            : 'Joined. Open the host episode when you are ready.',
      );
      _schedulePoll(generation, immediate: false);
      if (_playbackPort case final port?) {
        final sample = _lastSample;
        unawaited(
          _setGuestReady(
            sample?.ready == true,
            sessionOverride: joined.session,
            attachmentGeneration: _playbackAttachmentGeneration,
            attachmentPort: port,
          ),
        );
      }
      return true;
    } on WatchPartyClientException catch (error) {
      if (generation == _generation) {
        state = WatchPartyState(message: watchPartyFriendlyError(error));
      }
      return false;
    }
  }

  Future<void> leave() async {
    ++_generation;
    await _leaveCurrent(send: true);
    state = const WatchPartyState(message: 'You left the Watch Together room.');
  }

  Future<void> attachPlayback({
    required WatchPartyPlaybackPort port,
    required WatchPartyMedia media,
  }) async {
    if (_disposed) return;
    final attachmentGeneration = ++_playbackAttachmentGeneration;
    _pendingPlaybackPort = port;
    final previousSubscription = _playbackSubscription;
    _playbackSubscription = null;
    _playbackPort = null;
    await previousSubscription?.cancel();
    if (_disposed || attachmentGeneration != _playbackAttachmentGeneration) {
      if (identical(_pendingPlaybackPort, port)) {
        _pendingPlaybackPort = null;
      }
      return;
    }
    _pendingPlaybackPort = null;
    _playbackPort = port;
    _lastSample = null;
    _resetGuestReconciliation();
    state = state.copyWith(attachedMedia: media, timelineMismatch: false);
    _playbackSubscription = port.snapshots.listen((sample) {
      _lastSample = sample;
      if (state.isHost) {
        unawaited(_publishHostSample(force: false));
      } else if (state.session case final session?
          when session.role == WatchPartyRole.guest) {
        unawaited(
          _handleGuestPlaybackSample(
            session: session,
            port: port,
            attachmentGeneration: attachmentGeneration,
            sample: sample,
          ),
        );
      }
    });
    if (state.session case final session?
        when session.role == WatchPartyRole.guest) {
      await _setGuestReady(
        false,
        sessionOverride: session,
        attachmentGeneration: attachmentGeneration,
        attachmentPort: port,
        force: true,
      );
    }
  }

  Future<void> _handleGuestPlaybackSample({
    required WatchPartySession session,
    required WatchPartyPlaybackPort port,
    required int attachmentGeneration,
    required WatchPartyPlaybackSample sample,
  }) async {
    final observedSnapshot = state.snapshot;
    final readyForObservedMedia =
        sample.ready &&
        _guestSampleMatchesRemoteMedia(sample.media, observedSnapshot?.media);
    await _setGuestReady(
      readyForObservedMedia,
      sessionOverride: session,
      attachmentGeneration: attachmentGeneration,
      attachmentPort: port,
    );
    if (_disposed ||
        attachmentGeneration != _playbackAttachmentGeneration ||
        !identical(_playbackPort, port) ||
        state.session != session) {
      return;
    }
    final snapshot = state.snapshot;
    if (snapshot == null) return;
    if (readyForObservedMedia &&
        !_guestSampleMatchesRemoteMedia(sample.media, snapshot.media)) {
      await _setGuestReady(
        false,
        sessionOverride: session,
        attachmentGeneration: attachmentGeneration,
        attachmentPort: port,
        force: true,
      );
      return;
    }
    await _applyGuestSnapshot(snapshot);
  }

  Future<void> detachPlayback(WatchPartyPlaybackPort port) async {
    if (_disposed) return;
    final activeAttachment = identical(_playbackPort, port);
    final pendingAttachment = identical(_pendingPlaybackPort, port);
    if (!activeAttachment && !pendingAttachment) return;
    final attachmentGeneration = ++_playbackAttachmentGeneration;
    if (pendingAttachment) _pendingPlaybackPort = null;
    final subscription = activeAttachment ? _playbackSubscription : null;
    _playbackSubscription = null;
    _playbackPort = null;
    _lastSample = null;
    _resetGuestReconciliation();
    final session = state.session;
    final readyFuture = session?.role == WatchPartyRole.guest
        ? _setGuestReady(
            false,
            sessionOverride: session,
            force: true,
            allowAfterDispose: true,
          )
        : Future<void>.value();
    final cancellation = subscription?.cancel() ?? Future<void>.value();
    // Player routes detach from State.dispose. Notify listeners in a microtask
    // so Riverpod is never mutated while Flutter unmounts the tree, without
    // leaving a zero-duration Timer behind in widget tests.
    await Future<void>.value();
    if (!_disposed &&
        attachmentGeneration == _playbackAttachmentGeneration &&
        _playbackPort == null &&
        _pendingPlaybackPort == null) {
      state = state.copyWith(attachedMedia: null, timelineMismatch: false);
    }
    await cancellation;
    await readyFuture;
  }

  Future<void> setGuestReady(bool ready) => _setGuestReady(ready);

  void clearMessage() {
    if (state.message != null) state = state.copyWith(message: null);
  }

  void _schedulePoll(int generation, {required bool immediate}) {
    _pollTimer?.cancel();
    _pollTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 1200),
      () {
        unawaited(_poll(generation));
      },
    );
  }

  Future<void> _poll(int generation) async {
    final session = state.session;
    if (session == null || generation != _generation) return;
    try {
      final snapshot = await _client.snapshot(session);
      if (generation != _generation) return;
      state = state.copyWith(
        connection: WatchPartyConnection.connected,
        snapshot: snapshot,
        message: state.connection == WatchPartyConnection.reconnecting
            ? 'Watch Together reconnected.'
            : state.message,
      );
      if (session.role == WatchPartyRole.guest) {
        await _applyGuestSnapshot(snapshot);
      } else if (_lastSample != null &&
          (DateTime.now().toUtc().difference(
                _lastPublishedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
              ) >=
              const Duration(milliseconds: 2200))) {
        await _publishHostSample(force: true);
      }
    } on WatchPartyClientException catch (error) {
      if (generation != _generation) return;
      if (error.code == 'party_not_found' ||
          error.code == 'invalid_party_token') {
        await _leaveCurrent(send: false);
        state = WatchPartyState(message: watchPartyFriendlyError(error));
        return;
      }
      state = state.copyWith(
        connection: WatchPartyConnection.reconnecting,
        message: watchPartyFriendlyError(error),
      );
    } finally {
      if (generation == _generation && state.session != null) {
        _schedulePoll(generation, immediate: false);
      }
    }
  }

  Future<void> _publishHostSample({required bool force}) async {
    final session = state.session;
    final sample = _lastSample;
    if (session == null ||
        session.role != WatchPartyRole.host ||
        sample == null) {
      return;
    }
    final last = _lastPublishedAt;
    final now = DateTime.now().toUtc();
    final currentSnapshot = state.snapshot;
    final immediateChange =
        currentSnapshot == null ||
        currentSnapshot.media != sample.media ||
        currentSnapshot.playing != sample.playing ||
        (currentSnapshot.expectedPositionAt(now) - sample.position).abs() >
            const Duration(seconds: 3);
    if (!force &&
        !immediateChange &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 2200)) {
      return;
    }
    if (_publishing) {
      _publishAgain = true;
      return;
    }
    _publishing = true;
    try {
      final elapsed = sample.playing
          ? now.difference(sample.sampledAt)
          : Duration.zero;
      final position = sample.position + elapsed;
      final snapshot = await _client.updateState(
        session: session,
        baseRevision: state.snapshot?.revision ?? 0,
        media: sample.media,
        playing: sample.playing,
        position: position > sample.duration && sample.duration > Duration.zero
            ? sample.duration
            : position,
      );
      if (state.session == session) {
        _lastPublishedAt = now;
        state = state.copyWith(
          connection: WatchPartyConnection.connected,
          snapshot: snapshot,
          timelineMismatch: false,
        );
      }
    } on WatchPartyClientException catch (error) {
      if (error.code == 'stale_revision') {
        _schedulePoll(_generation, immediate: true);
      } else if (state.session == session) {
        state = state.copyWith(message: watchPartyFriendlyError(error));
      }
    } finally {
      _publishing = false;
      if (_publishAgain) {
        _publishAgain = false;
        unawaited(_publishHostSample(force: true));
      }
    }
  }

  Future<void> _applyGuestSnapshot(WatchPartySnapshot snapshot) async {
    final pending = _pendingGuestSnapshot;
    if (pending == null || snapshot.revision >= pending.revision) {
      _pendingGuestSnapshot = snapshot;
    }
    if (_guestReconciliationInFlight) {
      _guestReconcileAgain = true;
      return;
    }
    _guestReconciliationInFlight = true;
    try {
      do {
        _guestReconcileAgain = false;
        final latest = _pendingGuestSnapshot;
        _pendingGuestSnapshot = null;
        if (latest != null) await _reconcileGuestSnapshot(latest);
      } while (_guestReconcileAgain || _pendingGuestSnapshot != null);
    } finally {
      _guestReconciliationInFlight = false;
    }
  }

  Future<void> _reconcileGuestSnapshot(WatchPartySnapshot snapshot) async {
    final port = _playbackPort;
    final attachmentGeneration = _playbackAttachmentGeneration;
    final sample = _lastSample;
    final remoteMedia = snapshot.media;
    if (port == null || sample == null || remoteMedia == null) return;
    // A website host intentionally has no app catalog/source capability, so
    // it publishes `private`. Let that timeline control only the media the
    // guest explicitly opened and marked ready. The warning below makes the
    // unverifiable identity/coarse-sync tradeoff visible.
    final remotePrivateTimeline = remoteMedia.kind == 'private';
    final sameEpisode =
        remotePrivateTimeline ||
        (sample.media.kind == remoteMedia.kind &&
            sample.media.anilistId == remoteMedia.anilistId &&
            sample.media.episode == remoteMedia.episode);
    if (!sameEpisode) return;
    final remotePrivateTimelineUnverified =
        remotePrivateTimeline &&
        (sample.media.kind != 'private' ||
            sample.media.timelineFingerprint == null ||
            remoteMedia.timelineFingerprint == null);
    final timelineMismatch =
        remotePrivateTimelineUnverified ||
        (sample.media.timelineFingerprint != null &&
            remoteMedia.timelineFingerprint != null &&
            sample.media.timelineFingerprint !=
                remoteMedia.timelineFingerprint);
    if (timelineMismatch != state.timelineMismatch) {
      state = state.copyWith(
        timelineMismatch: timelineMismatch,
        message: timelineMismatch
            ? remotePrivateTimelineUnverified
                  ? 'Private room sync is coarse. Make sure you opened the same video as the host.'
                  : 'This release may use a different cut. Watch Together will keep coarse sync.'
            : state.message,
      );
    }
    if (!sample.ready) return;
    final target = snapshot.expectedPositionAt(DateTime.now().toUtc());
    final commandCooldownActive =
        snapshot.revision == _lastGuestCommandRevision &&
        DateTime.now().toUtc().difference(
              _lastGuestCommandAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ) <
            const Duration(milliseconds: 650);
    if (commandCooldownActive) return;
    var issuedCommand = false;
    try {
      if ((sample.position - target).abs() > const Duration(seconds: 2)) {
        await port.seekTo(target);
        issuedCommand = true;
      }
      if (attachmentGeneration != _playbackAttachmentGeneration ||
          !identical(_playbackPort, port)) {
        return;
      }
      if (snapshot.playing != sample.playing) {
        if (snapshot.playing) {
          await port.play();
        } else {
          await port.pause();
        }
        issuedCommand = true;
      }
    } catch (_) {
      if (attachmentGeneration == _playbackAttachmentGeneration &&
          identical(_playbackPort, port)) {
        _lastGuestCommandRevision = snapshot.revision;
        _lastGuestCommandAt = DateTime.now().toUtc();
        state = state.copyWith(
          message:
              'Watch Together could not resync playback. Retrying shortly.',
        );
      }
      return;
    }
    if (issuedCommand) {
      _lastGuestCommandRevision = snapshot.revision;
      _lastGuestCommandAt = DateTime.now().toUtc();
    }
  }

  void _resetGuestReconciliation() {
    _guestReconcileAgain = false;
    _pendingGuestSnapshot = null;
    _lastGuestCommandRevision = -1;
    _lastGuestCommandAt = null;
  }

  Future<void> _setGuestReady(
    bool ready, {
    WatchPartySession? sessionOverride,
    int? attachmentGeneration,
    WatchPartyPlaybackPort? attachmentPort,
    bool force = false,
    bool allowAfterDispose = false,
  }) {
    if (_disposed && !allowAfterDispose) return Future<void>.value();
    final session = sessionOverride ?? state.session;
    if (session?.role != WatchPartyRole.guest) return Future<void>.value();
    final previous = _guestReadyTail;
    final operation = () async {
      try {
        await previous;
      } catch (_) {
        // A failed readiness request must not block later cleanup.
      }
      final attachmentGuarded = attachmentGeneration != null;
      if (ready &&
          (_disposed ||
              (attachmentGuarded &&
                  (attachmentGeneration != _playbackAttachmentGeneration ||
                      !identical(_playbackPort, attachmentPort))) ||
              (!_disposed && state.session != session))) {
        return;
      }
      if (_disposed && !allowAfterDispose) return;
      if (!force &&
          identical(_guestReadySession, session) &&
          _guestReady == ready) {
        return;
      }
      try {
        final snapshot = await _client.setReady(
          session: session!,
          ready: ready,
        );
        _guestReadySession = session;
        _guestReady = ready;
        if (_disposed) return;
        final attachmentStillCurrent =
            !attachmentGuarded ||
            (attachmentGeneration == _playbackAttachmentGeneration &&
                identical(_playbackPort, attachmentPort));
        final currentRevision = state.snapshot?.revision ?? -1;
        if (state.session == session &&
            attachmentStillCurrent &&
            snapshot.revision >= currentRevision) {
          state = state.copyWith(snapshot: snapshot);
        }
      } on WatchPartyClientException catch (error) {
        if (!_disposed && state.session == session) {
          state = state.copyWith(message: watchPartyFriendlyError(error));
        }
      }
    }();
    _guestReadyTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _leaveCurrent({required bool send}) async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final session = state.session;
    _guestReady = false;
    _guestReadySession = null;
    _lastPublishedAt = null;
    _resetGuestReconciliation();
    if (send && session != null) {
      try {
        await _client.leave(session);
      } catch (_) {
        // Local exit must not depend on room-service reachability.
      }
    }
  }

  @override
  void dispose() {
    final session = state.session;
    final shouldClearGuestReady =
        session?.role == WatchPartyRole.guest &&
        (_playbackPort != null ||
            _pendingPlaybackPort != null ||
            (identical(_guestReadySession, session) && _guestReady));
    _disposed = true;
    ++_generation;
    ++_playbackAttachmentGeneration;
    _pollTimer?.cancel();
    final subscription = _playbackSubscription;
    _playbackSubscription = null;
    _playbackPort = null;
    _pendingPlaybackPort = null;
    unawaited(subscription?.cancel());
    if (shouldClearGuestReady) {
      unawaited(
        _setGuestReady(
          false,
          sessionOverride: session,
          force: true,
          allowAfterDispose: true,
        ),
      );
    }
    super.dispose();
  }
}

String watchPartyFriendlyError(WatchPartyClientException error) =>
    switch (error.code) {
      'invalid_room_code' =>
        'Enter the eight-digit room code using numbers 2-9 only.',
      'party_not_found' => 'That room ended or expired.',
      'party_full' => 'That room is full.',
      'party_capacity_reached' =>
        'Watch Together is temporarily at capacity. Try again shortly.',
      'invalid_party_token' || 'party_token_required' =>
        'This room session expired. Join again with the room code.',
      'rate_limited' => 'Too many room requests. Wait a minute and try again.',
      'timeout' || 'network_unavailable' =>
        'Watch Together cannot reach the room service right now.',
      _ => 'Watch Together could not complete that request.',
    };

bool _guestSampleMatchesRemoteMedia(
  WatchPartyMedia local,
  WatchPartyMedia? remote,
) {
  if (remote == null) return false;
  // A website host publishes an opaque private file identity that the app
  // cannot resolve. The guest's explicit local choice is therefore the only
  // readiness assertion available for that legacy/coarse-sync mode.
  if (remote.kind == 'private') return true;
  return local.kind == remote.kind &&
      local.anilistId == remote.anilistId &&
      local.episode == remote.episode;
}
