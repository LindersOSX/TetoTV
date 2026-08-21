import 'package:anime_tv/features/player/presentation/watch_party_player_dialog.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_controller.dart';
import 'package:anime_tv/features/watch_together/application/watch_party_public_identity_provider.dart';
import 'package:anime_tv/features/watch_together/data/watch_party_client.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player HUD labels backend participant count as guests', () {
    expect(watchPartyGuestCountLabel(-1), '0 guests');
    expect(watchPartyGuestCountLabel(0), '0 guests');
    expect(watchPartyGuestCountLabel(1), '1 guest');
    expect(watchPartyGuestCountLabel(2), '2 guests');
  });

  testWidgets(
    'player HUD creates a room, shows QR guidance, and Close keeps it active',
    (tester) async {
      final client = _HudWatchPartyClient();
      final controller = WatchPartyController(client);
      final identity = WatchPartyPublicIdentity.tryCreate(
        displayName: 'Teto Fan',
        avatarUrl:
            'https://s4.anilist.co/file/anilistcdn/user/avatar/large/x.jpg',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            watchPartyControllerProvider.overrideWith((_) => controller),
            watchPartyClientProvider.overrideWithValue(client),
            watchPartyPublicIdentityProvider.overrideWithValue(identity),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showWatchPartyPlayerDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump();

      expect(client.createCalls, 1);
      expect(client.publicIdentity?.displayName, 'Teto Fan');
      expect(
        find.byKey(const ValueKey('player-watch-party-dialog')),
        findsOneWidget,
      );
      expect(find.text('23456789'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-watch-party-qr')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Closing this panel does not end'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Stream URLs, tokens, headers'),
        findsOneWidget,
      );
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'player.watch-party.copy',
      );

      expect(find.text('Host profile'), findsNothing);
      expect(find.text('1 guest • 1 ready'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('player-watch-party-room-code-action')),
      );
      await tester.pump();
      expect(find.text('Host profile'), findsOneWidget);
      expect(find.text('Guest profile'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('player-watch-party-close')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('player-watch-party-dialog')),
        findsNothing,
      );
      expect(controller.state.isActive, isTrue);
      expect(client.leaveCalls, 0);

      // Dispose the overridden provider before its recurring room poll is due.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class _HudWatchPartyClient extends WatchPartyClient {
  _HudWatchPartyClient() : super(baseUrl: 'https://tetotv-bot.wisp.uno');

  var createCalls = 0;
  var leaveCalls = 0;
  WatchPartyPublicIdentity? publicIdentity;

  @override
  void setPublicIdentity(WatchPartyPublicIdentity? identity) {
    super.setPublicIdentity(identity);
    publicIdentity = identity;
  }

  final session = WatchPartySession(
    roomCode: '23456789',
    token: List.filled(48, 'a').join(),
    role: WatchPartyRole.host,
    expiresAt: DateTime.utc(2030),
    watchUrl: Uri.parse('https://tetotv-bot.wisp.uno/watch?room=23456789'),
  );

  @override
  Future<WatchPartyCreated> create() async {
    createCalls += 1;
    return WatchPartyCreated(session: session);
  }

  @override
  Future<WatchPartySnapshot> snapshot(WatchPartySession session) async =>
      WatchPartySnapshot(
        roomCode: session.roomCode,
        role: WatchPartyRole.host,
        revision: 0,
        playing: false,
        position: Duration.zero,
        effectiveAt: DateTime.utc(2026),
        serverTime: DateTime.utc(2026),
        participantCount: 1,
        readyCount: 1,
        participants: const [
          WatchPartyParticipant(
            displayName: 'Host profile',
            role: WatchPartyRole.host,
            ready: true,
          ),
          WatchPartyParticipant(
            displayName: 'Guest profile',
            role: WatchPartyRole.guest,
            ready: false,
          ),
        ],
        expiresAt: DateTime.utc(2030),
      );

  @override
  Future<void> leave(WatchPartySession session) async {
    leaveCalls += 1;
  }
}
