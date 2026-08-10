import 'dart:collection';

import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/features/marketplace/application/source_pairing_controller.dart';
import 'package:anime_tv/features/marketplace/data/source_pairing_client.dart';
import 'package:anime_tv/features/marketplace/domain/source_pairing.dart';
import 'package:anime_tv/features/marketplace/presentation/source_pairing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('shows the QR and code with CANCEL focused on a narrow phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _DialogApi(session: _dialogSession());
    late SourcePairingController controller;

    await tester.pumpWidget(
      _harness(api: api, onController: (value) => controller = value),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel,
      'qr code',
    );
    expect(find.text('ABCD-EFGH'), findsOneWidget);
    expect(
      find.textContaining('https://pair.example/source-pair'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'CANCEL'),
    );
    expect(cancel.autofocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(SourcePairingDialog), findsNothing);
    expect(api.cancelCalls, greaterThanOrEqualTo(1));
    expect(controller.mounted, isFalse);
  });

  testWidgets('fits at 1280x720 and focuses DONE after a successful import', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _DialogApi(
      session: _dialogSession(),
      polls: [
        () async => const SourcePairingPollResult(
          status: SourcePairingPollStatus.submitted,
          payload: SourcePairingPayload(
            repositoryUrls: ['https://example.com/marketplace.json'],
          ),
        ),
      ],
    );
    late SourcePairingController controller;

    await tester.pumpWidget(
      _harness(api: api, onController: (value) => controller = value),
    );
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await controller.pollNow();
    await tester.pumpAndSettle();

    expect(find.text('Sources added'), findsOneWidget);
    final done = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'DONE'),
    );
    expect(done.autofocus, isTrue);
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SourcePairingDialog), findsNothing);
  });
}

Widget _harness({
  required _DialogApi api,
  required void Function(SourcePairingController) onController,
}) {
  return ProviderScope(
    overrides: [
      sourcePairingControllerProvider.overrideWith((ref) {
        final controller = SourcePairingController(
          () async => 'https://pair.example',
          (_) => api,
          (_) async => const SourceImportSummary(repositoriesAdded: 1),
        );
        onController(controller);
        return controller;
      }),
    ],
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showSourcePairingDialog(context),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );
}

SourcePairingSession _dialogSession() => SourcePairingSession(
  pairingId: 'dialog-session',
  deviceCode: 'd' * 48,
  userCode: 'ABCD-EFGH',
  verificationUri: Uri.parse('https://pair.example/source-pair'),
  verificationUriComplete: Uri.parse(
    'https://pair.example/source-pair?code=ABCD-EFGH',
  ),
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  pollInterval: const Duration(hours: 1),
);

class _DialogApi implements SourcePairingApi {
  _DialogApi({
    required this.session,
    List<Future<SourcePairingPollResult> Function()> polls = const [],
  }) : _polls = Queue<Future<SourcePairingPollResult> Function()>.of(polls);

  final SourcePairingSession session;
  final Queue<Future<SourcePairingPollResult> Function()> _polls;
  int cancelCalls = 0;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<SourcePairingSession> createSession() async => session;

  @override
  Future<SourcePairingPollResult> poll(SourcePairingSession session) =>
      _polls.isEmpty
      ? Future.value(
          const SourcePairingPollResult(
            status: SourcePairingPollStatus.pending,
          ),
        )
      : _polls.removeFirst()();

  @override
  Future<void> cancel(SourcePairingSession session) async {
    cancelCalls++;
  }
}
