import 'package:anime_tv/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class NetworkArtwork extends StatelessWidget {
  const NetworkArtwork({
    required this.url,
    this.fit = BoxFit.cover,
    this.icon = Icons.movie_outlined,
    this.cacheWidth,
    super.key,
  });

  final String? url;
  final BoxFit fit;
  final IconData icon;
  final int? cacheWidth;

  static void precache(BuildContext context, String url, {int? cacheWidth}) {
    precacheImage(
      CachedNetworkImageProvider(url, maxWidth: cacheWidth ?? 800),
      context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) return _Fallback(icon: icon);
    return CachedNetworkImage(
      imageUrl: source,
      fit: fit,
      memCacheWidth: cacheWidth ?? 800,
      fadeInDuration: Duration.zero,
      placeholder: (_, _) => _Fallback(icon: icon),
      errorWidget: (_, _, _) => _Fallback(icon: icon),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.panelRaised,
      child: Center(child: Icon(icon, color: AppColors.textMuted, size: 42)),
    );
  }
}
