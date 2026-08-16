import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/features/auth/application/tracking_token_service.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum MainNavigationDestination { home, myList, discover, calendar }

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
        final visibleDestinations = preferences.topNavigationOrder
            .where(preferences.isTopNavigationDestinationVisible)
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
    required this.onSwitch,
    required this.onManage,
  });

  final TrackingAccountProfile profile;
  final List<StoredTrackingProfile> savedProfiles;
  final Map<TrackingProvider, String> activeProfileIds;
  final bool isLoading;
  final Future<void> Function(StoredTrackingProfile profile) onSwitch;
  final VoidCallback onManage;

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
      ],
    );
    if (result == null) return;
    if (result == 'manage') {
      onManage();
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
            'Open statistics and switch profiles.',
        excludeSemantics: true,
        child: TvFocusable(
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
