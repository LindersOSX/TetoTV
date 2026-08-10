import 'dart:async';

import 'package:anime_tv/features/auth/application/pairing_controller.dart';
import 'package:anime_tv/features/marketplace/application/marketplace_controller.dart';
import 'package:anime_tv/features/marketplace/data/source_pairing_client.dart';
import 'package:anime_tv/features/marketplace/domain/addon_models.dart';
import 'package:anime_tv/features/marketplace/domain/source_pairing.dart';
import 'package:anime_tv/features/streaming/application/user_torrent_sources_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef SourcePairingApiFactory = SourcePairingApi Function(String baseUrl);
typedef SourcePairingBaseUrlLoader = Future<String?> Function();
typedef SourcePayloadImporter =
    Future<SourceImportSummary> Function(SourcePairingPayload payload);
typedef PairedRepositoryAdder =
    Future<String?> Function(String url, {bool refreshAfterAdd});
typedef PairedManifestAdder = Future<String?> Function(String url);

final sourcePairingControllerProvider =
    StateNotifierProvider.autoDispose<
      SourcePairingController,
      SourcePairingState
    >((ref) {
      final marketplace = ref.read(marketplaceControllerProvider.notifier);
      final torrentSources = ref.read(
        userTorrentSourcesControllerProvider.notifier,
      );
      return SourcePairingController(
        () => effectiveAuthBrokerBaseUrl(ref.read(secureStorageProvider)),
        (baseUrl) => SourcePairingClient(baseUrl: baseUrl),
        (payload) => importPairedSources(
          payload,
          marketplace: marketplace,
          torrentSources: torrentSources,
        ),
      );
    });

class SourcePairingController extends StateNotifier<SourcePairingState> {
  SourcePairingController(
    this._baseUrlLoader,
    this._clientFactory,
    this._importer, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const SourcePairingState());

  final SourcePairingBaseUrlLoader _baseUrlLoader;
  final SourcePairingApiFactory _clientFactory;
  final SourcePayloadImporter _importer;
  final DateTime Function() _now;
  SourcePairingApi? _client;
  Timer? _pollTimer;
  int? _pollingGeneration;
  int _generation = 0;
  int _consecutivePollFailures = 0;

