import 'dart:async';

import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/settings/application/device_setup_controller.dart';
import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/settings/application/torbox_settings_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/streaming/domain/debrid_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class InitialSetupScreen extends ConsumerStatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  ConsumerState<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends ConsumerState<InitialSetupScreen> {
  static const _stepCount = 6;
  final _pages = PageController();
  int _step = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _setStep(int step) async {
    final next = step.clamp(0, _stepCount - 1);
    setState(() => _step = next);
    await _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    if (next == 2 && ref.read(deviceSetupProvider).report == null) {
      unawaited(ref.read(deviceSetupProvider.notifier).scan());
    }
  }

  Future<void> _finish() async {
    if (ref.read(deviceSetupProvider).report != null) {
      await ref.read(deviceSetupProvider.notifier).markCompleted();
    }
    await ref.read(setupProgressProvider.notifier).complete();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(settingsPreferencesProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        minimum: context.responsiveScreenPadding,
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Image.asset(
                    'assets/branding/tetotv_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Set up TetoTV',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                _SetupButton(
                  label: 'Skip setup',
                  icon: Icons.skip_next_rounded,
                  autofocus: true,
                  onPressed: _finish,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SetupProgress(step: _step, count: _stepCount),
            const SizedBox(height: 12),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  const _WelcomeStep(),
                  _CustomizationStep(preferences: preferences),
                  const _DeviceStep(),
                  const _DebridStep(),
                  const _TrackingStep(),
                  const _FinishedStep(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_step > 0)
                  _SetupButton(
                    label: 'Back',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => _setStep(_step - 1),
                  ),
                const Spacer(),
                _SetupButton(
                  label: _step == _stepCount - 1 ? 'Finish' : 'Continue',
                  icon: _step == _stepCount - 1
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  primary: true,
                  onPressed: _step == _stepCount - 1
                      ? _finish
                      : () => _setStep(_step + 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) => _SetupPage(
    icon: Icons.auto_awesome_rounded,
    title: 'Welcome to TetoTV',
    subtitle:
        'This short walkthrough configures the interface, checks playback compatibility, and connects your services.',
    child: const Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        _FeaturePill(Icons.tv_rounded, 'TV and mobile layouts'),
        _FeaturePill(Icons.high_quality_rounded, 'Device-aware playback'),
        _FeaturePill(Icons.cloud_done_rounded, 'Debrid streaming'),
        _FeaturePill(Icons.sync_rounded, 'Anime tracking'),
      ],
    ),
  );
}

class _CustomizationStep extends ConsumerWidget {
  const _CustomizationStep({required this.preferences});

  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsPreferencesProvider.notifier);
    return _SetupPage(
      icon: Icons.tune_rounded,
      title: 'Make it yours',
      subtitle:
          'Choose a spacious cinematic Home or a denser layout, then keep only the shortcuts you use.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Home layout',
            children: [
              for (final layout in HomeLayout.values)
                _SetupChoice(
                  label: layout.displayName,
                  selected: preferences.homeLayout == layout,
                  onPressed: () => controller.setHomeLayout(layout),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _SetupChoiceRow(
            label: 'Top navigation',
            children: [
              _SetupChoice(
                label: 'My List',
                selected: preferences.showMyList,
                onPressed: () =>
                    controller.setShowMyList(!preferences.showMyList),
              ),
              _SetupChoice(
                label: 'Discover',
                selected: preferences.showDiscover,
                onPressed: () =>
                    controller.setShowDiscover(!preferences.showDiscover),
              ),
              _SetupChoice(
                label: 'Calendar',
                selected: preferences.showCalendar,
                onPressed: () =>
                    controller.setShowCalendar(!preferences.showCalendar),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SetupChoiceRow(
            label: 'Home details',
            children: [
              _SetupChoice(
                label: 'Featured hero',
                selected: preferences.showHero,
                onPressed: () => controller.setShowHero(!preferences.showHero),
              ),
              _SetupChoice(
                label: 'Poster badges',
                selected: preferences.showPosterMetadata,
                onPressed: () => controller.setShowPosterMetadata(
                  !preferences.showPosterMetadata,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceStep extends ConsumerWidget {
  const _DeviceStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(deviceSetupProvider);
    final report = state.report;
    return _SetupPage(
      icon: Icons.memory_rounded,
      title: 'Playback compatibility',
      subtitle:
          'TetoTV checks the device’s hardware decoders, HDR display, audio output, and anime subtitle renderer.',
      child: state.loading
          ? const Padding(
              padding: EdgeInsets.all(26),
              child: CircularProgressIndicator(color: AppColors.accentBright),
            )
          : state.error != null
          ? Column(
              children: [
                Text(state.error!, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                _SetupButton(
                  label: 'Scan again',
                  icon: Icons.refresh_rounded,
                  onPressed: () =>
                      ref.read(deviceSetupProvider.notifier).scan(),
                ),
              ],
            )
          : report == null
          ? _SetupButton(
              label: 'Run scan',
              icon: Icons.play_arrow_rounded,
              primary: true,
              onPressed: () => ref.read(deviceSetupProvider.notifier).scan(),
            )
          : Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final check in report.checks)
                      _CapabilityPill(check: check),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  report.recommendation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
    );
  }
}

class _DebridStep extends ConsumerWidget {
  const _DebridStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(settingsPreferencesProvider);
    final realDebrid = ref.watch(realDebridSettingsControllerProvider);
    final torBox = ref.watch(torBoxSettingsControllerProvider);
    final selectedConnected =
        preferences.debridProvider == DebridService.realDebrid
        ? realDebrid.hasSavedToken
        : torBox.hasSavedToken;
    return _SetupPage(
      icon: Icons.cloud_done_rounded,
      title: 'Choose your debrid service',
      subtitle:
          'TetoTV only sends supported releases through the debrid provider you select.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Provider',
            children: [
              for (final service in DebridService.values)
                _SetupChoice(
                  label: service.displayName,
                  selected: preferences.debridProvider == service,
                  onPressed: () => ref
                      .read(settingsPreferencesProvider.notifier)
                      .setDebridProvider(service),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _SetupButton(
            label: selectedConnected
                ? '${preferences.debridProvider.displayName} connected'
                : 'Connect ${preferences.debridProvider.displayName}',
            icon: selectedConnected
                ? Icons.check_rounded
                : Icons.qr_code_rounded,
            primary: !selectedConnected,
            onPressed: () => context.push(
              preferences.debridProvider == DebridService.realDebrid
                  ? '/pair/realdebrid'
                  : '/pair/torbox',
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackingStep extends ConsumerWidget {
  const _TrackingStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(settingsPreferencesProvider);
    final accounts = ref.watch(trackingAccountsControllerProvider);
    final connected = accounts.isConnected(preferences.trackingProvider);
    return _SetupPage(
      icon: Icons.sync_alt_rounded,
      title: 'Connect an anime list',
      subtitle:
          'Choose the service that should populate My List and receive episode progress. You can change it later.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Tracking service',
            children: [
              for (final provider in TrackingProvider.values)
                _SetupChoice(
                  label: provider.displayName,
                  selected: preferences.trackingProvider == provider,
                  onPressed: () => ref
                      .read(settingsPreferencesProvider.notifier)
                      .setTrackingProvider(provider),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _SetupButton(
            label: connected
                ? '${preferences.trackingProvider.displayName} connected'
                : 'Connect ${preferences.trackingProvider.displayName}',
            icon: connected ? Icons.check_rounded : Icons.qr_code_rounded,
            primary: !connected,
            onPressed: () => context.push(
              preferences.trackingProvider == TrackingProvider.anilist
                  ? '/pair/anilist'
                  : '/pair/myanimelist',
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Connecting is optional. TetoTV can still browse and play without an anime-list account.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _FinishedStep extends StatelessWidget {
  const _FinishedStep();

  @override
  Widget build(BuildContext context) => const _SetupPage(
    icon: Icons.check_circle_rounded,
    title: 'TetoTV is ready',
    subtitle:
        'Your choices are saved on this device. Everything in this walkthrough remains available under Settings → System.',
    child: _FeaturePill(Icons.play_arrow_rounded, 'Start watching'),
  );
}

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(context.isCompactWidth ? 18 : 28),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.accentBright, size: 48),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

class _SetupProgress extends StatelessWidget {
  const _SetupProgress({required this.step, required this.count});

  final int step;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < count; index++) ...[
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 4,
            decoration: BoxDecoration(
              color: index <= step ? AppColors.accentBright : Colors.white12,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        if (index != count - 1) const SizedBox(width: 5),
      ],
    ],
  );
}

class _SetupChoiceRow extends StatelessWidget {
  const _SetupChoiceRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: children,
      ),
    ],
  );
}

class _SetupChoice extends StatelessWidget {
  const _SetupChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TvFocusable(
    onPressed: onPressed,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : AppColors.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AppColors.accentBright : Colors.white12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(selected ? Icons.check_rounded : Icons.add_rounded, size: 17),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    ),
  );
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.panelRaised,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.cyan),
        const SizedBox(width: 7),
        Text(label),
      ],
    ),
  );
}

class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill({required this.check});

  final CapabilityCheck check;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: check.supported ? const Color(0xFF143526) : AppColors.panelRaised,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          check.supported ? Icons.check_rounded : Icons.info_outline_rounded,
          size: 16,
        ),
        const SizedBox(width: 5),
        Text(
          check.label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _SetupButton extends StatelessWidget {
  const _SetupButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvFocusable(
    autofocus: autofocus,
    onPressed: onPressed,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: primary ? AppColors.accent : AppColors.panelRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    ),
  );
}
