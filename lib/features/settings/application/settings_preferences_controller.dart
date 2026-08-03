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
