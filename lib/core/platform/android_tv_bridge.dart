import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class TvDisplayMode {
  const TvDisplayMode({
    required this.id,
    required this.width,
    required this.height,
    required this.refreshRate,
  });

  final int id;
  final int width;
  final int height;
  final double refreshRate;

  factory TvDisplayMode.fromMap(Map<Object?, Object?> value) => TvDisplayMode(
    id: value['id'] as int? ?? 0,
    width: value['width'] as int? ?? 0,
    height: value['height'] as int? ?? 0,
    refreshRate: (value['refreshRate'] as num?)?.toDouble() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'width': width,
    'height': height,
    'refreshRate': refreshRate,
  };
}

class TvCodecCapability {
  const TvCodecCapability({
    required this.name,
    required this.mime,
    required this.hardware,
  });

  final String name;
  final String mime;
  final bool hardware;

  factory TvCodecCapability.fromMap(Map<Object?, Object?> value) =>
      TvCodecCapability(
        name: value['name'] as String? ?? '',
        mime: value['mime'] as String? ?? '',
        hardware: value['hardware'] as bool? ?? false,
      );

  Map<String, Object?> toJson() => {
    'name': name,
    'mime': mime,
    'hardware': hardware,
  };
}

class TvDeviceProfile {
  const TvDeviceProfile({
    required this.manufacturer,
    required this.model,
    required this.sdk,
    required this.abis,
    required this.displayModes,
    required this.hdrTypes,
    required this.codecs,
    required this.audioOutputs,
  });

  const TvDeviceProfile.unknown()
    : manufacturer = 'Unknown',
      model = 'Unknown',
      sdk = 0,
      abis = const [],
      displayModes = const [],
      hdrTypes = const [],
      codecs = const [],
      audioOutputs = const [];

  final String manufacturer;
  final String model;
  final int sdk;
  final List<String> abis;
  final List<TvDisplayMode> displayModes;
  final List<int> hdrTypes;
  final List<TvCodecCapability> codecs;
  final List<Map<String, Object?>> audioOutputs;

  String get key => '$manufacturer/$model/sdk$sdk'.toLowerCase();
  bool get hasHdr => hdrTypes.isNotEmpty;
  bool get hasHdmiAudio => audioOutputs.any((output) => output['hdmi'] == true);

  bool supportsCodec(String? codec) {
    final normalized = codec?.toLowerCase() ?? '';
    final mime = switch (normalized) {
      final value when value.contains('av1') => 'video/av01',
      final value when value.contains('hevc') || value.contains('h265') =>
        'video/hevc',
      final value when value.contains('h264') || value.contains('avc') =>
        'video/avc',
      final value when value.contains('vp9') => 'video/x-vnd.on2.vp9',
      _ => '',
    };
    if (mime.isEmpty) return true;
    return codecs.any((item) => item.mime == mime && item.hardware);
  }

  Map<String, Object?> toJson() => {
    'manufacturer': manufacturer,
    'model': model,
    'sdk': sdk,
    'abis': abis,
    'displayModes': displayModes.map((mode) => mode.toJson()).toList(),
    'hdrTypes': hdrTypes,
    'codecs': codecs.map((codec) => codec.toJson()).toList(),
    'audioOutputs': audioOutputs,
  };

  factory TvDeviceProfile.fromMap(Map<Object?, Object?> value) {
    List<Map<Object?, Object?>> maps(Object? input) =>
        (input as List? ?? const [])
            .whereType<Map>()
            .map((item) => item.cast<Object?, Object?>())
            .toList(growable: false);
    return TvDeviceProfile(
      manufacturer: value['manufacturer'] as String? ?? 'Unknown',
      model: value['model'] as String? ?? 'Unknown',
      sdk: value['sdk'] as int? ?? 0,
      abis: (value['abis'] as List? ?? const []).whereType<String>().toList(),
      displayModes: maps(
        value['displayModes'],
      ).map(TvDisplayMode.fromMap).toList(growable: false),
      hdrTypes: (value['hdrTypes'] as List? ?? const [])
          .whereType<int>()
          .toList(),
      codecs: maps(
        value['codecs'],
      ).map(TvCodecCapability.fromMap).toList(growable: false),
      audioOutputs: maps(value['audioOutputs'])
          .map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList(growable: false),
    );
  }
}

class MediaAction {
  const MediaAction(this.action, this.value);
  final String action;
  final int? value;
}

class AppVersionInfo {
  const AppVersionInfo({required this.name, required this.code});

  const AppVersionInfo.unknown() : name = 'unknown', code = 0;

  final String name;
  final int code;

