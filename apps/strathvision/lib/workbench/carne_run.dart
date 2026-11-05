import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../profiles/clip_probe.dart';
import '../workspace/project.dart';

typedef ClipFingerprinter = Future<String> Function(String path);
typedef ExperimentWriter = Future<String?> Function(
  String fileName,
  String contents,
);

/// Stream on a worker isolate, keeping long source files out of UI memory.
Future<String> hashVideoContent(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);

String canonicalHash(Object? value) {
  Object? ordered(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: ordered(v[key])};
    }
    if (v is List) return [for (final item in v) ordered(item)];
    return v;
  }

  return sha256.convert(utf8.encode(jsonEncode(ordered(value)))).toString();
}

class CarneSource {
  CarneSource({required this.hash, required this.name, required this.info});
  final String hash, name;
  final ClipInfo info;
  String get clipId => 'sha256:$hash';
  final Set<String> paths = {};
  final Map<String, List<Mark>> marksByPath = {};

  List<Mark> get marks => {
    for (final list in marksByPath.values)
      for (final mark in list) mark.markId: mark,
  }.values.toList();
}
