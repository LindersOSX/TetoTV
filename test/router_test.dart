import 'package:anime_tv/app/router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('route integers accept only positive decimal values', () {
    expect(positiveRouteInt('42'), 42);
    expect(positiveRouteInt('001'), 1);

    expect(positiveRouteInt(null), isNull);
    expect(positiveRouteInt(''), isNull);
    expect(positiveRouteInt('not-a-number'), isNull);
    expect(positiveRouteInt('0'), isNull);
    expect(positiveRouteInt('-1'), isNull);
  });

  test('legal disclosures have internal settings routes', () {
    final paths = appRouter.configuration.routes
        .whereType<GoRoute>()
        .map((route) => route.path)
        .toSet();

    expect(paths, contains('/settings/privacy'));
    expect(paths, contains('/settings/notices'));
  });
}
