import 'dart:async';

import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/data/anilist_catalog_client.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/search_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a stale search cannot replace the latest results', (
    tester,
  ) async {
    final client = _DeferredCatalogClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: SearchScreen(initialQuery: 'old')),
      ),
    );
    await tester.pump();
    expect(client.requests, contains('old'));

    await tester.tap(find.byType(TvTextInput));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('CLEAR'));
    await tester.tap(find.text('n'));
    await tester.tap(find.text('e'));
    await tester.tap(find.text('w'));
    await tester.tap(find.text('DONE'));
    await tester.pump();
    expect(client.requests, contains('new'));

    client.complete('new', [_anime(2, 'Latest result')]);
    await tester.pump();
    expect(find.text('Latest result'), findsOneWidget);

    client.complete('old', [_anime(1, 'Stale result')]);
    await tester.pump();
    expect(find.text('Latest result'), findsOneWidget);
    expect(find.text('Stale result'), findsNothing);
  });

  testWidgets('a completed empty search has a distinct no-match state', (
    tester,
  ) async {
    final client = _DeferredCatalogClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: SearchScreen(initialQuery: 'missing')),
      ),
    );
    await tester.pump();

    client.complete('missing', const []);
    await tester.pump();

    expect(find.text('No matches found'), findsOneWidget);
    expect(find.text('Find your next show'), findsNothing);
  });

  testWidgets('voice search submits the recognized anime title', (
    tester,
  ) async {
    final client = _DeferredCatalogClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.tetotv/android_tv'),
          (call) async => call.method == 'voiceSearch' ? 'Cowboy Bebop' : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.tetotv/android_tv'),
            null,
          ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(client.requests, contains('Cowboy Bebop'));
    expect(find.text('Results for “Cowboy Bebop”'), findsOneWidget);
  });

  testWidgets('built-in keyboard submission focuses the first result', (
    tester,
  ) async {
    final client = _DeferredCatalogClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogClientProvider.overrideWithValue(client)],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );

    await tester.tap(find.byType(TvTextInput));
    await tester.pumpAndSettle();
    await tester.tap(find.text('c'));
    await tester.tap(find.text('o'));
    await tester.tap(find.text('w'));
    await tester.tap(find.text('DONE'));
    await tester.pump();
    client.complete('cow', [_anime(11, 'Cowboy Bebop')]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Cowboy Bebop'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'search.result.first',
    );
  });
  testWidgets('focused long result titles stay inside the card', (
    tester,
  ) async {
    const longTitle =
        'Skeleton Knight in Another World Season Two With an Extra Long Name';
    const query = 'skeleton';
    final viewports = <Size>[const Size(1280, 720), const Size(400, 800)];
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final viewport in viewports) {
      await tester.binding.setSurfaceSize(viewport);
      final client = _DeferredCatalogClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [catalogClientProvider.overrideWithValue(client)],
          child: const MaterialApp(home: SearchScreen(initialQuery: query)),
        ),
      );
      await tester.pump();

      client.complete(query, [_anime(3, longTitle)]);
      await tester.pump();

      final title = find.text(longTitle);
      expect(title, findsOneWidget, reason: 'viewport: $viewport');
      final card = find.ancestor(of: title, matching: find.byType(TvFocusable));
      expect(card, findsOneWidget, reason: 'viewport: $viewport');
      final focusDetector = find.descendant(
        of: card,
        matching: find.byType(FocusableActionDetector),
      );
      tester
          .widget<FocusableActionDetector>(focusDetector)
          .focusNode!
          .requestFocus();
      await tester.pump(const Duration(milliseconds: 100));

      final titleRect = tester.getRect(title);
      final cardRect = tester.getRect(card);
      const safeInset = 5.0;
      expect(
        titleRect.left,
        greaterThanOrEqualTo(cardRect.left + safeInset),
        reason: 'left edge at viewport $viewport',
      );
      expect(
        titleRect.right,
        lessThanOrEqualTo(cardRect.right - safeInset),
        reason: 'right edge at viewport $viewport',
      );
      expect(
        titleRect.top,
        greaterThanOrEqualTo(cardRect.top + safeInset),
        reason: 'top edge at viewport $viewport',
      );
      expect(
        titleRect.bottom,
        lessThanOrEqualTo(cardRect.bottom - safeInset),
        reason: 'bottom edge at viewport $viewport',
      );
      expect(tester.takeException(), isNull, reason: 'viewport: $viewport');

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

AnimeSummary _anime(int id, String title) => AnimeSummary(
  id: id,
  title: title,
  description: '',
  episodes: 1,
  score: null,
);

class _DeferredCatalogClient extends AniListCatalogClient {
  _DeferredCatalogClient()
    : super(
        dio: Dio(BaseOptions(baseUrl: 'https://example.invalid')),
        kitsuDio: Dio(BaseOptions(baseUrl: 'https://example.invalid')),
      );

  final Map<String, Completer<List<AnimeSummary>>> _requests = {};

  Iterable<String> get requests => _requests.keys;

  @override
  Future<List<AnimeSummary>> search(String term, {int page = 1}) {
    return (_requests[term] ??= Completer<List<AnimeSummary>>()).future;
  }

  void complete(String term, List<AnimeSummary> results) {
    _requests[term]!.complete(results);
  }
}
