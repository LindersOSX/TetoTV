import 'package:media_kit/media_kit.dart';

/// Gives a demuxer a short, bounded window to finish publishing its track
/// list. Some Android backends announce the default audio stream first and
/// add the remaining embedded streams a few frames later. Opening the picker
/// from that first snapshot makes a dual-audio file look Japanese-only.
Future<T> waitForStableTrackSnapshot<T>({
  required Future<T> Function() read,
  required Object Function(T snapshot) signature,
  required bool Function(T snapshot) hasTracks,
  bool Function(T snapshot)? isComplete,
  Duration pollInterval = const Duration(milliseconds: 200),
  Duration minimumWait = const Duration(milliseconds: 800),
  Duration maximumWait = const Duration(seconds: 2),
}) async {
  var latest = await read();
  var latestSignature = signature(latest);
  var stableSamples = 0;
  var elapsed = Duration.zero;
  while (elapsed < maximumWait) {
    await Future<void>.delayed(pollInterval);
    elapsed += pollInterval;
    final next = await read();
    final nextSignature = signature(next);
    if (nextSignature == latestSignature) {
      stableSamples++;
    } else {
      stableSamples = 0;
      latestSignature = nextSignature;
    }
    latest = next;
    final complete = isComplete?.call(latest) ?? hasTracks(latest);
    if (elapsed >= minimumWait && complete && stableSamples >= 2) {
      break;
    }
  }
  return latest;
}

/// Release names are hints, not proof, but a dual/multi-audio label tells the
/// picker to give a slow demuxer longer to publish its second embedded track.
bool releaseAdvertisesMultipleAudio(String releaseName) {
  final normalized = releaseName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  return RegExp(r'\b(?:dual|multi) audio\b').hasMatch(normalized);
}

String mediaKitAudioTrackSignature(Iterable<AudioTrack> tracks) => tracks
    .where((track) => track.id != 'auto' && track.id != 'no')
    .map(
      (track) => [
        track.id,
        track.title ?? '',
        track.language ?? '',
        track.codec ?? '',
        track.channelscount ?? 0,
      ].join('\u001f'),
    )
    .join('\u001e');

String vlcAudioTrackSignature(Map<int, String> tracks) {
  final entries = tracks.entries.where((entry) => entry.key >= 0).toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries
      .map((entry) => '${entry.key}\u001f${entry.value}')
      .join('\u001e');
}

String? mediaKitAudioTrackDetail(AudioTrack track) {
  final values = <String>[];
  if (playerTrackMatchesEnglish(track)) {
    values.add('English');
  } else if (track.language case final language?) {
    values.add(language);
  }
  if (track.codec case final codec?) values.add(codec.toUpperCase());
  if (track.channelscount case final channels?) {
    values.add('$channels channel${channels == 1 ? '' : 's'}');
  }
  return values.isEmpty ? null : values.join(' / ');
}

bool playerTrackMatchesEnglish(AudioTrack track) {
  final language = (track.language ?? '').trim().toLowerCase();
  final title = (track.title ?? '').trim().toLowerCase();
  return const {'en', 'eng', 'en-us', 'en-gb'}.contains(language) ||
      title.contains('english') ||
      title.contains('dub') ||
      title.contains('eng ');
}

AudioTrack? preferredDubAudioTrack(
  Iterable<AudioTrack> tracks, {
  bool preferSurround = false,
}) {
  final available = tracks
      .where((track) => track.id != 'auto' && track.id != 'no')
      .toList(growable: false);
  if (available.isEmpty) return null;

  int score(AudioTrack track) {
    final language = (track.language ?? '').toLowerCase();
    final title = (track.title ?? '').toLowerCase();
    var value = 0;
    if (const {'en', 'eng', 'en-us', 'en-gb'}.contains(language)) {
      value += 100;
    }
    if (title.contains('english') ||
        title.contains('dub') ||
        title.contains('eng ')) {
      value += 80;
    }
    if (track.isDefault == true) value += 10;
    if (preferSurround) {
      value += (track.channelscount ?? 0).clamp(0, 8) * 2;
    }
    if (title.contains('commentary') ||
        title.contains('descriptive') ||
        title.contains('signs')) {
      value -= 150;
    }
    return value;
  }

  final ranked = [...available]..sort((a, b) => score(b).compareTo(score(a)));
  return score(ranked.first) >= 50 ? ranked.first : null;
}
