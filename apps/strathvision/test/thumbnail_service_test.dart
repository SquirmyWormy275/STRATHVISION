import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/media/thumbnail_service.dart';

void main() {
  late Directory root;
  late File source;
  setUp(() {
    root = Directory.systemTemp.createTempSync('sv-preview-');
    source = File('${root.path}/source.mp4')..writeAsStringSync('original');
  });
  tearDown(() => root.deleteSync(recursive: true));
  test('duplicate requests share a decoder and preserve original', () async {
    var decoded = 0;
    final service = ThumbnailService(
      directory: () async => Directory('${root.path}/cache'),
      decoder: (_) async {
        decoded++;
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    final before = await source.stat();
    final first = service.request(source.path),
        second = service.request(source.path);
    expect((await first.result)!.path, (await second.result)!.path);
    expect(decoded, 1);
    expect(await service.request(source.path).result, isNotNull);
    expect(decoded, 1);
    expect(await source.readAsString(), 'original');
    expect((await source.stat()).modified, before.modified);
    await service.dispose();
  });
  test('cancelled queued work is skipped and decoders are bounded', () async {
    var running = 0, peak = 0, decoded = 0;
    final other = File('${root.path}/other.mp4')..writeAsStringSync('other');
    final gate = Completer<void>(), entered = Completer<void>();
    final service = ThumbnailService(
      directory: () async => Directory('${root.path}/cache'),
      decoder: (_) async {
        decoded++;
        running++;
        if (running > peak) peak = running;
        if (!entered.isCompleted) entered.complete();
        await gate.future;
        running--;
        return Uint8List.fromList([1]);
      },
    );
    final first = service.request(source.path);
    await entered.future;
    final second = service.request(other.path)..cancel();
    gate.complete();
    await first.result;
    await second.result;
    await service.dispose();
    expect(peak, 1);
    expect(decoded, 1);
  });
  test('decode finished after every request cancelled is still cached', () async {
    var decoded = 0;
    final gate = Completer<void>(), entered = Completer<void>();
    final service = ThumbnailService(
      directory: () async => Directory('${root.path}/cache'),
      decoder: (_) async {
        decoded++;
        if (!entered.isCompleted) entered.complete();
        await gate.future;
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    final scrolledAway = service.request(source.path);
    await entered.future;
    scrolledAway.cancel();
    gate.complete();
    await scrolledAway.result;
    // The single worker runs jobs in order, so this one finishing means the
    // cancelled decode has finished too.
    final other = File('${root.path}/other.mp4')..writeAsStringSync('other');
    await service.request(other.path).result;
    expect(decoded, 2);
    expect(await service.request(source.path).result, isNotNull);
    expect(decoded, 2);
    await service.dispose();
  });
  test('mutation during decoding rejects stale preview', () async {
    final service = ThumbnailService(
      directory: () async => Directory('${root.path}/cache'),
      decoder: (_) async {
        await source.writeAsString('changed bytes');
        return Uint8List.fromList([1]);
      },
    );
    expect(await service.request(source.path).result, isNull);
    expect(await source.readAsString(), 'changed bytes');
    await service.dispose();
  });
  test('missing media and decoder errors resolve to fallbacks', () async {
    final service = ThumbnailService(
      directory: () async => Directory('${root.path}/cache'),
      decoder: (_) async => throw const FormatException('bad video'),
    );
    expect(await service.request('${root.path}/missing.mp4').result, isNull);
    expect(await service.request(source.path).result, isNull);
    await service.dispose();
  });
}
