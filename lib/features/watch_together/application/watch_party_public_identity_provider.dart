import 'package:anime_tv/features/settings/application/settings_preferences_controller.dart';
import 'package:anime_tv/features/settings/application/tracking_accounts_controller.dart';
import 'package:anime_tv/features/watch_together/domain/watch_party_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The only tracker-profile fields permitted in Watch Together room payloads.
/// Provider, account/slot IDs, email, OAuth identifiers, and tokens never
/// enter this model.
final watchPartyPublicIdentityProvider = Provider<WatchPartyPublicIdentity?>((
  ref,
) {
  final preferences = ref.watch(settingsPreferencesProvider);
  final accounts = ref.watch(trackingAccountsControllerProvider);
  var profile = accounts.profiles[preferences.trackingProvider];
  if (profile == null && accounts.profiles.isNotEmpty) {
    profile = accounts.profiles.values.first;
  }
  if (profile == null) return null;
  return WatchPartyPublicIdentity.tryCreate(
    displayName: profile.username,
    avatarUrl: profile.avatarUrl,
  );
});
