import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A text input that never invokes Android's full-screen/overlay IME.
///
/// Selecting the field opens a TV-sized keyboard that supports D-pad, gamepad,
/// mouse, clipboard paste, and a connected physical keyboard.
class TvTextInput extends StatelessWidget {
  const TvTextInput({
    required this.controller,
    required this.labelText,
    this.hintText,
    this.keyboardTitle,
    this.focusNode,
    this.autofocus = false,
    this.obscureText = false,
    this.autofillSuggestions = const [],
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final String? keyboardTitle;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool obscureText;
  final List<String> autofillSuggestions;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  Future<void> _openKeyboard(BuildContext context) async {
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .32),
      builder: (_) => TvKeyboardDialog(
        title: keyboardTitle ?? labelText,
        initialValue: controller.text,
        obscureText: obscureText,
        autofillSuggestions: autofillSuggestions,
      ),
    );
    if (value == null || !context.mounted) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    onChanged?.call(value);
    onSubmitted?.call(value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusNode?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = controller.text;
    final visibleValue = obscureText && value.isNotEmpty
        ? List.filled(value.length.clamp(1, 48), '•').join()
        : value;
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      focusScale: 1.015,
      borderRadius: BorderRadius.circular(8),
      onPressed: () => _openKeyboard(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.fromLTRB(13, 7, 10, 7),
        decoration: BoxDecoration(
          color: AppColors.ink.withValues(alpha: .65),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labelText,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    visibleValue.isEmpty ? (hintText ?? '') : visibleValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: visibleValue.isEmpty
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.keyboard_rounded, color: AppColors.cyan, size: 22),
          ],
        ),
      ),
    );
  }
}

class TvKeyboardDialog extends StatefulWidget {
  const TvKeyboardDialog({
    required this.title,
    required this.initialValue,
    this.obscureText = false,
    this.autofillSuggestions = const [],
    super.key,
  });

  final String title;
  final String initialValue;
  final bool obscureText;
  final List<String> autofillSuggestions;

  @override
  State<TvKeyboardDialog> createState() => _TvKeyboardDialogState();
}

