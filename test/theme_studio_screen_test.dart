import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/features/settings/application/theme_studio_controller.dart';
import 'package:anime_tv/features/settings/presentation/theme_studio_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('route renders all color roles and a responsive live preview', (
    tester,
  ) async {
    final harness = await _pumpStudio(tester);
    addTearDown(harness.dispose);

    expect(ThemeStudioScreen.routePath, '/settings/theme-studio');
    expect(find.byKey(const ValueKey('theme-studio-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-live-preview')), findsOneWidget);
    for (final role in AppThemeColorRole.values) {
      expect(find.byKey(ValueKey('theme-color-${role.name}')), findsOneWidget);
      expect(find.text(role.displayName), findsOneWidget);
    }
  });

  testWidgets('TV focus starts on Apply and D-pad reaches editable colors', (
    tester,
  ) async {
    final harness = await _pumpStudio(tester);
    addTearDown(harness.dispose);

    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey('theme-studio-apply')),
    );
    expect(apply.autofocus, isTrue);
    final focusedButton = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<FilledButton>();
    expect(focusedButton?.key, const ValueKey('theme-studio-apply'));

    final accentTile = find.byKey(const ValueKey('theme-color-accent'));
    await tester.ensureVisible(accentTile);
    await tester.pumpAndSettle();
    final accentFocusable = find.ancestor(
      of: accentTile,
      matching: find.byType(FocusableActionDetector),
    );
    final accentFocusNode = tester
        .widget<FocusableActionDetector>(accentFocusable)
        .focusNode!;
    accentFocusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('theme-editor-hex')), findsOneWidget);
  });

  testWidgets('color dialog supports D-pad focus traversal and Back cancel', (
    tester,
  ) async {
    final harness = await _pumpStudio(tester);
    addTearDown(harness.dispose);
    final accentTile = find.byKey(const ValueKey('theme-color-accent'));
    await tester.ensureVisible(accentTile);
    await tester.pumpAndSettle();
    await tester.tap(accentTile);
    await tester.pumpAndSettle();

    final hexEditable = find.descendant(
      of: find.byKey(const ValueKey('theme-editor-hex')),
      matching: find.byType(EditableText),
    );
    expect(hexEditable, findsOneWidget);
    expect(tester.widget<EditableText>(hexEditable).focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(
      tester.widget<EditableText>(hexEditable).focusNode.hasFocus,
      isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme-editor-hex')), findsNothing);
  });

  testWidgets('exact hex color can be previewed, applied and persisted', (
    tester,
  ) async {
    final values = <String, String>{};
    final harness = await _pumpStudio(tester, values: values);
    addTearDown(harness.dispose);

    final accentTile = find.byKey(const ValueKey('theme-color-accent'));
    await tester.ensureVisible(accentTile);
    await tester.pumpAndSettle();
    await tester.tap(accentTile);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('theme-editor-hex')),
      '#4C7DFF',
    );
    await tester.tap(find.byKey(const ValueKey('theme-editor-use-color')));
    await tester.pumpAndSettle();
    final applyButton = find.byKey(const ValueKey('theme-studio-apply'));
    await tester.ensureVisible(applyButton);
    await tester.pumpAndSettle();
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(harness.controller.state.palette.accent, const Color(0xFF4C7DFF));
    expect(values[themeStudioStorageKey], contains('4283203071'));
    expect(find.text('Theme applied.'), findsOneWidget);
  });

  testWidgets('contrast guard disables Apply for unreadable colors', (
    tester,
  ) async {
    final harness = await _pumpStudio(tester);
    addTearDown(harness.dispose);

    final primaryTextTile = find.byKey(
      const ValueKey('theme-color-primaryText'),
    );
    await tester.ensureVisible(primaryTextTile);
    await tester.pumpAndSettle();
    await tester.tap(primaryTextTile);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('theme-editor-hex')),
      '#030303',
    );
    await tester.tap(find.byKey(const ValueKey('theme-editor-use-color')));
    await tester.pumpAndSettle();

    final apply = tester.widget<FilledButton>(
      find.byKey(const ValueKey('theme-studio-apply')),
    );
    expect(apply.onPressed, isNull);
    expect(find.textContaining('Primary text needs'), findsWidgets);

    final contrastGuard = find.byKey(const ValueKey('theme-contrast-guard'));
    await tester.ensureVisible(contrastGuard);
    await tester.pumpAndSettle();
    await tester.tap(contrastGuard);
    await tester.pumpAndSettle();
    final unguardedApply = tester.widget<FilledButton>(
      find.byKey(const ValueKey('theme-studio-apply')),
    );
    expect(unguardedApply.onPressed, isNotNull);
  });

  testWidgets('reset immediately restores and persists the exact defaults', (
    tester,
  ) async {
    final values = <String, String>{};
    final harness = await _pumpStudio(tester, values: values);
    addTearDown(harness.dispose);
    await harness.controller.apply(
      palette: AppThemePalette.defaults.copyWith(
        accent: const Color(0xFF4C7DFF),
      ),
      contrastGuardEnabled: false,
    );
    await tester.pumpAndSettle();

    final resetButton = find.byKey(const ValueKey('theme-studio-reset'));
    await tester.ensureVisible(resetButton);
    await tester.pumpAndSettle();
    await tester.tap(resetButton);
    await tester.pumpAndSettle();

    expect(harness.controller.state.palette, AppThemePalette.defaults);
    expect(harness.controller.state.contrastGuardEnabled, isTrue);
    expect(values, isEmpty);
    expect(find.text('TetoTV colors restored.'), findsOneWidget);
  });
}

Future<_StudioHarness> _pumpStudio(
  WidgetTester tester, {
  Map<String, String>? values,
}) async {
  final storage = values ?? <String, String>{};
  final controller = ThemeStudioController(
    const FlutterSecureStorage(),
    readValue: (key) async => storage[key],
    writeValue: (key, value) async => storage[key] = value,
    deleteValue: (key) async => storage.remove(key),
  );
  await controller.load();
  final router = GoRouter(
    initialLocation: ThemeStudioScreen.routePath,
    routes: [
      GoRoute(
        path: ThemeStudioScreen.routePath,
        builder: (context, state) => const ThemeStudioScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        themeStudioControllerProvider.overrideWith((_) => controller),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final theme = ref.watch(themeStudioControllerProvider).palette;
          return MaterialApp.router(
            theme: AppTheme.darkFor(theme),
            routerConfig: router,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _StudioHarness(controller, router);
}

class _StudioHarness {
  const _StudioHarness(this.controller, this.router);

  final ThemeStudioController controller;
  final GoRouter router;

  void dispose() {
    router.dispose();
  }
}
