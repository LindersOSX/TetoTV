import 'dart:async';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_controller.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

@immutable
class WatchPartyPlaybackAffinity {
  const WatchPartyPlaybackAffinity({
    this.preferredProvider,
    this.preferredAuthor,
    this.preferredSourceId,
    this.preferredWebProviderId,
    this.preferredQualityHeight,
    this.preferredAudio,
  });

  final String? preferredProvider;
  final String? preferredAuthor;
  final String? preferredSourceId;
  final String? preferredWebProviderId;
  final int? preferredQualityHeight;
  final PlaybackAudioPreference? preferredAudio;
}

final watchPartyPlaybackAffinityProvider =
    StateNotifierProvider<
      WatchPartyPlaybackAffinityController,
      WatchPartyPlaybackAffinity?
    >((_) => WatchPartyPlaybackAffinityController());

/// Registers affinity for only the currently mounted player router.
///
/// The opaque owner prevents a late disposal from an old player route from
/// clearing the hints already registered by its replacement.
class WatchPartyPlaybackAffinityController
    extends StateNotifier<WatchPartyPlaybackAffinity?> {
  WatchPartyPlaybackAffinityController() : super(null);

  Object? _owner;

  void bind(Object owner, WatchPartyPlaybackAffinity affinity) {
    _owner = owner;
    state = affinity;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    state = null;
  }
}

@immutable
class WatchPartyNativePlayerSession {
  const WatchPartyNativePlayerSession({
    required this.checkpointKey,
    required this.playbackSessionGeneration,
  });

  final String checkpointKey;
  final int playbackSessionGeneration;
}

final watchPartyNativePlayerSessionProvider =
    StateNotifierProvider<
      WatchPartyNativePlayerSessionController,
      WatchPartyNativePlayerSession?
    >((_) => WatchPartyNativePlayerSessionController());

/// Exposes only the generation guard required to dismiss the separate native
/// Media3 Activity before a guest follows a newer host episode.
class WatchPartyNativePlayerSessionController
    extends StateNotifier<WatchPartyNativePlayerSession?> {
  WatchPartyNativePlayerSessionController() : super(null);

  Object? _owner;

  void bind(Object owner, WatchPartyNativePlayerSession session) {
    _owner = owner;
    state = session;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    state = null;
  }
}

@immutable
class WatchPartyMediaFollowRequest {
  const WatchPartyMediaFollowRequest({
    required this.location,
    required this.roomCode,
    required this.anilistId,
    required this.episode,
    required this.revision,
    required this.sessionGeneration,
    this.nativePlayerSession,
  });

  final String location;
  final String roomCode;
  final int anilistId;
  final int episode;
  final int revision;
  final int sessionGeneration;
  final WatchPartyNativePlayerSession? nativePlayerSession;

  String get eventKey =>
      '$roomCode:$sessionGeneration:$anilistId:$episode:$revision';
  String get mediaKey => '$roomCode:$sessionGeneration:$anilistId:$episode';
}

/// Keeps only the newest host-media request until the next navigation frame.
/// This prevents a rapid E2 -> E3 change from starting a stale E2 route.
class WatchPartyMediaFollowQueue {
  WatchPartyMediaFollowRequest? _latest;

  void add(WatchPartyMediaFollowRequest request) {
    final current = _latest;
    if (current == null ||
        request.sessionGeneration > current.sessionGeneration ||
        request.sessionGeneration == current.sessionGeneration &&
            request.revision >= current.revision) {
      _latest = request;
    }
  }

  WatchPartyMediaFollowRequest? takeLatest() {
    final value = _latest;
    _latest = null;
    return value;
  }

  bool get hasPending => _latest != null;
}

/// Converts authenticated room snapshots into catalog-only navigation.
///
/// Room tokens, host stream URLs, headers, magnets, and timeline fingerprints
/// are intentionally absent from both the request and its route.
class WatchPartyGuestMediaFollowPlanner {
  WatchPartySession? _session;
  int _sessionGeneration = 0;
  int _highestRevision = -1;
  String? _activeTargetKey;

