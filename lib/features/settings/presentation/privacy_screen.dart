import 'package:anime_tv/core/layout/adaptive_layout.dart';
import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:anime_tv/core/tv/tv_focusable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  final _scrollController = ScrollController();
  final _backFocusNode = FocusNode(debugLabel: 'privacy.back');
  late final Future<String> _policy = rootBundle
      .loadString('docs/PRIVACY.md')
      .then(_plainTextPolicy);

  @override
  void dispose() {
    _scrollController.dispose();
    _backFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.pageDown => 1,
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.pageUp => -1,
      _ => 0,
    };
    if (direction == 0 || !_scrollController.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = _scrollController.position;
    final destination = (position.pixels + direction * 240).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      destination.toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        minimum: context.responsiveScreenPadding,
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: _handleKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TvFocusable(
                    autofocus: true,
                    focusNode: _backFocusNode,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: Navigator.of(context).pop,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Back',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Privacy & data',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<String>(
                  future: _policy,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accentBright,
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          'The privacy disclosure could not be loaded.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      );
                    }
                    return Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(right: 20, bottom: 32),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 980),
                          child: SelectableText(
                            snapshot.data!,
                            style: const TextStyle(
                              color: Color(0xFFD6D6DC),
                              fontSize: 15,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _plainTextPolicy(String markdown) {
  return markdown
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^-\s+', multiLine: true), '• ')
      .replaceAllMapped(RegExp(r'<(https://[^>]+)>'), (match) => match[1]!)
      .replaceAll('**', '')
      .trim();
}
