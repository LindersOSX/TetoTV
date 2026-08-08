import 'dart:async';

import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/auth/data/real_debrid_oauth_client.dart';
import 'package:anime_tv/features/settings/application/real_debrid_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

class RealDebridPairingScreen extends ConsumerStatefulWidget {
  const RealDebridPairingScreen({super.key});

  @override
  ConsumerState<RealDebridPairingScreen> createState() =>
      _RealDebridPairingScreenState();
}

class _RealDebridPairingScreenState
    extends ConsumerState<RealDebridPairingScreen> {
  final _client = RealDebridOAuthClient();
  RealDebridDeviceSession? _session;
  Timer? _pollTimer;
  String? _error;
  bool _authorized = false;
  bool _polling = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!mounted) return;
    final generation = ++_generation;
    _pollTimer?.cancel();
    setState(() {
      _session = null;
      _error = null;
      _authorized = false;
    });
    try {
      final session = await _client.startDeviceAuthorization();
      if (!mounted || generation != _generation) return;
      setState(() => _session = session);
      _pollTimer = Timer.periodic(session.interval, (_) => _poll(generation));
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _poll(int generation) async {
    if (!mounted || generation != _generation) return;
    final session = _session;
    if (_polling || session == null || _authorized) return;
    if (DateTime.now().isAfter(session.expiresAt)) {
      _pollTimer?.cancel();
      setState(() => _error = 'The authorization code expired.');
      return;
    }
    _polling = true;
    try {
      final credentials = await _client.pollCredentials(session);
      if (credentials == null) return;
      if (!mounted || generation != _generation) return;
      final tokens = await _client.exchangeDeviceCode(
        session: session,
        credentials: credentials,
      );
      if (!mounted || generation != _generation) return;
      final settingsController = ref.read(
        realDebridSettingsControllerProvider.notifier,
      );
      final valid = await settingsController.saveAndValidate(
        tokens.accessToken,
      );
      if (!mounted || generation != _generation) return;
      if (!valid) {
        final message = ref
            .read(realDebridSettingsControllerProvider)
            .errorMessage;
        throw StateError(message ?? 'Real-Debrid account validation failed.');
      }

      // Validation persists the access token. Add device-flow metadata only
      // after Premium access is confirmed so unusable credentials are never
      // treated as a connected streaming account.
      final storage = ref.read(secureStorageProvider);
      await Future.wait([
        storage.write(
          key: realDebridTokenStorageKey,
          value: tokens.accessToken,
        ),
        storage.write(
          key: realDebridRefreshTokenStorageKey,
          value: tokens.refreshToken,
        ),
        storage.write(
          key: realDebridClientIdStorageKey,
          value: credentials.clientId,
        ),
        storage.write(
          key: realDebridClientSecretStorageKey,
          value: credentials.clientSecret,
        ),
        storage.write(
          key: realDebridAccessExpiryStorageKey,
          value: tokens.expiresAt.toUtc().toIso8601String(),
        ),
      ]);
      if (!mounted || generation != _generation) return;
      _pollTimer?.cancel();
      setState(() => _authorized = true);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _pollTimer?.cancel();
      setState(() => _error = error.toString());
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 42, vertical: 28),
        child: Column(
          children: [
            Row(
              children: [
                _BackButton(onPressed: context.pop),
                const SizedBox(width: 18),
                Text(
                  'Connect Real-Debrid',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                const Text(
                  'Your Real-Debrid password never touches this TV',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Expanded(child: Center(child: _content(context))),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (_authorized) {
      return _MessagePanel(
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF67D49B),
        title: 'Real-Debrid connected',
        body: 'Premium status and streaming access are ready.',
        actionLabel: 'Done',
        onAction: context.pop,
      );
    }
    if (_error case final error?) {
      return _MessagePanel(
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFFF929B),
        title: 'Could not connect',
        body: error,
        actionLabel: 'Try again',
        onAction: _start,
      );
    }
    final session = _session;
    if (session == null) {
      return const CircularProgressIndicator(color: AppColors.cyan);
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 880),
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Container(
            width: 220,
            height: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: session.verificationUrl.toString(),
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.Q,
              padding: EdgeInsets.zero,
              eyeStyle: const QrEyeStyle(color: AppColors.ink),
              dataModuleStyle: const QrDataModuleStyle(color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 38),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _WaitingPill(),
                const SizedBox(height: 18),
                Text(
                  'Scan with your phone',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Open ${session.verificationUrl} and enter:',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 18),
                Text(
                  session.userCode,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'This screen updates automatically after approval.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingPill extends StatelessWidget {
  const _WaitingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync_rounded, size: 15, color: AppColors.cyan),
          SizedBox(width: 7),
          Text(
            'WAITING FOR APPROVAL',
            style: TextStyle(
              color: AppColors.cyan,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 72, color: color),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 10),
        Text(body, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        _ActionButton(label: actionLabel, onPressed: onAction),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: true,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: const ColoredBox(
        color: AppColors.panel,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back_rounded, size: 20),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: true,
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: AppColors.accent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
