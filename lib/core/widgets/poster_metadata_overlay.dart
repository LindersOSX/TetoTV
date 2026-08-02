import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class PosterMetadataOverlay extends StatelessWidget {
  const PosterMetadataOverlay({
    this.score,
    this.releaseYear,
    this.durationMinutes,
    super.key,
  });

  final double? score;
  final int? releaseYear;
  final int? durationMinutes;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xC9000000),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (score case final value?)
              _PosterBadge(
                text: '★${value.toStringAsFixed(1)}',
                color: AppColors.accent,
              ),
            if (releaseYear case final value?) ...[
              const SizedBox(width: 3),
              _PosterBadge(text: '$value', color: const Color(0xFF59111F)),
            ],
            if (durationMinutes case final value?) ...[
              const SizedBox(width: 3),
              _PosterBadge(text: '${value}m', color: const Color(0xFF202020)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PosterBadge extends StatelessWidget {
  const _PosterBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
