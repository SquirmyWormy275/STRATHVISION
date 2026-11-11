import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';

/// Local presentation state: never exported as feedback or coaching evidence.
class ReviewPresentation {
  const ReviewPresentation({
    this.eventKey,
    this.schema,
    this.activeStage = 'a',
    this.attribute,
    this.profileKey,
    this.profileChosen = false,
    this.positions = const {},
    this.signatures = const {},
    this.viewedAt,
  });
  final String? eventKey, schema, attribute, profileKey;
  final String activeStage;
  final bool profileChosen;
  final Map<String, int> positions;
  final Map<String, String> signatures;
  final DateTime? viewedAt;

  Map<String, Object?> toJson() => {
    'format': 'review-presentation/1',
    'event': eventKey,
    'schema': schema,
    'active_stage': activeStage,
    'attribute': attribute,
    'profile': profileKey,
    'profile_chosen': profileChosen,
    'positions_ms': Map.of(positions),
    'source_signatures': Map.of(signatures),
    'viewed_at': viewedAt?.toUtc().toIso8601String(),
  };

  factory ReviewPresentation.fromJson(Map<String, Object?> j) {
    if (j['format'] != 'review-presentation/1') {
      throw const FormatException('Unsupported saved review context.');
    }
    final positions = Map<String, int>.from(j['positions_ms'] as Map);
    if (positions.values.any((v) => v < 0) ||
        !['a', 'b'].contains(j['active_stage'])) {
      throw const FormatException('Invalid saved review position.');
    }
    return ReviewPresentation(
      eventKey: j['event'] as String?,
      schema: j['schema'] as String?,
      activeStage: j['active_stage'] as String,
      attribute: j['attribute'] as String?,
      profileKey: j['profile'] as String?,
      profileChosen: j['profile_chosen'] as bool,
      positions: Map.unmodifiable(positions),
      signatures: Map.unmodifiable(
        Map<String, String>.from(j['source_signatures'] as Map),
      ),
      viewedAt: j['viewed_at'] == null
          ? null
          : DateTime.parse(j['viewed_at'] as String),
    );
  }
}

class ReviewLease {
  ReviewLease(this.projectId, this.token, this.initial);
  final String projectId, token;
  final ReviewPresentation initial;
  int revision = 0;
}

/// Separate settings records avoid rewriting stale Project JSON from a timer.
/// Transactions + route leases reject late saves from an older review session.
class ReviewStateStore {
  ReviewStateStore(this.db);
  final AppDatabase db;
  static const prefix = 'review.presentation.v1:';
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, Object?>?> _read(String id) async {
    final row = await (db.select(
      db.settings,
    )..where((t) => t.key.equals('$prefix$id'))).getSingleOrNull();
    return row == null
        ? null
        : Map<String, Object?>.from(jsonDecode(row.value) as Map);
  }

  ReviewPresentation _state(Map<String, Object?> record) =>
      ReviewPresentation.fromJson(
        Map<String, Object?>.from(record['state'] as Map),
      );

  Future<ReviewPresentation?> read(String id) => _serial(() async {
    final record = await _read(id);
    return record == null ? null : _state(record);
  });

  Future<ReviewLease> claim(String id) => _serial(
    () => db.transaction(() async {
      final record = await _read(id);
      final initial = record == null
          ? const ReviewPresentation()
          : _state(record);
      final lease = ReviewLease(id, const Uuid().v4(), initial);
      await db.setSetting(
        '$prefix$id',
        jsonEncode({
          'lease': lease.token,
          'revision': 0,
          'state': initial.toJson(),
        }),
      );
      return lease;
    }),
  );

  Future<bool> save(ReviewLease lease, ReviewPresentation state) {
    final revision = ++lease.revision;
    final payload = state.toJson();
    return _serial(
      () => db.transaction(() async {
        final current = await _read(lease.projectId);
        if (current == null ||
            current['lease'] != lease.token ||
            (current['revision'] as int) >= revision) {
          return false;
        }
        _state(current);
        await db.setSetting(
          '$prefix${lease.projectId}',
          jsonEncode({
            'lease': lease.token,
            'revision': revision,
            'state': payload,
          }),
        );
        return true;
      }),
    );
  }

  Stream<Map<String, DateTime>> watchVisits() =>
      (db.select(db.settings)..where((t) => t.key.like('$prefix%')))
          .watch()
          .map((rows) {
            final visits = <String, DateTime>{};
            for (final row in rows) {
              try {
                final state = _state(
                  Map<String, Object?>.from(jsonDecode(row.value) as Map),
                );
                if (state.viewedAt != null) {
                  visits[row.key.substring(prefix.length)] = state.viewedAt!;
                }
              } catch (_) {
                /* An unreadable presentation record cannot hide the library. */
              }
            }
            return visits;
          })
          .distinct((a, b) => mapEquals(a, b));
}
