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
    final isUnreleased = animeAiringStatusLabel(anime.status) == 'UNRELEASED';
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
    _EpisodeActions episodeActions({required bool autofocusPrimary}) =>
        _EpisodeActions(
          isAvailable: !isUnreleased,
          autofocusPrimary: autofocusPrimary,
          selectedEpisode: selectedEpisode,
          resumeEpisode: targetEpisode,
          totalEpisodes: knownEpisodes,
          hasProgress: progress > 0 || localResume,
          resumePosition: localResume ? localPlayback.position : null,
          onDecrease: !isUnreleased && selectedEpisode > 1
              ? () => setState(() => _selectedEpisode = selectedEpisode - 1)
              : null,
          onIncrease: !isUnreleased && selectedEpisode < knownEpisodes
              ? () => setState(() => _selectedEpisode = selectedEpisode + 1)
              : null,
          onPlayFromBeginning: isUnreleased
              ? null
              : () => _openEpisode(
                  context,
                  anime,
                  selectedEpisode,
                  restart: true,
                ),
          onResume: isUnreleased
              ? null
              : () => _openEpisode(context, anime, targetEpisode),
          onPlaySelected: isUnreleased
              ? null
              : () => _openEpisode(context, anime, selectedEpisode),
        );
    final onFranchise = anime.relatedAnime.isEmpty
        ? null
        : () => context.push('/anime/${anime.id}/franchise');
    final onCredits =
        anime.studios.isEmpty && anime.staff.isEmpty && anime.characters.isEmpty
        ? null
        : () => context.push('/anime/${anime.id}/credits');
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
              final useCompactLayout =
                  constraints.maxWidth < 700 ||
                  constraints.maxHeight > constraints.maxWidth ||
                  (constraints.maxWidth < 900 && constraints.maxHeight < 520);
              if (useCompactLayout) {
                final portrait = constraints.maxHeight > constraints.maxWidth;
                final posterWidth =
                    (constraints.maxWidth * (portrait ? .24 : .18))
                        .clamp(112.0, portrait ? 320.0 : 168.0)
                        .toDouble();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _DetailsBack(onPressed: context.pop, autofocus: true),
                        const Spacer(),
                        _EpisodeCounterBadge(
                          selectedEpisode: selectedEpisode,
                          totalEpisodes: knownEpisodes,
                          compact: true,
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
                                  key: const ValueKey('anime-details-poster'),
                                  width: posterWidth,
                                  height: posterWidth * 1.5,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        NetworkArtwork(
                                          url: anime.coverImageUrl,
                                          cacheWidth: 240,
                                        ),
                                        if (animeAiringStatusLabel(
                                              anime.status,
                                            ) !=
                                            null)
                                          Positioned(
                                            left: 7,
                                            top: 7,
                                            child: PosterAiringStatusBadge(
                                              status: anime.status,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    key: const ValueKey('anime-details-info'),
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
                            const SizedBox(height: 14),
                            _MetadataRow(anime: anime),
                            const SizedBox(height: 12),
                            _MediaFactsRow(anime: anime),
                            const SizedBox(height: 16),
                            Text(
                              anime.description.isEmpty
                                  ? 'No synopsis is available.'
                                  : anime.description,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 18),
                            episodeActions(autofocusPrimary: false),
                            if (onFranchise != null || onCredits != null) ...[
                              const SizedBox(height: 12),
                              _InformationActions(
                                onFranchise: onFranchise,
                                onCredits: onCredits,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }
              final wide = constraints.maxWidth >= 1500;
              final spacious = constraints.maxWidth >= 1080;
              final posterWidth = wide ? 340.0 : (spacious ? 255.0 : 175.0);
              final actionWidth = wide ? 460.0 : (spacious ? 350.0 : 252.0);
              final columnGap = wide ? 48.0 : (spacious ? 30.0 : 20.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _DetailsBack(
                        onPressed: context.pop,
                        autofocus: isUnreleased,
                      ),
                      const Spacer(),
                      _EpisodeCounterBadge(
                        selectedEpisode: selectedEpisode,
                        totalEpisodes: knownEpisodes,
                        large: wide,
                      ),
                    ],
                  ),
                  SizedBox(height: wide ? 38 : 14),
                  Expanded(
                    child: Center(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            key: const ValueKey('anime-details-poster'),
                            width: posterWidth,
                            child: AspectRatio(
                              aspectRatio: 2 / 3,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .2),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(19),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      NetworkArtwork(
                                        url: anime.coverImageUrl,
                                        cacheWidth: wide
                                            ? 680
                                            : (spacious ? 540 : 360),
                                      ),
                                      if (animeAiringStatusLabel(
                                            anime.status,
                                          ) !=
                                          null)
                                        Positioned(
                                          left: wide ? 18 : 9,
                                          top: wide ? 18 : 9,
                                          child: PosterAiringStatusBadge(
                                            status: anime.status,
                                          ),
                                        ),
                                      if (anime.score != null ||
                                          anime.seasonYear != null ||
                                          anime.durationMinutes != null)
                                        Positioned(
                                          left: wide ? 18 : 9,
                                          right: wide ? 18 : 9,
                                          bottom: wide ? 18 : 9,
                                          child: PosterMetadataOverlay(
                                            score: anime.score,
                                            releaseYear: anime.seasonYear,
                                            durationMinutes:
                                                anime.durationMinutes,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: columnGap),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Column(
                                key: const ValueKey('anime-details-info'),
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    anime.displayTitle(titlePreference),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(
                                          fontSize: wide
                                              ? 58
                                              : (spacious ? 44 : 34),
                                          height: 1,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                  SizedBox(height: wide ? 20 : 10),
                                  _MetadataRow(anime: anime),
                                  SizedBox(height: wide ? 18 : 10),
                                  _MediaFactsRow(anime: anime),
                                  SizedBox(height: wide ? 24 : 12),
                                  Text(
                                    anime.description.isEmpty
                                        ? 'No synopsis is available.'
                                        : anime.description,
                                    maxLines: wide ? 8 : (spacious ? 7 : 5),
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: AppColors.textPrimary,
                                          fontSize: wide ? 18 : 15,
                                          height: 1.48,
                                        ),
                                  ),
                                  if (anime.status case final status?) ...[
                                    SizedBox(height: wide ? 20 : 10),
                                    Text(
                                      'Status:  ${status.replaceAll('_', ' ')}',
                                      style: TextStyle(
                                        color: AppColors.accentBright,
                                        fontSize: wide ? 17 : 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                  if (onFranchise != null ||
                                      onCredits != null) ...[
                                    SizedBox(height: wide ? 22 : 12),
                                    _InformationActions(
                                      onFranchise: onFranchise,
                                      onCredits: onCredits,
                                      large: wide,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: columnGap),
                          SizedBox(
                            width: actionWidth,
                            child: episodeActions(autofocusPrimary: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
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
      ...anime.genres.take(3),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final value in values)
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

class _EpisodeCounterBadge extends StatelessWidget {
  const _EpisodeCounterBadge({
    required this.selectedEpisode,
    required this.totalEpisodes,
    this.large = false,
    this.compact = false,
  });

  final int selectedEpisode;
  final int totalEpisodes;
  final bool large;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 20 : (compact ? 10 : 14),
        vertical: large ? 11 : (compact ? 7 : 8),
      ),
      decoration: BoxDecoration(
        color: const Color(0xD9111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Text(
        compact
            ? 'EP $selectedEpisode / $totalEpisodes'
            : 'EPISODE $selectedEpisode OF $totalEpisodes',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: large ? 15 : (compact ? 10 : 12),
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _MediaFactsRow extends StatelessWidget {
  const _MediaFactsRow({required this.anime});

  final AnimeSummary anime;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final large = width >= 1500;
    return Wrap(
      spacing: large ? 22 : 14,
      runSpacing: 8,
      children: [
        if (anime.seasonYear case final year?)
          _MediaFact(
            icon: Icons.calendar_today_outlined,
            label: '$year',
            large: large,
          ),
        if (anime.durationMinutes case final minutes?)
          _MediaFact(
            icon: Icons.schedule_rounded,
            label: '${minutes}m',
            large: large,
          ),
        if (anime.score case final score?)
          _MediaFact(
            icon: Icons.star_border_rounded,
            label: '${score.toStringAsFixed(1)} / 10',
            large: large,
            accent: true,
          ),
      ],
    );
  }
}

class _MediaFact extends StatelessWidget {
  const _MediaFact({
    required this.icon,
    required this.label,
    required this.large,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool large;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: large ? 22 : 17,
          color: accent ? AppColors.accentBright : AppColors.textMuted,
        ),
        SizedBox(width: large ? 8 : 5),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: large ? 17 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _InformationActions extends StatelessWidget {
  const _InformationActions({
    required this.onFranchise,
    required this.onCredits,
    this.large = false,
  });

  final VoidCallback? onFranchise;
  final VoidCallback? onCredits;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        if (onCredits != null)
          _InformationButton(
            label: 'Cast & crew',
            icon: Icons.groups_rounded,
            onPressed: onCredits!,
            large: large,
          ),
        if (onFranchise != null)
          _InformationButton(
            label: 'Related series',
            icon: Icons.account_tree_rounded,
            onPressed: onFranchise!,
            large: large,
          ),
      ],
    );
  }
}

class _InformationButton extends StatelessWidget {
  const _InformationButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.large,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: large ? 58 : 42,
        padding: EdgeInsets.symmetric(horizontal: large ? 20 : 13),
        decoration: BoxDecoration(
          color: const Color(0xEE171717),
          border: Border.all(color: Colors.white.withValues(alpha: .15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: large ? 23 : 18),
            SizedBox(width: large ? 10 : 7),
            Text(
              label,
              style: TextStyle(
                fontSize: large ? 16 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: large ? 12 : 7),
            Icon(Icons.chevron_right_rounded, size: large ? 22 : 17),
          ],
        ),
      ),
    );
  }
}

class _EpisodeActions extends StatelessWidget {
  const _EpisodeActions({
    required this.isAvailable,
    required this.autofocusPrimary,
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
  });

  final bool isAvailable;
  final bool autofocusPrimary;
  final int selectedEpisode;
  final int resumeEpisode;
  final int totalEpisodes;
  final bool hasProgress;
  final Duration? resumePosition;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;
  final VoidCallback? onPlayFromBeginning;
  final VoidCallback? onResume;
  final VoidCallback? onPlaySelected;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 1500;
    return Container(
      key: const ValueKey('episode-actions-panel'),
      width: double.infinity,
      padding: EdgeInsets.all(large ? 22 : 8),
      decoration: BoxDecoration(
        color: const Color(0xF5111111),
        borderRadius: BorderRadius.circular(large ? 20 : 14),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EpisodeActionButton(
            key: const ValueKey('episode-action-resume'),
            label: !isAvailable
                ? 'Not released yet'
                : resumePosition == null
                ? (hasProgress ? 'Resume' : 'Start watching')
                : 'Resume at ${_formatDuration(resumePosition!)}',
            trailing: isAvailable ? 'EP-$resumeEpisode' : null,
            icon: Icons.play_arrow_rounded,
            primary: true,
            autofocus: isAvailable && autofocusPrimary,
            onPressed: onResume,
            large: large,
          ),
          SizedBox(height: large ? 14 : 6),
          _EpisodeActionButton(
            key: const ValueKey('episode-action-restart'),
            label: 'Play from beginning',
            icon: Icons.replay_rounded,
            onPressed: onPlayFromBeginning,
            large: large,
          ),
          SizedBox(height: large ? 14 : 6),
          _EpisodeActionButton(
            key: const ValueKey('episode-action-selected'),
            label: 'Play selected',
            trailing: 'EP-$selectedEpisode',
            icon: Icons.skip_next_rounded,
            onPressed: onPlaySelected,
            large: large,
          ),
          SizedBox(height: large ? 22 : 7),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'EPISODE',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: large ? 13 : 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          SizedBox(height: large ? 10 : 5),
          Container(
            height: large ? 68 : 44,
            decoration: BoxDecoration(
              color: const Color(0xFF191919),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: .14)),
            ),
            child: Row(
              children: [
                _EpisodeStepButton(
                  key: const ValueKey('episode-step-previous'),
                  icon: Icons.remove_rounded,
                  label: 'Previous episode',
                  onPressed: onDecrease,
                ),
                Expanded(
                  child: Text(
                    'Episode $selectedEpisode of $totalEpisodes',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: large ? 16 : 13,
                    ),
                  ),
                ),
                _EpisodeStepButton(
                  key: const ValueKey('episode-step-next'),
                  icon: Icons.add_rounded,
                  label: 'Next episode',
                  onPressed: onIncrease,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeActionButton extends StatelessWidget {
  const _EpisodeActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.trailing,
    this.primary = false,
    this.autofocus = false,
    this.large = false,
  });

  final String label;
  final String? trailing;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool autofocus;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final content = Container(
      height: large ? 76 : 42,
      padding: EdgeInsets.symmetric(horizontal: large ? 22 : 13),
      color: primary ? AppColors.accent : const Color(0xFF1B1B1B),
      child: Row(
        children: [
          Icon(icon, size: large ? 29 : 19),
          SizedBox(width: large ? 16 : 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: large ? 18 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (trailing case final value?)
            Text(
              value,
              style: TextStyle(
                color: Colors.white70,
                fontSize: large ? 14 : 11,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
    if (!enabled) {
      return Semantics(
        button: true,
        enabled: false,
        child: Opacity(opacity: .38, child: content),
      );
    }
    return TvFocusable(
      autofocus: autofocus,
      focusScale: 1.025,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed!,
      child: content,
    );
  }
}

class _EpisodeStepButton extends StatelessWidget {
  const _EpisodeStepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: 48,
      height: 48,
      child: Icon(icon, size: 22),
    );
    if (onPressed == null) {
      return Semantics(
        label: label,
        button: true,
        enabled: false,
        child: Opacity(opacity: .32, child: content),
      );
    }
    return Semantics(
      label: label,
      button: true,
      enabled: true,
      child: TvFocusable(
        focusScale: 1.04,
        borderRadius: BorderRadius.circular(9),
        onPressed: onPressed!,
        child: content,
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
  final alternativeTitles = <String?>{
    anime.titleEnglish,
    anime.titleRomaji,
    ...anime.synonyms,
  }.whereType<String>().toSet()..remove(anime.title);
  context.push(
    Uri(
      path: '/resolve',
      queryParameters: {
        'anilistId': '${anime.id}',
        if (anime.idMal != null) 'malId': '${anime.idMal}',
        'title': anime.title,
        'episode': '$episode',
        if (anime.seasonYear != null) 'year': '${anime.seasonYear}',
        if (anime.coverImageUrl != null) 'cover': anime.coverImageUrl!,
        if (restart) 'restart': '1',
        if (alternativeTitles.isNotEmpty)
          'synonyms': alternativeTitles.join('|'),
      },
    ).toString(),
  );
}
