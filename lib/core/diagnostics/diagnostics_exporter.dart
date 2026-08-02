import 'dart:convert';
import 'dart:io';

import 'package:anime_tv/core/platform/android_tv_bridge.dart';
import 'package:anime_tv/core/storage/tetotv_database.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class DiagnosticsExporter {
  const DiagnosticsExporter();

  Future<File> export() async {
    final directory = await getApplicationDocumentsDirectory();
    final profile = await AndroidTvBridge.instance.getDeviceProfile(
      refresh: true,
    );
    final database = await TetoTvDatabase.instance.diagnosticsSnapshot();
    final payload = <String, Object?>{
      'app': {'name': 'TetoTV', 'version': '1.5.0', 'build': 30000},
      'device': profile.toJson(),
      'database': database,
      'privacy':
          'Authentication tokens and direct stream URLs are never exported.',
    };
    final file = File(path.join(directory.path, 'tetotv-diagnostics.json'));
    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }
}
