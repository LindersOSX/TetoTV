import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';

class AddonTypescriptCompiler {
  AddonTypescriptCompiler({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  static const _compilerAsset = 'assets/typescript/sucrase.js';
  static const _maximumSourceCharacters = 768 * 1024;

  final AssetBundle _bundle;
  Future<String>? _compilerSource;

  Future<String> compile(String source) async {
    if (source.isEmpty ||
        utf8.encode(source).length > _maximumSourceCharacters) {
      throw const FormatException('The TypeScript addon payload is invalid.');
    }
    final compiler = await (_compilerSource ??= _bundle.loadString(
      _compilerAsset,
      cache: true,
    ));
    return Isolate.run(
      () => _compileInQuickJs(compiler: compiler, source: source),
    ).timeout(const Duration(seconds: 30));
  }
}

String _compileInQuickJs({required String compiler, required String source}) {
  final runtime = QuickJsRuntime2(
    timeout: 5000,
    memoryLimit: 48 * 1024 * 1024,
    stackSize: 1024 * 1024,
  );
  try {
    final compilerResult = runtime.evaluate(
      compiler,
      sourceUrl: 'asset://typescript.js',
    );
    if (compilerResult.isError) {
      throw FormatException(
        'Could not initialize the TypeScript transformer: '
        '${compilerResult.stringResult}',
      );
    }
    final result = runtime.evaluate('''
      JSON.stringify({code: __tetoCompileTypescript(${jsonEncode(source)})})
    ''', sourceUrl: 'tetotv://typescript-compiler.js');
    if (result.isError) {
      throw FormatException(
        'TypeScript compilation failed: ${result.stringResult}',
      );
    }
    final decoded = jsonDecode(result.stringResult);
    if (decoded is! Map) {
      throw const FormatException(
        'The TypeScript compiler returned no output.',
      );
    }
    final code = decoded['code'];
    if (code is! String || code.trim().isEmpty) {
      throw const FormatException('The TypeScript compiler returned no code.');
    }
    if (utf8.encode(code).length >
        AddonTypescriptCompiler._maximumSourceCharacters) {
      throw const FormatException(
        'The compiled TypeScript addon payload is too large.',
      );
    }
    return code;
  } finally {
    runtime.dispose();
  }
}
