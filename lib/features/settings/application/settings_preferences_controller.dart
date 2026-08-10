import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _debridProviderKey = 'settings_selected_debrid_provider';
const _trackingProviderKey = 'settings_selected_tracking_provider';
const _captionTextColorKey = 'appearance_caption_text_color';
const _captionBackgroundColorKey = 'appearance_caption_background_color';
const _captionTextSizeKey = 'appearance_caption_text_size';
const _thumbnailScaleKey = 'appearance_thumbnail_scale';
const _interfaceScaleKey = 'appearance_interface_scale';
const _contentDensityKey = 'appearance_content_density';
const _seekBackSecondsKey = 'player_seek_back_seconds';
const _seekForwardSecondsKey = 'player_seek_forward_seconds';
const _builtInKeyboardKey = 'input_use_built_in_keyboard';
const _debridStreamsEnabledKey = 'streaming_debrid_enabled';
const _webStreamsEnabledKey = 'streaming_web_enabled';
const _autoSkipIntrosKey = 'player_auto_skip_intros';
const _autoSkipOutrosKey = 'player_auto_skip_outros';
const _homeLayoutKey = 'appearance_home_layout';
const _showSearchKey = 'navigation_show_search';
const _showMyListKey = 'navigation_show_my_list';
const _showDiscoverKey = 'navigation_show_discover';
const _showCalendarKey = 'navigation_show_calendar';
const _showHeroKey = 'home_show_featured_hero';
const _showPosterMetadataKey = 'home_show_poster_metadata';
const _showCardSubtitlesKey = 'home_show_card_subtitles';
const _trackerUpdateThresholdKey = 'tracking_episode_update_threshold';

/// AniList and MyAnimeList only accept a whole number of completed episodes.
/// This setting controls how much of the current episode must be watched before
/// TetoTV records that episode number on the connected trackers.
enum TrackerUpdateThreshold {
  halfway,
  threeQuarters,
  nearlyFinished,
  episodeEnd,
}

extension TrackerUpdateThresholdLabel on TrackerUpdateThreshold {
  String get displayName => switch (this) {
    TrackerUpdateThreshold.halfway => 'After 50%',
    TrackerUpdateThreshold.threeQuarters => 'After 75%',
    TrackerUpdateThreshold.nearlyFinished => 'After 90%',
    TrackerUpdateThreshold.episodeEnd => 'At episode end',
  };

  String get description => switch (this) {
    TrackerUpdateThreshold.halfway =>
      'Mark the episode watched once half of it has played.',
    TrackerUpdateThreshold.threeQuarters =>
      'Mark the episode watched after three quarters has played.',
    TrackerUpdateThreshold.nearlyFinished =>
      'Mark the episode watched near the end (recommended).',
    TrackerUpdateThreshold.episodeEnd =>
      'Only mark the episode watched after playback finishes.',
  };

  double get watchedFraction => switch (this) {
    TrackerUpdateThreshold.halfway => .5,
    TrackerUpdateThreshold.threeQuarters => .75,
    TrackerUpdateThreshold.nearlyFinished => .9,
    TrackerUpdateThreshold.episodeEnd => 1,
  };
}

bool trackerUpdateThresholdReached({
  required Duration position,
  required Duration duration,
  required TrackerUpdateThreshold threshold,
  bool playbackEnded = false,
}) {
  if (playbackEnded) return true;
  if (duration <= Duration.zero || position < Duration.zero) return false;
  if (threshold == TrackerUpdateThreshold.episodeEnd) return false;
  return position.inMilliseconds / duration.inMilliseconds >=
      threshold.watchedFraction;
}

enum HomeLayout { cinematic, compact }

extension HomeLayoutLabel on HomeLayout {
  String get displayName => switch (this) {
    HomeLayout.cinematic => 'Cinematic',
    HomeLayout.compact => 'Compact',
  };
}

enum ContentDensity { compact, standard, comfortable }

