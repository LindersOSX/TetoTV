import 'package:media_kit/media_kit.dart';

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
