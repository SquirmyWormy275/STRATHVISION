import 'dart:convert';

import 'errors.dart';
import 'pack.dart';

/// One event in a pack: its display label and analysis section.
class PackEvent {
  const PackEvent({required this.label, required this.analysis});
  final String label;
  final AnalysisPack analysis;
  String get eventId => analysis.eventId;
}

/// A whole pack file (INTERFACES.md "Pack File"): the unit of domain
/// knowledge. Loaded at runtime; swapping packs needs no engine change.
class PackDefinition {
  const PackDefinition({
    required this.packId,
    required this.name,
    required this.topAttributes,
    required this.moreAttributes,
    required this.phaseLabels,
    required this.metricLabels,
    required this.events,
  });

  final String packId;
  final String name;
  final List<String> topAttributes;
  final List<String> moreAttributes;
  final Map<String, String> phaseLabels;
  final Map<String, String> metricLabels;
  final List<PackEvent> events;

  PackEvent? event(String eventId) =>
      events.where((e) => e.eventId == eventId).firstOrNull;

  static PackDefinition parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw AnalysisError(ErrorCode.schemaMismatch, 'The pack is not valid JSON.',
          {'cause': e.message});
    }
    return PackDefinition.fromJson(json);
  }

  factory PackDefinition.fromJson(Object? json) {
    final problems = <String>[];
    if (json is! Map) {
      throw AnalysisError(ErrorCode.schemaMismatch, 'A pack must be a JSON object.');
    }
    if (json['format_version'] != 1) problems.add('format_version must be 1');
    final packId = json['pack_id'];
    final name = json['name'];
    if (packId is! String || packId.isEmpty) problems.add('pack_id must be a non-empty string');
    if (name is! String || name.isEmpty) problems.add('name must be a non-empty string');

    List<String> strings(Object? v, String path) {
      if (v is List && v.every((x) => x is String)) return v.cast<String>();
      problems.add('$path must be a list of strings');
      return const [];
    }

    Map<String, String> labels(Object? v, String path) {
      if (v == null) return const {};
      if (v is Map && v.values.every((x) => x is String)) {
        return {for (final e in v.entries) '${e.key}': e.value as String};
      }
      problems.add('$path must map ids to strings');
      return const {};
    }

    final attrs = json['attributes'];
    final top = attrs is Map ? strings(attrs['top'], 'attributes.top') : const <String>[];
    final more = attrs is Map ? strings(attrs['more'], 'attributes.more') : const <String>[];
    if (attrs is! Map) problems.add('attributes must be an object');

    final events = <PackEvent>[];
    final rawEvents = json['events'];
    if (rawEvents is! List || rawEvents.isEmpty) {
      problems.add('events must be a non-empty list');
    } else {
      for (var i = 0; i < rawEvents.length; i++) {
        final e = rawEvents[i];
        if (e is! Map) {
          problems.add('events[$i] must be an object');
          continue;
        }
        final label = e['label'];
        if (label is! String || label.isEmpty) {
          problems.add('events[$i].label must be a non-empty string');
        }
        try {
          final analysis = AnalysisPack.fromJson({...e, 'pack_id': packId});
          if (events.any((x) => x.eventId == analysis.eventId)) {
            problems.add('events[$i].event_id is duplicated');
          } else if (label is String) {
            events.add(PackEvent(label: label, analysis: analysis));
          }
        } on AnalysisError catch (err) {
          for (final p in (err.details['problems'] as List? ?? [err.message])) {
            problems.add('events[$i].$p');
          }
        }
      }
    }
    if (problems.isNotEmpty) {
      throw AnalysisError(ErrorCode.schemaMismatch,
          'The pack does not match the schema.', {'problems': problems});
    }
    return PackDefinition(
      packId: packId as String,
      name: name as String,
      topAttributes: top,
      moreAttributes: more,
      phaseLabels: labels(json['phase_labels'], 'phase_labels'),
      metricLabels: labels(json['metric_labels'], 'metric_labels'),
      events: events,
    );
  }
}