extension ContentDensityLabel on ContentDensity {
  String get displayName => switch (this) {
    ContentDensity.compact => 'Compact',
    ContentDensity.standard => 'Standard',
    ContentDensity.comfortable => 'Comfortable',
  };

  double get spacingScale => switch (this) {
    ContentDensity.compact => .88,
    ContentDensity.standard => 1,
    ContentDensity.comfortable => 1.12,
  };
}

class SettingsPreferences {
  const SettingsPreferences({
    this.debridProvider = DebridService.realDebrid,
    this.trackingProvider = TrackingProvider.anilist,
    this.captionTextColor = 0xFFFFFFFF,
    this.captionBackgroundColor = 0x00000000,
    this.captionTextSize = 34,
    this.thumbnailScale = 1,
    this.interfaceScale = 1,
    this.contentDensity = ContentDensity.standard,
    this.seekBackSeconds = 10,
    this.seekForwardSeconds = 10,
    this.useBuiltInKeyboard = true,
    this.debridStreamsEnabled = true,
    this.webStreamsEnabled = true,
    this.autoSkipIntros = false,
    this.autoSkipOutros = false,
    this.homeLayout = HomeLayout.cinematic,
    this.showSearch = true,
    this.showMyList = true,
    this.showDiscover = true,
    this.showCalendar = true,
    this.showHero = true,
    this.showPosterMetadata = true,
    this.showCardSubtitles = true,
    this.trackerUpdateThreshold = TrackerUpdateThreshold.nearlyFinished,
  });

  final DebridService debridProvider;
  final TrackingProvider trackingProvider;
  final int captionTextColor;
  final int captionBackgroundColor;
  final double captionTextSize;
  final double thumbnailScale;
  final double interfaceScale;
  final ContentDensity contentDensity;
  final int seekBackSeconds;
  final int seekForwardSeconds;
  final bool useBuiltInKeyboard;
  final bool debridStreamsEnabled;
  final bool webStreamsEnabled;
  final bool autoSkipIntros;
  final bool autoSkipOutros;
  final HomeLayout homeLayout;
  final bool showSearch;
  final bool showMyList;
  final bool showDiscover;
  final bool showCalendar;
  final bool showHero;
  final bool showPosterMetadata;
  final bool showCardSubtitles;
  final TrackerUpdateThreshold trackerUpdateThreshold;

  SettingsPreferences copyWith({
    DebridService? debridProvider,
    TrackingProvider? trackingProvider,
    int? captionTextColor,
    int? captionBackgroundColor,
    double? captionTextSize,
    double? thumbnailScale,
    double? interfaceScale,
    ContentDensity? contentDensity,
    int? seekBackSeconds,
    int? seekForwardSeconds,
    bool? useBuiltInKeyboard,
    bool? debridStreamsEnabled,
    bool? webStreamsEnabled,
    bool? autoSkipIntros,
    bool? autoSkipOutros,
    HomeLayout? homeLayout,
    bool? showSearch,
    bool? showMyList,
    bool? showDiscover,
    bool? showCalendar,
    bool? showHero,
    bool? showPosterMetadata,
    bool? showCardSubtitles,
    TrackerUpdateThreshold? trackerUpdateThreshold,
  }) => SettingsPreferences(
    debridProvider: debridProvider ?? this.debridProvider,
    trackingProvider: trackingProvider ?? this.trackingProvider,
    captionTextColor: captionTextColor ?? this.captionTextColor,
    captionBackgroundColor:
        captionBackgroundColor ?? this.captionBackgroundColor,
    captionTextSize: captionTextSize ?? this.captionTextSize,
    thumbnailScale: thumbnailScale ?? this.thumbnailScale,
    interfaceScale: interfaceScale ?? this.interfaceScale,
    contentDensity: contentDensity ?? this.contentDensity,
    seekBackSeconds: seekBackSeconds ?? this.seekBackSeconds,
    seekForwardSeconds: seekForwardSeconds ?? this.seekForwardSeconds,
    useBuiltInKeyboard: useBuiltInKeyboard ?? this.useBuiltInKeyboard,
    debridStreamsEnabled: debridStreamsEnabled ?? this.debridStreamsEnabled,
    webStreamsEnabled: webStreamsEnabled ?? this.webStreamsEnabled,
    autoSkipIntros: autoSkipIntros ?? this.autoSkipIntros,
    autoSkipOutros: autoSkipOutros ?? this.autoSkipOutros,
    homeLayout: homeLayout ?? this.homeLayout,
    showSearch: showSearch ?? this.showSearch,
    showMyList: showMyList ?? this.showMyList,
    showDiscover: showDiscover ?? this.showDiscover,
    showCalendar: showCalendar ?? this.showCalendar,
    showHero: showHero ?? this.showHero,
    showPosterMetadata: showPosterMetadata ?? this.showPosterMetadata,
    showCardSubtitles: showCardSubtitles ?? this.showCardSubtitles,
    trackerUpdateThreshold:
        trackerUpdateThreshold ?? this.trackerUpdateThreshold,
  );
}