  WatchPartyMediaFollowRequest? evaluate(
    WatchPartyState party, {
    WatchPartyPlaybackAffinity? affinity,
    WatchPartyNativePlayerSession? nativePlayerSession,
  }) {
    final session = party.session;
    if (!identical(session, _session)) {
      _session = session;
      _sessionGeneration++;
      _highestRevision = -1;
      _activeTargetKey = null;
    }
    if (session == null || session.role != WatchPartyRole.guest) return null;
    final snapshot = party.snapshot;
    if (snapshot == null || snapshot.roomCode != session.roomCode) return null;
    if (snapshot.revision < _highestRevision) return null;
    _highestRevision = snapshot.revision;

    final target = _safeCatalogTarget(snapshot.media);
    if (target == null) return null;
    // Never navigate away from a private/local playback attachment. Private
    // rooms also fail [_safeCatalogTarget], so neither side can route local
    // media based on unverifiable metadata.
    if (party.attachedMedia?.kind == 'private') return null;

    final targetKey =
        '${session.roomCode}:$_sessionGeneration:'
        '${target.anilistId}:${target.episode}';
    final attached = party.attachedMedia;
    if (attached?.kind == 'anilist' &&
        attached?.anilistId == target.anilistId &&
        attached?.episode == target.episode) {
      _activeTargetKey = targetKey;
      return null;
    }
    if (_activeTargetKey == targetKey) return null;
    _activeTargetKey = targetKey;
    return WatchPartyMediaFollowRequest(
      location: watchPartyCatalogFollowLocation(
        target.media,
        affinity: affinity,
      ),
      roomCode: session.roomCode,
      anilistId: target.anilistId,
      episode: target.episode,
      revision: snapshot.revision,
      sessionGeneration: _sessionGeneration,
      nativePlayerSession: nativePlayerSession,
    );
  }
}

typedef _SafeCatalogTarget = ({
  WatchPartyMedia media,
  int anilistId,
  int episode,
});

_SafeCatalogTarget? _safeCatalogTarget(WatchPartyMedia? media) {
  if (media == null || media.kind != 'anilist') return null;
  final anilistId = media.anilistId;
  final episode = media.episode;
  if (anilistId == null ||
      anilistId <= 0 ||
      anilistId > 100000000 ||
      episode == null ||
      episode <= 0 ||
      episode > 100000) {
    return null;
  }
  return (media: media, anilistId: anilistId, episode: episode);
}

String watchPartyCatalogFollowLocation(
  WatchPartyMedia media, {
  WatchPartyPlaybackAffinity? affinity,
}) {
  final target = _safeCatalogTarget(media);
  if (target == null) {
    throw ArgumentError.value(media, 'media', 'Expected a catalog episode');
  }
  final title = _boundedRouteText(media.title, maxLength: 240) ?? 'Anime';
  final titleEnglish = _boundedRouteText(media.titleEnglish, maxLength: 240);
  final titleRomaji = _boundedRouteText(media.titleRomaji, maxLength: 240);
  final year = media.year != null && media.year! >= 1900 && media.year! <= 2200
      ? media.year
      : null;
  final cover = _safePublicCover(media.coverUrl);
  final quality = affinity?.preferredQualityHeight;
  final safeQuality = quality != null && quality >= 144 && quality <= 4320
      ? quality
      : null;
  final provider = _boundedRouteText(
    affinity?.preferredProvider,
    maxLength: 160,
  );
  final author = _boundedRouteText(affinity?.preferredAuthor, maxLength: 96);
  final sourceId = _boundedRouteText(
    affinity?.preferredSourceId,
    maxLength: 160,
  );
  final webProviderId = _boundedRouteText(
    affinity?.preferredWebProviderId,
    maxLength: 160,
  );
  final yearText = year?.toString();
  final qualityText = safeQuality?.toString();
  final preferredAudio = affinity?.preferredAudio?.name;
  final query = <String, String>{
    'anilistId': '${target.anilistId}',
    'episode': '${target.episode}',
    'title': title,
    'titleEnglish': ?titleEnglish,
    'titleRomaji': ?titleRomaji,
    'year': ?yearText,
    'cover': ?cover,
    'autoplay': '1',
    'watchPartyFollow': '1',
    'preferredProvider': ?provider,
    'preferredAuthor': ?author,
    'preferredSourceId': ?sourceId,
    'preferredWebProviderId': ?webProviderId,
    'preferredQualityHeight': ?qualityText,
    'preferredAudio': ?preferredAudio,
  };
  return Uri(path: '/resolve', queryParameters: query).toString();
}

