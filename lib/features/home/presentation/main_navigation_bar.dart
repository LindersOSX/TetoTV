import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/tv/tv_shelf_focus.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum MainNavigationDestination { home, myList, discover, calendar }

/// The shared geometry contract for the Modern Layout navigation rail.
///
/// Keeping the black rail surface, divider, logo, and actions in one immutable
/// value prevents the surrounding content inset from drifting away from the
/// selected Small/Medium/Large chrome size.
@immutable
class HomeNavigationRailMetrics {
  const HomeNavigationRailMetrics({
    required this.width,
    required this.actionWidth,
    required this.actionHeight,
    required this.iconSize,
    required this.logoSize,
    required this.actionGap,
  });

  final double width;
  final double actionWidth;
  final double actionHeight;
  final double iconSize;
  final double logoSize;
  final double actionGap;
}

/// Resolves all rail geometry from the persisted chrome size.
///
/// The black surface wraps the logo with a small gutter based on the action
/// spacing. It therefore changes with Small/Medium/Large but does not become
/// disproportionately wide merely because the TV canvas is wider.
HomeNavigationRailMetrics homeNavigationRailMetrics(NavigationChromeSize size) {
  final double actionWidth = switch (size) {
    NavigationChromeSize.small => 30,
    NavigationChromeSize.medium => 38,
    NavigationChromeSize.large => 48,
  };
  final double actionHeight = switch (size) {
    NavigationChromeSize.small => 28,
    NavigationChromeSize.medium => 36,
    NavigationChromeSize.large => 44,
  };
  final double iconSize = switch (size) {
    NavigationChromeSize.small => 17,
    NavigationChromeSize.medium => 20,
    NavigationChromeSize.large => 25,
  };
  final double logoSize = switch (size) {
    NavigationChromeSize.small => 34,
    NavigationChromeSize.medium => 42,
    NavigationChromeSize.large => 52,
  };
  final double actionGap = switch (size) {
    NavigationChromeSize.small => 5,
    NavigationChromeSize.medium => 7,
    NavigationChromeSize.large => 8,
  };
  final width = logoSize + ((actionGap + 2) * 2);

  return HomeNavigationRailMetrics(
    width: width,
    actionWidth: actionWidth,
    actionHeight: actionHeight,
    iconSize: iconSize,
    logoSize: logoSize,
    actionGap: actionGap,
  );
}

double homeNavigationRailWidth(double _, NavigationChromeSize size) =>
    homeNavigationRailMetrics(size).width;

/// Home's fixed TV rail. The existing [MainNavigationBar] remains available
/// to compact layouts and the other top-level screens, while Home can match the
/// reference's icon-first 10-foot layout without changing those screens.
class HomeSideNavigation extends ConsumerStatefulWidget {
  const HomeSideNavigation({
    required this.preferences,
    required this.onExitRight,
    this.activeDestination = TopNavigationDestination.home,
    this.activeFocusNode,
    this.onActivePressed,
    this.autofocusActive = false,
    this.onHomePressed,
    this.homeFocusNode,
    this.onFocusChanged,
    required this.metrics,
    super.key,
  });

  final SettingsPreferences preferences;
  final VoidCallback onExitRight;
  final TopNavigationDestination activeDestination;
  final FocusNode? activeFocusNode;
  final VoidCallback? onActivePressed;
  final bool autofocusActive;
  final VoidCallback? onHomePressed;
  final FocusNode? homeFocusNode;
  final ValueChanged<bool>? onFocusChanged;
  final HomeNavigationRailMetrics metrics;

  @override
  ConsumerState<HomeSideNavigation> createState() => _HomeSideNavigationState();
}

class _HomeSideNavigationState extends ConsumerState<HomeSideNavigation> {
  final _repeatGate = TvDirectionalRepeatGate();
  bool _focusRecoveryScheduled = false;
  final _fallbackNodes = <TopNavigationDestination, FocusNode>{
    for (final destination in TopNavigationDestination.values)
      destination: FocusNode(debugLabel: 'home.navigation.${destination.name}'),
  };
  List<TopNavigationDestination> _visibleDestinations = const [];
  TopNavigationDestination? _activeFocusDestination;

