import 'package:anime_tv/features/watch_together/application/watch_party_controller.dart';

String? watchPartyPlayerStatus(WatchPartyState state) {
  final session = state.session;
  if (session == null) return null;
  if (state.timelineMismatch) {
    return 'PARTY ${session.roomCode} • DIFFERENT CUT';
  }
  final connection = state.connection == WatchPartyConnection.connected
      ? ''
      : ' • RECONNECTING';
  if (state.isHost) {
    final guests = state.snapshot?.participantCount ?? 0;
    return 'PARTY ${session.roomCode} • HOST • $guests watching$connection';
  }
  return 'PARTY ${session.roomCode} • SYNCED$connection';
}
