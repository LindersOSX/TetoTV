import 'dart:async';

import 'package:anime_tv/features/catalog/application/catalog_providers.dart';
import 'package:anime_tv/features/catalog/data/anilist_catalog_client.dart';
import 'package:anime_tv/features/catalog/domain/anime_summary.dart';
import 'package:anime_tv/features/catalog/presentation/search_screen.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
