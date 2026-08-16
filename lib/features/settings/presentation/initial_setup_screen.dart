import 'dart:async';

import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/preferences/playback_audio_preference.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/auth/domain/tracking_provider.dart';
import 'package:anime_tv/features/discord/application/discord_account_link_resolver.dart';
import 'package:anime_tv/features/discord/application/discord_presence_controller.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/presentation/source_pairing_dialog.dart';
import 'package:anime_tv/features/settings/application/all_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/device_setup_controller.dart';
import 'package:anime_tv/features/settings/application/premiumize_settings_controller.dart';
import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/setup_progress_controller.dart';
import 'package:anime_tv/features/settings/application/torbox_settings_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/streaming/application/user_torrent_sources_controller.dart';
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
  static const _stepCount = 5;
  static const _stepNames = [
    'Playback',
    'Home',
    'Streaming',
    'Accounts',
    'Privacy',
  ];
  final _pages = PageController();
  bool _finishing = false;
  bool _transitioning = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(setupProgressProvider.notifier).start();
      if (ref.read(deviceSetupProvider).report == null) {
        unawaited(ref.read(deviceSetupProvider.notifier).scan());
      }
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _setStep(int step) async {
    final next = step.clamp(0, _stepCount - 1);
    if (_transitioning || next == _step) return;
    _transitioning = true;
    try {
      setState(() => _step = next);
      await _pages.animateToPage(
        next,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _transitioning = false;
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final deviceSetup = ref.read(deviceSetupProvider.notifier);
    final setupProgress = ref.read(setupProgressProvider.notifier);
    try {
      deviceSetup.persistWhenReady();
      await setupProgress.complete();
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } finally {
      _finishing = false;
    }
  }

  Future<void> _handleBack() async {
    if (_transitioning || _finishing) return;
    if (_step > 0) {
      await _setStep(_step - 1);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appPalette.surface,
        title: const Text('Leave setup?'),
        content: const Text(
          'You can finish these choices later from Settings.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep setting up'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set up later'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(settingsPreferencesProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: context.appPalette.background,
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
                    label: 'Set up later',
                    icon: Icons.schedule_rounded,
                    onPressed: _finish,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SetupProgress(
                step: _step,
                count: _stepCount,
                label: _stepNames[_step],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _PlaybackStep(preferences: preferences),
                    _TvExperienceStep(preferences: preferences),
                    const _StreamingStep(),
                    const _AccountsStep(),
                    _PrivacyStep(preferences: preferences),
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
                    autofocus: true,
                    onPressed: _step == _stepCount - 1
                        ? _finish
                        : () => _setStep(_step + 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvExperienceStep extends ConsumerWidget {
  const _TvExperienceStep({required this.preferences});

  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsPreferencesProvider.notifier);
    return _SetupPage(
      icon: Icons.tune_rounded,
      title: 'Make it feel right on your TV',
      subtitle: 'Choose how Home looks and keep your everyday shortcuts close.',
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

class _PlaybackStep extends ConsumerWidget {
  const _PlaybackStep({required this.preferences});

  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsPreferencesProvider.notifier);
    final report = ref.watch(deviceSetupProvider).report;
    final showCompatibilityAdvice =
        report != null &&
        report.profile.sdk > 0 &&
        !report.profile.codecs.any(
          (codec) => codec.hardware && codec.mime == 'video/avc',
        );
    return _SetupPage(
      icon: Icons.play_circle_outline_rounded,
      title: 'Choose your playback defaults',
      subtitle: 'Set how you type, listen, and move through episodes.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Text input',
            children: [
              _SetupChoice(
                label: 'TetoTV keyboard',
                selected: preferences.useBuiltInKeyboard,
                onPressed: () => controller.setUseBuiltInKeyboard(true),
              ),
              _SetupChoice(
                label: 'Device keyboard',
                selected: !preferences.useBuiltInKeyboard,
                onPressed: () => controller.setUseBuiltInKeyboard(false),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SetupChoiceRow(
            label: 'Preferred anime audio',
            children: [
              for (final audio in PlaybackAudioPreference.values)
                _SetupChoice(
                  label: audio.displayName,
                  selected: preferences.preferredAudio == audio,
                  onPressed: () => controller.setPreferredAudio(audio),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _SetupChoiceRow(
            label: 'Automatic skipping',
            children: [
              _SetupChoice(
                label: 'Skip intros',
                selected: preferences.autoSkipIntros,
                onPressed: () =>
                    controller.setAutoSkipIntros(!preferences.autoSkipIntros),
              ),
              _SetupChoice(
                label: 'Skip outros',
                selected: preferences.autoSkipOutros,
                onPressed: () =>
                    controller.setAutoSkipOutros(!preferences.autoSkipOutros),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Automatic skipping only runs when reliable timestamps are available.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          if (showCompatibilityAdvice) ...[
            const SizedBox(height: 16),
            const _SetupNote(
              key: ValueKey('setup-compatibility-warning'),
              icon: Icons.info_outline_rounded,
              text:
                  'For smoother playback on this TV, start with 1080p H.264 releases. TetoTV will use compatibility playback automatically.',
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountsStep extends ConsumerWidget {
  const _AccountsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(settingsPreferencesProvider);
    final accounts = ref.watch(trackingAccountsControllerProvider);
    final trackingConnected = accounts.isConnected(
      preferences.trackingProvider,
    );
    final isTelevision = ref.watch(isTelevisionProvider);
    final discord = ref.watch(discordPresenceControllerProvider);
    final discordController = ref.read(
      discordPresenceControllerProvider.notifier,
    );
    final discordLabel = discord.busy
        ? 'Connecting Discord'
        : !discord.loaded
        ? 'Checking Discord'
        : !discord.available
        ? 'Discord unavailable on this device'
        : discord.linked
        ? discord.enabled
              ? 'Discord linked and enabled'
              : 'Discord linked but disabled'
        : 'Link Discord (optional)';
    return _SetupPage(
      icon: Icons.people_alt_outlined,
      title: 'Connect your accounts',
      subtitle: 'Sync your watchlist and Discord presence, or skip either one.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Anime list',
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
          const SizedBox(height: 10),
          _SetupButton(
            label: trackingConnected
                ? '${preferences.trackingProvider.displayName} connected'
                : 'Connect ${preferences.trackingProvider.displayName}',
            icon: trackingConnected
                ? Icons.check_rounded
                : Icons.qr_code_rounded,
            onPressed: () => context.push(
              preferences.trackingProvider == TrackingProvider.anilist
                  ? '/pair/anilist'
                  : '/pair/myanimelist',
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Discord presence',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (discord.busy || !discord.loaded || !discord.available)
            _FeaturePill(Icons.forum_rounded, discordLabel)
          else
            _SetupButton(
              label: discordLabel,
              icon: discord.linked ? Icons.check_rounded : Icons.forum_rounded,
              primary: !discord.linked,
              onPressed: discord.linked
                  ? () => discordController.setEnabled(!discord.enabled)
                  : () async {
                      final resolver = ref.read(
                        discordAccountLinkResolverProvider,
                      );
                      final flow = await resolver.resolve(
                        startupTelevision: isTelevision,
                      );
                      if (!context.mounted) return;
                      if (flow == DiscordAccountLinkFlow.deviceQr) {
                        await context.push('/pair/discord');
                      } else {
                        await discordController.linkAccount();
                      }
                    },
            ),
          const SizedBox(height: 9),
          Text(
            'Connections are optional. TetoTV never sees or stores your account passwords.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          if (discord.error case final error?) ...[
            const SizedBox(height: 9),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appPalette.accentBright),
            ),
          ],
        ],
      ),
    );
  }
}

class _StreamingStep extends ConsumerWidget {
  const _StreamingStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(settingsPreferencesProvider);
    final realDebrid = ref.watch(realDebridSettingsControllerProvider);
    final torBox = ref.watch(torBoxSettingsControllerProvider);
    final allDebrid = ref.watch(allDebridSettingsControllerProvider);
    final premiumize = ref.watch(premiumizeSettingsControllerProvider);
    final marketplace = ref.watch(marketplaceControllerProvider);
    final torrentSources = ref.watch(userTorrentSourcesControllerProvider);
    final repositoryCount = marketplace.repositories.length;
    final manifestCount = torrentSources.manifestUrls.length;
    final selectedConnected = switch (preferences.debridProvider) {
      DebridService.realDebrid => realDebrid.hasSavedToken,
      DebridService.torBox => torBox.hasSavedToken,
      DebridService.allDebrid => allDebrid.hasSavedToken,
      DebridService.premiumize => premiumize.hasSavedToken,
    };
    return _SetupPage(
      icon: Icons.cloud_done_rounded,
      title: 'Set up streaming',
      subtitle:
          'Choose a debrid provider if you use one. Connecting it now is optional.',
      child: Column(
        children: [
          const Text(
            'Debrid provider',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
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
          const SizedBox(height: 10),
          _SetupButton(
            label: selectedConnected
                ? '${preferences.debridProvider.displayName} connected'
                : 'Connect ${preferences.debridProvider.displayName}',
            icon: selectedConnected
                ? Icons.check_rounded
                : Icons.qr_code_rounded,
            primary: !selectedConnected,
            onPressed: () => context.push(switch (preferences.debridProvider) {
              DebridService.realDebrid => '/pair/realdebrid',
              DebridService.torBox => '/pair/torbox',
              DebridService.allDebrid => '/pair/alldebrid',
              DebridService.premiumize => '/pair/premiumize',
            }),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your sources',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            'Add only repositories and manifests you trust and are authorized to use. TetoTV does not bundle or recommend sources.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _SourceCount(
                icon: Icons.extension_rounded,
                count: repositoryCount,
                label: repositoryCount == 1
                    ? 'Marketplace repository'
                    : 'Marketplace repositories',
              ),
              _SourceCount(
                icon: Icons.cloud_download_outlined,
                count: manifestCount,
                label: manifestCount == 1
                    ? 'Torrent source manifest'
                    : 'Torrent source manifests',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _SetupButton(
                label: 'Add sources with phone',
                icon: Icons.phone_android_rounded,
                primary: true,
                onPressed: () => showSourcePairingDialog(context),
              ),
              _SetupButton(
                label: 'Open Marketplace manually',
                icon: Icons.tune_rounded,
                onPressed: () => context.push('/settings/marketplace'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyStep extends ConsumerWidget {
  const _PrivacyStep({required this.preferences});

  final SettingsPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsPreferencesProvider.notifier);
    return _SetupPage(
      icon: Icons.privacy_tip_outlined,
      title: 'One last choice',
      subtitle:
          'Choose whether anonymous technical errors can be sent to help improve TetoTV.',
      child: Column(
        children: [
          _SetupChoiceRow(
            label: 'Anonymous crash and error reports',
            children: [
              _SetupChoice(
                label: 'Do not send',
                selected: !preferences.anonymousCrashReportingEnabled,
                onPressed: () =>
                    settings.setAnonymousCrashReportingEnabled(false),
              ),
              _SetupChoice(
                label: 'Allow error reports',
                selected: preferences.anonymousCrashReportingEnabled,
                onPressed: () =>
                    settings.setAnonymousCrashReportingEnabled(true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Reports may include the app version, Android version, device class, error type, time, and a redacted trace. They never include what you watch, accounts, device IDs, sources, or URLs.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 10),
          ),
          const SizedBox(height: 18),
          const _SetupNote(
            icon: Icons.check_circle_outline_rounded,
            text:
                'That’s it. Your choices are saved on this TV and remain available in Settings.',
          ),
        ],
      ),
    );
  }
}

class _SourceCount extends StatelessWidget {
  const _SourceCount({
    required this.icon,
    required this.count,
    required this.label,
  });

  final IconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: context.appPalette.surfaceRaised,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: context.appPalette.secondaryAccent),
        const SizedBox(width: 7),
        Text(
          '$count',
          style: TextStyle(
            color: context.appPalette.accentBright,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
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
            color: context.appPalette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Column(
            children: [
              Icon(icon, color: context.appPalette.accentBright, size: 48),
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
                style: TextStyle(color: context.appPalette.mutedText),
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
  const _SetupProgress({
    required this.step,
    required this.count,
    required this.label,
  });

  final int step;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          Text(
            '${step + 1} of $count',
            style: TextStyle(color: context.appPalette.mutedText, fontSize: 11),
          ),
        ],
      ),
      const SizedBox(height: 7),
      Row(
        children: [
          for (var index = 0; index < count; index++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 3,
                decoration: BoxDecoration(
                  color: index <= step
                      ? context.appPalette.accentBright
                      : Colors.white12,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            if (index != count - 1) const SizedBox(width: 5),
          ],
        ],
      ),
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
      padding: EdgeInsets.symmetric(
        horizontal: context.isCompactWidth ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: selected
            ? context.appPalette.accent
            : context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? context.appPalette.accentBright : Colors.white12,
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
      color: context.appPalette.surfaceRaised,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: context.appPalette.secondaryAccent),
        const SizedBox(width: 7),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class _SetupNote extends StatelessWidget {
  const _SetupNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 660),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: context.appPalette.surfaceRaised,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: context.appPalette.secondaryAccent),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
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
        color: primary
            ? context.appPalette.accent
            : context.appPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: primary ? Colors.white : null),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: primary ? Colors.white : null,
                fontSize: context.isCompactWidth ? 12 : null,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
