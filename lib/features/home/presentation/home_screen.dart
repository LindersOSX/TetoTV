import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/widgets/poster_metadata_overlay.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/home_shelf_preferences_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:anime_tv/features/tracking/domain/tracking_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _connectTracking = [
    _ShelfItem(
      'Connect your tracker',
      'AniList or MyAnimeList',
      AppColors.accent,
      route: '/settings/accounts',
    ),
  ];

  static const _seasonalFallback = [
    _ShelfItem('Jujutsu Kaisen', 'Action • Supernatural', AppColors.accent),
    _ShelfItem('Frieren', 'Adventure • Fantasy', Color(0xFF8E2038)),
    _ShelfItem('Demon Slayer', 'Action • Historical', Color(0xFFB62A47)),
    _ShelfItem('Attack on Titan', 'Action • Drama', Color(0xFF75172A)),
    _ShelfItem('My Hero Academia', 'Action • Hero', Color(0xFFD23A58)),
  ];

  final _heroFocus = FocusNode(debugLabel: 'home.watch-now');
  final _scrollController = ScrollController();
  bool _catalogFocusSettled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusHero());
  }

  void _focusHero() {
    if (!mounted) return;
    _heroFocus.requestFocus();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  void dispose() {
    _heroFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(trendingAnimeProvider, (_, next) {
      if (!_catalogFocusSettled && next.valueOrNull?.isNotEmpty == true) {
        _catalogFocusSettled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusHero());
      }
    });

    final trending = ref.watch(trendingAnimeProvider).valueOrNull;
    final seasonal = ref.watch(seasonalAnimeProvider).valueOrNull;
    final tracking = ref.watch(trackingHomeProvider).valueOrNull;
    final localHistory = ref.watch(recentPlaybackProvider).valueOrNull;
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    final enabledShelves = ref.watch(homeShelfPreferencesProvider);
    final hero = trending?.firstOrNull;
    final seasonalItems = seasonal == null || seasonal.isEmpty
        ? _seasonalFallback
        : seasonal
              .map((anime) => _ShelfItem.fromAnime(anime, titlePreference))
              .toList(growable: false);
    final trendingItems = trending
        ?.skip(1)
        .map((anime) => _ShelfItem.fromAnime(anime, titlePreference))
        .toList(growable: false);
    final watchingItems = tracking?.watching.isNotEmpty == true
        ? tracking!.watching
              .map((item) => _ShelfItem.fromTracked(item, titlePreference))
              .toList(growable: false)
        : _connectTracking;
    final plannedItems = tracking?.planToWatch.isNotEmpty == true
        ? tracking!.planToWatch
              .map((item) => _ShelfItem.fromTracked(item, titlePreference))
              .toList(growable: false)
        : const <_ShelfItem>[];
    final completedItems = tracking?.completed
        .map((item) => _ShelfItem.fromTracked(item, titlePreference))
        .toList(growable: false);
    final historyItems = localHistory
        ?.map(_ShelfItem.fromCheckpoint)
        .toList(growable: false);
    final airingItems = seasonal
        ?.where((anime) => anime.nextAiringEpisode != null)
        .take(20)
        .map(
          (anime) => _ShelfItem.fromAnime(anime, titlePreference).copyWith(
            subtitle: 'Episode ${anime.nextAiringEpisode} airing soon',
          ),
        )
        .toList(growable: false);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 34),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: _Header(onMyList: () => context.push('/my-list')),
            ),
            SliverToBoxAdapter(
              child: _HeroPanel(
                anime: hero,
                focusNode: _heroFocus,
                titlePreference: titlePreference,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            if (enabledShelves.contains(HomeShelf.tracking))
              SliverToBoxAdapter(
                child: _MediaShelf(
                  title: 'Continue watching',
                  items: watchingItems,
                ),
              ),
            if (enabledShelves.contains(HomeShelf.history) &&
                historyItems != null &&
                historyItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _MediaShelf(title: 'Watch history', items: historyItems),
              ),
            SliverToBoxAdapter(
              child: _MediaShelf(
                title: 'Recently released',
                items: seasonalItems,
              ),
            ),
            if (enabledShelves.contains(HomeShelf.trending) &&
                trendingItems != null &&
                trendingItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _MediaShelf(title: 'Trending now', items: trendingItems),
              ),
            if (enabledShelves.contains(HomeShelf.planned) &&
                plannedItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _MediaShelf(title: 'Plan to watch', items: plannedItems),
              ),
            if (enabledShelves.contains(HomeShelf.airing) &&
                airingItems != null &&
                airingItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _MediaShelf(title: 'Airing soon', items: airingItems),
              ),
            if (enabledShelves.contains(HomeShelf.completed) &&
                completedItems != null &&
                completedItems.isNotEmpty)
              SliverToBoxAdapter(
                child: _MediaShelf(
                  title: 'Recently completed',
                  items: completedItems,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 42)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onMyList});

  final VoidCallback onMyList;

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
          const SizedBox(width: 14),
          _HeaderAction(
            icon: Icons.search_rounded,
            label: 'Search',
            compact: true,
            onPressed: () => context.push('/search'),
          ),
          const SizedBox(width: 6),
          _HeaderAction(
            icon: Icons.home_rounded,
            label: 'Home',
            compact: true,
            active: true,
            onPressed: () {},
          ),
          const SizedBox(width: 6),
          _HeaderAction(
            icon: Icons.video_library_rounded,
            label: 'My List',
            onPressed: onMyList,
          ),
          const SizedBox(width: 6),
          _HeaderAction(
            icon: Icons.explore_rounded,
            label: 'Discover',
            compact: true,
            onPressed: () => context.push('/discover'),
          ),
          const SizedBox(width: 6),
          _HeaderAction(
            icon: Icons.calendar_month_rounded,
            label: 'Calendar',
            compact: true,
            onPressed: () => context.push('/calendar'),
          ),
          const Spacer(),
          _HeaderAction(
            icon: Icons.settings_rounded,
            label: 'Settings',
            onPressed: () => context.push('/settings/accounts'),
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.focusNode,
    required this.titlePreference,
    this.anime,
  });

  final AnimeSummary? anime;
  final FocusNode focusNode;
  final TitleLanguagePreference titlePreference;

  @override
  Widget build(BuildContext context) {
    final route = anime == null ? '/search?q=Frieren' : '/anime/${anime!.id}';
    return Container(
      height: 292,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: AppColors.panel),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF26050C), Color(0xFF080808)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
          ),
          if (anime?.bannerImageUrl != null)
            NetworkArtwork(url: anime!.bannerImageUrl!, cacheWidth: 1280),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFA000000),
                  Color(0xC7000000),
                  Color(0x22000000),
                ],
                stops: [0, .50, 1],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xE6000000)],
                begin: Alignment.center,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Eyebrow(text: 'FEATURED NOW'),
                const SizedBox(height: 8),
                SizedBox(
                  width: 620,
                  child: Text(
                    anime?.displayTitle(titlePreference) ??
                        'Frieren: Beyond Journey’s End',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.displaySmall?.copyWith(fontSize: 40, height: 1),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 610,
                  child: Text(
                    anime?.description.isNotEmpty == true
                        ? anime!.description
                        : 'An elven mage retraces a legendary journey and '
                              'discovers what the brief lives of her friends meant.',
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.32,
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    _TvButton(
                      focusNode: focusNode,
                      autofocus: true,
                      icon: Icons.play_arrow_rounded,
                      label: 'Watch now',
                      onPressed: () => context.push(route),
                    ),
                    const SizedBox(width: 16),
                    if (anime?.score case final score?)
                      _HeroMeta(
                        icon: Icons.star_rounded,
                        text: score.toStringAsFixed(1),
                      ),
                    if (anime?.format case final format?)
                      _HeroMeta(text: format.replaceAll('_', ' ')),
                    if (anime?.seasonYear case final year?)
                      _HeroMeta(text: '$year'),
                    if (anime?.durationMinutes case final minutes?)
                      _HeroMeta(text: '$minutes min'),
                    if (anime?.episodes case final episodes?)
                      _HeroMeta(text: '$episodes episodes'),
                  ],
                ),
              ],
            ),
          ),
          const Positioned(
            right: 20,
            bottom: 18,
            child: Row(
              children: [
                _HeroDot(active: true),
                _HeroDot(),
                _HeroDot(),
                _HeroDot(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  const _HeroMeta({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: AppColors.accentBright),
            const SizedBox(width: 4),
          ],
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroDot extends StatelessWidget {
  const _HeroDot({this.active = false});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 24 : 7,
      height: 7,
      margin: const EdgeInsets.only(left: 5),
      decoration: BoxDecoration(
        color: active ? AppColors.accentBright : Colors.white54,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _MediaShelf extends StatelessWidget {
  const _MediaShelf({required this.title, required this.items});

  final String title;
  final List<_ShelfItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SizedBox(
            height: 205,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                return _PosterCard(
                  item: item,
                  onPressed: () => item.route != null
                      ? context.push(item.route!)
                      : item.animeId == null
                      ? context.push(
                          Uri(
                            path: '/search',
                            queryParameters: {'q': item.title},
                          ).toString(),
                        )
                      : context.push('/anime/${item.animeId}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item, required this.onPressed});

  final _ShelfItem item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 106,
      child: TvFocusable(
        onPressed: onPressed,
        focusScale: 1.025,
        borderRadius: BorderRadius.circular(7),
        child: ColoredBox(
          color: Colors.black,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (item.coverImageUrl == null)
                        ColoredBox(
                          color: item.color,
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_outline_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        )
                      else
                        NetworkArtwork(
                          url: item.coverImageUrl,
                          cacheWidth: 190,
                        ),
                      if (item.hasPosterMetadata)
                        Positioned(
                          left: 4,
                          right: 4,
                          bottom: 4,
                          child: PosterMetadataOverlay(
                            score: item.score,
                            releaseYear: item.releaseYear,
                            durationMinutes: item.durationMinutes,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (item.progress != null) ...[
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  color: AppColors.accentBright,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TvButton extends StatelessWidget {
  const _TvButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(99),
      focusScale: 1.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 21, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(7),
      focusScale: 1.02,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 11,
          vertical: 8,
        ),
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
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ],
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.accentBright,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.6,
      ),
    );
  }
}

class _ShelfItem {
  const _ShelfItem(
    this.title,
    this.subtitle,
    this.color, {
    this.progress,
    this.animeId,
    this.coverImageUrl,
    this.route,
    this.score,
    this.releaseYear,
    this.durationMinutes,
  });

  final String title;
  final String subtitle;
  final Color color;
  final double? progress;
  final int? animeId;
  final String? coverImageUrl;
  final String? route;
  final double? score;
  final int? releaseYear;
  final int? durationMinutes;

  bool get hasPosterMetadata =>
      score != null || releaseYear != null || durationMinutes != null;

  factory _ShelfItem.fromAnime(
    AnimeSummary anime,
    TitleLanguagePreference titlePreference,
  ) {
    return _ShelfItem(
      anime.displayTitle(titlePreference),
      anime.episodes == null ? '' : '${anime.episodes} episodes',
      AppColors.accent,
      animeId: anime.id,
      coverImageUrl: anime.coverImageUrl,
      score: anime.score,
      releaseYear: anime.seasonYear,
      durationMinutes: anime.durationMinutes,
    );
  }

  factory _ShelfItem.fromCheckpoint(PlaybackCheckpoint checkpoint) {
    return _ShelfItem(
      checkpoint.title,
      'Episode ${checkpoint.episode} • ${_shortDuration(checkpoint.position)}',
      AppColors.accent,
      progress: checkpoint.progress,
      animeId: checkpoint.anilistMediaId,
      coverImageUrl: checkpoint.coverImageUrl,
    );
  }

  _ShelfItem copyWith({String? subtitle}) => _ShelfItem(
    title,
    subtitle ?? this.subtitle,
    color,
    progress: progress,
    animeId: animeId,
    coverImageUrl: coverImageUrl,
    route: route,
    score: score,
    releaseYear: releaseYear,
    durationMinutes: durationMinutes,
  );

  factory _ShelfItem.fromTracked(
    HomeTrackedAnime item,
    TitleLanguagePreference titlePreference,
  ) {
    final tracked = item.tracked;
    final subtitle = switch (tracked.status) {
      TrackingListStatus.watching =>
        'Episode ${tracked.progress}'
            '${tracked.totalEpisodes == null ? '' : ' of ${tracked.totalEpisodes}'}',
      TrackingListStatus.planToWatch => 'Plan to watch',
      TrackingListStatus.completed =>
        tracked.totalEpisodes == null
            ? 'Completed'
            : '${tracked.totalEpisodes} episodes • Completed',
      TrackingListStatus.dropped => 'Dropped',
      TrackingListStatus.onHold => 'On hold',
    };
    return _ShelfItem(
      tracked.displayTitle(titlePreference),
      subtitle,
      AppColors.accent,
      progress: tracked.totalEpisodes == null || tracked.totalEpisodes == 0
          ? null
          : (tracked.progress / tracked.totalEpisodes!).clamp(0, 1),
      animeId: item.anilistId,
      coverImageUrl: item.coverImageUrl,
      route: item.anilistId == null
          ? Uri(
              path: '/search',
              queryParameters: {'q': tracked.title},
            ).toString()
          : null,
    );
  }
}

String _shortDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