  factory AppVersionInfo.fromMap(Map<Object?, Object?> value) => AppVersionInfo(
    name: value['versionName'] as String? ?? 'unknown',
    code: (value['versionCode'] as num?)?.toInt() ?? 0,
  );
}

class NativePlaybackResult {
  const NativePlaybackResult({
    required this.status,
    required this.position,
    required this.duration,
    this.completed = false,
    this.firstFrameRendered = false,
    this.droppedFrames = 0,
    this.decoder,
    this.error,
    this.subtitleSize,
    this.audioLanguage,
    this.subtitleLanguage,
    this.subtitlesEnabled,
    this.diagnostics = const {},
  });

  final String status;
  final Duration position;
  final Duration duration;
  final bool completed;
  final bool firstFrameRendered;
  final int droppedFrames;
  final String? decoder;
  final String? error;
  final double? subtitleSize;
  final String? audioLanguage;
  final String? subtitleLanguage;
  final bool? subtitlesEnabled;
  final Map<String, Object?> diagnostics;

  bool get failed => status == 'error' || status == 'no_first_frame';

  factory NativePlaybackResult.fromMap(Map<Object?, Object?> value) =>
      NativePlaybackResult(
        status: value['status'] as String? ?? 'exit',
        position: Duration(
          milliseconds: (value['positionMs'] as num?)?.round() ?? 0,
        ),
        duration: Duration(
          milliseconds: (value['durationMs'] as num?)?.round() ?? 0,
        ),
        completed: value['completed'] as bool? ?? false,
        firstFrameRendered: value['firstFrameRendered'] as bool? ?? false,
        droppedFrames: (value['droppedFrames'] as num?)?.round() ?? 0,
        decoder: value['decoder'] as String?,
        error: value['error'] as String?,
        subtitleSize: (value['subtitleSize'] as num?)?.toDouble(),
        audioLanguage: value['audioLanguage'] as String?,
        subtitleLanguage: value['subtitleLanguage'] as String?,
        subtitlesEnabled: value['subtitlesEnabled'] as bool?,
        diagnostics: {
          for (final key in const [
            'surfaceReady',
            'manufacturer',
            'model',
            'sdk',
            'abis',
            'memoryClassMb',
            'lowMemoryDevice',
            'videoMime',
            'videoCodecs',
            'videoWidth',
            'videoHeight',
            'videoFrameRate',
            'audioMime',
            'audioCodecs',
          ])
            if (value.containsKey(key)) key: value[key],
        },
      );

  factory NativePlaybackResult.platformError(Object error) =>
      NativePlaybackResult(
        status: 'error',
        position: Duration.zero,
        duration: Duration.zero,
        error: error.toString(),
      );
}

class AndroidTvBridge {
  AndroidTvBridge._() {
    _channel.setMethodCallHandler(_handleMethod);
  }

  static final instance = AndroidTvBridge._();
  static const _channel = MethodChannel('dev.tetotv/android_tv');
  final _mediaActions = StreamController<MediaAction>.broadcast();
  TvDeviceProfile? _cachedProfile;

