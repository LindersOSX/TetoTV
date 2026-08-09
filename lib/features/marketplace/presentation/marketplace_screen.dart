import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/core/widgets/tv_text_input.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class MarketplaceScreen extends ConsumerWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(marketplaceControllerProvider);
    final controller = ref.read(marketplaceControllerProvider.notifier);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        minimum: context.responsiveScreenPadding,
        child: Column(
          children: [
            Row(
              children: [
                _MarketplaceButton(
                  icon: Icons.arrow_back_rounded,
                  label: context.isCompactWidth ? null : 'Settings',
                  autofocus: true,
                  onPressed: context.pop,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Streaming Marketplace',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (!context.isCompactWidth)
                        Text(
                          'Install isolated web-stream providers from repositories you trust.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                _MarketplaceButton(
                  icon: Icons.refresh_rounded,
                  label: context.isCompactWidth ? null : 'Refresh',
                  onPressed: state.loading ? null : () => controller.refresh(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: state.loading && state.repositories.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentBright,
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        _section(
                          context,
                          icon: Icons.hub_outlined,
                          title: 'Repositories',
                          subtitle:
                              'Catalogs are cached locally. Disabling one keeps installed addons.',
                        ),
                        SliverList.builder(
                          itemCount: state.repositories.length,
                          itemBuilder: (context, index) {
                            final repository = state.repositories[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _RepositoryTile(
                                repository: repository,
                                error: state.repositoryErrors[repository.url],
                                onToggle: () => controller.setRepositoryEnabled(
                                  repository,
                                  !repository.enabled,
                                ),
                                onRemove: () => _confirmRepositoryRemoval(
                                  context,
                                  repository,
                                  controller,
                                ),
                              ),
                            );
                          },
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 24),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _MarketplaceButton(
                                  icon: Icons.add_link_rounded,
                                  label: 'Add repository',
                                  onPressed: () =>
                                      _addRepository(context, controller),
                                ),
                                _MarketplaceButton(
                                  icon: Icons.restore_rounded,
                                  label: 'Restore default',
                                  onPressed:
                                      controller.restoreDefaultRepository,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (state.installed.isNotEmpty) ...[
                          _section(
                            context,
                            icon: Icons.extension_rounded,
                            title: 'Installed providers',
                            subtitle:
                                'Enabled providers participate in Web Stream searches.',
                          ),
                          SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 540,
                                  mainAxisExtent: 260,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final addon = state.installed[index];
                              return _InstalledAddonCard(
                                addon: addon,
                                health: state.providerHealth[addon.manifest.id],
                                message:
                                    state.providerMessages[addon.manifest.id],
                                busy: state.busyAddonId == addon.manifest.id,
                                onToggle: () => controller.setAddonEnabled(
                                  addon.manifest.id,
                                  !addon.enabled,
                                ),
                                onUninstall: () => _confirmUninstall(
                                  context,
                                  addon,
                                  controller,
                                ),
                                onTest: () => controller.testAddon(addon),
                                onReset: () => controller.resetAddonHealth(
                                  addon.manifest.id,
                                ),
                              );
                            }, childCount: state.installed.length),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 28)),
                        ],
                        _section(
                          context,
                          icon: Icons.storefront_outlined,
                          title: 'Available web providers',
                          subtitle:
                              '${state.catalog.where((item) => item.isCompatible).length} compatible JavaScript and TypeScript providers. '
                              'TypeScript is compiled once during installation.',
                        ),
                        if (state.catalog.isEmpty)
                          SliverToBoxAdapter(
                            child: _EmptyCatalog(
                              errors: state.repositoryErrors,
                            ),
                          )
                        else
                          SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 540,
                                  mainAxisExtent: 250,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final addon = state.catalog[index];
                              final installed = state.installedById(addon.id);
                              final busy = state.busyAddonId == addon.id;
                              return _CatalogAddonCard(
                                addon: addon,
                                installed: installed,
                                updateAvailable: state.updateAvailable(addon),
                                busy: busy,
                                onInstall: addon.isCompatible && !busy
                                    ? () => _confirmInstall(
                                        context,
                                        addon,
                                        controller,
                                      )
                                    : null,
                              );
                            }, childCount: state.catalog.length),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 28)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

SliverToBoxAdapter _section(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
}) => SliverToBoxAdapter(
  child: Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.accentBright),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  ),
);