final settingsPreferencesProvider =
    StateNotifierProvider<SettingsPreferencesController, SettingsPreferences>((
      ref,
    ) {
      final controller = SettingsPreferencesController(
        ref.watch(secureStorageProvider),
      );
      Future.microtask(controller.load);
      return controller;
    });

class SettingsPreferencesController extends StateNotifier<SettingsPreferences> {
  SettingsPreferencesController(this._storage)
    : super(const SettingsPreferences());

  final FlutterSecureStorage _storage;

  Future<void> load() async {
    try {
      final values = await Future.wait([
        _storage.read(key: _debridProviderKey),
        _storage.read(key: _trackingProviderKey),
        _storage.read(key: _captionTextColorKey),
        _storage.read(key: _captionBackgroundColorKey),
        _storage.read(key: _captionTextSizeKey),
        _storage.read(key: _thumbnailScaleKey),
        _storage.read(key: _interfaceScaleKey),
        _storage.read(key: _contentDensityKey),
        _storage.read(key: _seekBackSecondsKey),
        _storage.read(key: _seekForwardSecondsKey),
        _storage.read(key: _builtInKeyboardKey),
        _storage.read(key: _debridStreamsEnabledKey),
        _storage.read(key: _webStreamsEnabledKey),
        _storage.read(key: _autoSkipIntrosKey),
        _storage.read(key: _autoSkipOutrosKey),
        _storage.read(key: _homeLayoutKey),
        _storage.read(key: _showSearchKey),
        _storage.read(key: _showMyListKey),
        _storage.read(key: _showDiscoverKey),
        _storage.read(key: _showCalendarKey),
        _storage.read(key: _showHeroKey),
        _storage.read(key: _showPosterMetadataKey),
        _storage.read(key: _showCardSubtitlesKey),
        _storage.read(key: _trackerUpdateThresholdKey),
      ]);
      state = SettingsPreferences(
        debridProvider:
            DebridService.fromSlug(values[0]) ?? DebridService.realDebrid,
        trackingProvider: TrackingProvider.values.firstWhere(
          (provider) => provider.slug == values[1],
          orElse: () => TrackingProvider.anilist,
        ),
        captionTextColor: _parseInt(values[2], 0xFFFFFFFF),
        captionBackgroundColor: _parseInt(values[3], 0x00000000),
        captionTextSize: _parseDouble(values[4], 34).clamp(18, 60),
        thumbnailScale: _parseDouble(values[5], 1).clamp(.8, 1.25),
        interfaceScale: _parseDouble(values[6], 1).clamp(.85, 1.15),
        contentDensity: ContentDensity.values.firstWhere(
          (density) => density.name == values[7],
          orElse: () => ContentDensity.standard,
        ),
        seekBackSeconds: _seekValue(values[8]),
        seekForwardSeconds: _seekValue(values[9]),
        useBuiltInKeyboard: values[10] != 'false',
        debridStreamsEnabled: values[11] != 'false',
        webStreamsEnabled: values[12] != 'false',
        autoSkipIntros: values[13] == 'true',
        autoSkipOutros: values[14] == 'true',
        homeLayout: HomeLayout.values.firstWhere(
          (layout) => layout.name == values[15],
          orElse: () => HomeLayout.cinematic,
        ),
        showSearch: values[16] != 'false',
        showMyList: values[17] != 'false',
        showDiscover: values[18] != 'false',
        showCalendar: values[19] != 'false',
        showHero: values[20] != 'false',
        showPosterMetadata: values[21] != 'false',
        showCardSubtitles: values[22] != 'false',
        trackerUpdateThreshold: TrackerUpdateThreshold.values.firstWhere(
          (threshold) => threshold.name == values[23],
          orElse: () => TrackerUpdateThreshold.nearlyFinished,
        ),
      );
    } catch (_) {
      // Appearance preferences are optional; safe defaults remain usable.
    }
  }

