import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum MainNavigationDestination { home, myList, discover, calendar }

/// Keeps the primary destinations and linked tracker identity in one stable
/// row on every main screen. Tracker identity always carries a text label when
/// it is visible, so a linked account never turns into an unexplained avatar.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // A 1080p TV commonly exposes a 960 logical-pixel canvas. Keep the
        // icon-only navigation tier until the labelled row and full profile
        // card can fit together without pushing Settings off-screen.
        final compact = constraints.maxWidth < 940;
        final showLogo = constraints.maxWidth >= 430;
        final showBrandName = constraints.maxWidth >= 520;
        final showProfileDetails = constraints.maxWidth >= 940;
        final showEveryProfile = constraints.maxWidth >= 1200;
        final showProfiles = profiles.isNotEmpty && constraints.maxWidth >= 282;
        final profileWidth = showProfileDetails
            ? showEveryProfile
                  ? 500.0
                  : 278.0
            : constraints.maxWidth < 340
            ? 64.0
            : constraints.maxWidth < 430
            ? 120.0
            : 164.0;
        return SizedBox(
          key: const ValueKey('main-navigation'),
          height: compact ? 62 : 70,
          child: Row(
            children: [
              if (showLogo) ...[
                Container(
                  width: 36,
                  height: 36,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Image.asset(
                    'assets/branding/tetotv_icon.png',
                    cacheWidth: 72,
                    cacheHeight: 72,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  ),
                ),
                SizedBox(width: compact ? 7 : 10),
              ],
              if (showBrandName)
                Text('TetoTV', style: Theme.of(context).textTheme.titleLarge),
              SizedBox(width: compact ? 4 : 14),
              if (preferences.showSearch) ...[
                _NavigationAction(
                  key: const ValueKey('main-nav-search'),
                  icon: Icons.search_rounded,
                  label: 'Search',
                  compact: true,
                  onPressed: () => context.push('/search'),
                ),
                SizedBox(width: compact ? 2 : 6),
              ],
              _NavigationAction(
                key: const ValueKey('main-nav-home'),
                icon: Icons.home_rounded,
                label: 'Home',
                compact: true,
                active: active == MainNavigationDestination.home,
                autofocus:
                    autofocusActive && active == MainNavigationDestination.home,
                focusNode: homeFocusNode,
                onPressed: onHomePressed ?? () => context.go('/'),
              ),
              if (preferences.showMyList) ...[
                SizedBox(width: compact ? 2 : 6),
                _NavigationAction(
                  key: const ValueKey('main-nav-my-list'),
                  icon: Icons.video_library_rounded,
                  label: 'My List',
                  compact: compact,
                  active: active == MainNavigationDestination.myList,
                  autofocus:
                      autofocusActive &&
                      active == MainNavigationDestination.myList,
                  onPressed: active == MainNavigationDestination.myList
                      ? () {}
                      : () => context.go('/my-list'),
                ),
              ],
              if (preferences.showDiscover) ...[
                SizedBox(width: compact ? 2 : 6),
                _NavigationAction(
                  key: const ValueKey('main-nav-discover'),
                  icon: Icons.explore_rounded,
                  label: 'Discover',
                  compact: true,
                  active: active == MainNavigationDestination.discover,
                  autofocus:
                      autofocusActive &&
                      active == MainNavigationDestination.discover,
                  onPressed: active == MainNavigationDestination.discover
                      ? () {}
                      : () => context.go('/discover'),
                ),
              ],
              if (preferences.showCalendar) ...[
                SizedBox(width: compact ? 2 : 6),
                _NavigationAction(
                  key: const ValueKey('main-nav-calendar'),
                  icon: Icons.calendar_month_rounded,
                  label: 'Calendar',
                  compact: true,
                  active: active == MainNavigationDestination.calendar,
                  autofocus:
                      autofocusActive &&
                      active == MainNavigationDestination.calendar,
                  onPressed: active == MainNavigationDestination.calendar
                      ? () {}
                      : () => context.go('/calendar'),
                ),
              ],
              const Spacer(),
              if (showProfiles) ...[
                SizedBox(
                  width: profileWidth,
                  child: _TrackerIdentitySummary(
                    profiles: profiles,
                    showDetails: showProfileDetails,
                    showEveryProfile: showEveryProfile,
                    onPressed: () => context.push('/settings/accounts'),
                  ),
                ),
                SizedBox(width: compact ? 2 : 6),
              ],
              _NavigationAction(
                key: const ValueKey('main-nav-settings'),
                icon: Icons.settings_rounded,
                label: 'Settings',
                compact: compact,
                onPressed: () => context.push('/settings/accounts'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackerIdentitySummary extends StatelessWidget {
  const _TrackerIdentitySummary({
    required this.profiles,
    required this.showDetails,
    required this.showEveryProfile,
    required this.onPressed,
  });

  final List<TrackingAccountProfile> profiles;
  final bool showDetails;
  final bool showEveryProfile;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final visible = showEveryProfile ? profiles : profiles.take(1).toList();
    final hiddenCount = profiles.length - visible.length;
    final label = profiles
        .map(
          (profile) => '${profile.username} on ${profile.provider.displayName}',
        )
        .join(', ');
    return Semantics(
      label: 'Linked tracker profiles: $label',
      button: true,
      child: TvFocusable(
        key: const ValueKey('main-nav-profile-summary'),
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(12),
        focusScale: 1.02,
        child: Container(
          width: double.infinity,
          height: showDetails ? 54 : 46,
          padding: EdgeInsets.symmetric(
            horizontal: showDetails ? 8 : 7,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: context.appPalette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: context.appPalette.primaryText.withValues(alpha: .09),
            ),
          ),
          child: showDetails
              ? Row(
                  children: [
                    for (var index = 0; index < visible.length; index++) ...[
                      Expanded(
                        child: _ProfileIdentity(profile: visible[index]),
                      ),
                      if (index != visible.length - 1)
                        Container(
                          width: 1,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          color: context.appPalette.primaryText.withValues(
                            alpha: .09,
                          ),
                        ),
                    ],
                    if (hiddenCount > 0) ...[
                      const SizedBox(width: 7),
                      Text(
                        '+$hiddenCount',
                        style: TextStyle(
                          color: context.appPalette.accentBright,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                )
              : _CompactProfileIdentity(
                  profile: profiles.first,
                  hiddenCount: hiddenCount,
                ),
        ),
      ),
    );
  }
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({required this.profile});

  final TrackingAccountProfile profile;

  @override
  Widget build(BuildContext context) {
    final statistics = _profileStatistics(profile);
    return Row(
      key: ValueKey('main-nav-profile-${profile.provider.slug}'),
      children: [
        _ProfileAvatar(profile: profile, size: 38),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ProviderBadge(provider: profile.provider),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      profile.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appPalette.primaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                statistics.isEmpty ? 'Linked account' : statistics.join(' · '),
                key: ValueKey(
                  'main-nav-profile-stats-${profile.provider.slug}',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appPalette.mutedText,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactProfileIdentity extends StatelessWidget {
  const _CompactProfileIdentity({
    required this.profile,
    required this.hiddenCount,
  });

  final TrackingAccountProfile profile;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    final statistics = _profileStatistics(profile);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 74;
        return Column(
          key: ValueKey('main-nav-profile-${profile.provider.slug}'),
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (!tiny) ...[
                  _ProviderBadge(provider: profile.provider, compact: true),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    tiny ? profile.provider.displayName : profile.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appPalette.primaryText,
                      fontSize: tiny ? 9 : 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (hiddenCount > 0) ...[
                  const SizedBox(width: 3),
                  Text(
                    '+$hiddenCount',
                    style: TextStyle(
                      color: context.appPalette.accentBright,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              tiny
                  ? profile.username
                  : statistics.firstOrNull ?? 'Linked account',
              key: ValueKey('main-nav-profile-stats-${profile.provider.slug}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appPalette.mutedText,
                fontSize: tiny ? 8 : 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider, this.compact = false});

  final TrackingProvider provider;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 5,
        vertical: compact ? 1.5 : 2,
      ),
      decoration: BoxDecoration(
        color: context.appPalette.accent.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        provider.displayName,
        style: TextStyle(
          color: context.appPalette.accentBright,
          fontSize: compact ? 7 : 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

List<String> _profileStatistics(TrackingAccountProfile profile) => [
  if (profile.animeCount case final count?) '${_compactCount(count)} titles',
  if (profile.episodesWatched case final episodes?)
    '${_compactCount(episodes)} eps',
  if (profile.minutesWatched case final minutes?) _watchedDuration(minutes),
  if (profile.meanScore case final score?)
    '${score.toStringAsFixed(1)}'
        '/${profile.provider == TrackingProvider.anilist ? 100 : 10} mean',
];

String _compactCount(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final digits = value >= 10000 ? 0 : 1;
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
  const _ProfileAvatar({required this.profile, required this.size});

  final TrackingAccountProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.appPalette.surfaceRaised,
        border: Border.all(
          color: context.appPalette.accentBright.withValues(alpha: .72),
          width: 1.5,
        ),
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
