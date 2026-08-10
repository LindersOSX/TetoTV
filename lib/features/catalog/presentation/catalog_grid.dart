import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/widgets/poster_metadata_overlay.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CatalogGrid extends StatelessWidget {
  const CatalogGrid({
    required this.items,
    required this.titlePreference,
    this.autofocus = true,
    super.key,
  });

  final List<AnimeSummary> items;
  final TitleLanguagePreference titlePreference;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 28),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: .57,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final anime = items[index];
        return TvFocusable(
          autofocus: autofocus && index == 0,
          onPressed: () => context.push('/anime/${anime.id}'),
          focusScale: 1.035,
          borderRadius: BorderRadius.circular(7),
          child: ColoredBox(
            color: Colors.black,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetworkArtwork(
                          url: anime.coverImageUrl,
                          cacheWidth: 260,
                        ),
                        if (animeAiringStatusLabel(anime.status) != null)
                          Positioned(
                            left: 5,
                            top: 5,
                            child: PosterAiringStatusBadge(
                              status: anime.status,
                            ),
                          ),
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
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    anime.displayTitle(titlePreference),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
