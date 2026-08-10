import 'dart:async';

import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
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
  var _searchGeneration = 0;
  var _hasSearched = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.length >= 2) {
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
      _searchGeneration++;
      setState(() {
        _hasSearched = false;
        _results = const AsyncData([]);
      });
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(query));
  }

  void _submitSearch(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      _queueSearch(query);
      return;
    }
    unawaited(_search(query));
  }

  Future<void> _search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) return;
    final generation = ++_searchGeneration;
    setState(() {
      _hasSearched = true;
      _results = const AsyncLoading();
    });
    try {
      final results = await ref.read(catalogClientProvider).search(normalized);
      if (mounted && generation == _searchGeneration) {
        setState(() => _results = AsyncData(results));
      }
    } catch (error, stackTrace) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _results = AsyncError(error, stackTrace));
      }
    }
  }

  Future<void> _voiceSearch() async {
    final query = await AndroidTvBridge.instance.voiceSearch();
    if (!mounted) return;
    if (query == null || query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice search is unavailable or no title was recognized.',
          ),
          backgroundColor: AppColors.panelRaised,
        ),
      );
      return;
    }
    _queryController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _submitSearch(query);
  }

  @override
  Widget build(BuildContext context) {
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        minimum: context.responsiveScreenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final back = TvFocusable(
                  onPressed: context.pop,
                  borderRadius: BorderRadius.circular(10),
                  child: const ColoredBox(
                    color: AppColors.panel,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.arrow_back_rounded, size: 20),
                    ),
                  ),
                );
                final input = TvTextInput(
                  focusNode: _searchFocusNode,
                  controller: _queryController,
                  labelText: 'Search',
                  hintText: 'Title, synonym, or Japanese name',
                  keyboardTitle: 'Search anime',
                  autofocus: true,
                  onChanged: _queueSearch,
                  onSubmitted: _submitSearch,
                );
                final voice = TvFocusable(
                  onPressed: () => unawaited(_voiceSearch()),
                  borderRadius: BorderRadius.circular(12),
                  focusScale: 1.03,
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    color: AppColors.panel,
                    child: const Icon(
                      Icons.mic_rounded,
                      color: AppColors.accentBright,
                      size: 25,
                    ),
                  ),
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    children: [
                      Row(
                        children: [
                          back,
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Search anime',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          voice,
                        ],
                      ),
                      const SizedBox(height: 10),
                      input,
                    ],
                  );
                }
                return Row(
                  children: [
                    back,
                    const SizedBox(width: 18),
                    Text(
                      'Search anime',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(width: 28),
                    Expanded(child: input),
                    const SizedBox(width: 10),
                    voice,
                  ],
                );
              },
            ),
            SizedBox(height: context.isCompactWidth ? 20 : 34),
            Text(
              !_hasSearched
                  ? 'Start typing to search anime'
                  : 'Results for “${_queryController.text.trim()}”',
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
        body: error is StateError
            ? error.message.toString()
            : 'The catalog could not be reached. Please try again.',
      ),
      data: (items) {
        if (items.isEmpty) {
          return _hasSearched
              ? const _SearchMessage(
                  icon: Icons.search_off_rounded,
                  title: 'No matches found',
                  body: 'Try another title, spelling, or Japanese name.',
                )
              : const _SearchMessage(
                  icon: Icons.manage_search_rounded,
                  title: 'Find your next show',
                  body: 'Search results will appear here.',
                );
        }
        if (context.isCompactWidth) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisExtent: 225,
              crossAxisSpacing: 10,
              mainAxisSpacing: 14,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final anime = items[index];
              return _SearchCard(
                anime: anime,
                titlePreference: titlePreference,
                onPressed: () => context.push('/anime/${anime.id}'),
              );
            },
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
                      if (animeAiringStatusLabel(anime.status) != null)
                        Positioned(
                          left: 5,
                          top: 5,
                          child: PosterAiringStatusBadge(status: anime.status),
                        ),
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
