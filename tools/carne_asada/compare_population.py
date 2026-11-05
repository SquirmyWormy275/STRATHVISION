"""Compare complete population passes without treating phase counts as accuracy."""
import argparse
import json
from pathlib import Path

from footage import sha256, write_json


def aggregate(document):
    sources = document['sources']
    events = sorted({event for source in sources for event in source['candidate_event_passes']})
    fields = ('candidate_strokes', 'duplicate_predictions_removed', 'gate_passing_candidates',
              'gate_passing_union_seconds', 'selection_and_pack_eligible_candidates')
    return {'deferred_windows': sum(s['deferred_windows'] for s in sources),
            'events': {event: {field: sum(s['candidate_event_passes'].get(event, {}).get(field, 0)
                                         for s in sources) for field in fields} for event in events}}


def compare(native, base, current):
    expected = native['summary']
    if not (expected['native_completed_windows'] == expected['native_windows'] == expected['core_intervals_reached']
            and expected['unique_recordings'] == expected['complete_sources'] == expected['sources_reaching_all_scored_cores']
            and expected['native_failed_windows'] == 0):
        raise ValueError('Population coverage is incomplete')
    for replay in (base, current):
        if replay['summary'] != expected or replay['freeze'] != native['freeze']:
            raise ValueError('Different native inputs or coverage in replay')
        if not replay['engine_replay']['same_native_pose_inputs']:
            raise ValueError('Replay did not use the same native poses')
    if base['sources'] != native['sources']:
        raise ValueError('Baseline replay does not reproduce native results')
    if base['engine_replay']['fingerprint'] == current['engine_replay']['fingerprint']:
        raise ValueError('Both replay engines are identical')
    original = {s['clip_sha256']: s for s in native['sources']}
    if set(original) != {s['clip_sha256'] for s in current['sources']}:
        raise ValueError('Source population changed')
    changed = []
    for source in current['sources']:
        before = original[source['clip_sha256']]
        if {k: v for k, v in source.items() if k != 'candidate_event_passes'} != {
                k: v for k, v in before.items() if k != 'candidate_event_passes'}:
            raise ValueError('Source coverage changed during engine replay')
        differences = {event: {'base': before['candidate_event_passes'].get(event), 'current': values}
                       for event, values in source['candidate_event_passes'].items()
                       if values != before['candidate_event_passes'].get(event)}
        if differences:
            changed.append({'clip_sha256': source['clip_sha256'], 'source_name': source['source_name'],
                            'events': differences})
    return {'format': 'gurr-population-engine-comparison/1', 'coverage': expected,
            'baseline_reproduces_native': True,
            'base_engine_revision': base['engine_replay']['revision'],
            'current_engine_revision': current['engine_replay']['revision'],
            'base': aggregate(base), 'current': aggregate(current), 'changed_sources': changed,
            'limitations': ['Same cached native poses; later tracking changes were not re-inferred.',
                            'Event stress-test passes overlap and must not be added as unique footage.',
                            'Gate-passing candidates are not confirmed contacts, correct identity or coaching validation.',
                            'Event hints remain unreviewed; eligible counts are diagnostic, not profile readiness.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('native', 'base', 'current', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    paths = {name: getattr(args, name) for name in ('native', 'base', 'current')}
    result = compare(*(json.loads(paths[name].read_text()) for name in paths))
    result['artifacts_sha256'] = {name: sha256(path) for name, path in paths.items()}
    write_json(args.output, result)
    print(json.dumps({k: result[k] for k in ('coverage', 'base', 'current')}, indent=2))


if __name__ == '__main__':
    main()