class _RepositoryTile extends StatelessWidget {
  const _RepositoryTile({
    required this.repository,
    required this.error,
    required this.onToggle,
    required this.onRemove,
  });

  final AddonRepository repository;
  final String? error;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Icon(
            repository.enabled ? Icons.link_rounded : Icons.link_off_rounded,
            color: repository.enabled ? AppColors.cyan : Colors.white38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repository.isDefault
                      ? 'Default repository'
                      : 'Custom repository',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  repository.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (error != null)
                  Text(
                    error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFF929B),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          _MarketplaceButton(
            icon: repository.enabled
                ? Icons.toggle_on_rounded
                : Icons.toggle_off_rounded,
            label: context.isCompactWidth
                ? null
                : repository.enabled
                ? 'Enabled'
                : 'Disabled',
            onPressed: onToggle,
          ),
          const SizedBox(width: 8),
          _MarketplaceButton(
            icon: Icons.delete_outline_rounded,
            label: context.isCompactWidth ? null : 'Remove',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _InstalledAddonCard extends StatelessWidget {
  const _InstalledAddonCard({
    required this.addon,
    required this.health,
    required this.message,
    required this.busy,
    required this.onToggle,
    required this.onUninstall,
    required this.onTest,
    required this.onReset,
  });

  final InstalledStreamingAddon addon;
  final ProviderHealth? health;
  final String? message;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onUninstall;
  final VoidCallback onTest;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => _AddonShell(
    addon: addon.manifest,
    badge: !addon.enabled
        ? 'DISABLED'
        : health?.isQuarantined == true
        ? 'PAUSED AFTER FAILURES'
        : health?.lastSuccessAt != null
        ? 'HEALTHY'
        : 'NOT TESTED',
    footer: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (message != null || health?.lastError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Text(
              message ??
                  '${health!.consecutiveFailures} failure(s): ${health!.lastError}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MarketplaceButton(
              icon: busy
                  ? Icons.hourglass_top_rounded
                  : Icons.health_and_safety,
              label: busy ? 'Testing…' : 'Test',
              onPressed: busy || !addon.enabled ? null : onTest,
            ),
            _MarketplaceButton(
              icon: addon.enabled
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              label: addon.enabled ? 'Disable' : 'Enable',
              onPressed: onToggle,
            ),
            if (health != null)
              _MarketplaceButton(
                icon: Icons.restart_alt_rounded,
                label: 'Reset',
                onPressed: onReset,
              ),
            _MarketplaceButton(
              icon: Icons.delete_outline_rounded,
              label: 'Uninstall',
              onPressed: onUninstall,
            ),
          ],
        ),
      ],
    ),
  );
}

class _CatalogAddonCard extends StatelessWidget {
  const _CatalogAddonCard({
    required this.addon,
    required this.installed,
    required this.updateAvailable,
    required this.busy,
    required this.onInstall,
  });

  final MarketplaceAddon addon;
  final InstalledStreamingAddon? installed;
  final bool updateAvailable;
  final bool busy;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final unsupported = !addon.isCompatible;
    return _AddonShell(
      addon: addon,
      badge: unsupported
          ? '${addon.language.toUpperCase()} / UNSUPPORTED'
          : installed == null
          ? addon.isTypescript
                ? 'TYPESCRIPT'
                : 'AVAILABLE'
          : updateAvailable
          ? 'UPDATE AVAILABLE'
          : 'INSTALLED',
      footer: _MarketplaceButton(
        icon: busy
            ? Icons.hourglass_top_rounded
            : updateAvailable
            ? Icons.system_update_alt_rounded
            : installed == null
            ? Icons.download_rounded
            : Icons.check_rounded,
        label: busy
            ? 'Installing…'
            : updateAvailable
            ? 'Update'
            : installed == null
            ? unsupported
                  ? 'Incompatible runtime'
                  : 'Install'
            : 'Installed',
        onPressed: installed != null && !updateAvailable ? null : onInstall,
      ),
    );
  }
}

