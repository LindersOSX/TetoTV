import 'package:anime_tv/features/auth/presentation/anilist_pairing_screen.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/auth/presentation/real_debrid_pairing_screen.dart';
import 'package:anime_tv/features/auth/presentation/torbox_pairing_screen.dart';
import 'package:anime_tv/features/catalog/presentation/anime_details_screen.dart';
import 'package:anime_tv/features/catalog/presentation/search_screen.dart';
import 'package:anime_tv/features/catalog/presentation/discover_screen.dart';
import 'package:anime_tv/features/catalog/presentation/airing_calendar_screen.dart';
import 'package:anime_tv/features/catalog/presentation/franchise_screen.dart';
import 'package:anime_tv/features/catalog/presentation/credits_screen.dart';
import 'package:anime_tv/features/catalog/presentation/catalog_collection_screen.dart';
import 'package:anime_tv/features/home/presentation/home_screen.dart';
import 'package:anime_tv/features/marketplace/presentation/marketplace_screen.dart';
import 'package:anime_tv/features/player/presentation/tv_player_screen.dart';
import 'package:anime_tv/features/settings/presentation/accounts_screen.dart';
import 'package:anime_tv/features/tracking/presentation/my_list_screen.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/streaming/presentation/resolve_episode_screen.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/my-list',
      builder: (context, state) => const MyListScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) =>
          SearchScreen(initialQuery: state.uri.queryParameters['q']),
    ),
    GoRoute(
      path: '/discover',
      builder: (context, state) => const DiscoverScreen(),
    ),
    GoRoute(
      path: '/calendar',
      builder: (context, state) => const AiringCalendarScreen(),
    ),
    GoRoute(
      path: '/anime/:id',
      builder: (context, state) =>
          AnimeDetailsScreen(animeId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/anime/:id/franchise',
      builder: (context, state) =>
          FranchiseScreen(mediaId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/anime/:id/credits',
      builder: (context, state) =>
          CreditsScreen(mediaId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/studio/:id',
      builder: (context, state) => CatalogCollectionScreen(
        id: int.parse(state.pathParameters['id']!),
        name: state.uri.queryParameters['name'] ?? 'Studio',
        type: CatalogCollectionType.studio,
      ),
    ),
    GoRoute(
      path: '/staff/:id',
      builder: (context, state) => CatalogCollectionScreen(
        id: int.parse(state.pathParameters['id']!),
        name: state.uri.queryParameters['name'] ?? 'Staff member',
        type: CatalogCollectionType.staff,
      ),
    ),
    GoRoute(
      path: '/pair/anilist',
      builder: (context, state) =>
          const TrackingPairingScreen(provider: TrackingProvider.anilist),
    ),
    GoRoute(
      path: '/pair/myanimelist',
      builder: (context, state) =>
          const TrackingPairingScreen(provider: TrackingProvider.myAnimeList),
    ),
    GoRoute(
      path: '/pair/realdebrid',
      builder: (context, state) => const RealDebridPairingScreen(),
    ),
    GoRoute(
      path: '/pair/torbox',
      builder: (context, state) => const TorBoxPairingScreen(),
    ),
    GoRoute(
      path: '/settings/accounts',
      builder: (context, state) => const AccountsScreen(),
    ),
    GoRoute(
      path: '/settings/marketplace',
      builder: (context, state) => const MarketplaceScreen(),
    ),
    GoRoute(
      path: '/resolve',
      builder: (context, state) {
        final query = state.uri.queryParameters;
        return ResolveEpisodeScreen(
          episode: EpisodeReference(
            anilistMediaId: int.parse(query['anilistId']!),
            malMediaId: int.tryParse(query['malId'] ?? ''),
            title: query['title'] ?? 'Anime',
            episode: int.parse(query['episode'] ?? '1'),
            alternativeTitles:
                query['synonyms']
                    ?.split('|')
                    .where((value) => value.isNotEmpty)
                    .toList(growable: false) ??
                const [],
            coverImageUrl: query['cover'],
            startFromBeginning: query['restart'] == '1',
            autoPlay: query['autoplay'] == '1',
          ),
        );
      },
    ),
    GoRoute(
      path: '/player',
      builder: (context, state) {
        final query = state.uri.queryParameters;
        final source = query['source'];
        final service = DebridService.fromSlug(query['debrid']);
        final resolved = state.extra;
        final validTypedStream =
            resolved is PlaybackLaunch &&
            resolved.stream.uri.toString() == source &&
            ((resolved.stream.debridService != null &&
                    resolved.stream.debridService == service) ||
                (resolved.stream.isWebStream &&
                    service == null &&
                    resolved.stream.providerId?.isNotEmpty == true));
        if (source == null ||
            !source.startsWith('https://') ||
            !validTypedStream) {
          return const DebridOnlyPlaybackScreen();
        }
        final launch = resolved;
        return TvPlayerScreen(
          launch: launch,
          source: launch.stream.uri.toString(),
          subtitle: query['subtitle'],
          title: query['title'] ?? 'Anime playback',
          debridService: service ?? DebridService.realDebrid,
          anilistMediaId: launch.episode.anilistMediaId,
          malMediaId: launch.episode.malMediaId,
          episode: launch.episode.episode,
          coverImageUrl: launch.episode.coverImageUrl,
        );
      },
    ),
  ],
);
