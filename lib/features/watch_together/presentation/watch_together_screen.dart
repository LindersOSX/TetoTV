import 'dart:async';

import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/teto_top_level_shell.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_controller.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

class WatchTogetherScreen extends ConsumerStatefulWidget {
  const WatchTogetherScreen({this.initialRoomCode, super.key});

  final String? initialRoomCode;

  @override
  ConsumerState<WatchTogetherScreen> createState() =>
      _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends ConsumerState<WatchTogetherScreen> {
  final _createFocus = FocusNode(debugLabel: 'watch-together.create');
  final _roomCodeFocus = FocusNode(debugLabel: 'watch-together.room-code');
  final _joinFocus = FocusNode(debugLabel: 'watch-together.join');
  final _copyFocus = FocusNode(debugLabel: 'watch-together.copy');
  final _watchFocus = FocusNode(debugLabel: 'watch-together.watch');
  final _leaveFocus = FocusNode(debugLabel: 'watch-together.leave');
  late final TextEditingController _roomCodeController;

  @override
  void initState() {
    super.initState();
    _roomCodeController = TextEditingController(text: widget.initialRoomCode);
  }

  @override
  void dispose() {
    _createFocus.dispose();
    _roomCodeFocus.dispose();
    _joinFocus.dispose();
    _copyFocus.dispose();
    _watchFocus.dispose();
    _leaveFocus.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    await ref
        .read(watchPartyControllerProvider.notifier)
        .join(_roomCodeController.text);
  }

  void _openHostEpisode(WatchPartyMedia media) {
    if (!media.isCatalogEpisode) return;
    context.push(
      Uri(
        path: '/resolve',
        queryParameters: <String, String>{
          'anilistId': '${media.anilistId}',
          'episode': '${media.episode}',
          'title': media.title,
          if (media.titleEnglish != null) 'titleEnglish': media.titleEnglish!,
          if (media.titleRomaji != null) 'titleRomaji': media.titleRomaji!,
          if (media.year != null) 'year': '${media.year}',
          if (media.coverUrl != null) 'cover': media.coverUrl!,
          'autoplay': '1',
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(settingsPreferencesProvider);
    final party = ref.watch(watchPartyControllerProvider);
    return TetoTopLevelShell(
      preferences: preferences,
      activeDestination: TopNavigationDestination.settings,
      firstContentFocusNode: party.isActive ? _copyFocus : _createFocus,
      fallbackContentFocusNode: party.isActive ? _leaveFocus : _roomCodeFocus,
      builder: (context, layout) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!layout.usesTvRail)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: layout.usesTvRail
                  ? EdgeInsets.zero
                  : const EdgeInsets.fromLTRB(20, 10, 20, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Watch Together',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Everyone uses their own TetoTV source or local video. Only playback timing and public show identity are synchronized.',
                      style: TextStyle(color: context.appPalette.mutedText),
                    ),
                    const SizedBox(height: 20),
                    if (!party.isActive)
                      _LobbyCard(
                        state: party,
                        roomCodeController: _roomCodeController,
                        createFocus: _createFocus,
                        roomCodeFocus: _roomCodeFocus,
                        joinFocus: _joinFocus,
                        onCreate: () => unawaited(
                          ref
                              .read(watchPartyControllerProvider.notifier)
                              .create(),
                        ),
                        onJoin: () => unawaited(_join()),
                        onLeftEdge: layout.focusRail,
                      )
                    else
                      _ActivePartyCard(
                        state: party,
                        copyFocus: _copyFocus,
                        watchFocus: _watchFocus,
                        leaveFocus: _leaveFocus,
                        onLeftEdge: layout.focusRail,
                        onWatch: party.snapshot?.media == null
                            ? null
                            : () => _openHostEpisode(party.snapshot!.media!),
                        onLeave: () => unawaited(
                          ref
                              .read(watchPartyControllerProvider.notifier)
                              .leave(),
                        ),
                      ),
                    if (party.message case final message?) ...[
                      const SizedBox(height: 14),
                      Text(
                        message,
                        key: const ValueKey('watch-together-message'),
                        style: TextStyle(
                          color: context.appPalette.accentBright,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyCard extends StatelessWidget {
  const _LobbyCard({
    required this.state,
    required this.roomCodeController,
    required this.createFocus,
    required this.roomCodeFocus,
    required this.joinFocus,
    required this.onCreate,
    required this.onJoin,
    required this.onLeftEdge,
  });

  final WatchPartyState state;
  final TextEditingController roomCodeController;
  final FocusNode createFocus;
  final FocusNode roomCodeFocus;
  final FocusNode joinFocus;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onLeftEdge;

  @override
  Widget build(BuildContext context) => _PartyPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start a room or enter a code',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _PartyButton(
              key: const ValueKey('watch-together-create'),
              focusNode: createFocus,
              autofocus: true,
              icon: Icons.groups_rounded,
              label: state.isBusy ? 'Starting…' : 'Create room',
              onPressed: state.isBusy ? null : onCreate,
              onLeft: onLeftEdge,
            ),
            SizedBox(
              width: 230,
              child: TextField(
                key: const ValueKey('watch-together-code-input'),
                controller: roomCodeController,
                focusNode: roomCodeFocus,
                enabled: !state.isBusy,
                maxLength: 9,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                ],
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: 'Room code',
                  hintText: 'ABCD-2345',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => onJoin(),
                onTapOutside: (_) => roomCodeFocus.unfocus(),
              ),
            ),
            _PartyButton(
              key: const ValueKey('watch-together-join'),
              focusNode: joinFocus,
              icon: Icons.login_rounded,
              label: state.isBusy ? 'Joining…' : 'Join room',
              onPressed: state.isBusy ? null : onJoin,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Rooms expire automatically. TetoTV never sends stream URLs, server tokens, headers, magnets, or video data to the room service.',
          style: TextStyle(color: context.appPalette.mutedText, fontSize: 12),
        ),
      ],
    ),
  );
}

class _ActivePartyCard extends StatelessWidget {
  const _ActivePartyCard({
    required this.state,
    required this.copyFocus,
    required this.watchFocus,
    required this.leaveFocus,
    required this.onLeftEdge,
    required this.onWatch,
    required this.onLeave,
  });

  final WatchPartyState state;
  final FocusNode copyFocus;
  final FocusNode watchFocus;
  final FocusNode leaveFocus;
  final VoidCallback onLeftEdge;
  final VoidCallback? onWatch;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final session = state.session!;
    final snapshot = state.snapshot;
    final media = snapshot?.media;
    return _PartyPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final qrSize = constraints.maxWidth < 620 ? 138.0 : 174.0;
          return Wrap(
            spacing: 24,
            runSpacing: 20,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    key: const ValueKey('watch-together-qr'),
                    data: session.watchUrl.toString(),
                    size: qrSize,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: constraints.maxWidth < 620
                    ? constraints.maxWidth
                    : constraints.maxWidth - qrSize - 48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isHost ? 'HOSTING' : 'JOINED',
                      style: TextStyle(
                        color: context.appPalette.accentBright,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SelectableText(
                      session.roomCode,
                      key: const ValueKey('watch-together-room-code'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${snapshot?.participantCount ?? 0} guests • ${snapshot?.readyCount ?? 0} ready',
                      style: TextStyle(color: context.appPalette.mutedText),
                    ),
                    if (media != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        media.isCatalogEpisode
                            ? '${media.title} • Episode ${media.episode}'
                            : media.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _PartyButton(
                          key: const ValueKey('watch-together-copy'),
                          focusNode: copyFocus,
                          autofocus: true,
                          icon: Icons.copy_rounded,
                          label: 'Copy code',
                          onLeft: onLeftEdge,
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: session.roomCode),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Room code copied.'),
                                ),
                              );
                            }
                          },
                        ),
                        if (!state.isHost && media?.isCatalogEpisode == true)
                          _PartyButton(
                            key: const ValueKey('watch-together-watch'),
                            focusNode: watchFocus,
                            icon: Icons.play_arrow_rounded,
                            label: 'Open this episode',
                            onPressed: onWatch,
                          ),
                        _PartyButton(
                          key: const ValueKey('watch-together-leave'),
                          focusNode: leaveFocus,
                          icon: Icons.logout_rounded,
                          label: state.isHost ? 'End room' : 'Leave room',
                          onPressed: onLeave,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PartyPanel extends StatelessWidget {
  const _PartyPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.appPalette.surface.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: context.appPalette.accent.withValues(alpha: .35),
      ),
    ),
    child: Padding(padding: const EdgeInsets.all(22), child: child),
  );
}

class _PartyButton extends StatelessWidget {
  const _PartyButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.onLeft,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onLeft;

  @override
  Widget build(BuildContext context) => TvFocusable(
    focusNode: focusNode,
    autofocus: autofocus,
    onPressed: onPressed ?? () {},
    onKeyEvent: onLeft == null
        ? null
        : (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              onLeft!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
    borderRadius: BorderRadius.circular(12),
    child: AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: onPressed == null ? .45 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.appPalette.selectableSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    ),
  );
}
