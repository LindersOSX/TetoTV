import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:anime_tv/features/settings/application/theme_studio_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const themeStudioRoutePath = '/settings/theme-studio';

class ThemeStudioScreen extends ConsumerStatefulWidget {
  const ThemeStudioScreen({super.key});

  static const routePath = themeStudioRoutePath;

  @override
  ConsumerState<ThemeStudioScreen> createState() => _ThemeStudioScreenState();
}

class _ThemeStudioScreenState extends ConsumerState<ThemeStudioScreen> {
  late AppThemePalette _draft;
  late bool _contrastGuardEnabled;
  bool _dirty = false;
  bool _restoredSavedTheme = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(themeStudioControllerProvider);
    _draft = saved.palette;
    _contrastGuardEnabled = saved.contrastGuardEnabled;
    _restoredSavedTheme = saved.loaded;
  }

  void _adoptSavedTheme(ThemeStudioState next) {
    if (_dirty || _restoredSavedTheme || !next.loaded) return;
    _restoredSavedTheme = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dirty) return;
      setState(() {
        _draft = next.palette;
        _contrastGuardEnabled = next.contrastGuardEnabled;
      });
    });
  }

  Future<void> _editColor(AppThemeColorRole role) async {
    final initial = _draft.colorFor(role);
    final selected = await showDialog<Color>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ColorEditorDialog(
        role: role,
        initialColor: initial,
        previewPalette: _draft,
      ),
    );
    if (selected == null || !mounted || selected == initial) return;
    setState(() {
      _draft = _draft.withRole(role, selected);
      _dirty = true;
    });
  }

  Future<void> _apply() async {
    if (_saving) return;
    final report = ThemeContrastReport.forPalette(_draft);
    if (_contrastGuardEnabled && report.hasIssues) {
      _showMessage('Fix the contrast warnings or turn off the safeguard.');
      return;
    }
    setState(() => _saving = true);
    final result = await ref
        .read(themeStudioControllerProvider.notifier)
        .apply(palette: _draft, contrastGuardEnabled: _contrastGuardEnabled);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result == ThemeApplyResult.applied) _dirty = false;
    });
    _showMessage(
      result == ThemeApplyResult.applied
          ? 'Theme applied.'
          : 'The readability safeguard blocked this theme.',
    );
  }

  Future<void> _reset() async {
    await ref.read(themeStudioControllerProvider.notifier).resetDefaults();
    if (!mounted) return;
    setState(() {
      _draft = AppThemePalette.defaults;
      _contrastGuardEnabled = true;
      _dirty = false;
      _restoredSavedTheme = true;
    });
    _showMessage('TetoTV colors restored.');
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(themeStudioControllerProvider);
    _adoptSavedTheme(saved);
    final report = ThemeContrastReport.forPalette(_draft);
    final applyBlocked = _contrastGuardEnabled && report.hasIssues;

    return Theme(
      data: AppTheme.darkFor(_draft),
      child: Builder(
        builder: (context) {
          final palette = context.appPalette;
          return Scaffold(
            key: const ValueKey('theme-studio-screen'),
            backgroundColor: palette.background,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final horizontalPadding = compact ? 18.0 : 36.0;
                  return CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          20,
                          horizontalPadding,
                          40,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1180),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Header(
                                    onBack: () => Navigator.maybePop(context),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Make TetoTV yours',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.displaySmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Change the app canvas, panels, focus color '
                                    'and text. Your saved theme is shared by '
                                    'phone and TV layouts.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                  const SizedBox(height: 26),
                                  if (compact) ...[
                                    _ColorRolesPanel(
                                      palette: _draft,
                                      onEdit: _editColor,
                                    ),
                                    const SizedBox(height: 18),
                                    _ThemePreview(palette: _draft),
                                  ] else
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: _ColorRolesPanel(
                                            palette: _draft,
                                            onEdit: _editColor,
                                          ),
                                        ),
                                        const SizedBox(width: 22),
                                        Expanded(
                                          flex: 4,
                                          child: _ThemePreview(palette: _draft),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 18),
                                  _ContrastGuardCard(
                                    enabled: _contrastGuardEnabled,
                                    report: report,
                                    onChanged: (value) => setState(() {
                                      _contrastGuardEnabled = value;
                                      _dirty = true;
                                    }),
                                  ),
                                  const SizedBox(height: 22),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      FilledButton.icon(
                                        key: const ValueKey(
                                          'theme-studio-apply',
                                        ),
                                        autofocus: true,
                                        onPressed: _saving || applyBlocked
                                            ? null
                                            : _apply,
                                        icon: _saving
                                            ? const SizedBox.square(
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.check_rounded),
                                        label: Text(
                                          _saving ? 'Applying…' : 'Apply theme',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'theme-studio-reset',
                                        ),
                                        onPressed: _reset,
                                        icon: const Icon(Icons.restart_alt),
                                        label: const Text('Reset defaults'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      children: [
        TvFocusable(
          onPressed: onBack,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            key: const ValueKey('theme-studio-back'),
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Theme Studio',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _ColorRolesPanel extends StatelessWidget {
  const _ColorRolesPanel({required this.palette, required this.onEdit});

  final AppThemePalette palette;
  final ValueChanged<AppThemeColorRole> onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primaryText.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('App colors', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final role in AppThemeColorRole.values) ...[
            _ColorRoleTile(
              role: role,
              color: palette.colorFor(role),
              onPressed: () => onEdit(role),
            ),
            if (role != AppThemeColorRole.values.last)
              const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _ColorRoleTile extends StatelessWidget {
  const _ColorRoleTile({
    required this.role,
    required this.color,
    required this.onPressed,
  });

  final AppThemeColorRole role;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return TvFocusable(
      onPressed: onPressed,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        key: ValueKey('theme-color-${role.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: contrastForeground(color).withValues(alpha: .32),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.displayName,
                    style: TextStyle(
                      color: palette.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    role.description,
                    style: TextStyle(color: palette.mutedText, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatOpaqueHexColor(color),
              style: TextStyle(
                color: palette.mutedText,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: palette.accentBright),
          ],
        ),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.palette});

  final AppThemePalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Live theme preview',
      child: Container(
        key: const ValueKey('theme-live-preview'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.focusRing, width: 2),
          boxShadow: [
            BoxShadow(
              color: palette.focusGlow,
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: contrastForeground(palette.accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Featured show',
                        style: TextStyle(
                          color: palette.primaryText,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Continue watching · Episode 7',
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 152,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 88,
                    decoration: BoxDecoration(
                      color: palette.surfaceRaised,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(14),
                      ),
                    ),
                    child: Icon(
                      Icons.movie_outlined,
                      size: 34,
                      color: palette.mutedText,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Your library',
                            style: TextStyle(
                              color: palette.primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Panels, labels and focus states update here.',
                            style: TextStyle(
                              color: palette.mutedText,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: palette.surfaceRaised,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: .62,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.accentBright,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      'Play',
                      style: TextStyle(
                        color: contrastForeground(palette.accent),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.selectableSurface,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: palette.focusRing, width: 2),
                    ),
                    child: Text(
                      'Focused',
                      style: TextStyle(
                        color: palette.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContrastGuardCard extends StatelessWidget {
  const _ContrastGuardCard({
    required this.enabled,
    required this.report,
    required this.onChanged,
  });

  final bool enabled;
  final ThemeContrastReport report;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final warning = report.hasIssues;
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: warning && enabled
              ? const Color(0xFFFFB74D)
              : palette.primaryText.withValues(alpha: .08),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('theme-contrast-guard'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Protect readable contrast',
                style: TextStyle(
                  color: palette.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                'Prevents a theme from hiding text or TV focus rings.',
                style: TextStyle(color: palette.mutedText),
              ),
              value: enabled,
              onChanged: onChanged,
            ),
            if (warning) ...[
              const SizedBox(height: 4),
              for (final issue in report.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Color(0xFFFFB74D),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          issue,
                          style: TextStyle(
                            color: palette.primaryText,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!enabled)
                Text(
                  'Low-contrast theme allowed because the safeguard is off.',
                  style: TextStyle(color: palette.mutedText, fontSize: 12),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorEditorDialog extends StatefulWidget {
  const _ColorEditorDialog({
    required this.role,
    required this.initialColor,
    required this.previewPalette,
  });

  final AppThemeColorRole role;
  final Color initialColor;
  final AppThemePalette previewPalette;

  @override
  State<_ColorEditorDialog> createState() => _ColorEditorDialogState();
}

class _ColorEditorDialogState extends State<_ColorEditorDialog> {
  late Color _color;
  late final TextEditingController _hexController;
  late final FocusNode _hexFocusNode;
  String? _hexError;

  @override
  void initState() {
    super.initState();
    _color = widget.initialColor;
    _hexController = TextEditingController(text: formatOpaqueHexColor(_color));
    _hexFocusNode = FocusNode(debugLabel: 'theme-studio.hex');
  }

  @override
  void dispose() {
    _hexController.dispose();
    _hexFocusNode.dispose();
    super.dispose();
  }

  void _setChannel(AppThemeColorChannel channel, double value) {
    final byte = value.round().clamp(0, 255);
    final current = _color.toARGB32();
    final next = switch (channel) {
      AppThemeColorChannel.red => (current & 0xFF00FFFF) | (byte << 16),
      AppThemeColorChannel.green => (current & 0xFFFF00FF) | (byte << 8),
      AppThemeColorChannel.blue => (current & 0xFFFFFF00) | byte,
    };
    setState(() {
      _color = Color(next);
      _hexController.text = formatOpaqueHexColor(_color);
      _hexError = null;
    });
  }

  void _applyHex(String value) {
    final parsed = parseOpaqueHexColor(value);
    setState(() {
      if (parsed == null) {
        _hexError = 'Use a 6-digit color such as #E52B50.';
      } else {
        _color = parsed;
        _hexController.text = formatOpaqueHexColor(parsed);
        _hexError = null;
      }
    });
  }

  KeyEventResult _handleDialogKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.previewPalette.withRole(widget.role, _color);
    return Theme(
      data: AppTheme.darkFor(preview),
      child: Builder(
        builder: (context) {
          final palette = context.appPalette;
          return Focus(
            canRequestFocus: false,
            onKeyEvent: _handleDialogKey,
            child: Dialog(
              backgroundColor: palette.surface,
              insetPadding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.role.displayName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Adjust RGB with a remote, controller, mouse, or enter '
                        'an exact hex color.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            key: const ValueKey('theme-editor-swatch'),
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: _color,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: contrastForeground(
                                  _color,
                                ).withValues(alpha: .36),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('theme-editor-hex'),
                              controller: _hexController,
                              focusNode: _hexFocusNode,
                              autofocus: true,
                              maxLength: 7,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[#0-9a-fA-F]'),
                                ),
                              ],
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                labelText: 'Hex color',
                                counterText: '',
                                errorText: _hexError,
                              ),
                              onSubmitted: _applyHex,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _ColorChannelSlider(
                        label: 'Red',
                        color: const Color(0xFFFF5A67),
                        value: (_color.toARGB32() >> 16) & 0xFF,
                        onChanged: (value) =>
                            _setChannel(AppThemeColorChannel.red, value),
                      ),
                      _ColorChannelSlider(
                        label: 'Green',
                        color: const Color(0xFF65D58A),
                        value: (_color.toARGB32() >> 8) & 0xFF,
                        onChanged: (value) =>
                            _setChannel(AppThemeColorChannel.green, value),
                      ),
                      _ColorChannelSlider(
                        label: 'Blue',
                        color: const Color(0xFF6D92FF),
                        value: _color.toARGB32() & 0xFF,
                        onChanged: (value) =>
                            _setChannel(AppThemeColorChannel.blue, value),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            key: const ValueKey('theme-editor-use-color'),
                            onPressed: () {
                              final parsed = parseOpaqueHexColor(
                                _hexController.text,
                              );
                              if (parsed == null) {
                                _applyHex(_hexController.text);
                                return;
                              }
                              Navigator.pop(context, parsed);
                            },
                            child: const Text('Use color'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum AppThemeColorChannel { red, green, blue }

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final int value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(label, style: TextStyle(color: palette.primaryText)),
        ),
        Expanded(
          child: SliderTheme(
            data: Theme.of(
              context,
            ).sliderTheme.copyWith(activeTrackColor: color, thumbColor: color),
            child: Slider(
              key: ValueKey('theme-slider-${label.toLowerCase()}'),
              value: value.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              label: value.toString(),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toString(),
            textAlign: TextAlign.right,
            style: TextStyle(color: palette.mutedText),
          ),
        ),
      ],
    );
  }
}

String formatOpaqueHexColor(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color? parseOpaqueHexColor(String input) {
  final normalized = input.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
  final value = int.tryParse(normalized, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
