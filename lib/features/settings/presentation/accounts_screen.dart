import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/app_update_controller.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/home_shelf_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/torbox_settings_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _SettingsArea { customize, streaming, tracking, appearance, system }

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  _SettingsArea _activeArea = _SettingsArea.customize;
  final _tokenController = TextEditingController();
  final _torBoxTokenController = TextEditingController();
  final _githubTokenController = TextEditingController();
  final _backFocus = FocusNode(debugLabel: 'accounts.back');
  final _titleLanguageFocus = FocusNode(debugLabel: 'accounts.title-language');
  final _debridProviderFocus = FocusNode(
    debugLabel: 'accounts.debrid.provider',
  );
  final _trackingProviderFocus = FocusNode(
    debugLabel: 'accounts.tracking.provider',
  );
  final _debridStreamsFocus = FocusNode(
    debugLabel: 'accounts.streaming.debrid',
  );
  final _webStreamsFocus = FocusNode(debugLabel: 'accounts.streaming.web');
  final _marketplaceFocus = FocusNode(
    debugLabel: 'accounts.streaming.marketplace',
  );
  final _appearanceFocus = FocusNode(debugLabel: 'accounts.appearance.first');
  final _customizationFocus = FocusNode(
    debugLabel: 'accounts.customization.first',
  );
  final _setupFocus = FocusNode(debugLabel: 'accounts.system.setup');
  final _calibrationFocus = FocusNode(
    debugLabel: 'accounts.system.calibration',
  );
  final _diagnosticsFocus = FocusNode(
    debugLabel: 'accounts.system.diagnostics',
  );
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
  final _githubTokenFocus = FocusNode(debugLabel: 'accounts.updates.token');
  final _githubSaveFocus = FocusNode(debugLabel: 'accounts.updates.save');
  final _automaticUpdatesFocus = FocusNode(
    debugLabel: 'accounts.updates.automatic',
  );
  final _checkUpdatesFocus = FocusNode(debugLabel: 'accounts.updates.check');
  final _areaFocusNodes = {
    for (final area in _SettingsArea.values)
      area: FocusNode(debugLabel: 'accounts.area.${area.name}'),
  };
  final _shelfFocusNodes = {
    for (final shelf in HomeShelf.values)
      shelf: FocusNode(debugLabel: 'accounts.shelf.${shelf.name}'),
  };

  @override
  void dispose() {
    _tokenController.dispose();
    _torBoxTokenController.dispose();
    _githubTokenController.dispose();
    _backFocus.dispose();
    _titleLanguageFocus.dispose();
    _debridProviderFocus.dispose();
    _trackingProviderFocus.dispose();
    _debridStreamsFocus.dispose();
    _webStreamsFocus.dispose();
    _marketplaceFocus.dispose();
    _appearanceFocus.dispose();
    _customizationFocus.dispose();
    _setupFocus.dispose();
    _calibrationFocus.dispose();
    _diagnosticsFocus.dispose();
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
    _githubTokenFocus.dispose();
    _githubSaveFocus.dispose();
    _automaticUpdatesFocus.dispose();
    _checkUpdatesFocus.dispose();
    for (final node in _areaFocusNodes.values) {
      node.dispose();
    }
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
    final preferences = ref.read(settingsPreferencesProvider);
    final selectedDebridAction =
        preferences.debridProvider == DebridService.realDebrid
        ? _debridConnectFocus
        : _torBoxActionFocus;
    final selectedDebridLast =
        preferences.debridProvider == DebridService.realDebrid
        ? _tokenSaveFocus
        : _torBoxSaveFocus;
    final selectedTrackingAction =
        preferences.trackingProvider == TrackingProvider.anilist
        ? _anilistFocus
        : _malFocus;
    FocusNode? target;
    final shelfNodes = [
      for (final shelf in HomeShelf.values) _shelfFocusNodes[shelf]!,
    ];
    final shelfIndex = current == null ? -1 : shelfNodes.indexOf(current);
    final areaNodes = [
      for (final area in _SettingsArea.values) _areaFocusNodes[area]!,
    ];
    final areaIndex = current == null ? -1 : areaNodes.indexOf(current);

    if (areaIndex >= 0) {
      if (key == LogicalKeyboardKey.arrowLeft && areaIndex > 0) {
        target = areaNodes[areaIndex - 1];
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          areaIndex < areaNodes.length - 1) {
        target = areaNodes[areaIndex + 1];
      }
      if (key == LogicalKeyboardKey.arrowUp) target = _titleLanguageFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = switch (_activeArea) {
          _SettingsArea.customize => shelfNodes.first,
          _SettingsArea.streaming => _debridProviderFocus,
          _SettingsArea.tracking => _trackingProviderFocus,
          _SettingsArea.appearance => _appearanceFocus,
          _SettingsArea.system => _setupFocus,
        };
      }
    } else if (shelfIndex >= 0) {
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
        target = _customizationFocus;
      }
    }

    if (areaIndex >= 0 || shelfIndex >= 0) {
      // Shelf navigation was handled above.
    } else if (current == _backFocus) {
      if (key == LogicalKeyboardKey.arrowRight) {
        target = _titleLanguageFocus;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _areaFocusNodes[_activeArea];
      }
    } else if (current == _titleLanguageFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _backFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _areaFocusNodes[_activeArea];
      }
    } else if (current == _debridProviderFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.streaming];
      }
      if (key == LogicalKeyboardKey.arrowDown) target = selectedDebridAction;
    } else if (current == _debridConnectFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _backFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _debridProviderFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _tokenFocus.context == null
            ? _debridStreamsFocus
            : _tokenFocus;
      }
    } else if (current == _tokenFocus) {
      if (key == LogicalKeyboardKey.arrowRight) target = _tokenSaveFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _debridConnectFocus;
    } else if (current == _tokenSaveFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _tokenFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _debridConnectFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _debridStreamsFocus;
      }
    } else if (current == _torBoxActionFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _debridProviderFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _torBoxTokenFocus.context == null
            ? _debridStreamsFocus
            : _torBoxTokenFocus;
      }
    } else if (current == _torBoxTokenFocus) {
      if (key == LogicalKeyboardKey.arrowRight) target = _torBoxSaveFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _torBoxActionFocus;
    } else if (current == _torBoxSaveFocus) {
      if (key == LogicalKeyboardKey.arrowLeft) target = _torBoxTokenFocus;
      if (key == LogicalKeyboardKey.arrowUp) target = _torBoxActionFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _debridStreamsFocus;
      }
    } else if (current == _debridStreamsFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = selectedDebridLast;
      if (key == LogicalKeyboardKey.arrowRight) target = _webStreamsFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _marketplaceFocus;
    } else if (current == _webStreamsFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = selectedDebridLast;
      if (key == LogicalKeyboardKey.arrowLeft) target = _debridStreamsFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _marketplaceFocus;
    } else if (current == _marketplaceFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _debridStreamsFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _trackingProviderFocus;
    } else if (current == _trackingProviderFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.tracking];
      }
      if (key == LogicalKeyboardKey.arrowDown) target = selectedTrackingAction;
    } else if (current == _anilistFocus) {
      if (key == LogicalKeyboardKey.arrowDown &&
          _anilistTokenFocus.context != null) {
        target = _anilistTokenFocus;
      }
      if (key == LogicalKeyboardKey.arrowUp) target = _trackingProviderFocus;
    } else if (current == _malFocus) {
      if (key == LogicalKeyboardKey.arrowDown &&
          _malTokenFocus.context != null) {
        target = _malTokenFocus;
      }
      if (key == LogicalKeyboardKey.arrowUp) target = _trackingProviderFocus;
    } else if (current == _anilistTokenFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _anilistFocus;
      if (key == LogicalKeyboardKey.arrowRight) target = _anilistSaveFocus;
    } else if (current == _anilistSaveFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _anilistFocus;
      if (key == LogicalKeyboardKey.arrowLeft) target = _anilistTokenFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _appearanceFocus;
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
      if (key == LogicalKeyboardKey.arrowDown) target = _appearanceFocus;
    } else if (current == _setupFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.system];
      }
      if (key == LogicalKeyboardKey.arrowRight) target = _calibrationFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _githubTokenFocus;
    } else if (current == _calibrationFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.system];
      }
      if (key == LogicalKeyboardKey.arrowLeft) target = _setupFocus;
      if (key == LogicalKeyboardKey.arrowRight) target = _diagnosticsFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _githubTokenFocus;
    } else if (current == _diagnosticsFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _areaFocusNodes[_SettingsArea.system];
      }
      if (key == LogicalKeyboardKey.arrowLeft) target = _calibrationFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _githubTokenFocus;
    } else if (current == _githubTokenFocus) {
      if (key == LogicalKeyboardKey.arrowUp) {
        target = _setupFocus;
      }
      if (key == LogicalKeyboardKey.arrowRight) target = _githubSaveFocus;
      if (key == LogicalKeyboardKey.arrowDown) {
        target = _automaticUpdatesFocus;
      }
    } else if (current == _githubSaveFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _malSaveFocus;
      if (key == LogicalKeyboardKey.arrowLeft) target = _githubTokenFocus;
      if (key == LogicalKeyboardKey.arrowDown) target = _checkUpdatesFocus;
    } else if (current == _automaticUpdatesFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _githubTokenFocus;
      if (key == LogicalKeyboardKey.arrowRight) target = _checkUpdatesFocus;
    } else if (current == _checkUpdatesFocus) {
      if (key == LogicalKeyboardKey.arrowUp) target = _githubSaveFocus;
      if (key == LogicalKeyboardKey.arrowLeft) {
        target = _automaticUpdatesFocus;
      }
    }

    if (target == null || target.context == null) {
      return KeyEventResult.ignored;
    }
    target.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = target?.context;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 160),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final debrid = ref.watch(realDebridSettingsControllerProvider);
    final torBox = ref.watch(torBoxSettingsControllerProvider);
    final tracking = ref.watch(trackingAccountsControllerProvider);
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    final homeShelves = ref.watch(homeShelfPreferencesProvider);
    final appUpdate = ref.watch(appUpdateControllerProvider);
    final preferences = ref.watch(settingsPreferencesProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        minimum: context.responsiveScreenPadding,
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: _handleKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final showSecurityLabel = constraints.maxWidth >= 1180;
                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _TvIconButton(
                              autofocus: true,
                              focusNode: _backFocus,
                              icon: Icons.arrow_back_rounded,
                              onPressed: context.pop,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Settings',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: AppColors.cyan,
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        _TitleLanguageToggle(
                          focusNode: _titleLanguageFocus,
                          preference: titlePreference,
                          onPressed: () => ref
                              .read(titleLanguagePreferenceProvider.notifier)
                              .toggle(),
                        ),
                      ],
                    );
                  }
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
                          'Settings',
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
              const SizedBox(height: 12),
              _SettingsAreaTabs(
                selected: _activeArea,
                focusNodes: _areaFocusNodes,
                onSelected: (area) => setState(() => _activeArea = area),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
                  ),
                  children: [
                    if (_activeArea == _SettingsArea.customize) ...[
                      const _SectionHeader(
                        icon: Icons.tune_rounded,
                        title: 'CUSTOMIZE TETOTV',
                        subtitle:
                            'Choose navigation shortcuts, Home layout, and visible content.',
                      ),
                      const SizedBox(height: 8),
                      _Panel(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final label = const SizedBox(
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
                            );
                            final toggles = Wrap(
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
                            );
                            if (constraints.maxWidth < 600) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  label,
                                  const SizedBox(height: 10),
                                  toggles,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                label,
                                Expanded(child: toggles),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      _CustomizationPanel(
                        preferences: preferences,
                        controller: ref.read(
                          settingsPreferencesProvider.notifier,
                        ),
                        firstFocusNode: _customizationFocus,
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_activeArea == _SettingsArea.streaming) ...[
                      const _SectionHeader(
                        icon: Icons.cloud_done_rounded,
                        title: 'DEBRID STREAMING',
                        subtitle:
                            'Choose the provider used to resolve streams.',
                      ),
                      const SizedBox(height: 8),
                      _SettingsSelection<DebridService>(
                        focusNode: _debridProviderFocus,
                        label: 'Debrid provider',
                        value: preferences.debridProvider,
                        options: [
                          for (final service in DebridService.values)
                            _SettingsOption(
                              value: service,
                              label: service.displayName,
                              detail:
                                  (service == DebridService.realDebrid
                                      ? debrid.hasSavedToken
                                      : torBox.hasSavedToken)
                                  ? 'Connected'
                                  : 'Not connected',
                            ),
                        ],
                        onSelected: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setDebridProvider,
                      ),
                      const SizedBox(height: 8),
                      if (preferences.debridProvider ==
                          DebridService.realDebrid)
                        _RealDebridPanel(
                          state: debrid,
                          tokenController: _tokenController,
                          onSave: () async {
                            final saved = await ref
                                .read(
                                  realDebridSettingsControllerProvider.notifier,
                                )
                                .saveAndValidate(_tokenController.text);
                            if (saved) _tokenController.clear();
                          },
                          onDisconnect: () => ref
                              .read(
                                realDebridSettingsControllerProvider.notifier,
                              )
                              .disconnect(),
                          onDeviceConnect: () =>
                              context.push('/pair/realdebrid'),
                          connectFocusNode: _debridConnectFocus,
                          tokenFocusNode: _tokenFocus,
                          saveFocusNode: _tokenSaveFocus,
                        )
                      else
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
                        icon: Icons.stream_rounded,
                        title: 'STREAM SOURCES',
                        subtitle:
                            'Choose which source types are searched for each episode.',
                      ),
                      const SizedBox(height: 8),
                      _StreamingSourcesPanel(
                        preferences: preferences,
                        debridFocusNode: _debridStreamsFocus,
                        webFocusNode: _webStreamsFocus,
                        marketplaceFocusNode: _marketplaceFocus,
                        onDebridChanged: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setDebridStreamsEnabled,
                        onWebChanged: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setWebStreamsEnabled,
                        onMarketplace: () =>
                            context.push('/settings/marketplace'),
                      ),
                      const SizedBox(height: 14),
                      const _DebridOnlyPanel(),
                      const SizedBox(height: 10),
                    ],
                    if (_activeArea == _SettingsArea.tracking) ...[
                      const _SectionHeader(
                        icon: Icons.sync_alt_rounded,
                        title: 'ANIME TRACKING',
                        subtitle: 'Configure one list service at a time.',
                      ),
                      const SizedBox(height: 8),
                      _SettingsSelection<TrackingProvider>(
                        focusNode: _trackingProviderFocus,
                        label: 'Anime-list provider',
                        value: preferences.trackingProvider,
                        options: [
                          for (final provider in TrackingProvider.values)
                            _SettingsOption(
                              value: provider,
                              label: provider.displayName,
                              detail: tracking.isConnected(provider)
                                  ? 'Connected as ${tracking.usernames[provider]}'
                                  : 'Not connected',
                            ),
                        ],
                        onSelected: ref
                            .read(settingsPreferencesProvider.notifier)
                            .setTrackingProvider,
                      ),
                      const SizedBox(height: 8),
                      _TrackingPanel(
                        provider: preferences.trackingProvider,
                        color:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? AppColors.accentBright
                            : const Color(0xFFB41F3D),
                        description:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? 'Seasonal discovery, lists, and automatic episode progress.'
                            : 'Sync watch progress and MyAnimeList statuses automatically.',
                        username:
                            tracking.usernames[preferences.trackingProvider],
                        error: tracking.errors[preferences.trackingProvider],
                        isLoading: tracking.isLoading,
                        onConnect: () async {
                          await context.push(
                            preferences.trackingProvider ==
                                    TrackingProvider.anilist
                                ? '/pair/anilist'
                                : '/pair/myanimelist',
                          );
                          await ref
                              .read(trackingAccountsControllerProvider.notifier)
                              .load();
                        },
                        onDisconnect: () => ref
                            .read(trackingAccountsControllerProvider.notifier)
                            .disconnect(preferences.trackingProvider),
                        onSaveToken: (token) => ref
                            .read(trackingAccountsControllerProvider.notifier)
                            .save(preferences.trackingProvider, token),
                        focusNode:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? _anilistFocus
                            : _malFocus,
                        tokenFocusNode:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? _anilistTokenFocus
                            : _malTokenFocus,
                        saveFocusNode:
                            preferences.trackingProvider ==
                                TrackingProvider.anilist
                            ? _anilistSaveFocus
                            : _malSaveFocus,
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_activeArea == _SettingsArea.appearance) ...[
                      const _SectionHeader(
                        icon: Icons.palette_outlined,
                        title: 'APPEARANCE & CONTROLS',
                        subtitle:
                            'Tune captions, card density, interface scale, and seeking.',
                      ),
                      const SizedBox(height: 8),
                      _AppearancePanel(
                        preferences: preferences,
                        firstFocusNode: _appearanceFocus,
                        controller: ref.read(
                          settingsPreferencesProvider.notifier,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_activeArea == _SettingsArea.system) ...[
                      const _SectionHeader(
                        icon: Icons.memory_rounded,
                        title: 'SYSTEM & SUPPORT',
                        subtitle:
                            'Setup, device compatibility, diagnostics, and app updates.',
                      ),
                      const SizedBox(height: 8),
                      _Panel(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final actions = [
                              _TvTextButton(
                                label: 'Run setup again',
                                icon: Icons.auto_awesome_rounded,
                                focusNode: _setupFocus,
                                onPressed: () => context.push('/setup'),
                              ),
                              _TvTextButton(
                                label: 'Device calibration',
                                icon: Icons.tune_rounded,
                                focusNode: _calibrationFocus,
                                onPressed: () =>
                                    context.push('/settings/device-setup'),
                              ),
                              _TvTextButton(
                                label: 'Diagnostics',
                                icon: Icons.monitor_heart_outlined,
                                focusNode: _diagnosticsFocus,
                                onPressed: () =>
                                    context.push('/settings/diagnostics'),
                              ),
                            ];
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: actions,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _SectionHeader(
                        icon: Icons.system_update_alt_rounded,
                        title: 'APP UPDATES',
                        subtitle:
                            'Private GitHub releases, downloaded directly to this device.',
                      ),
                      const SizedBox(height: 8),
                      _AppUpdatePanel(
                        state: appUpdate,
                        tokenController: _githubTokenController,
                        tokenFocusNode: _githubTokenFocus,
                        saveFocusNode: _githubSaveFocus,
                        automaticFocusNode: _automaticUpdatesFocus,
                        checkFocusNode: _checkUpdatesFocus,
                        onSaveToken: () async {
                          await ref
                              .read(appUpdateControllerProvider.notifier)
                              .saveAccessToken(_githubTokenController.text);
                          _githubTokenController.clear();
                        },
                        onRemoveToken: () => ref
                            .read(appUpdateControllerProvider.notifier)
                            .saveAccessToken(''),
                        onToggleAutomatic: () => ref
                            .read(appUpdateControllerProvider.notifier)
                            .setAutomaticUpdates(!appUpdate.automaticUpdates),
                        onCheckOrInstall: () {
                          final controller = ref.read(
                            appUpdateControllerProvider.notifier,
                          );
                          if (appUpdate.downloadedPath != null) {
                            controller.installDownloadedUpdate();
                          } else {
                            controller.checkForUpdates(launchInstaller: true);
                          }
                        },
                      ),
                    ],
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

class _SettingsAreaTabs extends StatelessWidget {
  const _SettingsAreaTabs({
    required this.selected,
    required this.focusNodes,
    required this.onSelected,
  });

  final _SettingsArea selected;
  final Map<_SettingsArea, FocusNode> focusNodes;
  final ValueChanged<_SettingsArea> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        itemCount: _SettingsArea.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final area = _SettingsArea.values[index];
          final active = area == selected;
          final (icon, label) = switch (area) {
            _SettingsArea.customize => (Icons.tune_rounded, 'Customize'),
            _SettingsArea.streaming => (Icons.play_circle_outline, 'Streaming'),
            _SettingsArea.tracking => (Icons.sync_alt_rounded, 'Tracking'),
            _SettingsArea.appearance => (Icons.palette_outlined, 'Appearance'),
            _SettingsArea.system => (Icons.memory_rounded, 'System'),
          };
          return TvFocusable(
            focusNode: focusNodes[area],
            onPressed: () => onSelected(area),
            focusScale: 1.02,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? AppColors.accent : AppColors.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active
                      ? AppColors.accentBright
                      : Colors.white.withValues(alpha: .08),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 19),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SettingsOption<T> {
  const _SettingsOption({
    required this.value,
    required this.label,
    required this.detail,
  });

  final T value;
  final String label;
  final String detail;
}

class _SettingsSelection<T> extends StatelessWidget {
  const _SettingsSelection({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.focusNode,
  });

  final String label;
  final T value;
  final List<_SettingsOption<T>> options;
  final ValueChanged<T> onSelected;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere((option) => option.value == value);
    return TvFocusable(
      focusNode: focusNode,
      onPressed: () async {
        final result = await showDialog<T>(
          context: context,
          barrierDismissible: true,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 560,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: .7),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  for (final option in options) ...[
                    TvFocusable(
                      autofocus: option.value == value,
                      onPressed: () => Navigator.of(context).pop(option.value),
                      borderRadius: BorderRadius.circular(9),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: option.value == value
                              ? AppColors.accent.withValues(alpha: .28)
                              : AppColors.panelRaised,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              option.value == value
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: option.value == value
                                  ? AppColors.accentBright
                                  : AppColors.textMuted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    option.detail,
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (option != options.last) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        );
        if (result != null) onSelected(result);
      },
      borderRadius: BorderRadius.circular(10),
      focusScale: 1.01,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final value = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selected.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  selected.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            );
            if (constraints.maxWidth < 560) {
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        value,
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: AppColors.accentBright,
                  ),
                ],
              );
            }
            return Row(
              children: [
                SizedBox(
                  width: 180,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(child: value),
                const SizedBox(width: 12),
                const Icon(
                  Icons.expand_more_rounded,
                  color: AppColors.accentBright,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CustomizationPanel extends StatelessWidget {
  const _CustomizationPanel({
    required this.preferences,
    required this.controller,
    required this.firstFocusNode,
  });

  final SettingsPreferences preferences;
  final SettingsPreferencesController controller;
  final FocusNode firstFocusNode;

  @override
  Widget build(BuildContext context) {
    Widget toggle({
      required String label,
      required bool value,
      required ValueChanged<bool> onChanged,
      FocusNode? focusNode,
    }) => _PreferenceChip(
      label: '$label ${value ? 'ON' : 'OFF'}',
      selected: value,
      focusNode: focusNode,
      onPressed: () => onChanged(!value),
    );

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _MiniSectionLabel('HOME LAYOUT'),
          _PreferenceRow(
            label: 'Layout style',
            children: [
              for (final layout in HomeLayout.values)
                _PreferenceChip(
                  label: layout.displayName,
                  selected: preferences.homeLayout == layout,
                  onPressed: () => controller.setHomeLayout(layout),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Home content',
            children: [
              toggle(
                label: 'Featured',
                value: preferences.showHero,
                onChanged: controller.setShowHero,
              ),
              toggle(
                label: 'Poster badges',
                value: preferences.showPosterMetadata,
                onChanged: controller.setShowPosterMetadata,
              ),
              toggle(
                label: 'Card details',
                value: preferences.showCardSubtitles,
                onChanged: controller.setShowCardSubtitles,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.white.withValues(alpha: .07), height: 1),
          const SizedBox(height: 8),
          const _MiniSectionLabel('TOP NAVIGATION'),
          _PreferenceRow(
            label: 'Visible shortcuts',
            children: [
              toggle(
                label: 'Search',
                value: preferences.showSearch,
                onChanged: controller.setShowSearch,
                focusNode: firstFocusNode,
              ),
              toggle(
                label: 'My List',
                value: preferences.showMyList,
                onChanged: controller.setShowMyList,
              ),
              toggle(
                label: 'Discover',
                value: preferences.showDiscover,
                onChanged: controller.setShowDiscover,
              ),
              toggle(
                label: 'Calendar',
                value: preferences.showCalendar,
                onChanged: controller.setShowCalendar,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: _TvTextButton(
              label: 'Reset customization',
              icon: Icons.restart_alt_rounded,
              onPressed: controller.resetCustomization,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniSectionLabel extends StatelessWidget {
  const _MiniSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: AppColors.accentBright,
      fontSize: 9,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.1,
    ),
  );
}

class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({
    required this.preferences,
    required this.controller,
    required this.firstFocusNode,
  });

  final SettingsPreferences preferences;
  final SettingsPreferencesController controller;
  final FocusNode firstFocusNode;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        children: [
          _PreferenceRow(
            label: 'On-screen keyboard',
            children: [
              _PreferenceChip(
                label: 'Built-in',
                selected: preferences.useBuiltInKeyboard,
                focusNode: firstFocusNode,
                onPressed: () => controller.setUseBuiltInKeyboard(true),
              ),
              _PreferenceChip(
                label: 'Device keyboard',
                selected: !preferences.useBuiltInKeyboard,
                onPressed: () => controller.setUseBuiltInKeyboard(false),
              ),
            ],
          ),
          _PreferenceRow(
            label: 'Caption text',
            children: [
              for (final option in const [
                (0xFFFFFFFF, 'White'),
                (0xFFFFFF66, 'Yellow'),
                (0xFF66E7FF, 'Cyan'),
              ])
                _PreferenceChip(
                  label: option.$2,
                  selected: preferences.captionTextColor == option.$1,
                  swatch: Color(option.$1),
                  onPressed: () => controller.setCaptionTextColor(option.$1),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Caption background',
            children: [
              for (final option in const [
                (0x00000000, 'Off'),
                (0x99000000, 'Dark'),
                (0xDD000000, 'Strong'),
              ])
                _PreferenceChip(
                  label: option.$2,
                  selected: preferences.captionBackgroundColor == option.$1,
                  swatch: Color(option.$1),
                  onPressed: () =>
                      controller.setCaptionBackgroundColor(option.$1),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Caption size',
            children: [
              for (final size in const [28.0, 34.0, 42.0, 50.0])
                _PreferenceChip(
                  label: '${size.round()}',
                  selected: preferences.captionTextSize == size,
                  onPressed: () => controller.setCaptionTextSize(size),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Thumbnail size',
            children: [
              for (final option in const [
                (.85, 'Small'),
                (1.0, 'Medium'),
                (1.15, 'Large'),
              ])
                _PreferenceChip(
                  label: option.$2,
                  selected: preferences.thumbnailScale == option.$1,
                  onPressed: () => controller.setThumbnailScale(option.$1),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Interface scale',
            children: [
              for (final option in const [
                (.9, '90%'),
                (1.0, '100%'),
                (1.1, '110%'),
              ])
                _PreferenceChip(
                  label: option.$2,
                  selected: preferences.interfaceScale == option.$1,
                  onPressed: () => controller.setInterfaceScale(option.$1),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Content density',
            children: [
              for (final density in ContentDensity.values)
                _PreferenceChip(
                  label: density.displayName,
                  selected: preferences.contentDensity == density,
                  onPressed: () => controller.setContentDensity(density),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Rewind',
            children: [
              for (final seconds in const [5, 10, 15, 30, 60])
                _PreferenceChip(
                  label: '${seconds}s',
                  selected: preferences.seekBackSeconds == seconds,
                  onPressed: () => controller.setSeekBackSeconds(seconds),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Fast-forward',
            children: [
              for (final seconds in const [5, 10, 15, 30, 60])
                _PreferenceChip(
                  label: '${seconds}s',
                  selected: preferences.seekForwardSeconds == seconds,
                  onPressed: () => controller.setSeekForwardSeconds(seconds),
                ),
            ],
          ),
          _PreferenceRow(
            label: 'Auto-skip intro',
            children: [
              _PreferenceChip(
                label: preferences.autoSkipIntros ? 'On' : 'Off',
                selected: preferences.autoSkipIntros,
                onPressed: () =>
                    controller.setAutoSkipIntros(!preferences.autoSkipIntros),
              ),
            ],
          ),
          _PreferenceRow(
            label: 'Auto-skip outro',
            children: [
              _PreferenceChip(
                label: preferences.autoSkipOutros ? 'On' : 'Off',
                selected: preferences.autoSkipOutros,
                onPressed: () =>
                    controller.setAutoSkipOutros(!preferences.autoSkipOutros),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerRight,
            child: _TvTextButton(
              label: 'Reset appearance',
              icon: Icons.restart_alt_rounded,
              onPressed: controller.resetAppearance,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingSourcesPanel extends StatelessWidget {
  const _StreamingSourcesPanel({
    required this.preferences,
    required this.debridFocusNode,
    required this.webFocusNode,
    required this.marketplaceFocusNode,
    required this.onDebridChanged,
    required this.onWebChanged,
    required this.onMarketplace,
  });

  final SettingsPreferences preferences;
  final FocusNode debridFocusNode;
  final FocusNode webFocusNode;
  final FocusNode marketplaceFocusNode;
  final ValueChanged<bool> onDebridChanged;
  final ValueChanged<bool> onWebChanged;
  final VoidCallback onMarketplace;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sources = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PreferenceChip(
                label:
                    'DEBRID ${preferences.debridStreamsEnabled ? 'ON' : 'OFF'}',
                selected: preferences.debridStreamsEnabled,
                focusNode: debridFocusNode,
                onPressed: () =>
                    onDebridChanged(!preferences.debridStreamsEnabled),
              ),
              _PreferenceChip(
                label: 'WEB ${preferences.webStreamsEnabled ? 'ON' : 'OFF'}',
                selected: preferences.webStreamsEnabled,
                focusNode: webFocusNode,
                onPressed: () => onWebChanged(!preferences.webStreamsEnabled),
              ),
            ],
          );
          final marketplace = _TvTextButton(
            label: 'Marketplace',
            icon: Icons.storefront_outlined,
            focusNode: marketplaceFocusNode,
            onPressed: onMarketplace,
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [sources, const SizedBox(height: 10), marketplace],
            );
          }
          return Row(
            children: [
              Expanded(child: sources),
              marketplace,
            ],
          );
        },
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final options = Wrap(spacing: 7, runSpacing: 7, children: children);
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                options,
              ],
            );
          }
          return Row(
            children: [
              SizedBox(
                width: 180,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(child: options),
            ],
          );
        },
      ),
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  const _PreferenceChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    this.focusNode,
    this.swatch,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      onPressed: onPressed,
      focusScale: 1.04,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 31,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.panelRaised,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? AppColors.accentBright
                : Colors.white.withValues(alpha: .1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatch case final color?) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppUpdatePanel extends StatelessWidget {
  const _AppUpdatePanel({
    required this.state,
    required this.tokenController,
    required this.tokenFocusNode,
    required this.saveFocusNode,
    required this.automaticFocusNode,
    required this.checkFocusNode,
    required this.onSaveToken,
    required this.onRemoveToken,
    required this.onToggleAutomatic,
    required this.onCheckOrInstall,
  });

  final AppUpdateState state;
  final TextEditingController tokenController;
  final FocusNode tokenFocusNode;
  final FocusNode saveFocusNode;
  final FocusNode automaticFocusNode;
  final FocusNode checkFocusNode;
  final VoidCallback onSaveToken;
  final VoidCallback onRemoveToken;
  final VoidCallback onToggleAutomatic;
  final VoidCallback onCheckOrInstall;

  @override
  Widget build(BuildContext context) {
    final latest = state.latestVersion;
    final status =
        state.message ??
        'Current ${state.currentVersion}'
            '${latest == null ? '' : ' • Latest $latest'}';
    final checkLabel = switch (state.phase) {
      AppUpdatePhase.checking => 'Checking…',
      AppUpdatePhase.downloading =>
        'Downloading ${(state.progress * 100).round()}%',
      AppUpdatePhase.installing => 'Opening installer…',
      AppUpdatePhase.ready => 'Install update',
      _ => 'Check for updates',
    };
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: AppColors.accentBright,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'TetoTV ${state.currentVersion}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        _StatusPill(
                          connected: state.hasAccessToken,
                          label: state.hasAccessToken
                              ? 'PRIVATE RELEASES READY'
                              : 'TOKEN REQUIRED',
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Uses a fine-grained GitHub token with read-only Contents '
                      'access. The token stays encrypted on this TV.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.white.withValues(alpha: .08), height: 1),
          const SizedBox(height: 10),
          _ResponsiveTokenRow(
            title: 'Private GitHub token',
            input: TvTextInput(
              focusNode: tokenFocusNode,
              controller: tokenController,
              labelText: 'Read-only GitHub token',
              hintText: state.hasAccessToken
                  ? 'Saved — select to replace'
                  : 'Select to enter or paste',
              keyboardTitle: 'Private GitHub update token',
              obscureText: true,
              onSubmitted: (_) => onSaveToken(),
            ),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TvTextButton(
                  label: state.hasAccessToken ? 'Replace' : 'Save token',
                  icon: Icons.lock_rounded,
                  onPressed: onSaveToken,
                  focusNode: saveFocusNode,
                ),
                if (state.hasAccessToken) ...[
                  const SizedBox(width: 7),
                  _TvTextButton(
                    label: 'Remove',
                    icon: Icons.delete_outline_rounded,
                    onPressed: onRemoveToken,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: state.phase == AppUpdatePhase.error
                  ? const Color(0xFFFF929B)
                  : AppColors.textMuted,
              fontSize: 10,
            ),
          ),
          if (state.release?.notes.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white.withValues(alpha: .07)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WHAT’S NEW',
                    style: TextStyle(
                      color: AppColors.accentBright,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.release!.notes.trim(),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _TvTextButton(
                  label: state.automaticUpdates
                      ? 'Automatic: ON'
                      : 'Automatic: OFF',
                  icon: state.automaticUpdates
                      ? Icons.autorenew_rounded
                      : Icons.update_disabled_rounded,
                  onPressed: state.isBusy ? null : onToggleAutomatic,
                  focusNode: automaticFocusNode,
                ),
                _TvTextButton(
                  label: checkLabel,
                  icon: state.downloadedPath == null
                      ? Icons.refresh_rounded
                      : Icons.install_mobile_rounded,
                  onPressed: state.isBusy || !state.hasAccessToken
                      ? null
                      : onCheckOrInstall,
                  focusNode: checkFocusNode,
                ),
              ],
            ),
          ),
          if (state.phase == AppUpdatePhase.downloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: state.progress > 0 ? state.progress : null,
              color: AppColors.accentBright,
              backgroundColor: const Color(0xFF2A2A2A),
            ),
          ],
        ],
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

class _ServiceAccountHeader extends StatelessWidget {
  const _ServiceAccountHeader({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.status,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final List<Color> gradient;
  final String title;
  final Widget status;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final summary = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.ink, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  status,
                ],
              ),
              const SizedBox(height: 3),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summary,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: summary),
            const SizedBox(width: 12),
            action,
          ],
        );
      },
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
          _ServiceAccountHeader(
            icon: Icons.cloud_download_rounded,
            gradient: const [AppColors.accent, AppColors.cyan],
            title: 'Real-Debrid',
            status: _StatusPill(
              connected: account != null,
              label: account == null
                  ? state.hasSavedToken
                        ? 'RECONNECTING'
                        : 'NOT CONNECTED'
                  : account.isPremium
                  ? 'PREMIUM'
                  : account.type.toUpperCase(),
            ),
            description: account == null
                ? 'Authorize on your phone, or use a personal API token below.'
                : 'Connected as ${account.username}. Cached torrents will '
                      'resolve almost instantly.',
            action: account == null
                ? _TvTextButton(
                    label: 'Connect by QR',
                    icon: Icons.qr_code_rounded,
                    onPressed: onDeviceConnect,
                    focusNode: connectFocusNode,
                  )
                : _TvTextButton(
                    label: 'Disconnect',
                    icon: Icons.link_off_rounded,
                    onPressed: onDisconnect,
                    focusNode: connectFocusNode,
                  ),
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
          _ServiceAccountHeader(
            icon: Icons.cloud_circle_rounded,
            gradient: const [AppColors.accent, AppColors.accentBright],
            title: 'TorBox',
            status: _StatusPill(
              connected: account != null,
              label: account == null
                  ? state.hasSavedToken
                        ? 'RECONNECTING'
                        : 'NOT CONNECTED'
                  : account.planName.toUpperCase(),
            ),
            description: account == null
                ? 'Authorize with a QR code, or enter a TorBox API token below.'
                : 'Connected as ${account.email}. Torrent files are resolved '
                      'and streamed through TorBox only.',
            action: account == null
                ? _TvTextButton(
                    label: 'Connect by QR',
                    icon: Icons.qr_code_rounded,
                    onPressed: onDeviceConnect,
                    focusNode: actionFocusNode,
                  )
                : _TvTextButton(
                    label: 'Disconnect',
                    icon: Icons.link_off_rounded,
                    onPressed: onDisconnect,
                    focusNode: actionFocusNode,
                  ),
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
                  'Protected streaming paths',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 3),
                Text(
                  'Torrents are only played through Real-Debrid or TorBox. '
                  'Installed web addons run without access to account tokens '
                  'or device files.',
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
        final fieldAndAction = constraints.maxWidth < 600
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  input,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              )
            : Row(
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
