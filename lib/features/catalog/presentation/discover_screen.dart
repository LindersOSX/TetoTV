import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/catalog_grid.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  String? _genre;
  String? _format;
  String? _status;
  String _sort = 'POPULARITY_DESC';
  late Future<List<AnimeSummary>> _results;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _results = ref
        .read(catalogClientProvider)
        .discover(
          CatalogFilters(
            genre: _genre,
            format: _format,
            status: _status,
            sort: _sort,
          ),
        );
  }

  void _change(VoidCallback update) {
    setState(() {
      update();
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(34, 24, 34, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Back(onPressed: context.pop),
                const SizedBox(width: 16),
                Text(
                  'Discover',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(width: 18),
                const Expanded(
                  child: Text(
                    'Filter AniList by genre, format, status, and ranking',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FilterRow(
              label: 'GENRE',
              values: const [
                null,
                'Action',
                'Adventure',
                'Comedy',
                'Drama',
                'Fantasy',
                'Romance',
                'Sci-Fi',
              ],
              selected: _genre,
              onSelected: (value) => _change(() => _genre = value),
            ),
            _FilterRow(
              label: 'FORMAT',
              values: const [null, 'TV', 'MOVIE', 'ONA', 'OVA', 'TV_SHORT'],
              selected: _format,
              onSelected: (value) => _change(() => _format = value),
            ),
            _FilterRow(
              label: 'STATUS',
              values: const [null, 'RELEASING', 'FINISHED', 'NOT_YET_RELEASED'],
              selected: _status,
              onSelected: (value) => _change(() => _status = value),
            ),
            _FilterRow(
              label: 'SORT',
              values: const [
                'POPULARITY_DESC',
                'TRENDING_DESC',
                'SCORE_DESC',
                'START_DATE_DESC',
              ],
              selected: _sort,
              onSelected: (value) => _change(() => _sort = value!),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<AnimeSummary>>(
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentBright,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load discovery: ${snapshot.error}',
                      ),
                    );
                  }
                  return CatalogGrid(
                    items: snapshot.data ?? const [],
                    titlePreference: titlePreference,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<String?> values;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 39,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final value = values[index];
                final active = selected == value;
                return TvFocusable(
                  onPressed: () => onSelected(value),
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    color: active ? AppColors.accent : const Color(0xFF181818),
                    child: Text(
                      (value ?? 'ANY').replaceAll('_', ' '),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TvFocusable(
    onPressed: onPressed,
    child: const ColoredBox(
      color: Color(0xFF181818),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: 18),
            SizedBox(width: 6),
            Text('Back'),
          ],
        ),
      ),
    ),
  );
}
