import 'dart:async';

import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_controller.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_public_identity_provider.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<void> showWatchPartyPlayerDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xDD000000),
      builder: (_) => const WatchPartyPlayerDialog(),
    );

String watchPartyGuestCountLabel(int count) {
  final safeCount = count < 0 ? 0 : count;
  return '$safeCount ${safeCount == 1 ? 'guest' : 'guests'}';
}

/// Playback-safe Watch Together entry point shared by MPV and VLC.
///
/// Closing this dialog deliberately leaves the room and player attachment
/// intact. Ending a room remains an explicit action on the full Watch Together
/// screen, so dismissing a HUD never surprises every connected viewer.
class WatchPartyPlayerDialog extends ConsumerStatefulWidget {
  const WatchPartyPlayerDialog({super.key});

  @override
  ConsumerState<WatchPartyPlayerDialog> createState() =>
      _WatchPartyPlayerDialogState();
}

class _WatchPartyPlayerDialogState
    extends ConsumerState<WatchPartyPlayerDialog> {
  final _copyFocus = FocusNode(debugLabel: 'player.watch-party.copy');
  final _roomCodeFocus = FocusNode(debugLabel: 'player.watch-party.room-code');
  final _retryFocus = FocusNode(debugLabel: 'player.watch-party.retry');
  final _closeFocus = FocusNode(debugLabel: 'player.watch-party.close');
  final _leaveFocus = FocusNode(debugLabel: 'player.watch-party.leave');
  bool _creating = false;
  bool _leaving = false;
  bool _createAttempted = false;
  bool _showParticipants = false;
  String? _localMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !ref.read(watchPartyControllerProvider).isActive) {
        unawaited(_createRoom());
      }
    });
  }

  @override
  void dispose() {
    _copyFocus.dispose();
    _roomCodeFocus.dispose();
    _retryFocus.dispose();
    _closeFocus.dispose();
    _leaveFocus.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (_creating) return;
    setState(() {
      _creating = true;
      _createAttempted = true;
      _localMessage = null;
    });
    ref
        .read(watchPartyClientProvider)
        .setPublicIdentity(ref.read(watchPartyPublicIdentityProvider));
    await ref.read(watchPartyControllerProvider.notifier).create();
    if (!mounted) return;
    setState(() => _creating = false);
  }

  Future<void> _leaveRoom(WatchPartyRole role) async {
    if (_leaving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xCC000000),
      builder: (_) => _ConfirmLeaveRoomDialog(role: role),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _leaving = true);
    await ref.read(watchPartyControllerProvider.notifier).leave();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) setState(() => _localMessage = 'Room code copied.');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final state = ref.watch(watchPartyControllerProvider);
    final session = state.session;
    final snapshot = state.snapshot;
    final media = MediaQuery.of(context);
    final compact = media.size.width < 720 || media.size.height < 480;
    final hasRoom = session != null;
    final failureMessage = !hasRoom && _createAttempted && !_creating
        ? state.message ?? 'Watch Together could not create a room.'
        : null;

    return Dialog(
      key: const ValueKey('player-watch-party-dialog'),
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(compact ? 14 : 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          key: const ValueKey('player-watch-party-panel'),
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: .98),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.accent.withValues(alpha: .72)),
            boxShadow: [
              BoxShadow(
                color: palette.background.withValues(alpha: .78),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 18 : 24),
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.groups_rounded, color: palette.accentBright),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasRoom
                              ? 'Watch Together room'
                              : 'Start Watch Together',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Playback keeps running. Closing this panel does not end the room.',
                    style: TextStyle(color: palette.mutedText),
                  ),
                  SizedBox(height: compact ? 14 : 20),
                  if (hasRoom)
                    Flexible(
                      child: SingleChildScrollView(
                        child: _ActivePlayerParty(
                          roomCode: session.roomCode,
                          watchUrl: session.watchUrl,
                          participantCount: snapshot?.participantCount ?? 0,
                          readyCount: snapshot?.readyCount ?? 0,
                          participants:
                              snapshot?.participants ??
                              const <WatchPartyParticipant>[],
                          roomCodeFocusNode: _roomCodeFocus,
                          showParticipants: _showParticipants,
                          onRoomCodePressed: () => setState(
                            () => _showParticipants = !_showParticipants,
                          ),
                          compact: compact,
                        ),
                      ),
                    )
                  else if (_creating || state.isBusy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Row(
                        children: [
                          SizedBox.square(
                            dimension: 26,
                            child: CircularProgressIndicator(strokeWidth: 3),
                          ),
                          SizedBox(width: 14),
                          Text('Creating a private room…'),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        failureMessage ?? 'Preparing Watch Together…',
                        key: const ValueKey('player-watch-party-error'),
                        style: TextStyle(color: palette.accentBright),
                      ),
                    ),
                  if (state.message case final message?
                      when hasRoom && message.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(message, style: TextStyle(color: palette.mutedText)),
                  ],
                  if (_localMessage case final message?) ...[
                    const SizedBox(height: 10),
                    Text(
                      message,
                      key: const ValueKey('player-watch-party-message'),
                      style: TextStyle(color: palette.accentBright),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (hasRoom)
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: _DialogAction(
                            key: const ValueKey('player-watch-party-copy'),
                            focusNode: _copyFocus,
                            autofocus: true,
                            icon: Icons.copy_rounded,
                            label: 'Copy code',
                            onPressed: () =>
                                unawaited(_copyCode(session.roomCode)),
                          ),
                        )
                      else if (!_creating && !state.isBusy)
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: _DialogAction(
                            key: const ValueKey('player-watch-party-retry'),
                            focusNode: _retryFocus,
                            autofocus: true,
                            icon: Icons.refresh_rounded,
                            label: 'Try again',
                            onPressed: () => unawaited(_createRoom()),
                          ),
                        ),
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: _DialogAction(
                          key: const ValueKey('player-watch-party-close'),
                          focusNode: _closeFocus,
                          autofocus: !hasRoom && (_creating || state.isBusy),
                          icon: Icons.close_rounded,
                          label: 'Close',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      if (hasRoom)
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(3),
                          child: _DialogAction(
                            key: const ValueKey('player-watch-party-leave'),
                            focusNode: _leaveFocus,
                            icon: session.role == WatchPartyRole.host
                                ? Icons.stop_circle_outlined
                                : Icons.logout_rounded,
                            label: _leaving
                                ? 'Leaving…'
                                : session.role == WatchPartyRole.host
                                ? 'End room'
                                : 'Leave room',
                            onPressed: _leaving
                                ? () {}
                                : () => unawaited(_leaveRoom(session.role)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivePlayerParty extends StatelessWidget {
  const _ActivePlayerParty({
    required this.roomCode,
    required this.watchUrl,
    required this.participantCount,
    required this.readyCount,
    required this.participants,
    required this.roomCodeFocusNode,
    required this.showParticipants,
    required this.onRoomCodePressed,
    required this.compact,
  });

  final String roomCode;
  final Uri watchUrl;
  final int participantCount;
  final int readyCount;
  final List<WatchPartyParticipant> participants;
  final FocusNode roomCodeFocusNode;
  final bool showParticipants;
  final VoidCallback onRoomCodePressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final qrSize = compact ? 112.0 : 148.0;
    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TvFocusable(
          key: const ValueKey('player-watch-party-room-code-action'),
          focusNode: roomCodeFocusNode,
          onPressed: onRoomCodePressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: palette.selectableSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: palette.accentBright.withValues(alpha: .42),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  roomCode,
                  key: const ValueKey('player-watch-party-room-code'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: palette.accentBright,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  showParticipants
                      ? Icons.expand_less_rounded
                      : Icons.people_outline_rounded,
                  color: palette.accentBright,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${watchPartyGuestCountLabel(participantCount)} • $readyCount ready',
          style: TextStyle(color: palette.mutedText),
        ),
        if (showParticipants) ...[
          const SizedBox(height: 10),
          _CompactParticipantPreview(participants: participants),
        ],
        const SizedBox(height: 10),
        Text(
          'Share this code, or scan the QR code to open the room on a phone or computer.',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          watchUrl.toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.mutedText, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Text(
          'Only room timing is synchronized. Stream URLs, tokens, headers, and video data stay on each viewer’s device.',
          style: TextStyle(color: palette.mutedText, fontSize: 12),
        ),
      ],
    );
    final qr = ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: QrImageView(
          key: const ValueKey('player-watch-party-qr'),
          data: watchUrl.toString(),
          size: qrSize,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(color: Colors.black),
          dataModuleStyle: const QrDataModuleStyle(color: Colors.black),
        ),
      ),
    );
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [qr, const SizedBox(height: 14), details],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        qr,
        const SizedBox(width: 20),
        Expanded(child: details),
      ],
    );
  }
}

