import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strathvision/data/database.dart';
import 'package:strathvision/workspace/project.dart';
import 'package:strathvision/workspace/review_presentation.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  test('context round-trips without changing project edits or marks', () async {
    await db.saveProject(
      const Project(projectId: 'p', name: 'Existing review'),
    );
    final before = (await db.select(db.projectRows).get()).single;
    final store = ReviewStateStore(db);
    final lease = await store.claim('p');
    final state = ReviewPresentation(
      eventKey: 'pack/event',
      schema: 'v1',
      activeStage: 'b',
      attribute: 'Timing',
      profileChosen: true,
      profileKey: 'profile@3',
      positions: const {'a': 5860, 'b': 7030},
      signatures: const {'a': 'one', 'b': 'two'},
      viewedAt: DateTime.utc(2026, 11, 7),
    );
    expect(await store.save(lease, state), isTrue);
    expect((await store.read('p'))!.toJson(), state.toJson());
    final after = (await db.select(db.projectRows).get()).single;
    expect(after.json, before.json);
    expect(after.updatedAt, before.updatedAt);
  });
  test('newer route lease rejects a late older-session save', () async {
    final oldStore = ReviewStateStore(db), newStore = ReviewStateStore(db);
    final old = await oldStore.claim('p');
    await oldStore.save(old, const ReviewPresentation(positions: {'a': 1000}));
    final fresh = await newStore.claim('p');
    expect(fresh.initial.positions['a'], 1000);
    expect(
      await newStore.save(
        fresh,
        const ReviewPresentation(positions: {'a': 2000}),
      ),
      isTrue,
    );
    expect(
      await oldStore.save(
        old,
        const ReviewPresentation(positions: {'a': 3000}),
      ),
      isFalse,
    );
    expect((await newStore.read('p'))!.positions['a'], 2000);
  });
  test(
    'writes copy caller maps and preserve explicit no-profile choice',
    () async {
      final store = ReviewStateStore(db), positions = {'a': 100};
      final lease = await store.claim('p');
      final write = store.save(
        lease,
        ReviewPresentation(positions: positions, profileChosen: true),
      );
      positions['a'] = 999;
      expect(await write, isTrue);
      final loaded = (await store.read('p'))!;
      expect(loaded.positions['a'], 100);
      expect(loaded.profileChosen, isTrue);
      expect(loaded.profileKey, isNull);
    },
  );
  test('future formats and invalid positions are not overwritten', () async {
    final raw = jsonEncode({
      'lease': 'old',
      'revision': 2,
      'state': {'format': 'review-presentation/99'},
    });
    await db.setSetting('${ReviewStateStore.prefix}p', raw);
    await expectLater(
      ReviewStateStore(db).claim('p'),
      throwsA(isA<FormatException>()),
    );
    expect(await db.watchSetting('${ReviewStateStore.prefix}p').first, raw);
    expect(
      () => ReviewPresentation.fromJson(
        const ReviewPresentation(positions: {'a': -1}).toJson(),
      ),
      throwsFormatException,
    );
  });
}
