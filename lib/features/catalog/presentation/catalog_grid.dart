import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/widgets/poster_metadata_overlay.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class CatalogGrid extends StatelessWidget {
  const CatalogGrid({
    required this.items,
    required this.titlePreference,
    this.autofocus = true,
    this.firstFocusNode,
    this.onNavigateUpFromFirstRow,
    this.onLongPress,
    super.key,
  });

  final List<AnimeSummary> items;
  final TitleLanguagePreference titlePreference;
  final bool autofocus;
  final FocusNode? firstFocusNode;
  final VoidCallback? onNavigateUpFromFirstRow;
  final ValueChanged<AnimeSummary>? onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const maximumCardWidth = 150.0;
        const crossAxisSpacing = 10.0;
        final crossAxisCount = items.isEmpty
            ? 1
            : ((constraints.maxWidth + crossAxisSpacing) /
                      (maximumCardWidth + crossAxisSpacing))
                  .ceil()
                  .clamp(1, items.length);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 28),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maximumCardWidth,
            childAspectRatio: .57,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisSpacing: 14,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final anime = items[index];
            return TvFocusable(
              focusNode: index == 0 ? firstFocusNode : null,
              autofocus: autofocus && index == 0,
              onKeyEvent: (node, event) {
                if (onNavigateUpFromFirstRow != null &&
                    index < crossAxisCount &&
                    event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  onNavigateUpFromFirstRow!();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              onPressed: () => context.push('/anime/${anime.id}'),
              onLongPress: onLongPress == null
                  ? null
                  : () => onLongPress!(anime),
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
                      // TvFocusable paints a 3 px focus ring plus an inner
                      // keyline over the card. Keep title glyphs clear of it
                      // on every edge instead of letting the red ring cover
                      // the first letter or second-line descenders.
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
      },
    );
  }
}
