import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:strathvision/media/picked_video.dart';

void main() {
  late Directory root, temporary, support;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('sv-picked-video-');
    temporary = await Directory(p.join(root.path, 'temporary')).create();
    support = Directory(p.join(root.path, 'support'));
  });
  tearDown(() => root.delete(recursive: true));

  Future<String> retain(
    String path, {
    bool onIOS = true,
    Future<void> Function(File, File)? copy,
  }) => retainPickedVideo(
    path,
    onIOS: onIOS,
    supportDirectory: () async => support,
    copy: copy,
  );

  test('iOS picked bytes survive removal of the temporary export', () async {
    final source = await File(p.join(temporary.path, 'swing.MOV'))
        .writeAsBytes([0, 1, 2, 255, 42]);
    final retained = File(await retain(source.path));
    expect(p.isWithin(support.path, retained.path), isTrue);
    expect(p.basename(retained.path), 'swing.MOV');
    expect(await source.readAsBytes(), [0, 1, 2, 255, 42]);
    await temporary.delete(recursive: true);
    expect(await retained.readAsBytes(), [0, 1, 2, 255, 42]);
  });

  test('same-name picks keep separate durable contents', () async {
    final source = File(p.join(temporary.path, 'swing.MOV'));
    await source.writeAsBytes([1]);
    final first = File(await retain(source.path));
    await source.writeAsBytes([2]);
    final second = File(await retain(source.path));
    expect(second.path, isNot(first.path));
    expect(await first.readAsBytes(), [1]);
    expect(await second.readAsBytes(), [2]);
  });

  test(
    'desktop paths remain unchanged without resolving app storage',
    () async {
      final source = await File(p.join(temporary.path, 'swing.MOV'))
          .writeAsBytes([1]);
      expect(await retain(source.path, onIOS: false), source.path);
      final original = await File(p.join(root.path, 'original.MOV'))
          .writeAsBytes([2]);
      expect(await retain(original.path, onIOS: false), original.path);
      expect(await support.exists(), isFalse);
    },
  );

  test(
    'iOS picks are retained regardless of picker export directory',
    () async {
      final source = await File(p.join(root.path, 'other-export.MOV'))
          .writeAsBytes([2]);
      final retained = File(await retain(source.path));
      expect(p.isWithin(support.path, retained.path), isTrue);
      await source.delete();
      expect(await retained.readAsBytes(), [2]);
    },
  );

  test(
    'picker path aliases retain the same bytes',
    () async {
      final source = await File(p.join(temporary.path, 'swing.MOV'))
          .writeAsBytes([3]);
      final alias = await Link(p.join(root.path, 'alias'))
          .create(temporary.path);
      final retained = File(await retain(p.join(alias.path, 'swing.MOV')));
      expect(retained.path, isNot(source.path));
      expect(p.isWithin(support.path, retained.path), isTrue);
      expect(await retained.readAsBytes(), [3]);
    },
    skip: Platform.isWindows
        ? 'Windows links require optional privileges.'
        : false,
  );

  test(
    'failed copies remove their partial destination and preserve source',
    () async {
      final source = await File(p.join(temporary.path, 'swing.MOV'))
          .writeAsBytes([1, 2, 3]);
      final failure = FileSystemException('simulated full disk');
      await expectLater(
        retain(
          source.path,
          copy: (_, destination) async {
            await destination.writeAsBytes([1]);
            throw failure;
          },
        ),
        throwsA(same(failure)),
      );
      expect(await source.readAsBytes(), [1, 2, 3]);
      expect(
        await Directory(p.join(support.path, 'imported_clips')).list().toList(),
        isEmpty,
      );
    },
  );
}