  Future<void> start() async {
    final previousClient = _client;
    final previousSession = state.session;
    final generation = ++_generation;
    _pollTimer?.cancel();
    _pollingGeneration = null;
    _client = null;
    _consecutivePollFailures = 0;
    if (previousClient != null && previousSession != null) {
      unawaited(_cancelBestEffort(previousClient, previousSession));
    }
    state = const SourcePairingState(stage: SourcePairingStage.starting);
    try {
      final baseUrl = await _baseUrlLoader();
      if (!mounted || generation != _generation) return;
      if (baseUrl == null) {
        throw StateError(
          'The TetoTV HTTPS broker is not configured. Configure account QR pairing first.',
        );
      }
      final client = _clientFactory(baseUrl);
      _client = client;
      await client.ensureReady();
      if (!mounted || generation != _generation) return;
      final session = await client.createSession();
      if (!mounted || generation != _generation) return;
      state = SourcePairingState(
        stage: SourcePairingStage.waiting,
        session: session,
      );
      _pollTimer = Timer.periodic(
        session.pollInterval,
        (_) => unawaited(pollNow()),
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = SourcePairingState(
        stage: SourcePairingStage.failed,
        message: _safeMessage(error),
      );
    }
  }

  Future<void> pollNow() async {
    if (!mounted) return;
    final session = state.session;
    final client = _client;
    if (state.stage != SourcePairingStage.waiting ||
        session == null ||
        client == null) {
      return;
    }
    if (!_now().isBefore(session.expiresAt)) {
      _pollTimer?.cancel();
      state = SourcePairingState(
        stage: SourcePairingStage.expired,
        session: session,
        message: 'The one-time source code expired. Create a new code.',
      );
      return;
    }

    final generation = _generation;
    if (_pollingGeneration == generation) return;
    _pollingGeneration = generation;
    try {
      final result = await client.poll(session);
      if (!mounted || generation != _generation) return;
      _consecutivePollFailures = 0;
      switch (result.status) {
        case SourcePairingPollStatus.pending:
          return;
        case SourcePairingPollStatus.expired:
          _pollTimer?.cancel();
          state = SourcePairingState(
            stage: SourcePairingStage.expired,
            session: session,
            message: 'The one-time source code expired. Create a new code.',
          );
          return;
        case SourcePairingPollStatus.submitted:
          final payload = result.payload;
          if (payload == null) {
            throw const FormatException(
              'The pairing service returned an empty submission.',
            );
          }
          _pollTimer?.cancel();
          state = SourcePairingState(
            stage: SourcePairingStage.validating,
            session: session,
            message: 'Received. Validating public HTTPS destinations…',
          );
          late final SourceImportSummary summary;
          try {
            summary = await _importer(payload);
          } catch (_) {
            if (!mounted || generation != _generation) return;
            state = SourcePairingState(
              stage: SourcePairingStage.failed,
              session: session,
              message:
                  'Sources were received but could not be imported safely. Create a new code and try again.',
            );
            return;
          }
          if (!mounted || generation != _generation) return;
          state = SourcePairingState(
            stage: summary.totalAdded > 0
                ? SourcePairingStage.completed
                : SourcePairingStage.failed,
            session: session,
            summary: summary,
            message: summary.message,
          );
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      _consecutivePollFailures++;
      if (_consecutivePollFailures >= 3) {
        _pollTimer?.cancel();
        state = SourcePairingState(
          stage: SourcePairingStage.failed,
          session: session,
          message: _safeMessage(error),
        );
      }
    } finally {
      if (_pollingGeneration == generation) {
        _pollingGeneration = null;
      }
    }
  }

  void stop() {
    if (!mounted) return;
    final client = _client;
    final session = state.session;
    _generation++;
    _pollTimer?.cancel();
    _pollingGeneration = null;
    _client = null;
    if (client != null && session != null) {
      unawaited(_cancelBestEffort(client, session));
    }
    if (mounted &&
        state.stage != SourcePairingStage.completed &&
        state.stage != SourcePairingStage.failed) {
      state = const SourcePairingState(stage: SourcePairingStage.stopped);
    }
  }

  @override
  void dispose() {
    final client = _client;
    final session = state.session;
    _generation++;
    _pollTimer?.cancel();
    _pollingGeneration = null;
    _client = null;
    if (client != null && session != null) {
      unawaited(_cancelBestEffort(client, session));
    }
    super.dispose();
  }
}

Future<void> _cancelBestEffort(
  SourcePairingApi client,
  SourcePairingSession session,
) async {
  try {
    await client.cancel(session);
  } catch (_) {
    // The broker still expires abandoned sessions after ten minutes.
  }
}

Future<SourceImportSummary> importPairedSources(
  SourcePairingPayload payload, {
  required MarketplaceController marketplace,
  required UserTorrentSourcesController torrentSources,
  Future<void> Function(Uri uri)? repositoryTargetValidator,
}) => importPairedSourcesWithOperations(
  payload,
  addRepository: marketplace.addRepository,
  refreshRepositories: () => marketplace.refresh(),
  addManifest: torrentSources.add,
  repositoryTargetValidator: repositoryTargetValidator,
);

/// Applies a one-time submission through the same validated controller
/// operations used by manual entry. Exposed separately so atomic/partial bulk
/// behavior can be verified without replacing the application controllers.
Future<SourceImportSummary> importPairedSourcesWithOperations(
  SourcePairingPayload payload, {
  required PairedRepositoryAdder addRepository,
  required Future<void> Function() refreshRepositories,
  required PairedManifestAdder addManifest,
  Future<void> Function(Uri uri)? repositoryTargetValidator,
}) async {
  var repositoriesAdded = 0;
  var manifestsAdded = 0;
  final errors = <String>[];

  for (var index = 0; index < payload.repositoryUrls.length; index++) {
    final value = payload.repositoryUrls[index];
    final uri = safePublicHttpsUri(value);
    if (uri == null) {
      errors.add('Repository ${index + 1}: invalid public HTTPS URL.');
      continue;
    }
    try {
      // Validate DNS before MarketplaceController persists the repository.
      // Marketplace network requests pin the validated public address again.
      await (repositoryTargetValidator ?? validatePublicNetworkTarget)(uri);
      final error = await addRepository(uri.toString(), refreshAfterAdd: false);
      if (error == null) {
        repositoriesAdded++;
      } else {
        errors.add('Repository ${index + 1}: $error');
      }
    } catch (_) {
      errors.add('Repository ${index + 1}: host is not a public address.');
    }
  }

  if (repositoriesAdded > 0) {
    try {
      // A paired form can contain several repositories. Refresh the combined
      // catalog once rather than blocking the TV on one network pass per URL.
      await refreshRepositories();
    } catch (_) {
      errors.add(
        'Repositories were saved, but the marketplace catalog could not refresh.',
      );
    }
  }

  for (var index = 0; index < payload.manifestUrls.length; index++) {
    try {
      final error = await addManifest(payload.manifestUrls[index]);
      if (error == null) {
        manifestsAdded++;
      } else {
        errors.add('Torrent manifest ${index + 1}: $error');
      }
    } catch (_) {
      errors.add('Torrent manifest ${index + 1}: could not be saved.');
    }
  }

  return SourceImportSummary(
    repositoriesAdded: repositoriesAdded,
    manifestsAdded: manifestsAdded,
    errors: List<String>.unmodifiable(errors),
  );
}

String _safeMessage(Object error) {
  final value = error.toString().replaceFirst(
    RegExp(r'^[A-Za-z]+(?:Exception|Error):\s*'),
    '',
  );
  return value.length <= 220 ? value : '${value.substring(0, 220)}…';
}
