enum DebridService {
  realDebrid(
    slug: 'realdebrid',
    displayName: 'Real-Debrid',
    shortName: 'RD',
    tokenStorageKey: 'real_debrid_access_token',
  ),
  torBox(
    slug: 'torbox',
    displayName: 'TorBox',
    shortName: 'TB',
    tokenStorageKey: 'torbox_api_token',
  );

  const DebridService({
    required this.slug,
    required this.displayName,
    required this.shortName,
    required this.tokenStorageKey,
  });

  final String slug;
  final String displayName;
  final String shortName;
  final String tokenStorageKey;

  static DebridService? fromSlug(String? slug) {
    for (final service in values) {
      if (service.slug == slug) return service;
    }
    return null;
  }
}
