import 'package:anime_tv/core/preferences/title_language_preference.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/network_artwork.dart';
import 'package:anime_tv/core/widgets/poster_metadata_overlay.dart';
import 'package:anime_tv/core/storage/storage_providers.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/display_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/tracking/application/tracking_home_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AnimeDetailsScreen extends ConsumerWidget {
  const AnimeDetailsScreen({required this.animeId, super.key});

  final int animeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(animeDetailsProvider(animeId));
    return Scaffold(
      body: details.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.cyan),
        ),
        error: (error, _) => _DetailsError(
          message: error.toString(),
          onBack: context.pop,
          onRetry: () => ref.invalidate(animeDetailsProvider(animeId)),
        ),
        data: (anime) => _DetailsContent(anime: anime),
      ),
    );
  }
}

class _DetailsContent extends ConsumerStatefulWidget {
  const _DetailsContent({required this.anime});

  final AnimeSummary anime;

  @override
  ConsumerState<_DetailsContent> createState() => _DetailsContentState();
}

class _DetailsContentState extends ConsumerState<_DetailsContent> {
  int? _selectedEpisode;

  AnimeSummary get anime => widget.anime;

  @override
  Widget build(BuildContext context) {
    final titlePreference = ref.watch(titleLanguagePreferenceProvider);
    final preferences = ref.watch(settingsPreferencesProvider);
    final knownEpisodes = (anime.episodes != null && anime.episodes! > 0)
        ? anime.episodes!
        : ((anime.nextAiringEpisode ?? 1) - 1).clamp(1, 999);

    final tracking = ref.watch(trackingHomeProvider).valueOrNull;
    final localPlayback = ref
        .watch(latestPlaybackProvider(anime.id))
        .valueOrNull;
    final trackedItem = tracking?.watching
        .where(
          (item) =>
              item.anilistId == anime.id ||
              (anime.idMal != null &&
                  item.provider == TrackingProvider.myAnimeList &&
                  item.tracked.mediaId == anime.idMal),
        )
        .firstOrNull;
    final progress = trackedItem?.tracked.progress ?? 0;

    final localResume =
        localPlayback != null &&
        !localPlayback.completed &&
        localPlayback.position > const Duration(seconds: 15);
    final targetEpisode = (localResume ? localPlayback.episode : (progress + 1))
        .clamp(1, knownEpisodes);
    final selectedEpisode = (_selectedEpisode ?? targetEpisode).clamp(
      1,
      knownEpisodes,
    );
    final episodeActions = _EpisodeActions(
      selectedEpisode: selectedEpisode,
      resumeEpisode: targetEpisode,
      totalEpisodes: knownEpisodes,
      hasProgress: progress > 0 || localResume,
      resumePosition: localResume ? localPlayback.position : null,
      onDecrease: selectedEpisode > 1
          ? () => setState(() => _selectedEpisode = selectedEpisode - 1)
          : null,
      onIncrease: selectedEpisode < knownEpisodes
          ? () => setState(() => _selectedEpisode = selectedEpisode + 1)
          : null,
      onPlayFromBeginning: () =>
          _openEpisode(context, anime, selectedEpisode, restart: true),
      onResume: () => _openEpisode(context, anime, targetEpisode),
      onPlaySelected: () => _openEpisode(context, anime, selectedEpisode),
      onFranchise: anime.relatedAnime.isEmpty
          ? null
          : () => context.push('/anime/${anime.id}/franchise'),
      onCredits:
          anime.studios.isEmpty &&
              anime.staff.isEmpty &&
              anime.characters.isEmpty
          ? null
          : () => context.push('/anime/${anime.id}/credits'),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        NetworkArtwork(
          url: anime.bannerImageUrl ?? anime.coverImageUrl,
          cacheWidth: 1000,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xF5000000), Color(0xB8000000), Color(0xFA000000)],
              stops: [0, .52, 1],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        SafeArea(
          minimum: context.responsiveScreenPadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 700) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _DetailsBack(onPressed: context.pop),
                        const Spacer(),
                        Text(
                          'EP $selectedEpisode / $knownEpisodes',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 112,
                                  height: 168,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: NetworkArtwork(
                                      url: anime.coverImageUrl,
                                      cacheWidth: 240,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        anime.displayTitle(titlePreference),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 9),
                                      _MetadataRow(anime: anime),
                                      if (anime.status case final status?) ...[
                                        const SizedBox(height: 9),
                                        Text(
                                          'Status: ${status.replaceAll('_', ' ')}',
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              anime.description.isEmpty
                                  ? 'No synopsis is available.'
                                  : anime.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 18),
                            episodeActions,
                            if (anime.relatedAnime.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              const Text(
                                'RELATED',
                                style: TextStyle(
                                  color: AppColors.accentBright,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 96 * preferences.thumbnailScale,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: anime.relatedAnime.length,
                                  separatorBuilder: (_, _) => SizedBox(
                                    width:
                                        10 *
                                        preferences.contentDensity.spacingScale,
                                  ),
                                  itemBuilder: (context, index) {
                                    final related = anime.relatedAnime[index];
                                    return _RelatedCard(
                                      related: related,
                                      titlePreference: titlePreference,
                                      thumbnailScale:
                                          preferences.thumbnailScale,
                                      onPressed: () => context.push(
                                        '/anime/${related.anime.id}',
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
              final spacious = constraints.maxWidth >= 1080;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _DetailsBack(onPressed: context.pop, autofocus: false),
                      const Spacer(),
                      Text(
                        'EPISODE $selectedEpisode OF $knownEpisodes',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: spacious ? 205 : 170,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                NetworkArtwork(
                                  url: anime.coverImageUrl,
                                  cacheWidth: spacious ? 430 : 350,
                                ),
                                if (anime.score != null ||
                                    anime.seasonYear != null ||
                                    anime.durationMinutes != null)
                                  Positioned(
                                    left: 9,
                                    right: 9,
                                    bottom: 9,
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
                        SizedBox(width: spacious ? 28 : 22),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  anime.displayTitle(titlePreference),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.displaySmall,
                                ),
                                const SizedBox(height: 10),
                                _MetadataRow(anime: anime),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Text(
                                    anime.description.isEmpty
                                        ? 'No synopsis is available.'
                                        : anime.description,
                                    maxLines: spacious ? 9 : 6,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ),
                                if (anime.status case final status?)
                                  Text(
                                    'Status: ${status.replaceAll('_', ' ')}',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: spacious ? 28 : 20),
                        SizedBox(
                          width: spacious ? 305 : 252,
                          child: episodeActions,
                        ),
                      ],
                    ),
                  ),
                  if (anime.relatedAnime.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          'RELATED',
                          style: TextStyle(
                            color: AppColors.accentBright,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Sequels, prequels, and connected stories',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      height: 88 * preferences.thumbnailScale,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: anime.relatedAnime.length,
                        separatorBuilder: (_, _) => SizedBox(
                          width: 10 * preferences.contentDensity.spacingScale,
                        ),
                        itemBuilder: (context, index) {
                          final related = anime.relatedAnime[index];
                          return _RelatedCard(
                            related: related,
                            titlePreference: titlePreference,
                            thumbnailScale: preferences.thumbnailScale,
                            onPressed: () =>
                                context.push('/anime/${related.anime.id}'),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({
    required this.related,
    required this.titlePreference,
    required this.onPressed,
    required this.thumbnailScale,
  });

  final RelatedAnime related;
  final TitleLanguagePreference titlePreference;
  final VoidCallback onPressed;
  final double thumbnailScale;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210 * thumbnailScale,
      child: TvFocusable(
        onPressed: onPressed,
        focusScale: 1.02,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: const Color(0xF20B0B0B),
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              SizedBox(
                width: 50 * thumbnailScale,
                height: double.infinity,
                child: NetworkArtwork(
                  url: related.anime.coverImageUrl,
                  cacheWidth: 110,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      related.relationType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.accentBright,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      related.anime.displayTitle(titlePreference),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.anime});

  final AnimeSummary anime;

  @override
  Widget build(BuildContext context) {
    final values = <String>[
      if (anime.format case final format?) format.replaceAll('_', ' '),
      if (anime.episodes case final episodes?) '$episodes episodes',
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final value in [...values, ...anime.genres.take(3)])
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .36),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _EpisodeActions extends StatelessWidget {
  const _EpisodeActions({
    required this.selectedEpisode,
    required this.resumeEpisode,
    required this.totalEpisodes,
    required this.hasProgress,
    required this.resumePosition,
    required this.onDecrease,
    required this.onIncrease,
    required this.onPlayFromBeginning,
    required this.onResume,
    required this.onPlaySelected,
    required this.onFranchise,
    required this.onCredits,
  });

  final int selectedEpisode;
  final int resumeEpisode;
  final int totalEpisodes;
  final bool hasProgress;
  final Duration? resumePosition;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final VoidCallback onPlayFromBeginning;
  final VoidCallback onResume;
  final VoidCallback onPlaySelected;
  final VoidCallback? onFranchise;
  final VoidCallback? onCredits;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EpisodeActionButton(
            label: 'Play from beginning',
            icon: Icons.replay_rounded,
            onPressed: onPlayFromBeginning,
          ),
          const SizedBox(height: 8),
          _EpisodeActionButton(
            label: resumePosition == null
                ? (hasProgress ? 'Resume' : 'Start watching')
                : 'Resume at ${_formatDuration(resumePosition!)}',
            trailing: 'EP-$resumeEpisode',
            icon: Icons.play_arrow_rounded,
            primary: true,
            autofocus: true,
            onPressed: onResume,
          ),
          const SizedBox(height: 8),
          _EpisodeActionButton(
            label: 'Play selected',
            trailing: 'EP-$selectedEpisode',
            icon: Icons.skip_next_rounded,
            onPressed: onPlaySelected,
          ),
          const SizedBox(height: 10),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _EpisodeStepButton(
                  icon: Icons.remove_rounded,
                  label: 'Previous episode',
                  onPressed: onDecrease,
                ),
                Expanded(
                  child: Text(
                    'Episode $selectedEpisode / $totalEpisodes',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                _EpisodeStepButton(
                  icon: Icons.add_rounded,
                  label: 'Next episode',
                  onPressed: onIncrease,
                ),
              ],
            ),
          ),
          if (onFranchise != null || onCredits != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (onFranchise != null)
                  Expanded(
                    child: _EpisodeActionButton(
                      label: 'Franchise',
                      icon: Icons.account_tree_rounded,
                      onPressed: onFranchise!,
                    ),
                  ),
                if (onFranchise != null && onCredits != null)
                  const SizedBox(width: 8),
                if (onCredits != null)
                  Expanded(
                    child: _EpisodeActionButton(
                      label: 'Cast & crew',
                      icon: Icons.groups_rounded,
                      onPressed: onCredits!,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeActionButton extends StatelessWidget {
  const _EpisodeActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.trailing,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final String? trailing;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        color: primary ? AppColors.accent : const Color(0xFF1B1B1B),
        child: Row(
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (trailing case final value?)
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeStepButton extends StatelessWidget {
  const _EpisodeStepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Opacity(
        opacity: onPressed == null ? .32 : 1,
        child: TvFocusable(
          focusScale: 1.04,
          borderRadius: BorderRadius.circular(9),
          onPressed: onPressed ?? () {},
          child: SizedBox(width: 48, height: 48, child: Icon(icon, size: 22)),
        ),
      ),
    );
  }
}

class _DetailsBack extends StatelessWidget {
  const _DetailsBack({required this.onPressed, this.autofocus = false});

  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TvFocusable(
        autofocus: autofocus,
        onPressed: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: const ColoredBox(
          color: Color(0xCC111111),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded, size: 20),
                SizedBox(width: 8),
                Text('Back'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailsError extends StatelessWidget {
  const _DetailsError({
    required this.message,
    required this.onBack,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.all(42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailsBack(onPressed: onBack),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 66,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Could not load anime',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 20),
                  TvFocusable(
                    onPressed: onRetry,
                    child: const ColoredBox(
                      color: AppColors.textPrimary,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                        child: Text(
                          'Retry',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

void _openEpisode(
  BuildContext context,
  AnimeSummary anime,
  int episode, {
  bool restart = false,
}) {
  context.push(
    Uri(
      path: '/resolve',
      queryParameters: {
        'anilistId': '${anime.id}',
        if (anime.idMal != null) 'malId': '${anime.idMal}',
        'title': anime.title,
        'episode': '$episode',
        if (anime.coverImageUrl != null) 'cover': anime.coverImageUrl!,
        if (restart) 'restart': '1',
        if (anime.synonyms.isNotEmpty) 'synonyms': anime.synonyms.join('|'),
      },
    ).toString(),
  );
}
