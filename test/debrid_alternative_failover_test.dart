import 'package:anime_tv/features/player/presentation/native_media3_player_screen.dart';
import 'package:anime_tv/features/streaming/data/real_debrid_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('debrid alternative failover', () {
    test('continues after a release-specific rejection', () {
      final error = RealDebridException.fromApi(code: 35);

      expect(error.isCandidateSpecific, isTrue);
      expect(isTerminalDebridAlternativeFailure(error), isFalse);
      expect(error.toString().toLowerCase(), isNot(contains('infringing')));
    });

    test('stops after authentication or account-wide failures', () {
      expect(
        isTerminalDebridAlternativeFailure(
          RealDebridException.fromApi(code: 9),
        ),
        isTrue,
      );
      expect(
        isTerminalDebridAlternativeFailure(
          RealDebridException.fromApi(code: 21),
        ),
        isTrue,
      );
    });

    test('stops on provider-wide failures but keeps generic failover', () {
      expect(
        isTerminalDebridAlternativeFailure(
          RealDebridException.fromApi(code: 18),
        ),
        isTrue,
      );
      expect(
        isTerminalDebridAlternativeFailure(
          RealDebridException.fromApi(code: 34),
        ),
        isTrue,
      );
      expect(
        isTerminalDebridAlternativeFailure(Exception('network hiccup')),
        isFalse,
      );
    });
  });
}
