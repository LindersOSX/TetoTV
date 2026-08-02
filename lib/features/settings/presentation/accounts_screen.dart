import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/core/diagnostics/diagnostics_exporter.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/home_shelf_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/torbox_settings_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final _tokenController = TextEditingController();
  final _torBoxTokenController = TextEditingController();
  final _backFocus = FocusNode(debugLabel: 'accounts.back');
  final _titleLanguageFocus = FocusNode(debugLabel: 'accounts.title-language');
  final _debridConnectFocus = FocusNode(debugLabel: 'accounts.debrid.connect');
  final _tokenFocus = FocusNode(debugLabel: 'accounts.debrid.token');
  final _tokenSaveFocus = FocusNode(debugLabel: 'accounts.debrid.save');
  final _torBoxActionFocus = FocusNode(debugLabel: 'accounts.torbox.action');
  final _torBoxTokenFocus = FocusNode(debugLabel: 'accounts.torbox.token');
  final _torBoxSaveFocus = FocusNode(debugLabel: 'accounts.torbox.save');
  final _anilistFocus = FocusNode(debugLabel: 'accounts.anilist');
  final _malFocus = FocusNode(debugLabel: 'accounts.myanimelist');
  final _anilistTokenFocus = FocusNode(debugLabel: 'accounts.anilist.token');
  final _anilistSaveFocus = FocusNode(debugLabel: 'accounts.anilist.save');
  final _malTokenFocus = FocusNode(debugLabel: 'accounts.myanimelist.token');
  final _malSaveFocus = FocusNode(debugLabel: 'accounts.myanimelist.save');
  final _shelfFocusNodes = {
    for (final shelf in HomeShelf.values)
      shelf: FocusNode(debugLabel: 'accounts.shelf.${shelf.name}'),
  };

  @override
  void dispose() {
    _tokenController.dispose();
    _torBoxTokenController.dispose();
    _backFocus.dispose();
    _titleLanguageFocus.dispose();
    _debridConnectFocus.dispose();
    _tokenFocus.dispose();
    _tokenSaveFocus.dispose();
    _torBoxActionFocus.dispose();
    _torBoxTokenFocus.dispose();
    _torBoxSaveFocus.dispose();
    _anilistFocus.dispose();
    _malFocus.dispose();
    _anilistTokenFocus.dispose();
    _anilistSaveFocus.dispose();
    _malTokenFocus.dispose();
    _malSaveFocus.dispose();
    for (final node in _shelfFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final current = FocusManager.instance.primaryFocus;
    final key = event.logicalKey;
    FocusNode? target;
    final shelfNodes = [
      for (final shelf in HomeShelf.values) _shelfFocusNodes[shelf]!,
    ];
    final shelfIndex = current == null ? -1 : shelfNodes.indexOf(current);

    if (shelfIndex >= 0) {
      if (key == LogicalKeyboardKey.arrowLeft && shelfIndex > 0) {
        target = shelfNodes[shelfIndex - 1];
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          shelfIndex < shelfNodes.length - 1) {
        target = shelfNodes[shelfIndex + 1];
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _titleLanguageFocus;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _debridConnectFocus;
      }
    }

    if (shelfIndex >= 0) {
      // Shelf navigation was handled above.
    } else if (current == _backFocus) {
      if (key == LogicalKeyboardKey.arrowRight) {
        target = _titleLanguageFocus;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        target = shelfNodes.first;
      }
    } else if (current == _titleLanguageFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _backFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = shelfNodes.first;
    } else if (current == _debridConnectFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _backFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = shelfNodes.first;
      if (key == LogicalKeyboardKey.arrowDown) target = _torBoxActionFocus;
    } else if (current == _tokenFocus) {
      if (key == LogicalKeyboardKey.arrowRight) target = _tokenSaveFocus;
    } else if (current == _tokenSaveFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _tokenFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _debridConnectFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _torBoxActionFocus;
    } else if (current == _torBoxActionFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _tokenSaveFocus.context == null
            ? _debridConnectFocus
            : _tokenSaveFocus;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _torBoxTokenFocus.context == null
            ? _anilistFocus
            : _torBoxTokenFocus;
      }
    } else if (current == _torBoxTokenFocus) {
      if (key == LogicalKeyboardKey.arrowRight) target = _torBoxSaveFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _torBoxActionFocus;
    } else if (current == _torBoxSaveFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _torBoxTokenFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _torBoxActionFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _anilistFocus;
    } else if (current == _anilistFocus) {
      if (key == LogicalKeyboardKey.arrowRight) target = _malFocus;
      if (key == LogicalKeyboardKey.arrowDown &&
          _anilistTokenFocus.context != null) {
        target = _anilistTokenFocus;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _torBoxTokenFocus.context == null
            ? _torBoxActionFocus
            : _torBoxTokenFocus;
      }
    } else if (current == _malFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _anilistFocus;
      if (key == LogicalKeyboardKey.arrowDown &&
          _malTokenFocus.context != null) {
        target = _malTokenFocus;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _torBoxSaveFocus.context == null
            ? _torBoxActionFocus
            : _torBoxSaveFocus;
      }
    } else if (current == _anilistTokenFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _anilistFocus;
      if (key == LogicalKeyboardKey.arrowRight) target = _anilistSaveFocus;
    } else if (current == _anilistSaveFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _anilistFocus;
      if (key == LogicalKeyboardKey.arrowLeft) target = _anilistTokenFocus;
      if (key == LogicalKeyboardKey.arrowRight &&
          _malTokenFocus.context != null) {
        target = _malTokenFocus;
      }
    } else if (current == _malTokenFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _malFocus;
      if (key == LogicalKeyboardKey.arrowLeft &&
          _anilistSaveFocus.context != null) {
        target = _anilistSaveFocus;
      }
      if (key == LogicalKeyboardKey.arrowRight) target = _malSaveFocus;
    } else if (current == _malSaveFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _malFocus;
      if (key == LogicalKeyboardKey.arrowLeft) target = _malTokenFocus;
    }

    if (target == null) return KeyEventResult.ignored;
    target.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final debrid = ref.watch(realDebridSettingsControllerProvider);
    final torBox = ref.watch(torBoxSettingsControllerProvider);
    final tracking = ref.watch(trackingAccountsControllerProvider);
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    final homeShelves = ref.watch(homeShelfPreferencesProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(30, 18, 30, 22),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: _handleKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final showSecurityLabel = constraints.maxWidth >= 1180;
                  return Row(
                    children: [
                      _TvIconButton(
                        autofocus: true,
                        focusNode: _backFocus,
                        icon: Icons.arrow_back_rounded,
                        onPressed: context.pop,
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          'Accounts & streaming',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(width: 16),
                      _TitleLanguageToggle(
                        focusNode: _titleLanguageFocus,
                        preference: titlePreference,
                        onPressed: () {
                          ref
                              .read(titleLanguagePreferenceProvider.notifier)
                              .toggle();
                        },
                      ),
                      const SizedBox(width: 12),
                      const Tooltip(
                        message: 'Secrets stay encrypted on this device',
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: AppColors.cyan,
                        ),
                      ),
                      if (showSecurityLabel) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Secrets stay encrypted on this device',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
                  ),
                  children: [
                    _Panel(
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 150,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'HOME SHELVES',
                                  style: TextStyle(
                                    color: AppColors.accentBright,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Choose what appears on Home',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                for (final shelf in HomeShelf.values)
                                  _ShelfToggle(
                                    shelf: shelf,
                                    enabled: homeShelves.contains(shelf),
                                    focusNode: _shelfFocusNodes[shelf]!,
                                    onPressed: () => ref
                                        .read(
                                          homeShelfPreferencesProvider.notifier,
                                        )
                                        .toggle(shelf),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const _SectionHeader(
                      icon: Icons.cloud_done_rounded,
                      title: 'DEBRID STREAMING',
                      subtitle: 'Every playable link is resolved securely.',
                    ),
                    const SizedBox(height: 8),
                    _RealDebridPanel(
                      state: debrid,
                      tokenController: _tokenController,
                      onSave: () async {
                        final saved = await ref
                            .read(realDebridSettingsControllerProvider.notifier)
                            .saveAndValidate(_tokenController.text);
                        if (saved) _tokenController.clear();
                      },
                      onDisconnect: () => ref
                          .read(realDebridSettingsControllerProvider.notifier)
                          .disconnect(),
                      onDeviceConnect: () => context.push('/pair/realdebrid'),
                      connectFocusNode: _debridConnectFocus,
                      tokenFocusNode: _tokenFocus,
                      saveFocusNode: _tokenSaveFocus,
                    ),
                    const SizedBox(height: 10),
                    _TorBoxPanel(
                      state: torBox,
                      tokenController: _torBoxTokenController,
                      onSave: () async {
                        final saved = await ref
                            .read(torBoxSettingsControllerProvider.notifier)
                            .saveAndValidate(_torBoxTokenController.text);
                        if (saved) _torBoxTokenController.clear();
                      },
                      onDisconnect: () => ref
                          .read(torBoxSettingsControllerProvider.notifier)
                          .disconnect(),
                      onDeviceConnect: () async {
                        await context.push('/pair/torbox');
                        await ref
                            .read(torBoxSettingsControllerProvider.notifier)
                            .load();
                      },
                      actionFocusNode: _torBoxActionFocus,
                      tokenFocusNode: _torBoxTokenFocus,
                      saveFocusNode: _torBoxSaveFocus,
                    ),
                    const SizedBox(height: 14),
                    const _SectionHeader(
                      icon: Icons.sync_alt_rounded,
                      title: 'ANIME TRACKING',
                      subtitle: 'Lists and progress sync in both directions.',
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final anilistPanel = _TrackingPanel(
                          provider: TrackingProvider.anilist,
                          color: AppColors.accentBright,
                          description:
                              'Seasonal discovery, lists, and automatic '
                              'episode progress.',
                          username:
                              tracking.usernames[TrackingProvider.anilist],
                          error: tracking.errors[TrackingProvider.anilist],
                          isLoading: tracking.isLoading,
                          onConnect: () async {
                            await context.push('/pair/anilist');
                            await ref
                                .read(
                                  trackingAccountsControllerProvider.notifier,
                                )
                                .load();
                          },
                          onDisconnect: () => ref
                              .read(trackingAccountsControllerProvider.notifier)
                              .disconnect(TrackingProvider.anilist),
                          onSaveToken: (token) => ref
                              .read(trackingAccountsControllerProvider.notifier)
                              .save(TrackingProvider.anilist, token),
                          focusNode: _anilistFocus,
                          tokenFocusNode: _anilistTokenFocus,
                          saveFocusNode: _anilistSaveFocus,
                        );
                        final malPanel = _TrackingPanel(
                          provider: TrackingProvider.myAnimeList,
                          color: const Color(0xFFB41F3D),
                          description:
                              'Sync watch progress and your MyAnimeList '
                              'watching lists automatically.',
                          username:
                              tracking.usernames[TrackingProvider.myAnimeList],
                          error: tracking.errors[TrackingProvider.myAnimeList],
                          isLoading: tracking.isLoading,
                          onConnect: () async {
                            await context.push('/pair/myanimelist');
                            await ref
                                .read(
                                  trackingAccountsControllerProvider.notifier,
                                )
                                .load();
                          },
                          onDisconnect: () => ref
                              .read(trackingAccountsControllerProvider.notifier)
                              .disconnect(TrackingProvider.myAnimeList),
                          onSaveToken: (token) => ref
                              .read(trackingAccountsControllerProvider.notifier)
                              .save(TrackingProvider.myAnimeList, token),
                          focusNode: _malFocus,
                          tokenFocusNode: _malTokenFocus,
                          saveFocusNode: _malSaveFocus,
                        );
                        if (constraints.maxWidth >= 820) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: anilistPanel),
                              const SizedBox(width: 10),
                              Expanded(child: malPanel),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            anilistPanel,
                            const SizedBox(height: 10),
                            malPanel,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    const _DebridOnlyPanel(),
                    const SizedBox(height: 10),
                    _Panel(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.monitor_heart_outlined,
                            color: AppColors.accentBright,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Playback diagnostics',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Exports device codecs, frame timings, and redacted failures. No tokens or stream URLs.',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _TvTextButton(
                            label: 'Export report',
                            icon: Icons.file_download_outlined,
                            onPressed: () async {
                              final file = await const DiagnosticsExporter()
                                  .export();
                              await Clipboard.setData(
                                ClipboardData(text: file.path),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Saved diagnostics and copied the path: ${file.path}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfToggle extends StatelessWidget {
  const _ShelfToggle({
    required this.shelf,
    required this.enabled,
    required this.focusNode,
    required this.onPressed,
  });

  final HomeShelf shelf;
  final bool enabled;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = switch (shelf) {
      HomeShelf.history => 'History',
      HomeShelf.tracking => 'Watching',
      HomeShelf.trending => 'Trending',
      HomeShelf.planned => 'Planned',
      HomeShelf.airing => 'Airing',
      HomeShelf.completed => 'Completed',
    };
    return TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        color: enabled ? AppColors.accent : const Color(0xFF1A1A1A),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(enabled ? Icons.check_rounded : Icons.add_rounded, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.accentBright),
        const SizedBox(width: 7),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _RealDebridPanel extends StatelessWidget {
  const _RealDebridPanel({
    required this.state,
    required this.tokenController,
    required this.onSave,
    required this.onDisconnect,
    required this.onDeviceConnect,
    required this.connectFocusNode,
    required this.tokenFocusNode,
    required this.saveFocusNode,
  });

  final RealDebridSettingsState state;
  final TextEditingController tokenController;
  final VoidCallback onSave;
  final VoidCallback onDisconnect;
  final VoidCallback onDeviceConnect;
  final FocusNode connectFocusNode;
  final FocusNode tokenFocusNode;
  final FocusNode saveFocusNode;

  @override
  Widget build(BuildContext context) {
    final account = state.account;
    return _Panel(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.cyan],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.cloud_download_rounded,
                  color: AppColors.ink,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Real-Debrid',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(width: 12),
                        _StatusPill(
                          connected: account != null,
                          label: account == null
                              ? state.hasSavedToken
                                    ? 'RECONNECTING'
                                    : 'NOT CONNECTED'
                              : account.isPremium
                              ? 'PREMIUM'
                              : account.type.toUpperCase(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      account == null
                          ? 'Authorize on your phone, or use a personal API '
                                'token below.'
                          : 'Connected as ${account.username}. Cached torrents '
                                'will resolve almost instantly.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (account == null)
                _TvTextButton(
                  label: 'Connect by QR',
                  icon: Icons.qr_code_rounded,
                  onPressed: onDeviceConnect,
                  focusNode: connectFocusNode,
                )
              else
                _TvTextButton(
                  label: 'Disconnect',
                  icon: Icons.link_off_rounded,
                  onPressed: onDisconnect,
                  focusNode: connectFocusNode,
                ),
            ],
          ),
          if (state.errorMessage case final error?) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                style: const TextStyle(color: Color(0xFFFF929B)),
              ),
            ),
          ],
          if (account == null) ...[
            const SizedBox(height: 10),
            Divider(color: Colors.white.withValues(alpha: .08), height: 1),
            const SizedBox(height: 10),
            _ResponsiveTokenRow(
              title: 'Advanced: personal token',
              input: TvTextInput(
                focusNode: tokenFocusNode,
                controller: tokenController,
                labelText: 'Personal API token',
                hintText: 'Select to open the TV keyboard',
                keyboardTitle: 'Enter Real-Debrid token',
                obscureText: true,
                onSubmitted: (_) => onSave(),
              ),
              action: _TvTextButton(
                label: state.isLoading ? 'Checking…' : 'Save & verify',
                icon: state.isLoading
                    ? Icons.sync_rounded
                    : Icons.verified_user_outlined,
                onPressed: state.isLoading ? null : onSave,
                focusNode: saveFocusNode,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TorBoxPanel extends StatelessWidget {
  const _TorBoxPanel({
    required this.state,
    required this.tokenController,
    required this.onSave,
    required this.onDisconnect,
    required this.onDeviceConnect,
    required this.actionFocusNode,
    required this.tokenFocusNode,
    required this.saveFocusNode,
  });

  final TorBoxSettingsState state;
  final TextEditingController tokenController;
  final VoidCallback onSave;
  final VoidCallback onDisconnect;
  final VoidCallback onDeviceConnect;
  final FocusNode actionFocusNode;
  final FocusNode tokenFocusNode;
  final FocusNode saveFocusNode;

  @override
  Widget build(BuildContext context) {
    final account = state.account;
    return _Panel(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.accentBright],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.cloud_circle_rounded,
                  color: AppColors.ink,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'TorBox',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(width: 12),
                        _StatusPill(
                          connected: account != null,
                          label: account == null
                              ? state.hasSavedToken
                                    ? 'RECONNECTING'
                                    : 'NOT CONNECTED'
                              : account.planName.toUpperCase(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      account == null
                          ? 'Authorize with a QR code, or enter a TorBox API '
                                'token below.'
                          : 'Connected as ${account.email}. Torrent files are '
                                'resolved and streamed through TorBox only.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (account == null)
                _TvTextButton(
                  label: 'Connect by QR',
                  icon: Icons.qr_code_rounded,
                  onPressed: onDeviceConnect,
                  focusNode: actionFocusNode,
                )
              else
                _TvTextButton(
                  label: 'Disconnect',
                  icon: Icons.link_off_rounded,
                  onPressed: onDisconnect,
                  focusNode: actionFocusNode,
                ),
            ],
          ),
          if (state.errorMessage case final error?) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                error,
                style: const TextStyle(color: Color(0xFFFF929B)),
              ),
            ),
          ],
          if (account == null) ...[
            const SizedBox(height: 10),
            Divider(color: Colors.white.withValues(alpha: .08), height: 1),
            const SizedBox(height: 10),
            _ResponsiveTokenRow(
              title: 'TorBox API token',
              input: TvTextInput(
                focusNode: tokenFocusNode,
                controller: tokenController,
                labelText: 'Personal API token',
                hintText: 'Select to open the TV keyboard',
                keyboardTitle: 'Enter TorBox token',
                obscureText: true,
                onSubmitted: (_) => onSave(),
              ),
              action: _TvTextButton(
                label: state.isLoading ? 'Checking…' : 'Save & verify',
                icon: state.isLoading
                    ? Icons.sync_rounded
                    : Icons.verified_user_outlined,
                onPressed: state.isLoading ? null : onSave,
                focusNode: saveFocusNode,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackingPanel extends StatefulWidget {
  const _TrackingPanel({
    required this.provider,
    required this.color,
    required this.description,
    required this.onConnect,
    required this.onDisconnect,
    required this.onSaveToken,
    required this.focusNode,
    required this.tokenFocusNode,
    required this.saveFocusNode,
    required this.isLoading,
    this.username,
    this.error,
  });

  final TrackingProvider provider;
  final Color color;
  final String description;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Future<void> Function(String) onSaveToken;
  final FocusNode focusNode;
  final FocusNode tokenFocusNode;
  final FocusNode saveFocusNode;
  final bool isLoading;
  final String? username;
  final String? error;

  @override
  State<_TrackingPanel> createState() => _TrackingPanelState();
}

class _TrackingPanelState extends State<_TrackingPanel> {
  final _tokenController = TextEditingController();
  String? _inputError;
  bool _saving = false;

  Future<void> _saveToken([String? submitted]) async {
    final token = (submitted ?? _tokenController.text).trim();
    if (token.isEmpty) {
      setState(() => _inputError = 'Enter a token before saving.');
      return;
    }
    setState(() {
      _inputError = null;
      _saving = true;
    });
    try {
      await widget.onSaveToken(token);
      if (mounted && widget.error == null) _tokenController.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  Icons.playlist_add_check_rounded,
                  color: widget.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.provider.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(
                connected: widget.username != null,
                label: widget.username != null ? 'CONNECTED' : 'NOT CONNECTED',
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            widget.username == null
                ? widget.description
                : 'Connected as ${widget.username}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _TvTextButton(
              label: widget.username != null ? 'Disconnect' : 'Connect by QR',
              icon: widget.username == null
                  ? Icons.qr_code_rounded
                  : Icons.link_off_rounded,
              onPressed: widget.username == null
                  ? widget.onConnect
                  : widget.onDisconnect,
              focusNode: widget.focusNode,
            ),
          ),
          if (widget.username == null) ...[
            const SizedBox(height: 8),
            Divider(color: Colors.white.withValues(alpha: .08), height: 1),
            const SizedBox(height: 8),
            _ResponsiveTokenRow(
              title: 'Manual API token',
              input: TvTextInput(
                controller: _tokenController,
                focusNode: widget.tokenFocusNode,
                labelText: 'Personal Access Token',
                hintText: 'Select to open the TV keyboard',
                keyboardTitle: 'Enter ${widget.provider.displayName} token',
                obscureText: true,
                onSubmitted: _saveToken,
              ),
              action: _TvTextButton(
                label: _saving || widget.isLoading
                    ? 'Checking…'
                    : 'Save & verify',
                icon: Icons.verified_user_outlined,
                focusNode: widget.saveFocusNode,
                onPressed: _saving || widget.isLoading ? null : _saveToken,
              ),
            ),
            if (_inputError ?? widget.error case final message?) ...[
              const SizedBox(height: 10),
              Text(message, style: const TextStyle(color: Color(0xFFFF8DA0))),
            ],
          ],
        ],
      ),
    );
  }
}

class _DebridOnlyPanel extends StatelessWidget {
  const _DebridOnlyPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.accentBright,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Debrid-only playback',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  'The player accepts streams created by Real-Debrid or '
                  'TorBox. It never connects directly to torrent peers.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.lock_rounded, color: AppColors.accentBright),
        ],
      ),
    );
  }
}

class _ResponsiveTokenRow extends StatelessWidget {
  const _ResponsiveTokenRow({
    required this.title,
    required this.input,
    required this.action,
  });

  final String title;
  final Widget input;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldAndAction = Row(
          children: [
            Expanded(child: input),
            const SizedBox(width: 12),
            action,
          ],
        );
        if (constraints.maxWidth < 1100) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              fieldAndAction,
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: 210,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(child: fieldAndAction),
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.connected, required this.label});

  final bool connected;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF67D49B) : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _TitleLanguageToggle extends StatelessWidget {
  const _TitleLanguageToggle({
    required this.focusNode,
    required this.preference,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final TitleLanguagePreference preference;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      focusScale: 1.02,
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.translate_rounded,
              size: 17,
              color: AppColors.accentBright,
            ),
            const SizedBox(width: 7),
            Text(
              'Titles: ${preference.displayName}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvIconButton extends StatelessWidget {
  const _TvIconButton({
    required this.icon,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: AppColors.panel,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

class _TvTextButton extends StatelessWidget {
  const _TvTextButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.focusNode,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return TvFocusable(
      onPressed: onPressed ?? () {},
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: enabled ? AppColors.accent : const Color(0xFF3A2228),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: enabled ? Colors.white : Colors.white54,
              size: 19,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: enabled ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