String? _boundedRouteText(String? value, {required int maxLength}) {
  final normalized = value
      ?.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized == null ||
      normalized.isEmpty ||
      normalized.length > maxLength) {
    return null;
  }
  return normalized;
}

String? _safePublicCover(String? value) {
  final bounded = _boundedRouteText(value, maxLength: 2048);
  final uri = Uri.tryParse(bounded ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.toString();
}

/// Lives above GoRouter's pages so a replacement from player -> resolver does
/// not drop the listener. Newer host revisions can therefore replace a stale
/// in-flight resolver while the room session remains alive.
class WatchPartyMediaFollowScope extends ConsumerStatefulWidget {
  const WatchPartyMediaFollowScope({
    required this.router,
    required this.child,
    super.key,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<WatchPartyMediaFollowScope> createState() =>
      _WatchPartyMediaFollowScopeState();
}

class _WatchPartyMediaFollowScopeState
    extends ConsumerState<WatchPartyMediaFollowScope> {
  final _planner = WatchPartyGuestMediaFollowPlanner();
  final _queue = WatchPartyMediaFollowQueue();
  ProviderSubscription<WatchPartyState>? _partySubscription;
  ProviderSubscription<WatchPartyPlaybackAffinity?>? _affinitySubscription;
  ProviderSubscription<WatchPartyNativePlayerSession?>?
  _nativePlayerSubscription;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();
    _partySubscription = ref.listenManual(
      watchPartyControllerProvider,
      (_, _) => _evaluate(),
    );
    _affinitySubscription = ref.listenManual(
      watchPartyPlaybackAffinityProvider,
      (_, _) => _evaluate(),
    );
    _nativePlayerSubscription = ref.listenManual(
      watchPartyNativePlayerSessionProvider,
      (_, _) => _evaluate(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  void _evaluate() {
    if (!mounted) return;
    final request = _planner.evaluate(
      ref.read(watchPartyControllerProvider),
      affinity: ref.read(watchPartyPlaybackAffinityProvider),
      nativePlayerSession: ref.read(watchPartyNativePlayerSessionProvider),
    );
    if (request == null) return;
    _queue.add(request);
    if (_navigationScheduled) return;
    _navigationScheduled = true;
    scheduleMicrotask(_drainNavigation);
  }

  Future<void> _drainNavigation() async {
    try {
      if (!mounted) return;
      var latest = _queue.takeLatest();
      if (latest == null) return;
      final current = widget.router.routeInformationProvider.value.uri;
      if (current.path == '/resolve' &&
          current.queryParameters['anilistId'] == '${latest.anilistId}' &&
          current.queryParameters['episode'] == '${latest.episode}') {
        return;
      }
      final nativeSession = latest.nativePlayerSession;
      if (nativeSession != null) {
        await AndroidTvBridge.instance
            .dismissNativePlayerForWatchPartyTransition(
              checkpointKey: nativeSession.checkpointKey,
              playbackSessionGeneration:
                  nativeSession.playbackSessionGeneration,
            );
        if (!mounted) return;
        // If the host moved E2 -> E3 while the Activity was closing, never
        // expose the stale E2 resolver for a frame.
        latest = _queue.takeLatest() ?? latest;
      }
      final refreshed = widget.router.routeInformationProvider.value.uri;
      if (refreshed.path == '/resolve' &&
          refreshed.queryParameters['anilistId'] == '${latest.anilistId}' &&
          refreshed.queryParameters['episode'] == '${latest.episode}') {
        return;
      }
      unawaited(widget.router.pushReplacement<void>(latest.location));
    } catch (_) {
      // A newer snapshot will retry with a fresh route. The room controller
      // remains connected and the current screen stays usable.
    } finally {
      _navigationScheduled = false;
      if (mounted && _queue.hasPending) {
        _navigationScheduled = true;
        scheduleMicrotask(_drainNavigation);
      }
    }
  }

  @override
  void dispose() {
    _partySubscription?.close();
    _affinitySubscription?.close();
    _nativePlayerSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