  Stream<MediaAction> get mediaActions => _mediaActions.stream;

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method != 'mediaAction') return;
    final args = (call.arguments as Map?)?.cast<Object?, Object?>();
    if (args == null) return;
    _mediaActions.add(
      MediaAction(args['action'] as String? ?? '', args['value'] as int?),
    );
  }

  Future<TvDeviceProfile> getDeviceProfile({bool refresh = false}) async {
    if (!refresh && _cachedProfile != null) return _cachedProfile!;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const TvDeviceProfile.unknown();
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getDeviceProfile',
      );
      return _cachedProfile = result == null
          ? const TvDeviceProfile.unknown()
          : TvDeviceProfile.fromMap(result);
    } on PlatformException {
      return const TvDeviceProfile.unknown();
    }
  }

  Future<AppVersionInfo> getAppVersion() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const AppVersionInfo.unknown();
    }
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'getAppVersion',
      );
      return result == null
          ? const AppVersionInfo.unknown()
          : AppVersionInfo.fromMap(result);
    } on PlatformException {
      return const AppVersionInfo.unknown();
    }
  }

  Future<String> installApk(String path) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw PlatformException(
        code: 'APK_INSTALL_UNSUPPORTED',
        message: 'APK installation is only supported on Android.',
      );
    }
    return await _channel.invokeMethod<String>('installApk', {'path': path}) ??
        'launched';
  }

  Future<String?> voiceSearch() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final result = await _channel.invokeMethod<String>('voiceSearch');
      final query = result?.trim() ?? '';
      return query.isEmpty ? null : query;
    } on PlatformException {
      return null;
    }
  }

  Future<void> setPreferredFrameRate(double fps) async {
    if (fps <= 0 || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<int>('setPreferredFrameRate', {'fps': fps});
    } on PlatformException {
      // Mode switching is optional and unsupported by some Fire OS builds.
    }
  }

  Future<void> clearPreferredFrameRate() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('clearPreferredFrameRate');
    } on PlatformException {
      // Best effort only.
    }
  }

  /// Starts the dedicated Android Media3 player activity.
  ///
  /// Video is rendered by a native SurfaceView in a separate activity. This is
  /// deliberately not an AndroidView/Flutter texture: several Fire TV devices
  /// corrupt or drop frames when a decoder has to copy video through Flutter's
  /// texture compositor.
  Future<NativePlaybackResult> startNativePlayer({
    required Uri source,
    required String title,
    required String checkpointKey,
    required String releaseName,
    required Duration resumePosition,
    required bool startFromBeginning,
    DateTime? resumeUpdatedAt,
    String? externalSubtitle,
    String audioLanguage = 'eng',
    String subtitleLanguage = 'eng',
    bool subtitlesEnabled = true,
    double subtitleSize = 34,
    int subtitlePosition = 100,
    bool highContrastSubtitles = false,
    int subtitleTextColor = 0xFFFFFFFF,
    int subtitleBackgroundColor = 0x00000000,
    int seekBackSeconds = 10,
    int seekForwardSeconds = 10,
    String videoFit = 'contain',
    int? malMediaId,
    int? episodeNumber,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const NativePlaybackResult(
        status: 'unsupported',
        position: Duration.zero,
        duration: Duration.zero,
        error: 'The native Media3 player is only available on Android.',
      );
    }
    try {
      final value = await _channel
          .invokeMapMethod<Object?, Object?>('startNativePlayer', {
            'source': source.toString(),
            'title': title,
            'checkpointKey': checkpointKey,
            'releaseName': releaseName,
            'resumeMs': resumePosition.inMilliseconds,
            'resumeProvided':
                resumeUpdatedAt != null || resumePosition > Duration.zero,
            if (resumeUpdatedAt != null)
              'resumeUpdatedAtMs': resumeUpdatedAt.millisecondsSinceEpoch,
            'startFromBeginning': startFromBeginning,
            if (externalSubtitle != null && externalSubtitle.isNotEmpty)
              'externalSubtitle': externalSubtitle,
            'audioLanguage': audioLanguage,
            'subtitleLanguage': subtitleLanguage,
            'subtitlesEnabled': subtitlesEnabled,
            'subtitleSize': subtitleSize,
            'subtitlePosition': subtitlePosition,
            'highContrastSubtitles': highContrastSubtitles,
            'subtitleTextColor': subtitleTextColor,
            'subtitleBackgroundColor': subtitleBackgroundColor,
            'seekBackMs': seekBackSeconds * 1000,
            'seekForwardMs': seekForwardSeconds * 1000,
            'videoFit': videoFit,
            'malMediaId': ?malMediaId,
            'episodeNumber': ?episodeNumber,
          });
      return value == null
          ? const NativePlaybackResult(
              status: 'exit',
              position: Duration.zero,
              duration: Duration.zero,
            )
          : NativePlaybackResult.fromMap(value);
    } on PlatformException catch (error) {
      return NativePlaybackResult.platformError(error);
    }
  }

  Future<void> updateMediaSession({
    required String title,
    required int episode,
    required Duration position,
    required Duration duration,
    required bool playing,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('updateMediaSession', {
        'title': title,
        'subtitle': 'Episode $episode',
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
        'playing': playing,
      });
    } on PlatformException {
      // Playback must continue even when a vendor MediaSession is unavailable.
    }
  }

  Future<void> publishWatchNext({
    required int mediaId,
    required int episode,
    required String title,
    required Duration position,
    required Duration duration,
    String? posterUrl,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<int>('publishWatchNext', {
        'mediaId': mediaId,
        'episode': episode,
        'title': title,
        'description': 'Continue episode $episode on TetoTV',
        'posterUrl': posterUrl,
        'positionMs': position.inMilliseconds,
        'durationMs': duration.inMilliseconds,
      });
    } on PlatformException {
      // Fire TV and some operator devices do not expose the Watch Next provider.
    }
  }

  Future<bool> scheduleReminder({
    required int mediaId,
    required int episode,
    required String title,
    required DateTime airingAt,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final reminderAt = airingAt.subtract(const Duration(minutes: 10));
    if (reminderAt.isBefore(DateTime.now())) return false;
    try {
      return await _channel.invokeMethod<bool>('scheduleReminder', {
            'mediaId': mediaId,
            'episode': episode,
            'title': title,
            'atMillis': reminderAt.millisecondsSinceEpoch,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