  Future<void> setDebridProvider(DebridService value) => _update(
    state.copyWith(debridProvider: value),
    {_debridProviderKey: value.slug},
  );

  Future<void> setTrackingProvider(TrackingProvider value) => _update(
    state.copyWith(trackingProvider: value),
    {_trackingProviderKey: value.slug},
  );

  Future<void> setCaptionTextColor(int value) => _update(
    state.copyWith(captionTextColor: value),
    {_captionTextColorKey: value.toString()},
  );

  Future<void> setCaptionBackgroundColor(int value) => _update(
    state.copyWith(captionBackgroundColor: value),
    {_captionBackgroundColorKey: value.toString()},
  );

  Future<void> setCaptionTextSize(double value) => _update(
    state.copyWith(captionTextSize: value),
    {_captionTextSizeKey: value.toString()},
  );

  Future<void> setThumbnailScale(double value) => _update(
    state.copyWith(thumbnailScale: value),
    {_thumbnailScaleKey: value.toString()},
  );

  Future<void> setInterfaceScale(double value) => _update(
    state.copyWith(interfaceScale: value),
    {_interfaceScaleKey: value.toString()},
  );

  Future<void> setContentDensity(ContentDensity value) => _update(
    state.copyWith(contentDensity: value),
    {_contentDensityKey: value.name},
  );

  Future<void> setSeekBackSeconds(int value) => _update(
    state.copyWith(seekBackSeconds: value),
    {_seekBackSecondsKey: value.toString()},
  );

  Future<void> setSeekForwardSeconds(int value) => _update(
    state.copyWith(seekForwardSeconds: value),
    {_seekForwardSecondsKey: value.toString()},
  );

  Future<void> setUseBuiltInKeyboard(bool value) => _update(
    state.copyWith(useBuiltInKeyboard: value),
    {_builtInKeyboardKey: value.toString()},
  );

  Future<void> setDebridStreamsEnabled(bool value) => _update(
    state.copyWith(debridStreamsEnabled: value),
    {_debridStreamsEnabledKey: value.toString()},
  );

  Future<void> setWebStreamsEnabled(bool value) => _update(
    state.copyWith(webStreamsEnabled: value),
    {_webStreamsEnabledKey: value.toString()},
  );

  Future<void> setAutoSkipIntros(bool value) => _update(
    state.copyWith(autoSkipIntros: value),
    {_autoSkipIntrosKey: value.toString()},
  );

  Future<void> setAutoSkipOutros(bool value) => _update(
    state.copyWith(autoSkipOutros: value),
    {_autoSkipOutrosKey: value.toString()},
  );

