import 'dart:async';

import 'package:anime_tv/core/config/app_config.dart';
import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/features/marketplace/application/web_stream_aggregator.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/data/web_stream_validator.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/streaming/application/debrid_token_service.dart';
import 'package:anime_tv/features/streaming/data/hosted_release_source.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_stream_resolver.dart';
import 'package:anime_tv/features/streaming/data/torrentio_release_source.dart';
import 'package:anime_tv/features/streaming/data/torbox_client.dart';
import 'package:anime_tv/features/streaming/data/torbox_stream_resolver.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:anime_tv/features/streaming/domain/stream_resolver.dart';
import 'package:anime_tv/features/streaming/data/composite_release_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef DebridStreamResolverFactory =
    StreamResolver Function({
      required DebridService service,
      required String token,
      required ReleaseSource source,
    });

final debridStreamResolverFactoryProvider =
    Provider<DebridStreamResolverFactory>((_) {
      return ({required service, required token, required source}) =>
          switch (service) {
            DebridService.realDebrid => RealDebridStreamResolver(
              RealDebridClient(token: token),
              source,
            ),
            DebridService.torBox => TorBoxStreamResolver(
              TorBoxClient(token: token),
              source,
            ),
          };
    });

final configuredReleaseSourceProvider = Provider<ReleaseSource?>((_) {
  final sources = <ReleaseSource>[
    if (AppConfig.hasStremioAddon)
      TorrentioReleaseSource(manifestUrl: AppConfig.stremioAddonManifestUrl),
    if (AppConfig.hasReleaseResolver)
      HostedReleaseSource(baseUrl: AppConfig.releaseResolverBaseUrl),
  ];
  return sources.isEmpty ? null : CompositeReleaseSource(sources);
});

final webStreamPreflightProvider = Provider<WebStreamPreflight>(
  (_) => const WebStreamValidator().validate,
);

int tvPlaybackCompatibilityRank(
  ReleaseCandidate release, {
  TvDeviceProfile? device,
  int previousFailures = 0,
}) {
  final codec = release.codec?.toUpperCase();
  final codecRank = switch (codec) {
    'H.264' => 0,
    null => 1,
    'HEVC' => 2,
    'AV1' => 3,
    _ => 1,
  };
  final resolutionPenalty = switch (release.quality?.toLowerCase()) {
    '4k' || '2160p' => 2,
    '1440p' => 1,
    _ => 0,
  };
  final unsupportedCodec =
      device != null && !device.supportsCodec(release.codec) ? 12 : 0;
  final unsupportedHdr = release.isHdr && device != null && !device.hasHdr
      ? 8
      : 0;
  final softwareOnlyProfile = releaseRequiresSoftwareDecoder(release) ? 6 : 0;
  return codecRank +
      resolutionPenalty +
      (release.isHdr ? 2 : 0) +
      unsupportedCodec +
      unsupportedHdr +
      softwareOnlyProfile +
      previousFailures * 5;
}

bool isTvSafeRelease(ReleaseCandidate release) =>
    tvPlaybackCompatibilityRank(release) == 0;

bool releaseMatchesStreamFilters(
  ReleaseCandidate release, {
  String language = 'all',
  String quality = 'any',
  String codec = 'any',
  String hdr = 'any',
  bool allowBatch = true,
}) {
  if (language == 'dub' && !release.isDubbed) return false;
  if (language == 'sub' && release.isDubbed) return false;
  if (!allowBatch && release.isBatch) return false;
  final qualityText = '${release.quality ?? ''} ${release.releaseName}'
      .toLowerCase();
  if (quality == 'p2160' &&
      !qualityText.contains('2160') &&
      !qualityText.contains('4k')) {
    return false;
  }
  if (quality == 'p1080' && !qualityText.contains('1080')) return false;
  if (quality == 'p720' && !qualityText.contains('720')) return false;
  final codecText = '${release.codec ?? ''} ${release.releaseName}'
      .toLowerCase();
  if (codec == 'h264' &&
      !codecText.contains('264') &&
      !codecText.contains('avc')) {
    return false;
  }
  if (codec == 'hevc' &&
      !codecText.contains('hevc') &&
      !codecText.contains('265')) {
    return false;
  }
  if (codec == 'av1' && !codecText.contains('av1')) return false;
  if (hdr == 'hdr' && !release.isHdr) return false;
  if (hdr == 'sdr' && release.isHdr) return false;
  return true;
}

int compareStreamReleases(
  ReleaseCandidate left,
  ReleaseCandidate right, {
  TvDeviceProfile? device,
  Map<String, int> failureCounts = const {},
  String sortMode = 'compatibility',
  String? preferredProvider,
}) {
  final preferred = _providerRank(
    left,
    preferredProvider,
  ).compareTo(_providerRank(right, preferredProvider));
  if (preferred != 0) return preferred;
  switch (sortMode) {
    case 'seeders':
      final seeders = right.seeders.compareTo(left.seeders);
      if (seeders != 0) return seeders;
      break;
    case 'size':
      final size = _releaseSizeMb(left).compareTo(_releaseSizeMb(right));
      if (size != 0) return size;
      break;
    default:
      final compatibility =
          tvPlaybackCompatibilityRank(
            left,
            device: device,
            previousFailures: failureCounts[left.infoHash.toLowerCase()] ?? 0,
          ).compareTo(
            tvPlaybackCompatibilityRank(
              right,
              device: device,
              previousFailures:
                  failureCounts[right.infoHash.toLowerCase()] ?? 0,
            ),
          );
      if (compatibility != 0) return compatibility;
      break;
  }
  return right.seeders.compareTo(left.seeders);
}

int webStreamQualityRank(WebStreamResult stream) {
  final value = '${stream.quality ?? ''} ${stream.title}'.toLowerCase();
  if (value.contains('4320') || value.contains('8k')) return 7;
  if (value.contains('2160') || value.contains('4k') || value.contains('uhd')) {
    return 6;
  }
  if (value.contains('1440') || value.contains('2k')) return 5;
  if (value.contains('1080') || value.contains('full hd')) return 4;
  if (value.contains('720') || RegExp(r'\bhd\b').hasMatch(value)) return 3;
  if (value.contains('576')) return 2;
  if (value.contains('480') || value.contains('360')) return 1;
  return 0;
}