class _AddonShell extends StatelessWidget {
  const _AddonShell({
    required this.addon,
    required this.badge,
    required this.footer,
  });

  final MarketplaceAddon addon;
  final String badge;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AddonIcon(uri: addon.iconUri),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      addon.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${addon.author} • ${addon.locale.toUpperCase()}'
                      '${addon.version == null ? '' : ' • v${addon.version}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      addon.manifestUri.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              addon.description.isEmpty
                  ? 'No description provided.'
                  : addon.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Align(alignment: Alignment.centerRight, child: footer),
        ],
      ),
    );
  }
}

class _AddonIcon extends StatelessWidget {
  const _AddonIcon({required this.uri});

  final Uri? uri;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 50,
    height: 50,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        uri == null ? Icons.extension_rounded : Icons.language_rounded,
      ),
    ),
  );
}

class _MarketplaceButton extends StatelessWidget {
  const _MarketplaceButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return ExcludeFocus(
      excluding: disabled,
      child: IgnorePointer(
        ignoring: disabled,
        child: Opacity(
          opacity: disabled ? .42 : 1,
          child: TvFocusable(
            autofocus: autofocus,
            onPressed: onPressed ?? () {},
            borderRadius: BorderRadius.circular(12),
            focusScale: 1.025,
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              color: AppColors.panelRaised,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20),
                  if (label != null) ...[
                    const SizedBox(width: 7),
                    Text(
                      label!,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.errors});

  final Map<String, String> errors;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Center(
      child: Text(
        errors.isEmpty
            ? 'No compatible providers were found.'
            : 'Repositories could not be loaded. Select Refresh to retry.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}

Future<void> _addRepository(
  BuildContext context,
  MarketplaceController controller,
) async {
  final input = TextEditingController();
  try {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Add repository'),
        content: SizedBox(
          width: 680,
          child: TvTextInput(
            controller: input,
            autofocus: true,
            labelText: 'HTTPS catalog URL',
            hintText: 'https://example.com/marketplace.json',
            keyboardTitle: 'Repository URL',
            onSubmitted: (_) => Navigator.pop(context, true),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    final error = await controller.addRepository(input.text.trim());
    if (error != null && context.mounted) _notice(context, error);
  } finally {
    input.dispose();
  }
}

Future<void> _confirmInstall(
  BuildContext context,
  MarketplaceAddon addon,
  MarketplaceController controller,
) async {
  final accepted = await _confirm(
    context,
    title: 'Install ${addon.name}?',
    body:
        'This third-party provider may access public HTTPS websites. It cannot access TetoTV tokens, device files, or native Android APIs. Only install repositories you trust.',
    action: 'INSTALL',
  );
  if (!accepted) return;
  try {
    await controller.install(addon);
  } catch (error) {
    if (context.mounted) _notice(context, error.toString());
  }
}

Future<void> _confirmUninstall(
  BuildContext context,
  InstalledStreamingAddon addon,
  MarketplaceController controller,
) async {
  if (await _confirm(
    context,
    title: 'Uninstall ${addon.manifest.name}?',
    body:
        'Its web streams will no longer appear. Playback history and tracking are not changed.',
    action: 'UNINSTALL',
  )) {
    await controller.uninstall(addon.manifest.id);
  }
}

Future<void> _confirmRepositoryRemoval(
  BuildContext context,
  AddonRepository repository,
  MarketplaceController controller,
) async {
  if (await _confirm(
    context,
    title: 'Remove repository?',
    body:
        'Already installed providers remain installed. You can restore the default repository later.',
    action: 'REMOVE',
  )) {
    await controller.removeRepository(repository);
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(title),
        content: SizedBox(width: 620, child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void _notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: const Color(0xFF3A1119)),
  );
}