  Future<void> setHomeLayout(HomeLayout value) =>
      _update(state.copyWith(homeLayout: value), {_homeLayoutKey: value.name});

  Future<void> setShowSearch(bool value) => _update(
    state.copyWith(showSearch: value),
    {_showSearchKey: value.toString()},
  );

  Future<void> setShowMyList(bool value) => _update(
    state.copyWith(showMyList: value),
    {_showMyListKey: value.toString()},
  );

  Future<void> setShowDiscover(bool value) => _update(
    state.copyWith(showDiscover: value),
    {_showDiscoverKey: value.toString()},
  );

  Future<void> setShowCalendar(bool value) => _update(
    state.copyWith(showCalendar: value),
    {_showCalendarKey: value.toString()},
  );

  Future<void> setShowHero(bool value) => _update(
    state.copyWith(showHero: value),
    {_showHeroKey: value.toString()},
  );

  Future<void> setShowPosterMetadata(bool value) => _update(
    state.copyWith(showPosterMetadata: value),
    {_showPosterMetadataKey: value.toString()},
  );

  Future<void> setShowCardSubtitles(bool value) => _update(
    state.copyWith(showCardSubtitles: value),
    {_showCardSubtitlesKey: value.toString()},
  );

  Future<void> setTrackerUpdateThreshold(TrackerUpdateThreshold value) =>
      _update(state.copyWith(trackerUpdateThreshold: value), {
        _trackerUpdateThresholdKey: value.name,
      });

  Future<void> resetCustomization() async {
    const defaults = SettingsPreferences();
    state = state.copyWith(
      homeLayout: defaults.homeLayout,
      showSearch: defaults.showSearch,
      showMyList: defaults.showMyList,
      showDiscover: defaults.showDiscover,
      showCalendar: defaults.showCalendar,
      showHero: defaults.showHero,
      showPosterMetadata: defaults.showPosterMetadata,
      showCardSubtitles: defaults.showCardSubtitles,
    );
    for (final key in const [
      _homeLayoutKey,
      _showSearchKey,
      _showMyListKey,
      _showDiscoverKey,
      _showCalendarKey,
      _showHeroKey,
      _showPosterMetadataKey,
      _showCardSubtitlesKey,
    ]) {
      await _storage.delete(key: key);
    }
  }

  Future<void> resetAppearance() async {
    const defaults = SettingsPreferences();
    state = state.copyWith(
      captionTextColor: defaults.captionTextColor,
      captionBackgroundColor: defaults.captionBackgroundColor,
      captionTextSize: defaults.captionTextSize,
      thumbnailScale: defaults.thumbnailScale,
      interfaceScale: defaults.interfaceScale,
      contentDensity: defaults.contentDensity,
      seekBackSeconds: defaults.seekBackSeconds,
      seekForwardSeconds: defaults.seekForwardSeconds,
    );
    for (final key in const [
      _captionTextColorKey,
      _captionBackgroundColorKey,
      _captionTextSizeKey,
      _thumbnailScaleKey,
      _interfaceScaleKey,
      _contentDensityKey,
      _seekBackSecondsKey,
      _seekForwardSecondsKey,
    ]) {
      await _storage.delete(key: key);
    }
  }

  Future<void> _update(
    SettingsPreferences next,
    Map<String, String> values,
  ) async {
    state = next;
    try {
      for (final entry in values.entries) {
        await _storage.write(key: entry.key, value: entry.value);
      }
    } catch (_) {
      // Keep the in-memory preference if platform storage is unavailable.
    }
  }
}

int _parseInt(String? value, int fallback) =>
    int.tryParse(value ?? '') ?? fallback;

double _parseDouble(String? value, double fallback) =>
    double.tryParse(value ?? '') ?? fallback;

int _seekValue(String? value) {
  const allowed = {5, 10, 15, 30, 60};
  final parsed = int.tryParse(value ?? '');
  return allowed.contains(parsed) ? parsed! : 10;
}