int compareWebStreamsByQuality(WebStreamResult left, WebStreamResult right) {
  final quality = webStreamQualityRank(
    right,
  ).compareTo(webStreamQualityRank(left));
  if (quality != 0) return quality;
  final provider = left.providerName.compareTo(right.providerName);
  return provider != 0 ? provider : left.title.compareTo(right.title);
}

int _providerRank(ReleaseCandidate release, String? preferredProvider) {
  if (preferredProvider == null || preferredProvider.isEmpty) return 1;
  return release.provider?.toLowerCase() == preferredProvider.toLowerCase()
      ? 0
      : 1;
}

double _releaseSizeMb(ReleaseCandidate release) {
  final value = release.sizeLabel?.toUpperCase() ?? '';
  final amount = double.tryParse(
    RegExp(r'[\d.]+').firstMatch(value)?.group(0) ?? '',
  );
  if (amount == null) return double.maxFinite;
  if (value.contains('TB')) return amount * 1024 * 1024;
  if (value.contains('GB')) return amount * 1024;
  if (value.contains('KB')) return amount / 1024;
  return amount;
}

T _enumByName<T extends Enum>(List<T> values, String name, T fallback) {
  return values.where((value) => value.name == name).firstOrNull ?? fallback;
}

class ResolveEpisodeScreen extends ConsumerStatefulWidget {
  const ResolveEpisodeScreen({required this.episode, super.key});

  final EpisodeReference episode;

  @override
  ConsumerState<ResolveEpisodeScreen> createState() =>
      _ResolveEpisodeScreenState();
}

class _ResolveEpisodeScreenState extends ConsumerState<ResolveEpisodeScreen> {
  final _magnetController = TextEditingController();
  bool _loadingAccount = true;
  bool _loadingReleases = false;
  bool _resolving = false;
  bool _showManual = false;
  bool _showAdvancedFilters = false;
  double _progress = 0;
  String _status = 'Preparing…';
  String? _error;
  List<ReleaseCandidate> _releases = const [];
  List<WebStreamResult> _webStreams = const [];
  List<WebProviderFailure> _webFailures = const [];
  List<ReleaseSourceFailure> _releaseFailures = const [];
  int _debridSourcesCompleted = 0;
  int _debridSourcesTotal = 0;
  int _webProvidersCompleted = 0;
  int _webProvidersTotal = 0;
  List<String> _pendingDebridSources = const [];
  List<String> _pendingWebProviders = const [];
  int _releaseSearchGeneration = 0;
  Set<DebridService> _connectedServices = const {};
  DebridService _debridService = DebridService.realDebrid;
  _StreamLanguageFilter _languageFilter = _StreamLanguageFilter.dub;
  _StreamQualityFilter _qualityFilter = _StreamQualityFilter.any;
  _StreamCodecFilter _codecFilter = _StreamCodecFilter.any;
  _StreamHdrFilter _hdrFilter = _StreamHdrFilter.any;
  _StreamSortMode _sortMode = _StreamSortMode.compatibility;
  bool _allowBatchStreams = true;
  SeriesPlaybackPreferences _seriesPreferences =
      const SeriesPlaybackPreferences();
  TvDeviceProfile _deviceProfile = const TvDeviceProfile.unknown();
  Map<String, int> _failureCounts = const {};
  ReleaseCandidate? _lastAttemptedRelease;
  int _resolveAttempt = 0;
  final Set<String> _failedResolveHashes = {};
  int _automaticResolveFallbacks = 0;
  bool _autoPlayStarted = false;