class _TvKeyboardDialogState extends State<TvKeyboardDialog> {
  static const _rows = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
    ['-', '_', '.', ':', '/', '?', '=', '&', '%', '+', '@'],
  ];

  late String _value;
  bool _shift = false;
  late bool _reveal;
  String? _clipboardValue;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _reveal = !widget.obscureText;
    _loadClipboardAutofill();
  }

  Future<void> _loadClipboardAutofill() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text?.replaceAll(RegExp(r'[\r\n]+'), '').trim();
    if (!mounted || value == null || value.isEmpty || value.length > 8192) {
      return;
    }
    setState(() => _clipboardValue = value);
  }

  void _append(String value) {
    setState(() {
      _value += _shift ? value.toUpperCase() : value;
      if (_shift) _shift = false;
    });
  }

  void _backspace() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text;
    if (value == null || value.isEmpty || !mounted) return;
    setState(() => _value += value.replaceAll(RegExp(r'[\r\n]+'), ''));
  }

  void _autofill(String value) {
    setState(() => _value = value);
  }

  KeyEventResult _handlePhysicalKeyboard(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null &&
        character.length == 1 &&
        character.codeUnitAt(0) >= 32) {
      setState(() => _value += character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = !_reveal && _value.isNotEmpty
        ? List.filled(_value.length, '•').join()
        : _value;
    return Dialog(
      alignment: Alignment.bottomCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 90, 24, 12),
      backgroundColor: Colors.transparent,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handlePhysicalKeyboard,
        child: Container(
          width: 710,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF080808),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.accent.withValues(alpha: .46)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Text(
                    'D-pad • controller • keyboard',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Container(
                width: double.infinity,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.accentBright.withValues(alpha: .62),
                  ),
                ),
                child: Text(
                  displayValue.isEmpty ? 'Start typing…' : displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: displayValue.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                    fontSize: 15,
                    letterSpacing: widget.obscureText ? 1.4 : 0,
                  ),
                ),
              ),
              if (_clipboardValue != null ||
                  widget.autofillSuggestions.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Text(
                      'AUTOFILL',
                      style: TextStyle(
                        color: AppColors.accentBright,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_clipboardValue case final clipboard?)
                      _AutofillChip(
                        label: widget.obscureText
                            ? 'Use clipboard securely'
                            : 'Use clipboard',
                        icon: Icons.content_paste_go_rounded,
                        onPressed: () => _autofill(clipboard),
                      ),
                    for (final suggestion in widget.autofillSuggestions.take(
                      3,
                    )) ...[
                      const SizedBox(width: 7),
                      _AutofillChip(
                        label: suggestion,
                        icon: Icons.auto_awesome_rounded,
                        onPressed: () => _autofill(suggestion),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 10),
              FocusTraversalGroup(
                policy: ReadingOrderTraversalPolicy(),
                child: Column(
                  children: [
                    for (var rowIndex = 0; rowIndex < _rows.length; rowIndex++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (
                              var keyIndex = 0;
                              keyIndex < _rows[rowIndex].length;
                              keyIndex++
                            ) ...[
                              SizedBox(
                                width: 42,
                                child: _KeyboardKey(
                                  label: _shift
                                      ? _rows[rowIndex][keyIndex].toUpperCase()
                                      : _rows[rowIndex][keyIndex],
                                  autofocus: rowIndex == 0 && keyIndex == 0,
                                  onPressed: () =>
                                      _append(_rows[rowIndex][keyIndex]),
                                ),
                              ),
                              if (keyIndex != _rows[rowIndex].length - 1)
                                const SizedBox(width: 4),
                            ],
                          ],
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _KeyboardAction(
                          label: _shift ? 'SHIFT ON' : 'SHIFT',
                          icon: Icons.arrow_upward_rounded,
                          selected: _shift,
                          onPressed: () => setState(() => _shift = !_shift),
                        ),
                        const SizedBox(width: 6),
                        _KeyboardAction(
                          label: 'SPACE',
                          icon: Icons.space_bar_rounded,
                          flex: 2,
                          onPressed: () => _append(' '),
                        ),
                        const SizedBox(width: 6),
                        _KeyboardAction(
                          label: 'DELETE',
                          icon: Icons.backspace_outlined,
                          onPressed: _backspace,
                        ),
                        const SizedBox(width: 6),
                        _KeyboardAction(
                          label: 'PASTE',
                          icon: Icons.content_paste_rounded,
                          onPressed: _paste,
                        ),
                        if (widget.obscureText) ...[
                          const SizedBox(width: 6),
                          _KeyboardAction(
                            label: _reveal ? 'HIDE' : 'SHOW',
                            icon: _reveal
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            onPressed: () => setState(() => _reveal = !_reveal),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _KeyboardAction(
                          label: 'CLEAR',
                          icon: Icons.clear_all_rounded,
                          onPressed: () => setState(() => _value = ''),
                        ),
                        const SizedBox(width: 8),
                        _KeyboardAction(
                          label: 'CANCEL',
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                        _KeyboardAction(
                          label: 'DONE',
                          icon: Icons.check_rounded,
                          primary: true,
                          onPressed: () => Navigator.of(context).pop(_value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyboardKey extends StatelessWidget {
  const _KeyboardKey({
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusScale: 1.04,
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Container(
        height: 31,
        alignment: Alignment.center,
        color: const Color(0xFF191919),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _KeyboardAction extends StatelessWidget {
  const _KeyboardAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.flex = 1,
    this.primary = false,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final int flex;
  final bool primary;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: flex,
      child: TvFocusable(
        focusScale: 1.025,
        borderRadius: BorderRadius.circular(8),
        onPressed: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 72),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: primary
              ? AppColors.accent
              : selected
              ? AppColors.accent.withValues(alpha: .45)
              : const Color(0xFF202020),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutofillChip extends StatelessWidget {
  const _AutofillChip({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: TvFocusable(
        onPressed: onPressed,
        focusScale: 1.02,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: const Color(0xFF181818),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.accentBright),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