  TopNavigationDestination? _nearestVisibleDestination() {
    if (_visibleDestinations.isEmpty) return null;
    final order = widget.preferences.topNavigationOrder;
    final activeIndex = order.indexOf(widget.activeDestination);
    if (activeIndex < 0) return _visibleDestinations.first;
    for (var distance = 1; distance < order.length; distance++) {
      final after = activeIndex + distance;
      if (after < order.length && _visibleDestinations.contains(order[after])) {
        return order[after];
      }
      final before = activeIndex - distance;
      if (before >= 0 && _visibleDestinations.contains(order[before])) {
        return order[before];
      }
    }
    return _visibleDestinations.first;
  }

  void _recoverDetachedFocusAfterBuild() {
    if (!widget.autofocusActive || _focusRecoveryScheduled) return;
    _focusRecoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRecoveryScheduled = false;
      if (!mounted || !widget.autofocusActive) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary.context != null) return;
      final destination = _activeFocusDestination;
      if (destination == null) {
        widget.onExitRight();
      } else {
        _nodeFor(destination).requestFocus();
      }
    });
  }

  FocusNode _nodeFor(TopNavigationDestination destination) {
    if (destination == _activeFocusDestination) {
      final activeNode =
          widget.activeFocusNode ??
          (widget.activeDestination == TopNavigationDestination.home
              ? widget.homeFocusNode
              : null);
      if (activeNode != null) return activeNode;
    }
    if (destination == TopNavigationDestination.home &&
        widget.homeFocusNode != null) {
      return widget.homeFocusNode!;
    }
    return _fallbackNodes[destination]!;
  }

  KeyEventResult _handleNavigationKey(
    TopNavigationDestination destination,
    KeyEvent event,
  ) {
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent || event is KeyRepeatEvent) {
        if (_repeatGate.accept(event)) widget.onExitRight();
      } else if (event is KeyUpEvent) {
        _repeatGate.accept(event);
      }
      return KeyEventResult.handled;
    }
    final offset = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowLeft => 0,
      _ => null,
    };
    if (offset == null) return KeyEventResult.ignored;
    if (event is KeyUpEvent) {
      _repeatGate.accept(event);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (offset == 0 || !_repeatGate.accept(event)) {
      return KeyEventResult.handled;
    }
    final current = _visibleDestinations.indexOf(destination);
    if (current < 0) return KeyEventResult.handled;
    final next = (current + offset).clamp(0, _visibleDestinations.length - 1);
    if (next != current) _nodeFor(_visibleDestinations[next]).requestFocus();
    return KeyEventResult.handled;
  }

  void _activateDestination(TopNavigationDestination destination) {
    if (destination == widget.activeDestination &&
        widget.onActivePressed != null) {
      widget.onActivePressed!();
      return;
    }
    switch (destination) {
      case TopNavigationDestination.search:
        context.push('/search');
      case TopNavigationDestination.home:
        (widget.onHomePressed ?? () => context.go('/'))();
      case TopNavigationDestination.myList:
        context.go('/my-list');
      case TopNavigationDestination.discover:
        context.go('/discover');
      case TopNavigationDestination.calendar:
        context.go('/calendar');
      case TopNavigationDestination.settings:
        context.push('/settings/accounts');
    }
  }

  @override
  void dispose() {
    _repeatGate.reset();
    for (final entry in _fallbackNodes.entries) {
      if (entry.key == TopNavigationDestination.home &&
          identical(entry.value, widget.homeFocusNode)) {
        continue;
      }
      entry.value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(trackingAccountsControllerProvider);
    final hasProfile = accounts.profiles.isNotEmpty;
    final settingsInProfileMenu =
        hasProfile &&
        !accounts.isLoading &&
        widget.preferences.settingsEntryPlacement ==
            SettingsEntryPlacement.profileMenu;
    _visibleDestinations = widget.preferences.topNavigationOrder
        .where(
          (destination) =>
              widget.preferences.isTopNavigationDestinationVisible(
                destination,
              ) &&
              (destination != TopNavigationDestination.settings ||
                  !settingsInProfileMenu),
        )
        .toList(growable: false);
    // Settings may deliberately live under the profile menu. When that makes
    // the current destination absent from the rail, attach the screen-owned
    // focus node to the nearest deterministic visible action instead. LEFT
    // from Settings content can then enter the rail without resurrecting the
    // hidden Settings icon or landing on a detached FocusNode.
    _activeFocusDestination =
        _visibleDestinations.contains(widget.activeDestination)
        ? widget.activeDestination
        : _nearestVisibleDestination();
    _recoverDetachedFocusAfterBuild();
    final metrics = widget.metrics;

    return Container(
      key: const ValueKey('main-navigation'),
      width: metrics.width,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .96),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: .11)),
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: metrics.actionGap + 5),
          _HomeRailWordmark(metrics: metrics),
          SizedBox(height: metrics.actionGap + 2),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final destination in _visibleDestinations) ...[
                      _HomeRailAction(
                        key: _navigationKey(destination),
                        destination: destination,
                        metrics: metrics,
                        active: destination == widget.activeDestination,
                        autofocus:
                            widget.autofocusActive &&
                            destination == _activeFocusDestination,
                        focusNode: _nodeFor(destination),
                        onKeyEvent: (_, event) =>
                            _handleNavigationKey(destination, event),
                        onFocusChanged: widget.onFocusChanged,
                        onPressed: () => _activateDestination(destination),
                      ),
                      SizedBox(height: metrics.actionGap),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

Key _navigationKey(TopNavigationDestination destination) =>
    switch (destination) {
      TopNavigationDestination.search => const ValueKey('main-nav-search'),
      TopNavigationDestination.home => const ValueKey('main-nav-home'),
      TopNavigationDestination.myList => const ValueKey('main-nav-my-list'),
      TopNavigationDestination.discover => const ValueKey('main-nav-discover'),
      TopNavigationDestination.calendar => const ValueKey('main-nav-calendar'),
      TopNavigationDestination.settings => const ValueKey('main-nav-settings'),
    };

IconData _navigationIcon(TopNavigationDestination destination) =>
    switch (destination) {
      TopNavigationDestination.search => Icons.search_rounded,
      TopNavigationDestination.home => Icons.home_rounded,
      TopNavigationDestination.myList => Icons.video_library_rounded,
      TopNavigationDestination.discover => Icons.explore_rounded,
      TopNavigationDestination.calendar => Icons.calendar_month_rounded,
      TopNavigationDestination.settings => Icons.settings_rounded,
    };

class _HomeRailWordmark extends StatelessWidget {
  const _HomeRailWordmark({required this.metrics});

  final HomeNavigationRailMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('main-nav-wordmark'),
      label: 'Teto TV',
      image: true,
      child: SizedBox(
        width: metrics.logoSize,
        height: metrics.logoSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/branding/tetotv_icon.png',
              width: metrics.logoSize,
              height: metrics.logoSize,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            const Positioned(
              left: 0,
              top: 0,
              child: Offstage(
                child: Text('Teto', key: ValueKey('main-nav-wordmark-teto')),
              ),
            ),
            const Positioned(
              right: 0,
              top: 0,
              child: Offstage(
                child: Text('TV', key: ValueKey('main-nav-wordmark-tv')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeRailAction extends StatelessWidget {
  const _HomeRailAction({
    required this.destination,
    required this.metrics,
    required this.active,
    required this.autofocus,
    required this.focusNode,
    required this.onKeyEvent,
    this.onFocusChanged,
    required this.onPressed,
    super.key,
  });

  final TopNavigationDestination destination;
  final HomeNavigationRailMetrics metrics;
  final bool active;
  final bool autofocus;
  final FocusNode focusNode;
  final FocusOnKeyEventCallback onKeyEvent;
  final ValueChanged<bool>? onFocusChanged;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = destination.displayName;
    return Tooltip(
      message: label,
      child: TvFocusable(
        autofocus: autofocus,
        focusNode: focusNode,
        onKeyEvent: onKeyEvent,
        onFocusChanged: onFocusChanged,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(8),
        focusScale: 1.035,
        child: Semantics(
          label: label,
          selected: active,
          button: true,
          excludeSemantics: true,
          child: Container(
            width: metrics.actionWidth,
            height: metrics.actionHeight,
            decoration: BoxDecoration(
              color: active
                  ? context.appPalette.accent.withValues(alpha: .19)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? context.appPalette.accentBright
                    : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Icon(
              _navigationIcon(destination),
              color: active
                  ? context.appPalette.accentBright
                  : context.appPalette.primaryText,
              size: metrics.iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// The far-right shared-TV identity control used by Home's cinematic shell.
class HomeProfileSwitcher extends ConsumerWidget {
  const HomeProfileSwitcher({
    required this.preferences,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChanged,
    super.key,
  });

  final SettingsPreferences preferences;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(trackingAccountsControllerProvider);
    final profiles = [
      for (final provider in TrackingProvider.values)
        ?accounts.profiles[provider],
    ];
    final activeProfile = profiles
        .where((profile) => profile.provider == preferences.trackingProvider)
        .firstOrNull;
    final primaryProfile = activeProfile ?? profiles.firstOrNull;
    if (primaryProfile == null) return const SizedBox.shrink();
    final savedProfiles = [
      for (final provider in TrackingProvider.values)
        ...?accounts.savedProfiles[provider],
    ];
    final showSettings =
        !accounts.isLoading &&
        preferences.settingsEntryPlacement ==
            SettingsEntryPlacement.profileMenu;

    return SizedBox(
      key: const ValueKey('home-profile-switcher'),
      width: 210,
      height: 48,
      child: _TrackerProfileMenuButton(
        profile: primaryProfile,
        savedProfiles: savedProfiles,
        activeProfileIds: accounts.activeProfileIds,
        isLoading: accounts.isLoading,
        showSettings: showSettings,
        focusNode: focusNode,
        onKeyEvent: onKeyEvent,
        onFocusChanged: onFocusChanged,
        onSwitch: (profile) async {
          final switched = await ref
              .read(trackingAccountsControllerProvider.notifier)
              .switchProfile(profile);
          if (!switched) return;
          await ref
              .read(settingsPreferencesProvider.notifier)
              .setTrackingProvider(profile.provider);
        },
        onManage: () => context.push('/settings/accounts?section=tracking'),
        onSettings: () => context.push('/settings/accounts'),
      ),
    );
  }
}

/// Keeps primary navigation stable while presenting the active shared-TV
/// tracker identity as a compact menu at the far right of the row.
class MainNavigationBar extends ConsumerWidget {
  const MainNavigationBar({
    required this.active,
    required this.preferences,
    this.onHomePressed,
    this.homeFocusNode,
    this.autofocusActive = false,
    super.key,
  });

  final MainNavigationDestination active;
  final SettingsPreferences preferences;
  final VoidCallback? onHomePressed;
  final FocusNode? homeFocusNode;
  final bool autofocusActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(trackingAccountsControllerProvider);
    final profiles = [
      for (final provider in TrackingProvider.values)
        ?accounts.profiles[provider],
    ];
    final activeProfile = profiles
        .where((profile) => profile.provider == preferences.trackingProvider)
        .firstOrNull;
    final primaryProfile = activeProfile ?? profiles.firstOrNull;
    final savedProfiles = [
      for (final provider in TrackingProvider.values)
        ...?accounts.savedProfiles[provider],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final normalTvLayout = width >= 700;
        final showWordmark = width >= 900;
        final showProfile = primaryProfile != null && width >= 700;
        final settingsInProfileMenu =
            showProfile &&
            !accounts.isLoading &&
            preferences.settingsEntryPlacement ==
                SettingsEntryPlacement.profileMenu;
        final visibleDestinations = preferences.topNavigationOrder
            .where(
              (destination) =>
                  preferences.isTopNavigationDestinationVisible(destination) &&
                  (destination != TopNavigationDestination.settings ||
                      !settingsInProfileMenu),
            )
            .toList(growable: false);
        // Header height depends only on width, never on asynchronously loaded
        // account data, so linking/loading a tracker cannot shift the screen.
        final headerHeight = width >= 760 ? 96.0 : 62.0;

        return SizedBox(
          key: const ValueKey('main-navigation'),
          width: double.infinity,
          height: headerHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showWordmark) ...[
                const _TetoTvWordmark(),
                const SizedBox(width: 8),
              ],
              for (
                var index = 0;
                index < visibleDestinations.length;
                index++
              ) ...[
                if (index > 0) SizedBox(width: normalTvLayout ? 4 : 2),
                _navigationAction(
                  context: context,
                  destination: visibleDestinations[index],
                  active: active,
                  settingsCompact: width < 1200,
                  autofocusActive: autofocusActive,
                  homeFocusNode: homeFocusNode,
                  onHomePressed: onHomePressed,
                ),
              ],
              const Spacer(),
              if (showProfile) ...[
                SizedBox(width: normalTvLayout ? 8 : 4),
                SizedBox(
                  width: 190,
                  height: 46,
                  child: _TrackerProfileMenuButton(
                    profile: primaryProfile,
                    savedProfiles: savedProfiles,
                    activeProfileIds: accounts.activeProfileIds,
                    isLoading: accounts.isLoading,
                    showSettings: settingsInProfileMenu,
                    onSwitch: (profile) async {
                      final switched = await ref
                          .read(trackingAccountsControllerProvider.notifier)
                          .switchProfile(profile);
                      if (!switched) return;
                      await ref
                          .read(settingsPreferencesProvider.notifier)
                          .setTrackingProvider(profile.provider);
                    },
                    onManage: () =>
                        context.push('/settings/accounts?section=tracking'),
                    onSettings: () => context.push('/settings/accounts'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

Widget _navigationAction({
  required BuildContext context,
  required TopNavigationDestination destination,
  required MainNavigationDestination active,
  required bool settingsCompact,
  required bool autofocusActive,
  required FocusNode? homeFocusNode,
  required VoidCallback? onHomePressed,
}) => switch (destination) {
  TopNavigationDestination.search => _NavigationAction(
    key: const ValueKey('main-nav-search'),
    icon: Icons.search_rounded,
    label: 'Search',
    compact: true,
    onPressed: () => context.push('/search'),
  ),
  TopNavigationDestination.home => _NavigationAction(
    key: const ValueKey('main-nav-home'),
    icon: Icons.home_rounded,
    label: 'Home',
    compact: true,
    active: active == MainNavigationDestination.home,
    autofocus: autofocusActive && active == MainNavigationDestination.home,
    focusNode: homeFocusNode,
    onPressed: onHomePressed ?? () => context.go('/'),
  ),
  TopNavigationDestination.myList => _NavigationAction(
    key: const ValueKey('main-nav-my-list'),
    icon: Icons.video_library_rounded,
    label: 'My List',
    compact: false,
    active: active == MainNavigationDestination.myList,
    autofocus: autofocusActive && active == MainNavigationDestination.myList,
    onPressed: active == MainNavigationDestination.myList
        ? () {}
        : () => context.go('/my-list'),
  ),
  TopNavigationDestination.discover => _NavigationAction(
    key: const ValueKey('main-nav-discover'),
    icon: Icons.explore_rounded,
    label: 'Discover',
    compact: true,
    active: active == MainNavigationDestination.discover,
    autofocus: autofocusActive && active == MainNavigationDestination.discover,
    onPressed: active == MainNavigationDestination.discover
        ? () {}
        : () => context.go('/discover'),
  ),
  TopNavigationDestination.calendar => _NavigationAction(
    key: const ValueKey('main-nav-calendar'),
    icon: Icons.calendar_month_rounded,
    label: 'Calendar',
    compact: true,
    active: active == MainNavigationDestination.calendar,
    autofocus: autofocusActive && active == MainNavigationDestination.calendar,
    onPressed: active == MainNavigationDestination.calendar
        ? () {}
        : () => context.go('/calendar'),
  ),
  TopNavigationDestination.settings => _NavigationAction(
    key: const ValueKey('main-nav-settings'),
    icon: Icons.settings_rounded,
    label: 'Settings',
    compact: settingsCompact,
    onPressed: () => context.push('/settings/accounts'),
  ),
};

class _TetoTvWordmark extends StatelessWidget {
  const _TetoTvWordmark();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w900,
      letterSpacing: -.45,
    );
    return Semantics(
      key: const ValueKey('main-nav-wordmark'),
      label: 'Teto TV',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Teto',
            key: const ValueKey('main-nav-wordmark-teto'),
            style: style.copyWith(color: context.appPalette.primaryText),
          ),
          const SizedBox(width: 4),
          Text(
            'TV',
            key: const ValueKey('main-nav-wordmark-tv'),
            style: style.copyWith(color: context.appPalette.accent),
          ),
        ],
      ),
    );
  }
}

class _TrackerProfileMenuButton extends StatelessWidget {
  const _TrackerProfileMenuButton({
    required this.profile,
    required this.savedProfiles,
    required this.activeProfileIds,
    required this.isLoading,
    required this.showSettings,
    required this.onSwitch,
    required this.onManage,
    required this.onSettings,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChanged,
  });

  final TrackingAccountProfile profile;
  final List<StoredTrackingProfile> savedProfiles;
  final Map<TrackingProvider, String> activeProfileIds;
  final bool isLoading;
  final bool showSettings;
  final Future<void> Function(StoredTrackingProfile profile) onSwitch;
  final VoidCallback onManage;
  final VoidCallback onSettings;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChanged;

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final result = await showMenu<String>(
      context: context,
      color: context.appPalette.surface,
      elevation: 14,
      constraints: const BoxConstraints(minWidth: 360, maxWidth: 430),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          topLeft.dx,
          topLeft.dy + box.size.height + 4,
          box.size.width,
          box.size.height,
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 106,
          child: _TrackerMenuStats(profile: profile),
        ),
        const PopupMenuDivider(),
        for (final saved in savedProfiles)
          PopupMenuItem<String>(
            key: ValueKey(
              'main-nav-switch-profile-${saved.provider.slug}-${saved.id}',
            ),
            value: '${saved.provider.slug}:${saved.id}',
            height: 52,
            child: Row(
              children: [
                Icon(
                  saved.provider == profile.provider &&
                          activeProfileIds[saved.provider] == saved.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 19,
                  color:
                      saved.provider == profile.provider &&
                          activeProfileIds[saved.provider] == saved.id
                      ? context.appPalette.accentBright
                      : context.appPalette.mutedText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    saved.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                _ProviderBadge(provider: saved.provider, compact: true),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          key: ValueKey('main-nav-manage-profiles'),
          value: 'manage',
          height: 48,
          child: Row(
            children: [
              Icon(Icons.manage_accounts_rounded, size: 20),
              SizedBox(width: 10),
              Text(
                'Add or manage profiles',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        if (showSettings) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            key: ValueKey('main-nav-profile-settings'),
            value: 'settings',
            height: 48,
            child: Row(
              children: [
                Icon(Icons.settings_rounded, size: 20),
                SizedBox(width: 10),
                Text('Settings', style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ],
    );
    if (result == null) return;
    if (result == 'manage') {
      onManage();
      return;
    }
    if (result == 'settings') {
      onSettings();
      return;
    }
    final selected = savedProfiles
        .where((item) => '${item.provider.slug}:${item.id}' == result)
        .firstOrNull;
    if (selected == null) return;
    if (selected.provider == profile.provider &&
        activeProfileIds[selected.provider] == selected.id) {
      return;
    }
    await onSwitch(selected);
  }

  @override
  Widget build(BuildContext context) {
    final slug = profile.provider.slug;
    return Builder(
      builder: (buttonContext) => Semantics(
        key: const ValueKey('main-nav-profile-summary'),
        button: true,
        onTap: isLoading ? null : () => _openMenu(buttonContext),
        label:
            '${profile.username}, ${profile.provider.displayName} profile. '
            'Open statistics and switch profiles${showSettings ? ', or open Settings' : ''}.',
        excludeSemantics: true,
        child: TvFocusable(
          focusNode: focusNode,
          onKeyEvent: onKeyEvent,
          onFocusChanged: onFocusChanged,
          onPressed: isLoading ? () {} : () => _openMenu(buttonContext),
          borderRadius: BorderRadius.circular(9),
          focusScale: 1.02,
          child: Container(
            key: ValueKey('main-nav-profile-$slug'),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: Row(
              children: [
                _ProfileAvatar(profile: profile, size: 36),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    profile.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appPalette.primaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 20,
                  color: context.appPalette.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackerMenuStats extends StatelessWidget {
  const _TrackerMenuStats({required this.profile});

  final TrackingAccountProfile profile;

  @override
  Widget build(BuildContext context) {
    final scoreMaximum = profile.provider == TrackingProvider.anilist
        ? 100
        : 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            _ProfileAvatar(profile: profile, size: 34, identify: false),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                profile.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appPalette.primaryText,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _ProviderBadge(provider: profile.provider, compact: true),
          ],
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 12,
          runSpacing: 7,
          children: [
            _TrackerMenuStat(
              icon: Icons.video_library_outlined,
              text: profile.animeCount == null
                  ? '— titles'
                  : '${_readableCount(profile.animeCount!)} titles',
            ),
            _TrackerMenuStat(
              icon: Icons.play_circle_outline_rounded,
              text: profile.episodesWatched == null
                  ? '— episodes'
                  : '${_readableCount(profile.episodesWatched!)} episodes',
            ),
            _TrackerMenuStat(
              icon: Icons.schedule_rounded,
              text: profile.minutesWatched == null
                  ? '— watched'
                  : _watchedDuration(profile.minutesWatched!),
            ),
            _TrackerMenuStat(
              icon: Icons.star_rounded,
              text: profile.meanScore == null
                  ? 'Mean —/$scoreMaximum'
                  : 'Mean ${profile.meanScore!.toStringAsFixed(1)}/$scoreMaximum',
            ),
          ],
        ),
      ],
    );
  }
}

class _TrackerMenuStat extends StatelessWidget {
  const _TrackerMenuStat({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: context.appPalette.mutedText),
      const SizedBox(width: 4),
      Text(
        text,
        style: TextStyle(
          color: context.appPalette.mutedText,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider, this.compact = false});

  final TrackingProvider provider;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: context.appPalette.accent.withValues(alpha: .24),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        provider.displayName,
        style: TextStyle(
          color: context.appPalette.accentBright,
          fontSize: compact ? 8 : 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _readableCount(int value) {
  if (value < 10000) return '$value';
  if (value < 1000000) {
    final digits = value >= 100000 ? 0 : 1;
    return '${(value / 1000).toStringAsFixed(digits)}K';
  }
  final digits = value >= 10000000 ? 0 : 1;
  return '${(value / 1000000).toStringAsFixed(digits)}M';
}

String _watchedDuration(int minutes) {
  if (minutes < 60) return '${minutes}m watched';
  return '${(minutes / 60).round()}h watched';
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.profile,
    required this.size,
    this.identify = true,
  });

  final TrackingAccountProfile profile;
  final double size;
  final bool identify;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: identify
          ? ValueKey('main-nav-profile-avatar-${profile.provider.slug}')
          : null,
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: context.appPalette.surfaceRaised,
      ),
      child: NetworkArtwork(
        url: profile.avatarUrl,
        cacheWidth: (size * 2).round(),
        icon: Icons.person_rounded,
      ),
    );
  }
}

class _NavigationAction extends StatelessWidget {
  const _NavigationAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.compact = false,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;
  final bool compact;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: compact ? label : '',
      child: TvFocusable(
        autofocus: autofocus,
        focusNode: focusNode,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(7),
        focusScale: 1.02,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 11,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: active
                ? context.appPalette.accent.withValues(alpha: .13)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active
                    ? context.appPalette.accentBright
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: active
                    ? context.appPalette.accentBright
                    : context.appPalette.primaryText,
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
