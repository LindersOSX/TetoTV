import 'dart:async';
import 'dart:collection';

import 'package:anime_tv/features/marketplace/application/source_pairing_controller.dart';
import 'package:anime_tv/features/marketplace/data/source_pairing_client.dart';
import 'package:anime_tv/features/marketplace/domain/source_pairing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bulk import batches repository refresh and reports a URL-safe partial result',
    () async {
      final repositoryRefreshFlags = <bool>[];
      final validatedHosts = <String>[];
      var refreshCalls = 0;
      var manifestCalls = 0;
      const repositoryOne = 'https://repo-one.example/marketplace.json';
      const repositoryTwo = 'https://repo-two.example/catalog.json';
      const acceptedManifest =
          'https://addons.example/manifest.json?key=accepted-secret';
      const rejectedManifest =
          'https://broken.example/manifest.json?key=rejected-secret';

      final summary = await importPairedSourcesWithOperations(
        const SourcePairingPayload(
          repositoryUrls: [repositoryOne, repositoryTwo],
          manifestUrls: [acceptedManifest, rejectedManifest],
        ),
        repositoryTargetValidator: (uri) async {
          validatedHosts.add(uri.host);
        },
        addRepository: (url, {refreshAfterAdd = true}) async {
          repositoryRefreshFlags.add(refreshAfterAdd);
          return null;
        },
        refreshRepositories: () async {
          refreshCalls++;
        },
        addManifest: (url) async {
          manifestCalls++;
          return url == rejectedManifest ? 'manifest was rejected' : null;
        },
      );

      expect(validatedHosts, ['repo-one.example', 'repo-two.example']);
      expect(repositoryRefreshFlags, [false, false]);
      expect(refreshCalls, 1);
      expect(manifestCalls, 2);
      expect(summary.repositoriesAdded, 2);
      expect(summary.manifestsAdded, 1);
      expect(summary.errors, ['Torrent manifest 2: manifest was rejected']);
      expect(
        summary.message,
        contains('Added 2 repositories and 1 torrent manifest.'),
      );
      expect(summary.message, contains('1 item was rejected.'));
      for (final error in summary.errors) {
        expect(error, isNot(contains(repositoryOne)));
        expect(error, isNot(contains(repositoryTwo)));
        expect(error, isNot(contains(acceptedManifest)));
        expect(error, isNot(contains(rejectedManifest)));
        expect(error, isNot(contains('secret')));
      }
    },
  );

  group('SourcePairingController', () {
    test('completes with a partial-import summary', () async {
      final api = _FakeSourcePairingApi(
        session: _session('partial'),
        polls: [
          () async => const SourcePairingPollResult(
            status: SourcePairingPollStatus.submitted,
            payload: SourcePairingPayload(
              repositoryUrls: ['https://example.com/marketplace.json'],
              manifestUrls: ['https://example.com/manifest.json'],
            ),
          ),
        ],
      );
      final controller = SourcePairingController(
        () async => 'https://pair.example',
        (_) => api,
        (_) async => const SourceImportSummary(
          repositoriesAdded: 1,
          errors: ['Torrent manifest 1: invalid manifest.'],
        ),
      );
      addTearDown(controller.dispose);

      await controller.start();
      expect(controller.state.stage, SourcePairingStage.waiting);

      await controller.pollNow();

      expect(controller.state.stage, SourcePairingStage.completed);
      expect(controller.state.summary?.repositoriesAdded, 1);
      expect(controller.state.summary?.manifestsAdded, 0);
      expect(controller.state.summary?.errors, hasLength(1));
      expect(controller.state.message, contains('Added 1 repository.'));
      expect(controller.state.message, contains('1 item was rejected.'));
    });

    test(
      'an importer exception becomes an immediate terminal failure',
      () async {
        final api = _FakeSourcePairingApi(
          session: _session('import-error'),
          polls: [
            () async => const SourcePairingPollResult(
              status: SourcePairingPollStatus.submitted,
              payload: SourcePairingPayload(
                repositoryUrls: ['https://example.com/marketplace.json'],
              ),
            ),
          ],
        );
        final controller = SourcePairingController(
          () async => 'https://pair.example',
          (_) => api,
          (_) async => throw StateError('sensitive source URL'),
        );
        addTearDown(controller.dispose);

        await controller.start();
        await controller.pollNow();

        expect(controller.state.stage, SourcePairingStage.failed);
        expect(controller.state.session?.pairingId, 'import-error');
        expect(
          controller.state.message,
          contains('could not be imported safely'),
        );
        expect(
          controller.state.message,
          isNot(contains('sensitive source URL')),
        );
      },
    );

    test(
      'a restart can poll the new session while the old poll is pending',
      () async {
        final oldPoll = Completer<SourcePairingPollResult>();
        final oldApi = _FakeSourcePairingApi(
          session: _session('old'),
          polls: [() => oldPoll.future],
        );
        final newApi = _FakeSourcePairingApi(
          session: _session('new'),
          polls: [
            () async => const SourcePairingPollResult(
              status: SourcePairingPollStatus.submitted,
              payload: SourcePairingPayload(
                manifestUrls: ['https://example.com/manifest.json'],
              ),
            ),
          ],
        );
        final clients = Queue<SourcePairingApi>.of([oldApi, newApi]);
        final controller = SourcePairingController(
          () async => 'https://pair.example',
          (_) => clients.removeFirst(),
          (_) async => const SourceImportSummary(manifestsAdded: 1),
        );
        addTearDown(controller.dispose);

        await controller.start();
        final stalePoll = controller.pollNow();
        await Future<void>.delayed(Duration.zero);

        await controller.start();
        expect(controller.state.session?.pairingId, 'new');
        await controller.pollNow();
        expect(controller.state.stage, SourcePairingStage.completed);
        expect(controller.state.session?.pairingId, 'new');

        oldPoll.complete(
          const SourcePairingPollResult(
            status: SourcePairingPollStatus.expired,
          ),
        );
        await stalePoll;

        expect(controller.state.stage, SourcePairingStage.completed);
        expect(controller.state.session?.pairingId, 'new');
        expect(oldApi.cancelCalls, 1);
      },
    );

    test('stop cancels the session and ignores a late poll result', () async {
      final latePoll = Completer<SourcePairingPollResult>();
      final api = _FakeSourcePairingApi(
        session: _session('stopped'),
        polls: [() => latePoll.future],
      );
      final controller = SourcePairingController(
        () async => 'https://pair.example',
        (_) => api,
        (_) async => const SourceImportSummary(manifestsAdded: 1),
      );
      addTearDown(controller.dispose);

      await controller.start();
      final pending = controller.pollNow();
      await Future<void>.delayed(Duration.zero);
      controller.stop();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.stage, SourcePairingStage.stopped);
      expect(api.cancelCalls, 1);

      latePoll.complete(
        const SourcePairingPollResult(
          status: SourcePairingPollStatus.submitted,
          payload: SourcePairingPayload(
            manifestUrls: ['https://example.com/manifest.json'],
          ),
        ),
      );
      await pending;

      expect(controller.state.stage, SourcePairingStage.stopped);
    });

    test(
      'dispose cancels the session and safely ignores a late poll',
      () async {
        final latePoll = Completer<SourcePairingPollResult>();
        final api = _FakeSourcePairingApi(
          session: _session('disposed'),
          polls: [() => latePoll.future],
        );
        final controller = SourcePairingController(
          () async => 'https://pair.example',
          (_) => api,
          (_) async => const SourceImportSummary(manifestsAdded: 1),
        );

        await controller.start();
        final pending = controller.pollNow();
        await Future<void>.delayed(Duration.zero);
        controller.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(api.cancelCalls, 1);
        latePoll.complete(
          const SourcePairingPollResult(
            status: SourcePairingPollStatus.pending,
          ),
        );
        await pending;
      },
    );
  });
}

SourcePairingSession _session(String id) => SourcePairingSession(
  pairingId: id,
  deviceCode: 'd' * 48,
  userCode: 'ABCD-EFGH',
  verificationUri: Uri.parse('https://pair.example/source-pair'),
  verificationUriComplete: Uri.parse(
    'https://pair.example/source-pair?code=ABCD-EFGH',
  ),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  pollInterval: const Duration(hours: 1),
);

class _FakeSourcePairingApi implements SourcePairingApi {
  _FakeSourcePairingApi({required this.session, required List<_Poll> polls})
    : _polls = Queue<_Poll>.of(polls);

  final SourcePairingSession session;
  final Queue<_Poll> _polls;
  int cancelCalls = 0;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<SourcePairingSession> createSession() async => session;

  @override
  Future<SourcePairingPollResult> poll(SourcePairingSession session) {
    if (_polls.isEmpty) {
      return Future.value(
        const SourcePairingPollResult(status: SourcePairingPollStatus.pending),
      );
    }
    return _polls.removeFirst()();
  }

  @override
  Future<void> cancel(SourcePairingSession session) async {
    cancelCalls++;
  }
}

typedef _Poll = Future<SourcePairingPollResult> Function();