  bool get _hasDebrid =>
      ref.read(settingsPreferencesProvider).debridStreamsEnabled &&
      _connectedServices.contains(_debridService);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final tokenService = ref.read(debridTokenServiceProvider);
    final preferredDebrid = ref
        .read(settingsPreferencesProvider)
        .debridProvider;
    final tokensAndProfile = await Future.wait<Object?>([
      _usableToken(tokenService, DebridService.realDebrid),
      _usableToken(tokenService, DebridService.torBox),
      AndroidTvBridge.instance.getDeviceProfile(),
      TetoTvDatabase.instance
          .seriesPreferences(widget.episode.anilistMediaId)
          .catchError((_) => const SeriesPlaybackPreferences()),
    ]);
    final tokens = [
      tokensAndProfile[0] as String?,
      tokensAndProfile[1] as String?,
    ];
    final profile = tokensAndProfile[2] as TvDeviceProfile;
    final preferences = tokensAndProfile[3] as SeriesPlaybackPreferences;
    Map<String, int> failures = const {};
    try {
      failures = await TetoTvDatabase.instance.failureCounts(profile.key);
    } catch (_) {
      // Compatibility history improves sorting but is never required to find
      // or play a stream. A local database problem must not block Torrentio.
    }
    final connected = <DebridService>{
      if (tokens[0]?.isNotEmpty == true) DebridService.realDebrid,
      if (tokens[1]?.isNotEmpty == true) DebridService.torBox,
    };
    if (!mounted) return;
    setState(() {
      _connectedServices = connected;
      if (connected.contains(preferredDebrid)) {
        _debridService = preferredDebrid;
      } else if (!connected.contains(_debridService) && connected.isNotEmpty) {
        _debridService = connected.first;
      }
      _loadingAccount = false;
      _deviceProfile = profile;
      _failureCounts = failures;
      _seriesPreferences = preferences;
      _languageFilter = _enumByName(
        _StreamLanguageFilter.values,
        preferences.preferredStreamLanguage,
        _StreamLanguageFilter.dub,
      );
      _qualityFilter = _enumByName(
        _StreamQualityFilter.values,
        preferences.preferredQuality,
        _StreamQualityFilter.any,
      );
      _codecFilter = _enumByName(
        _StreamCodecFilter.values,
        preferences.preferredCodec,
        _StreamCodecFilter.any,
      );
      _hdrFilter = _enumByName(
        _StreamHdrFilter.values,
        preferences.preferredHdrMode,
        _StreamHdrFilter.any,
      );
      _sortMode = _enumByName(
        _StreamSortMode.values,
        preferences.streamSortMode,
        _StreamSortMode.compatibility,
      );
      _allowBatchStreams = preferences.allowBatchStreams;
    });
    await _loadConfiguredReleases();
  }

  Future<String?> _usableToken(
    DebridTokenService tokenService,
    DebridService service,
  ) async {
    try {
      return await tokenService.accessToken(service);
    } catch (_) {
      // Expired or unrefreshable credentials are not a connected service.
      // Resolution will remain available as soon as the user reconnects.
      return null;
    }
  }

  Future<void> _openSourceSettings(String route) async {
    await context.push(route);
    if (!mounted) return;
    setState(() => _loadingAccount = true);
    await _initialize();
  }

  Future<void> _loadConfiguredReleases() async {
    if (_loadingReleases) return;
    final preferences = ref.read(settingsPreferencesProvider);
    final source = ref.read(configuredReleaseSourceProvider);
    final shouldSearchDebrid =
        preferences.debridStreamsEnabled && source != null && _hasDebrid;
    var debridSearchFinished = !shouldSearchDebrid;
    final generation = ++_releaseSearchGeneration;
    setState(() {
      _loadingReleases = true;
      _status = 'Searching enabled stream sources…';
      _error = null;
      _releases = const [];
      _webStreams = const [];
      _webFailures = const [];
      _releaseFailures = const [];
      _debridSourcesCompleted = 0;
      _debridSourcesTotal = 0;
      _webProvidersCompleted = 0;
      _webProvidersTotal = 0;
      _pendingDebridSources = const [];
      _pendingWebProviders = const [];
    });

    Future<void> loadDebridSources() async {
      if (!shouldSearchDebrid) return;
      try {
        final progressStream = source is CompositeReleaseSource
            ? source.searchIncrementally(widget.episode)
            : searchReleaseSourcesIncrementally([source], widget.episode);
        await for (final progress in progressStream) {
          if (!mounted || generation != _releaseSearchGeneration) return;
          setState(() {
            _releases = progress.candidates;
            _releaseFailures = progress.failures;
            _debridSourcesCompleted = progress.completedSources;
            _debridSourcesTotal = progress.totalSources;
            _pendingDebridSources = progress.pendingSourceIds;
          });
          _tryStartAutoPlay(generation: generation, allowWebFallback: false);
        }
      } finally {
        debridSearchFinished = true;
        _tryStartAutoPlay(generation: generation, allowWebFallback: true);
      }
    }

    Future<void> loadWebProviders() async {
      if (!preferences.webStreamsEnabled) return;
      try {
        await for (final progress
            in ref
                .read(webStreamAggregatorProvider)
                .watchSearchIncrementally(widget.episode)) {
          if (!mounted || generation != _releaseSearchGeneration) return;
          setState(() {
            _webStreams = progress.aggregation.streams;
            _webFailures = progress.aggregation.failures;
            _webProvidersCompleted = progress.completedProviders;
            _webProvidersTotal = progress.totalProviders;
            _pendingWebProviders = progress.pendingProviderNames;
          });
          _tryStartAutoPlay(
            generation: generation,
            allowWebFallback: debridSearchFinished,
          );
        }
      } catch (error) {
        if (!mounted || generation != _releaseSearchGeneration) return;
        setState(() {
          _webFailures = [
            WebProviderFailure(
              providerName: 'Web providers',
              message: error.toString(),
            ),
          ];
        });
      }
    }

    try {
      await Future.wait([loadDebridSources(), loadWebProviders()]);
      if (!mounted || generation != _releaseSearchGeneration) return;
      setState(() {
        _loadingReleases = false;
        if (_releases.isEmpty && _webStreams.isEmpty) {
          if (!preferences.debridStreamsEnabled &&
              !preferences.webStreamsEnabled) {
            _error = 'Both Debrid Streams and Web Streams are disabled.';
          } else if (_releaseFailures.isNotEmpty && _webFailures.isNotEmpty) {
            _error = 'No enabled source completed successfully.';
          } else {
            _error = 'No playable streams were returned for this episode.';
          }
        }
      });
      _tryStartAutoPlay(generation: generation, allowWebFallback: true);
    } catch (error) {
      if (mounted && generation == _releaseSearchGeneration) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _releaseSearchGeneration) {
        setState(() => _loadingReleases = false);
      }
    }
  }

  Future<void> _resolve(
    ReleaseSource source, {
    required ReleaseCandidate selected,
  }) async {
    if (_resolving) return;
    final attempt = ++_resolveAttempt;
    setState(() {
      _resolving = true;
      _progress = 0;
      _status = 'Sending the release to ${_debridService.displayName}…';
      _error = null;
      _lastAttemptedRelease = selected;
    });
    try {
      final token = await ref
          .read(debridTokenServiceProvider)
          .accessToken(_debridService);
      if (!mounted || attempt != _resolveAttempt) return;
      if (token == null || token.isEmpty) {
        setState(
          () =>
              _connectedServices = {..._connectedServices}
                ..remove(_debridService),
        );
        throw StateError(
          '${_debridService.displayName} is not connected. '
          'Open Accounts to reconnect it.',
        );
      }
      final resolver = ref.read(debridStreamResolverFactoryProvider)(
        service: _debridService,
        token: token,
        source: source,
      );
      await for (final state in resolver.resolve(widget.episode)) {
        if (!mounted || attempt != _resolveAttempt) return;
        switch (state) {
          case StreamCaching():
            setState(() {
              _progress = state.progress;
              _status = state.progress <= 0
                  ? 'Selecting the episode file…'
                  : '${_debridService.displayName} is caching… '
                        '${(state.progress * 100).round()}%';
            });
          case StreamReady():
            final playerUri = Uri(
              path: '/player',
              queryParameters: {
                'source': state.uri.toString(),
                'title':
                    '${widget.episode.title} • Episode '
                    '${widget.episode.episode}',
                'anilistId': '${widget.episode.anilistMediaId}',
                if (widget.episode.malMediaId != null)
                  'malId': '${widget.episode.malMediaId}',
                'episode': '${widget.episode.episode}',
                if (state.debridService != null)
                  'debrid': state.debridService!.slug,
              },
            );
            final alternatives = [..._releases]
              ..removeWhere((item) => item.infoHash == selected.infoHash)
              ..sort((left, right) {
                final languageMatch =
                    (left.isDubbed == selected.isDubbed ? 0 : 1).compareTo(
                      right.isDubbed == selected.isDubbed ? 0 : 1,
                    );
                if (languageMatch != 0) return languageMatch;
                return compareStreamReleases(
                  left,
                  right,
                  device: _deviceProfile,
                  failureCounts: _failureCounts,
                  sortMode: 'compatibility',
                  preferredProvider: selected.provider,
                );
              });
            context.pushReplacement(
              playerUri.toString(),
              extra: PlaybackLaunch(
                stream: state,
                episode: widget.episode,
                selectedRelease: selected,
                alternatives: alternatives,
              ),
            );
            return;
        }
      }
    } catch (error) {
      if (mounted && attempt == _resolveAttempt) {
        _failedResolveHashes.add(selected.infoHash.toLowerCase());
        final preferred = _filteredAndSortedReleases(_releases);
        final recoveryPool = <ReleaseCandidate>[
          ...preferred,
          ..._releases.where((item) => !preferred.contains(item)),
        ];
        final next = recoveryPool
            .where(
              (item) =>
                  !_failedResolveHashes.contains(item.infoHash.toLowerCase()),
            )
            .firstOrNull;
        if (next != null && _automaticResolveFallbacks < 3) {
          _automaticResolveFallbacks++;
          setState(() {
            _resolving = false;
            _status = 'That release failed. Trying another cached stream…';
          });
          unawaited(
            Future<void>.microtask(
              () => _resolve(_SelectedReleaseSource(next), selected: next),
            ),
          );
          return;
        }
        setState(() {
          _error = error.toString().replaceFirst('Bad state: ', '');
          _status = 'Could not resolve this episode';
        });
      }
    } finally {
      if (mounted && attempt == _resolveAttempt) {
        setState(() => _resolving = false);
      }
    }
  }

  void _tryStartAutoPlay({
    required int generation,
    required bool allowWebFallback,
  }) {
    if (!mounted ||
        generation != _releaseSearchGeneration ||
        !widget.episode.autoPlay ||
        _autoPlayStarted ||
        _resolving) {
      return;
    }
    if (_hasDebrid && _releases.isNotEmpty) {
      final filtered = _filteredAndSortedReleases(_releases);
      final candidates = filtered.isNotEmpty
          ? filtered
          : _filteredAndSortedReleases(_releases, ignoreOptionalFilters: true);
      if (candidates.isNotEmpty) {
        _autoPlayStarted = true;
        unawaited(_resolveCandidate(candidates.first));
        return;
      }
    }
    if (!allowWebFallback || _webStreams.isEmpty) return;
    final filtered = _filteredWebStreams(_webStreams);
    final candidates = filtered.isNotEmpty
        ? filtered
        : _filteredWebStreams(_webStreams, ignoreOptionalFilters: true);
    if (candidates.isEmpty) return;
    _autoPlayStarted = true;
    unawaited(_openWebStream(candidates.first));
  }

  List<WebStreamResult> _filteredWebStreams(
    Iterable<WebStreamResult> input, {
    bool ignoreOptionalFilters = false,
  }) {
    final result = input.where((stream) {
      if (!ignoreOptionalFilters) {
        if (_languageFilter == _StreamLanguageFilter.dub && !stream.isDubbed) {
          return false;
        }
        if (_languageFilter == _StreamLanguageFilter.sub && stream.isDubbed) {
          return false;
        }
      }
      final quality = (stream.quality ?? stream.title).toLowerCase();
      if (ignoreOptionalFilters) return true;
      return switch (_qualityFilter) {
        _StreamQualityFilter.any => true,
        _StreamQualityFilter.p2160 =>
          quality.contains('2160') || quality.contains('4k'),
        _StreamQualityFilter.p1080 => quality.contains('1080'),
        _StreamQualityFilter.p720 => quality.contains('720'),
      };
    }).toList();
    result.sort(compareWebStreamsByQuality);
    return result;
  }

  ReleaseCandidate _releaseForWebStream(WebStreamResult stream) {
    return ReleaseCandidate(
      infoHash: 'web:${stream.providerId}:${stream.uri.hashCode}',
      magnetUri: '',
      releaseName: '${stream.providerName} / ${stream.title}',
      seeders: 0,
      sourceId: 'web:${stream.providerId}',
      quality: stream.quality,
      provider: stream.providerName,
      isDubbed: stream.isDubbed,
      hasSubtitles: stream.subtitleUri != null,
    );
  }

  StreamReady _readyForWebStream(
    WebStreamResult stream, {
    Uri? validatedUri,
    Map<String, String>? validatedHeaders,
  }) {
    final release = _releaseForWebStream(stream);
    return StreamReady(
      uri: validatedUri ?? stream.uri,
      displayName: release.releaseName,
      headers: validatedHeaders ?? stream.headers,
      externalSubtitle: stream.subtitleUri,
      providerId: stream.providerId,
      providerName: '${stream.providerName} web stream',
    );
  }

  Future<void> _openWebStream(WebStreamResult stream) async {
    if (_resolving) return;
    setState(() {
      _resolving = true;
      _status = 'Checking ${stream.providerName} stream…';
      _error = null;
    });
    late final ValidatedWebStream validated;
    try {
      validated = await ref.read(webStreamPreflightProvider)(
        stream.uri,
        stream.headers,
      );
      await ref
          .read(addonStoreProvider)
          .recordProviderSuccess(stream.providerId);
    } catch (error) {
      await ref
          .read(addonStoreProvider)
          .recordProviderFailure(stream.providerId, error);
      await TetoTvDatabase.instance.recordDiagnosticEvent(
        category: 'stream-preflight',
        message: '${stream.providerName}: $error',
      );
      if (mounted) {
        setState(() {
          _resolving = false;
          _status = 'Stream check failed';
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
      return;
    }
    final release = _releaseForWebStream(stream);
    await _rememberStreamSelection(release);
    if (!mounted) return;
    final ready = _readyForWebStream(
      stream,
      validatedUri: validated.uri,
      validatedHeaders: validated.headers,
    );
    final directAlternatives =
        _webStreams
            .where((candidate) => candidate.uri != stream.uri)
            .toList(growable: false)
          ..sort(compareWebStreamsByQuality);
    final playerUri = Uri(
      path: '/player',
      queryParameters: {
        'source': validated.uri.toString(),
        'title': '${widget.episode.title} / Episode ${widget.episode.episode}',
        'anilistId': '${widget.episode.anilistMediaId}',
        if (widget.episode.malMediaId != null)
          'malId': '${widget.episode.malMediaId}',
        'episode': '${widget.episode.episode}',
      },
    );
    setState(() => _resolving = false);
    context.pushReplacement(
      playerUri.toString(),
      extra: PlaybackLaunch(
        stream: ready,
        episode: widget.episode,
        selectedRelease: release,
        directAlternatives: directAlternatives
            .map(
              (candidate) => PlaybackStreamOption(
                stream: _readyForWebStream(candidate),
                release: _releaseForWebStream(candidate),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  void _resolveManual() {
    final magnet = _magnetController.text.trim();
    if (!magnet.startsWith('magnet:?')) {
      setState(() => _error = 'Enter a valid magnet URI.');
      return;
    }
    final source = _ManualReleaseSource(magnet);
    _resolve(source, selected: source.candidate(widget.episode));
  }

  Future<void> _resolveCandidate(ReleaseCandidate candidate) async {
    if (!_hasDebrid) {
      await context.push('/settings/accounts');
      await _initialize();
      return;
    }
    _failedResolveHashes.clear();
    _automaticResolveFallbacks = 0;
    await _rememberStreamSelection(candidate);
    await _resolve(_SelectedReleaseSource(candidate), selected: candidate);
  }

  List<ReleaseCandidate> _filteredAndSortedReleases(
    Iterable<ReleaseCandidate> releases, {
    bool ignoreOptionalFilters = false,
  }) {
    final filtered = releases.where((release) {
      return releaseMatchesStreamFilters(
        release,
        language: ignoreOptionalFilters ? 'all' : _languageFilter.name,
        quality: ignoreOptionalFilters ? 'any' : _qualityFilter.name,
        codec: ignoreOptionalFilters ? 'any' : _codecFilter.name,
        hdr: ignoreOptionalFilters ? 'any' : _hdrFilter.name,
        allowBatch: ignoreOptionalFilters || _allowBatchStreams,
      );
    }).toList();
    filtered.sort(
      (left, right) => compareStreamReleases(
        left,
        right,
        device: _deviceProfile,
        failureCounts: _failureCounts,
        sortMode: _sortMode.name,
        preferredProvider: _seriesPreferences.preferredReleaseProvider,
      ),
    );
    return filtered;
  }

  Future<void> _rememberPickerPreferences() async {
    _seriesPreferences = _seriesPreferences.copyWith(
      preferredStreamLanguage: _languageFilter.name,
      preferredQuality: _qualityFilter.name,
      preferredCodec: _codecFilter.name,
      preferredHdrMode: _hdrFilter.name,
      allowBatchStreams: _allowBatchStreams,
      streamSortMode: _sortMode.name,
    );
    try {
      await TetoTvDatabase.instance.saveSeriesPreferences(
        widget.episode.anilistMediaId,
        _seriesPreferences,
      );
    } catch (_) {
      // A local preference write must never block stream selection.
    }
  }

  Future<void> _rememberStreamSelection(ReleaseCandidate candidate) async {
    _seriesPreferences = _seriesPreferences.copyWith(
      preferredReleaseProvider: candidate.provider,
      preferredStreamLanguage: candidate.isDubbed ? 'dub' : 'sub',
    );
    try {
      await TetoTvDatabase.instance.saveSeriesPreferences(
        widget.episode.anilistMediaId,
        _seriesPreferences,
      );
    } catch (_) {
      // A local preference write must never block playback.
    }
  }

  void _updatePicker(VoidCallback update) {
    setState(update);
    unawaited(_rememberPickerPreferences());
  }

  String get _sourceSearchStatus {
    final progress = <String>[];
    if (_debridSourcesTotal > 0) {
      progress.add('Debrid $_debridSourcesCompleted/$_debridSourcesTotal');
    }
    if (_webProvidersTotal > 0) {
      progress.add('Web $_webProvidersCompleted/$_webProvidersTotal');
    }
    final pending = [..._pendingDebridSources, ..._pendingWebProviders];
    final pendingLabel = pending.take(3).join(', ');
    final remaining = pending.length - 3;
    final detail = pendingLabel.isEmpty
        ? ''
        : ' • Waiting for $pendingLabel${remaining > 0 ? ' +$remaining' : ''}';
    return '${progress.isEmpty ? 'Starting providers' : progress.join(' • ')}$detail';
  }

  @override
  void dispose() {
    _releaseSearchGeneration++;
    _magnetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        minimum: context.responsiveScreenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _BackButton(onPressed: context.pop),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    '${widget.episode.title} • Episode '
                    '${widget.episode.episode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            Expanded(child: Center(child: _body(context))),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loadingAccount) {
      return const CircularProgressIndicator(color: AppColors.cyan);
    }
    if (_loadingReleases && _releases.isEmpty && _webStreams.isEmpty) {
      return SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.cyan),
            const SizedBox(height: 22),
            Text(_status, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              _sourceSearchStatus,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    if (_resolving) {
      return SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_download_rounded,
              size: 68,
              color: AppColors.cyan,
            ),
            const SizedBox(height: 20),
            Text(_status, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: .12),
              color: AppColors.accentBright,
            ),
            const SizedBox(height: 12),
            Text(
              'Cached releases normally complete in a few seconds.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    final sourcePreferences = ref.read(settingsPreferencesProvider);
    if (!sourcePreferences.debridStreamsEnabled &&
        !sourcePreferences.webStreamsEnabled) {
      return _Message(
        icon: Icons.toggle_off_rounded,
        title: 'Stream sources are disabled',
        body:
            'Enable Debrid Streams, Web Streams, or both in Settings before searching again.',
        action: _ActionButton(
          label: 'Open settings',
          icon: Icons.settings_rounded,
          onPressed: () => _openSourceSettings('/settings/accounts'),
        ),
      );
    }
    if ((_releases.isNotEmpty || _webStreams.isNotEmpty) && !_showManual) {
      final filtered = _filteredAndSortedReleases(_releases);
      final filteredWeb = _filteredWebStreams(_webStreams);
      final sourcePreferences = ref.read(settingsPreferencesProvider);
      return _StreamPicker(
        releases: filtered,
        totalCount: _releases.length,
        webStreams: filteredWeb,
        webTotalCount: _webStreams.length,
        failedWebProviders: _webFailures.length,
        webFailures: _webFailures,
        failedDebridSources: _releaseFailures.length,
        isSearching: _loadingReleases,
        searchStatus: _sourceSearchStatus,
        debridEnabled: sourcePreferences.debridStreamsEnabled,
        webEnabled: sourcePreferences.webStreamsEnabled,
        connectedServices: _connectedServices,
        selectedService: _debridService,
        onServiceChanged: (value) => setState(() => _debridService = value),
        filter: _languageFilter,
        onFilterChanged: (value) =>
            _updatePicker(() => _languageFilter = value),
        qualityFilter: _qualityFilter,
        onQualityChanged: (value) =>
            _updatePicker(() => _qualityFilter = value),
        codecFilter: _codecFilter,
        onCodecChanged: (value) => _updatePicker(() => _codecFilter = value),
        hdrFilter: _hdrFilter,
        onHdrChanged: (value) => _updatePicker(() => _hdrFilter = value),
        sortMode: _sortMode,
        onSortChanged: (value) => _updatePicker(() => _sortMode = value),
        showAdvancedFilters: _showAdvancedFilters,
        onAdvancedFiltersChanged: (value) =>
            setState(() => _showAdvancedFilters = value),
        allowBatchStreams: _allowBatchStreams,
        onBatchChanged: (value) =>
            _updatePicker(() => _allowBatchStreams = value),
        onSelected: _resolveCandidate,
        onWebSelected: _openWebStream,
        error: _error,
        onRetry: _lastAttemptedRelease == null
            ? null
            : () => _resolveCandidate(_lastAttemptedRelease!),
        onRefresh: _loadConfiguredReleases,
        onManual: () => setState(() => _showManual = true),
      );
    }
    if (!_hasDebrid && _webStreams.isEmpty) {
      return _Message(
        icon: Icons.stream_rounded,
        title: 'No stream source is ready',
        body: sourcePreferences.webStreamsEnabled
            ? 'Connect Real-Debrid or TorBox, or install a compatible Web '
                  'Stream provider from Marketplace.'
            : 'Connect Real-Debrid or TorBox. TetoTV never streams a torrent '
                  'directly from peers.',
        action: _ActionButton(
          label: sourcePreferences.webStreamsEnabled
              ? 'Open marketplace'
              : 'Open accounts',
          icon: Icons.settings_rounded,
          onPressed: () => _openSourceSettings(
            sourcePreferences.webStreamsEnabled
                ? '/settings/marketplace'
                : '/settings/accounts',
          ),
        ),
      );
    }
    return _manualPanel(context);
  }

  Widget _manualPanel(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Container(
        width: 780,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _releases.isNotEmpty ? 'Paste a magnet' : 'Add a release',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _releases.isNotEmpty
                  ? 'Use a magnet for content you are authorized to access.'
                  : AppConfig.hasReleaseResolver || AppConfig.hasStremioAddon
                  ? 'Automatic matching did not return a playable stream. '
                        'You can provide a magnet manually.'
                  : 'No release resolver is configured. Paste a magnet for '
                        'content you are authorized to access.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 10),
              Text(error, style: const TextStyle(color: Color(0xFFFF929B))),
            ],
            const SizedBox(height: 20),
            if (_releases.isNotEmpty) ...[
              _ActionButton(
                label: 'Back to streams',
                icon: Icons.view_list_rounded,
                onPressed: () => setState(() => _showManual = false),
              ),
              const SizedBox(height: 14),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final input = TvTextInput(
                  controller: _magnetController,
                  autofocus: true,
                  labelText: 'Magnet URI',
                  hintText: 'Select to type or paste a magnet link',
                  keyboardTitle: 'Enter magnet URI',
                  onSubmitted: (_) => _resolveManual(),
                );
                final action = _ActionButton(
                  label: 'Send to ${_debridService.displayName}',
                  icon: Icons.play_arrow_rounded,
                  onPressed: _resolveManual,
                );
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      input,
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: action),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: input),
                    const SizedBox(width: 14),
                    action,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedReleaseSource implements ReleaseSource {
  const _SelectedReleaseSource(this.release);

  final ReleaseCandidate release;

  @override
  String get id => release.sourceId;

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async => [
    release,
  ];
}

enum _StreamLanguageFilter { all, sub, dub }

enum _StreamQualityFilter { any, p2160, p1080, p720 }

enum _StreamCodecFilter { any, h264, hevc, av1 }

enum _StreamHdrFilter { any, sdr, hdr }

enum _StreamSortMode { compatibility, seeders, size }

class _StreamPicker extends StatelessWidget {
  const _StreamPicker({
    required this.releases,
    required this.totalCount,
    required this.webStreams,
    required this.webTotalCount,
    required this.failedWebProviders,
    required this.webFailures,
    required this.failedDebridSources,
    required this.isSearching,
    required this.searchStatus,
    required this.debridEnabled,
    required this.webEnabled,
    required this.connectedServices,
    required this.selectedService,
    required this.onServiceChanged,
    required this.filter,
    required this.onFilterChanged,
    required this.qualityFilter,
    required this.onQualityChanged,
    required this.codecFilter,
    required this.onCodecChanged,
    required this.hdrFilter,
    required this.onHdrChanged,
    required this.sortMode,
    required this.onSortChanged,
    required this.showAdvancedFilters,
    required this.onAdvancedFiltersChanged,
    required this.allowBatchStreams,
    required this.onBatchChanged,
    required this.onSelected,
    required this.onWebSelected,
    required this.error,
    required this.onRetry,
    required this.onRefresh,
    required this.onManual,
  });

  final List<ReleaseCandidate> releases;
  final int totalCount;
  final List<WebStreamResult> webStreams;
  final int webTotalCount;
  final int failedWebProviders;
  final List<WebProviderFailure> webFailures;
  final int failedDebridSources;
  final bool isSearching;
  final String searchStatus;
  final bool debridEnabled;
  final bool webEnabled;
  final Set<DebridService> connectedServices;
  final DebridService selectedService;
  final ValueChanged<DebridService> onServiceChanged;
  final _StreamLanguageFilter filter;
  final ValueChanged<_StreamLanguageFilter> onFilterChanged;
  final _StreamQualityFilter qualityFilter;
  final ValueChanged<_StreamQualityFilter> onQualityChanged;
  final _StreamCodecFilter codecFilter;
  final ValueChanged<_StreamCodecFilter> onCodecChanged;
  final _StreamHdrFilter hdrFilter;
  final ValueChanged<_StreamHdrFilter> onHdrChanged;
  final _StreamSortMode sortMode;
  final ValueChanged<_StreamSortMode> onSortChanged;
  final bool showAdvancedFilters;
  final ValueChanged<bool> onAdvancedFiltersChanged;
  final bool allowBatchStreams;
  final ValueChanged<bool> onBatchChanged;
  final ValueChanged<ReleaseCandidate> onSelected;
  final ValueChanged<WebStreamResult> onWebSelected;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback onRefresh;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final activeAdvancedFilters = [
      qualityFilter != _StreamQualityFilter.any,
      codecFilter != _StreamCodecFilter.any,
      hdrFilter != _StreamHdrFilter.any,
      !allowBatchStreams,
      sortMode != _StreamSortMode.compatibility,
    ].where((active) => active).length;
    return SizedBox(
      width: 1260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: context.isCompactWidth ? 820 : 1260,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose your stream',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${debridEnabled ? '$totalCount Debrid' : 'Debrid off'}'
                          ' • ${webEnabled ? '$webTotalCount Web' : 'Web off'}'
                          '${failedWebProviders + failedDebridSources > 0 ? ' • ${failedWebProviders + failedDebridSources} source issue(s)' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (debridEnabled && connectedServices.length > 1) ...[
                    for (final service in DebridService.values.where(
                      connectedServices.contains,
                    )) ...[
                      _FilterButton(
                        label: service.shortName,
                        selected: selectedService == service,
                        onPressed: () => onServiceChanged(service),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      width: 1,
                      height: 32,
                      color: Colors.white.withValues(alpha: .12),
                    ),
                    const SizedBox(width: 8),
                  ],
                  for (final value in _StreamLanguageFilter.values) ...[
                    _FilterButton(
                      label: switch (value) {
                        _StreamLanguageFilter.all => 'ALL',
                        _StreamLanguageFilter.sub => 'SUB',
                        _StreamLanguageFilter.dub => 'DUB',
                      },
                      selected: filter == value,
                      onPressed: () => onFilterChanged(value),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _CompactAction(
                    icon: showAdvancedFilters
                        ? Icons.tune_rounded
                        : Icons.tune_outlined,
                    label: activeAdvancedFilters == 0
                        ? (showAdvancedFilters
                              ? 'Hide filters'
                              : 'More filters')
                        : 'Filters ($activeAdvancedFilters)',
                    onPressed: () =>
                        onAdvancedFiltersChanged(!showAdvancedFilters),
                  ),
                  const SizedBox(width: 8),
                  _CompactAction(
                    icon: Icons.refresh_rounded,
                    label: 'Refresh',
                    onPressed: onRefresh,
                  ),
                  const SizedBox(width: 8),
                  if (debridEnabled)
                    _CompactAction(
                      icon: Icons.add_link_rounded,
                      label: 'Magnet',
                      onPressed: onManual,
                    ),
                ],
              ),
            ),
          ),
          if (isSearching) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.cyan.withValues(alpha: .2)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.cyan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$searchStatus • Available results can be selected now.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showAdvancedFilters) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: .08)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const _FilterLabel('QUALITY'),
                  for (final value in _StreamQualityFilter.values)
                    _FilterButton(
                      label: switch (value) {
                        _StreamQualityFilter.any => 'ANY',
                        _StreamQualityFilter.p2160 => '4K',
                        _StreamQualityFilter.p1080 => '1080P',
                        _StreamQualityFilter.p720 => '720P',
                      },
                      selected: qualityFilter == value,
                      onPressed: () => onQualityChanged(value),
                    ),
                  const _FilterLabel('CODEC'),
                  for (final value in _StreamCodecFilter.values)
                    _FilterButton(
                      label: switch (value) {
                        _StreamCodecFilter.any => 'ANY',
                        _StreamCodecFilter.h264 => 'H.264',
                        _StreamCodecFilter.hevc => 'HEVC',
                        _StreamCodecFilter.av1 => 'AV1',
                      },
                      selected: codecFilter == value,
                      onPressed: () => onCodecChanged(value),
                    ),
                  const _FilterLabel('COLOR'),
                  for (final value in _StreamHdrFilter.values)
                    _FilterButton(
                      label: value.name.toUpperCase(),
                      selected: hdrFilter == value,
                      onPressed: () => onHdrChanged(value),
                    ),
                  _FilterButton(
                    label: allowBatchStreams ? 'BATCHES ON' : 'BATCHES OFF',
                    selected: allowBatchStreams,
                    onPressed: () => onBatchChanged(!allowBatchStreams),
                  ),
                  const _FilterLabel('SORT'),
                  for (final value in _StreamSortMode.values)
                    _FilterButton(
                      label: switch (value) {
                        _StreamSortMode.compatibility => 'BEST',
                        _StreamSortMode.seeders => 'SEEDERS',
                        _StreamSortMode.size => 'SMALLEST',
                      },
                      selected: sortMode == value,
                      onPressed: () => onSortChanged(value),
                    ),
                ],
              ),
            ),
          ],
          if (error case final message?) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1117),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accentBright.withValues(alpha: .65),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFFF929B),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Could not start this stream: $message',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFFFC4C9)),
                    ),
                  ),
                  if (onRetry case final retry?) ...[
                    const SizedBox(width: 16),
                    _CompactAction(
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                      onPressed: retry,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (webFailures.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: .12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.extension_off_rounded,
                    color: Color(0xFFFFA0A8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      webFailures
                          .map(
                            (failure) =>
                                '${failure.providerName}: ${failure.message}',
                          )
                          .join('\n'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFD5D5D5)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Expanded(
            child: releases.isEmpty && webStreams.isEmpty
                ? Center(
                    child: Text(
                      'No streams match the selected filters.',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      if (releases.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: _StreamSectionHeader(
                            icon: Icons.cloud_done_rounded,
                            title: 'DEBRID STREAMS',
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
                          sliver: SliverList.builder(
                            itemCount: releases.length,
                            findChildIndexCallback: (key) {
                              if (key is! ValueKey<String>) return null;
                              final index = releases.indexWhere(
                                (release) =>
                                    'debrid:${release.infoHash.toLowerCase()}' ==
                                    key.value,
                              );
                              return index < 0 ? null : index;
                            },
                            itemBuilder: (context, index) {
                              final release = releases[index];
                              return Padding(
                                key: ValueKey(
                                  'debrid:${release.infoHash.toLowerCase()}',
                                ),
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _ReleaseCard(
                                  release: release,
                                  recommended: index == 0,
                                  onPressed: () => onSelected(release),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      if (webStreams.isNotEmpty) ...[
                        const SliverToBoxAdapter(
                          child: _StreamSectionHeader(
                            icon: Icons.language_rounded,
                            title: 'WEB STREAMS',
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
                          sliver: SliverList.builder(
                            itemCount: webStreams.length,
                            findChildIndexCallback: (key) {
                              if (key is! ValueKey<String>) return null;
                              final index = webStreams.indexWhere(
                                (stream) =>
                                    'web:${stream.providerId}:${stream.uri}' ==
                                    key.value,
                              );
                              return index < 0 ? null : index;
                            },
                            itemBuilder: (context, index) {
                              final stream = webStreams[index];
                              return Padding(
                                key: ValueKey(
                                  'web:${stream.providerId}:${stream.uri}',
                                ),
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _WebStreamCard(
                                  stream: stream,
                                  onPressed: () => onWebSelected(stream),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _StreamSectionHeader extends StatelessWidget {
  const _StreamSectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accentBright),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebStreamCard extends StatelessWidget {
  const _WebStreamCard({required this.stream, required this.onPressed});

  final WebStreamResult stream;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(18),
      focusScale: 1.015,
      child: Container(
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.play_circle_outline_rounded),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stream.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${stream.providerName} / '
                    '${stream.isDubbed ? 'DUB' : 'SUB'}'
                    '${stream.quality == null ? '' : ' / ${stream.quality}'}'
                    '${stream.subtitleUri == null ? '' : ' / English captions'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.onPressed,
    required this.recommended,
  });

  final ReleaseCandidate release;
  final VoidCallback onPressed;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(18),
      focusScale: 1.015,
      child: Container(
        height: 126,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        color: AppColors.panel,
        child: Row(
          children: [
            Container(
              width: 92,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.cyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  release.quality?.toUpperCase() ?? 'AUTO',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    release.releaseName.replaceAll('\n', ' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (recommended)
                        const _MetaPill(
                          label: 'RECOMMENDED',
                          color: Color(0xFF67D49B),
                        ),
                      _MetaPill(
                        label: release.isDubbed ? 'DUB / DUAL' : 'SUB',
                        color: release.isDubbed
                            ? const Color(0xFFFFB86C)
                            : AppColors.cyan,
                      ),
                      if (isTvSafeRelease(release))
                        const _MetaPill(
                          label: 'TV SAFE',
                          color: Color(0xFF67D49B),
                        ),
                      if (release.hasSubtitles && release.isDubbed)
                        const _MetaPill(
                          label: 'SUBTITLES',
                          color: AppColors.cyan,
                        ),
                      if (release.codec case final codec?)
                        _MetaPill(label: codec),
                      if (release.isHdr)
                        const _MetaPill(label: 'HDR', color: Color(0xFFFFD166)),
                      if (release.isBatch) const _MetaPill(label: 'BATCH'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: 190,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    [
                      if (release.seeders > 0) '● ${release.seeders} seeders',
                      if (release.sizeLabel != null) release.sizeLabel!,
                    ].join('  •  '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    release.provider ?? 'Torrentio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            const Icon(
              Icons.play_circle_fill_rounded,
              color: AppColors.accentBright,
              size: 34,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(999),
      focusScale: 1.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentBright : AppColors.panel,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? AppColors.ink : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 7, right: 1),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    ),
  );
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(10),
      focusScale: 1.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: AppColors.panel,
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 7),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, this.color = AppColors.textMuted});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _ManualReleaseSource implements ReleaseSource {
  const _ManualReleaseSource(this.magnet);

  final String magnet;

  @override
  String get id => 'manual';

  @override
  Future<List<ReleaseCandidate>> search(EpisodeReference episode) async {
    return [candidate(episode)];
  }

  ReleaseCandidate candidate(EpisodeReference episode) {
    return ReleaseCandidate(
      infoHash: Uri.parse(magnet).queryParameters['xt'] ?? '',
      magnetUri: magnet,
      releaseName: '${episode.title} Episode ${episode.episode}',
      seeders: 0,
      sourceId: id,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 68, color: AppColors.textMuted),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        SizedBox(
          width: 560,
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 22),
        action,
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: true,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: const ColoredBox(
        color: AppColors.panel,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back_rounded, size: 20),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        color: AppColors.textPrimary,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.ink, size: 19),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}