class _CompactParticipantPreview extends StatelessWidget {
  const _CompactParticipantPreview({required this.participants});

  final List<WatchPartyParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    if (participants.isEmpty) {
      return Text(
        'Participant profiles will appear here as people join.',
        key: const ValueKey('player-watch-party-participants-empty'),
        style: TextStyle(color: palette.mutedText, fontSize: 12),
      );
    }
    final visible = participants.take(6).toList(growable: false);
    return Container(
      key: const ValueKey('player-watch-party-participants'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final participant in visible)
            _ParticipantChip(participant: participant),
          if (participants.length > visible.length)
            Chip(label: Text('+${participants.length - visible.length}')),
        ],
      ),
    );
  }
}

class _ParticipantChip extends StatelessWidget {
  const _ParticipantChip({required this.participant});

  final WatchPartyParticipant participant;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final avatarUrl = participant.avatarUrl;
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.fromLTRB(5, 5, 9, 5),
      decoration: BoxDecoration(
        color: palette.selectableSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: palette.accent.withValues(alpha: .35),
            foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
            child: avatarUrl == null
                ? Text(
                    participant.displayName.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              participant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 5),
          Icon(
            participant.role == WatchPartyRole.host
                ? Icons.star_rounded
                : participant.ready
                ? Icons.check_circle_rounded
                : Icons.hourglass_empty_rounded,
            size: 15,
            color: participant.role == WatchPartyRole.host || participant.ready
                ? palette.accentBright
                : palette.mutedText,
          ),
        ],
      ),
    );
  }
}

class _ConfirmLeaveRoomDialog extends StatelessWidget {
  const _ConfirmLeaveRoomDialog({required this.role});

  final WatchPartyRole role;

  @override
  Widget build(BuildContext context) {
    final host = role == WatchPartyRole.host;
    return AlertDialog(
      title: Text(host ? 'End Watch Together room?' : 'Leave this room?'),
      content: Text(
        host
            ? 'This ends the room for every participant. Playback on your device keeps running.'
            : 'You will stop following the host. Playback on your device keeps running.',
      ),
      actions: [
        _DialogAction(
          icon: Icons.close_rounded,
          label: 'Cancel',
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        _DialogAction(
          icon: host ? Icons.stop_circle_outlined : Icons.logout_rounded,
          label: host ? 'End room' : 'Leave room',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

class _DialogAction extends StatelessWidget {
  const _DialogAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvFocusable(
    focusNode: focusNode,
    autofocus: autofocus,
    onPressed: onPressed,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: context.appPalette.selectableSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    ),
  );
}
