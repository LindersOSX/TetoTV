import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/features/tracking/application/my_list_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  TrackingListStatus _status = TrackingListStatus.watching;
  bool _updating = false;

  Future<void> _chooseSort(MyListSort current) async {
    final selected = await showDialog<MyListSort>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _SortDialog(current: current),
    );
    if (selected == null || !mounted) return;
    await ref.read(myListSortProvider.notifier).setSort(selected);
  }

  void _open(HomeTrackedAnime item) {
    final route = item.anilistId == null
        ? Uri(
            path: '/search',
            queryParameters: {'q': item.tracked.title},
          ).toString()
        : '/anime/${item.anilistId}';
    context.push(route);
  }

  Future<void> _manage(
    HomeTrackedAnime item,
    TitleLanguagePreference titlePreference,
  ) async {
    final selected = await showDialog<TrackingListStatus>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _StatusDialog(
        item: item,
        titlePreference: titlePreference,
        onOpen: () {
          Navigator.of(dialogContext).pop();
          _open(item);
        },
      ),
    );
    if (selected == null || selected == item.tracked.status || !mounted) return;
    setState(() => _updating = true);
    try {
      await ref
          .read(trackingStatusControllerProvider.notifier)
          .update(item, selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.tracked.displayTitle(titlePreference)} moved to '
            '${selected.displayName}.',
          ),
          backgroundColor: AppColors.accent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update the list: $error'),
          backgroundColor: const Color(0xFF7D1E32),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(trackingListProvider(_status));
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    final sort = ref.watch(myListSortProvider);
    final preferences = ref.watch(settingsPreferencesProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _MyListHeader(),
            Row(
              children: [
                Text(
                  'My List',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(width: 22),
                for (final status in TrackingListStatus.values) ...[
                  _StatusTab(
                    status: status,
                    selected: status == _status,
                    onPressed: () => setState(() => _status = status),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                _SortButton(sort: sort, onPressed: () => _chooseSort(sort)),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: list.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accentBright,
                        ),
                      ),
                      error: (error, _) => _ListMessage(
                        icon: Icons.cloud_off_rounded,
                        title: 'Could not load ${_status.displayName}',
                        body: error.toString(),
                      ),
                      data: (items) => items.isEmpty
                          ? _ListMessage(
                              icon: Icons.video_library_outlined,
                              title: '${_status.displayName} is empty',
                              body:
                                  'Connect AniList or MyAnimeList, or change '
                                  'a title to this status.',
                            )
                          : _TrackedShelf(
                              items: sortMyListItems(items, sort),
                              titlePreference: titlePreference,
                              onPressed: _open,
                              onManage: (item) =>
                                  _manage(item, titlePreference),
                              preferences: preferences,
                            ),
                    ),
                  ),
                  if (_updating)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x99000000),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accentBright,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Text(
                'Select to view episodes. Hold OK or press Menu for quick '
                'watchlist actions.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyListHeader extends StatelessWidget {
  const _MyListHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(9)),
            child: Image.asset(
              'assets/branding/tetotv_icon.png',
              cacheWidth: 72,
              cacheHeight: 72,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            ),
          ),
          const SizedBox(width: 10),
          Text('TetoTV', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 28),
          _NavButton(
            icon: Icons.search_rounded,
            label: 'Search',
            onPressed: () => context.push('/search'),
          ),
          const SizedBox(width: 6),
          _NavButton(
            icon: Icons.home_rounded,
            label: 'Home',
            onPressed: () => context.go('/'),
          ),
          const SizedBox(width: 6),
          _NavButton(
            icon: Icons.video_library_rounded,
            label: 'My List',
            active: true,
            onPressed: () {},
          ),
          const Spacer(),
          _NavButton(
            icon: Icons.settings_rounded,
            label: 'Settings',
            onPressed: () => context.push('/settings/accounts'),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(7),
      focusScale: 1.02,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0x22E52B50) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.accentBright : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? AppColors.accentBright : AppColors.textPrimary,
            ),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.status,
    required this.selected,
    required this.onPressed,
  });

  final TrackingListStatus status;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      focusScale: 1.03,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.panel,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          status.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onPressed});

  final MyListSort sort;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      focusScale: 1.03,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 18),
            const SizedBox(width: 7),
            Text(
              'Sort: ${sort.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SortDialog extends StatelessWidget {
  const _SortDialog({required this.current});

  final MyListSort current;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha: .7)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sort My List', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            for (final sort in MyListSort.values) ...[
              TvFocusable(
                autofocus: sort == current,
                onPressed: () => Navigator.of(context).pop(sort),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: sort == current
                        ? AppColors.accent
                        : AppColors.panelRaised,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        sort == current
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_off_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        sort.displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (sort != MyListSort.values.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrackedShelf extends StatelessWidget {
  const _TrackedShelf({
    required this.items,
    required this.titlePreference,
    required this.onPressed,
    required this.onManage,
    required this.preferences,
  });

  final List<HomeTrackedAnime> items;
  final TitleLanguagePreference titlePreference;
  final ValueChanged<HomeTrackedAnime> onPressed;
  final ValueChanged<HomeTrackedAnime> onManage;
  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.fromLTRB(4, 5, 4, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) =>
          SizedBox(width: 10 * preferences.contentDensity.spacingScale),
      itemBuilder: (context, index) {
        final item = items[index];
        return Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 126 * preferences.thumbnailScale,
            height: 238 * preferences.thumbnailScale,
            child: TvFocusable(
              autofocus: index == 0,
              onPressed: () => onPressed(item),
              onLongPress: () => onManage(item),
              focusScale: 1.025,
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.black,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NetworkArtwork(
                            url: item.coverImageUrl,
                            cacheWidth: 210,
                          ),
                          Align(
                            alignment: Alignment.topRight,
                            child: Container(
                              margin: const EdgeInsets.all(7),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 4,
                              ),
                              color: const Color(0xE6000000),
                              child: Text(
                                item.provider.displayName,
                                style: const TextStyle(
                                  color: AppColors.accentBright,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.tracked.displayTitle(titlePreference),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.tracked.totalEpisodes == null
                          ? 'Episode ${item.tracked.progress}'
                          : 'Episode ${item.tracked.progress} / '
                                '${item.tracked.totalEpisodes}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusDialog extends StatelessWidget {
  const _StatusDialog({
    required this.item,
    required this.titlePreference,
    required this.onOpen,
  });

  final HomeTrackedAnime item;
  final TitleLanguagePreference titlePreference;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 760,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withValues(alpha: .55)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.tracked.displayTitle(titlePreference),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 7),
            Text(
              '${item.provider.displayName} • Currently '
              '${item.tracked.status.displayName}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Text('Move to', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final status in TrackingListStatus.values)
                  _DialogChoice(
                    status: status,
                    current: status == item.tracked.status,
                    onPressed: () => Navigator.of(context).pop(status),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerRight,
              child: _OpenButton(onPressed: onOpen),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogChoice extends StatelessWidget {
  const _DialogChoice({
    required this.status,
    required this.current,
    required this.onPressed,
  });

  final TrackingListStatus status;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: current,
      onPressed: onPressed,
      focusScale: 1.03,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 128,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        color: current ? AppColors.accent : AppColors.panelRaised,
        child: Text(
          status.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: AppColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: const Text(
          'View episodes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _ListMessage extends StatelessWidget {
  const _ListMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 58, color: AppColors.accentBright),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 7),
          SizedBox(
            width: 560,
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
