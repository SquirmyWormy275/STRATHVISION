import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:strathvision/profiles/profile_package.dart';

const fixture = 'test/fixtures/dummy_profile.json';

Map<String, Object?> loadFixture() =>
    jsonDecode(File(fixture).readAsStringSync()) as Map<String, Object?>;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sv_profile_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('reads metadata from the dummy profile JSON', () async {
    final m = await readProfilePackage(fixture);
    expect(m.coachName, 'Dummy Coach');
    expect(m.version, 1);
    expect(m.packId, 'example_pack');
    expect(m.sourceClipCount, 15);
    expect(m.metricCount, 1);
    expect(m.createdAt, DateTime.utc(2026, 11, 3, 12));
  });

  test('reads a package directory', () async {
    File(fixture).copySync(p.join(tmp.path, profileManifestName));
    final m = await readProfilePackage(tmp.path);
    expect(m.coachName, 'Dummy Coach');
  });

  test('reads a zip package with profile.json in a subfolder', () async {
    final bytes = File(fixture).readAsBytesSync();
    final archive = Archive()
      ..addFile(ArchiveFile('pkg/$profileManifestName', bytes.length, bytes))
      ..addFile(ArchiveFile('pkg/specialist_patches/.keep', 0, <int>[]));
    final zip = File(p.join(tmp.path, 'pkg.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    final m = await readProfilePackage(zip.path);
    expect(m.profileId, '7f1c2d3e-0000-4000-8000-000000000001');
  });

  group('rejects with SCHEMA_MISMATCH', () {
    Future<AnalysisError> rejection(String path) async {
      try {
        await readProfilePackage(path);
      } on AnalysisError catch (e) {
        return e;
      }
      fail('expected AnalysisError');
    }

    Future<AnalysisError> rejectJson(Object json) {
      final f = File(p.join(tmp.path, 'bad.json'))
        ..writeAsStringSync(jsonEncode(json));
      return rejection(f.path);
    }

    test('missing required field', () async {
      final e = await rejectJson(loadFixture()..remove('coach_name'));
      expect(e.errorCode, 'SCHEMA_MISMATCH');
      expect(e.details['problems'], contains('coach_name is missing'));
    });

    test('wrong type', () async {
      final e = await rejectJson(loadFixture()..['version'] = '1');
      expect(e.details['problems'], contains('version has the wrong type'));
    });

    test('bad metric entry', () async {
      final json = loadFixture();
      (json['metrics'] as Map)['example_angle'] = {'center': 'x'};
      final e = await rejectJson(json);
      final problems = e.details['problems'] as List;
      expect(problems, contains('metrics.example_angle.center must be a number'));
      expect(problems, contains('metrics.example_angle.unit must be a string'));
    });

    test('bad timestamp', () async {
      final e = await rejectJson(loadFixture()..['created_at'] = 'yesterday');
      expect(e.details['problems'], contains('created_at is not ISO 8601'));
    });

    test('not JSON', () async {
      final f = File(p.join(tmp.path, 'x.json'))..writeAsStringSync('{nope');
      final e = await rejection(f.path);
      expect(e.errorCode, 'SCHEMA_MISMATCH');
      expect(e.toJson().keys, ['error_code', 'message', 'details']);
    });

    test('zip without manifest', () async {
      final zip = File(p.join(tmp.path, 'empty.zip'))
        ..writeAsBytesSync(ZipEncoder()
            .encode(Archive()..addFile(ArchiveFile('readme.txt', 1, [65]))));
      final e = await rejection(zip.path);
      expect(e.message, contains('profile.json'));
    });

    test('missing file', () async {
      final e = await rejection(p.join(tmp.path, 'nope.json'));
      expect(e.errorCode, 'SCHEMA_MISMATCH');
    });
  });
}
