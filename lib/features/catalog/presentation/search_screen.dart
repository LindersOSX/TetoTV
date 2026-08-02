import 'dart:async';

import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/widgets/poster_metadata_overlay.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({this.initialQuery, super.key});

  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'search_input');
  Timer? _debounce;
  AsyncValue<List<AnimeSummary>> _results = const AsyncData([]);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _queryController.text = initial;
      Future.microtask(() => _search(initial));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _queueSearch(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() => _results = const AsyncData([]));
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _results = const AsyncLoading());
    try {
      final results = await ref.read(catalogClientProvider).search(query);
      if (mounted) setState(() => _results = AsyncData(results));
    } catch (error, stackTrace) {
      if (mounted) setState(() => _results = AsyncError(error, stackTrace));
    }
  }

  @override
  Widget build(BuildContext context) {
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(42, 28, 42, 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TvFocusable(
                  onPressed: context.pop,
                  borderRadius: BorderRadius.circular(10),
                  child: const ColoredBox(
                    color: AppColors.panel,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_rounded, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  'Search anime',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: TvTextInput(
                    focusNode: _searchFocusNode,
                    controller: _queryController,
                    labelText: 'Search',
                    hintText: 'Title, synonym, or Japanese name',
                    keyboardTitle: 'Search anime',
                    onChanged: _queueSearch,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 34),
            Text(
              _queryController.text.trim().length < 2
                  ? 'Start typing to search AniList'
                  : 'Results',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            Expanded(child: _resultsBody(titlePreference)),
          ],
        ),
      ),
    );
  }

  Widget _resultsBody(TitleLanguagePreference titlePreference) {
    return _results.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.cyan)),
      error: (error, _) => _SearchMessage(
        icon: Icons.cloud_off_rounded,
        title: 'Search failed',
        body: error.toString(),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _SearchMessage(
            icon: Icons.manage_search_rounded,
            title: 'Find your next show',
            body: 'Search results will appear here.',
          );
        }
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 9),
          itemBuilder: (context, index) {
            final anime = items[index];
            return _SearchCard(
              anime: anime,
              titlePreference: titlePreference,
              onPressed: () => context.push('/anime/${anime.id}'),
            );
          },
        );
      },
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.anime,
    required this.titlePreference,
    required this.onPressed,
  });

  final AnimeSummary anime;
  final TitleLanguagePreference titlePreference;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 122,
        height: 225,
        child: TvFocusable(
          onPressed: onPressed,
          child: ColoredBox(
            color: Colors.black,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetworkArtwork(url: anime.coverImageUrl, cacheWidth: 210),
                      if (anime.score != null ||
                          anime.seasonYear != null ||
                          anime.durationMinutes != null)
                        Positioned(
                          left: 5,
                          right: 5,
                          bottom: 5,
                          child: PosterMetadataOverlay(
                            score: anime.score,
                            releaseYear: anime.seasonYear,
                            durationMinutes: anime.durationMinutes,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 7, 2, 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        anime.displayTitle(titlePreference),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (anime.episodes case final episodes?) ...[
                        const SizedBox(height: 4),
                        Text(
                          '$episodes episodes',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
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
          Icon(icon, size: 60, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
