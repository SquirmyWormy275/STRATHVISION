"""Score anonymous target selection and contacts against frozen references."""
import argparse
from functools import lru_cache
import json
from pathlib import Path
from statistics import mean

from footage import sha256, write_json
from target import contains, rotate_box


def contact_matches(predictions, intervals, tolerance):
    """Maximum one-to-one ordered matches, then minimum midpoint error."""
    predicted, references = sorted(predictions), sorted(intervals)

    @lru_cache(None)
    def solve(i, j):
        if i == len(predicted) or j == len(references):
            return 0, 0., ()
        options = [solve(i + 1, j), solve(i, j + 1)]
        lo, hi = references[j]
        if lo - tolerance <= predicted[i] <= hi + tolerance:
            count, cost, pairs = solve(i + 1, j + 1)
            options.append((count + 1, cost + abs(predicted[i] - (lo + hi) / 2),
                            ((i, j),) + pairs))
        return max(options, key=lambda result: (result[0], -result[1]))

    count, _, pairs = solve(0, 0)
    return {'tp': count, 'fp': len(predicted) - count, 'fn': len(references) - count,
            'timing_errors_s': [abs(predicted[i] - sum(references[j]) / 2) for i, j in pairs]}


def rates(counts):
    tp, fp, fn = (counts[k] for k in ('tp', 'fp', 'fn'))
    return {'precision': tp / (tp + fp) if tp + fp else None,
            'recall': tp / (tp + fn) if tp + fn else None,
            'f1': 2 * tp / (2 * tp + fp + fn) if 2 * tp + fp + fn else None}


def validate_split(references):
    groups = {}
    ids = set()
    for row in references:
        if row['window_id'] in ids:
            raise ValueError('Duplicate window ID')
        ids.add(row['window_id'])
        sha, split = row['clip_sha256'], row['split']
        if sha in groups and groups[sha] != split:
            raise ValueError('Source content leaks across development and test')
        groups[sha] = split


def score_window(reference, prediction, contacts, tolerance):
    if reference['window_id'] != prediction['window_id'] or reference['clip_sha256'] != prediction['clip_sha256']:
        raise ValueError('Reference and prediction source do not match')
    if contacts['window_id'] != reference['window_id']:
        raise ValueError('Contact window mismatch')
    if ('prediction_sources_sha256' in contacts and
            contacts['prediction_sources_sha256'] != prediction.get('sources_sha256')):
        raise ValueError('Contact results came from different inference sources')
    hits = missing = misses = 0
    visible = [a for a in reference['target_anchors'] if a['visible']]
    observed = prediction['observations']
    for anchor in visible:
        nearest = min(observed, key=lambda o: abs(o['time_s'] - anchor['time_s']), default=None)
        if nearest is None or abs(nearest['time_s'] - anchor['time_s']) > .51 / prediction['sample_rate']:
            missing += 1
            continue
        box = rotate_box(nearest['box_raw'], reference['reference_rotation_cw'])
        valid = (0 <= box[0] < box[2] <= 1 and 0 <= box[1] < box[3] <= 1
                 and (box[2] - box[0]) * (box[3] - box[1]) < .9)
        if valid and contains(box, anchor['point']):
            hits += 1
        else:
            misses += 1
    result = {'window_id': reference['window_id'], 'split': reference['split'],
              'target_checkpoints': len(visible), 'target_hits': hits,
              'target_missing': missing, 'target_point_misses': misses,
              'selected_segments': len({o['segment'] for o in observed}),
              'orientation_correct': prediction['rotation_cw'] == reference['reference_rotation_cw'],
              'candidate_strokes': contacts['candidate_strokes'], 'usable_strokes': contacts['usable_strokes'],
              'engine_failures': contacts['failures']}
    if reference['contact_intervals_s'] is None:
        result['contacts'] = None
        return result
    lo, hi = reference['score_interval_s']
    def scored(t):
        return lo <= t <= hi and not any(a <= t <= b for a, b in reference['ignored_intervals_s'])
    actual = [x for x in reference['contact_intervals_s'] if scored(sum(x) / 2)]
    predicted = [t for t in contacts['contact_times_s'] if scored(t)]
    counted = contact_matches(predicted, actual, tolerance)
    result['contacts'] = {**counted, **rates(counted), 'reference_count': len(actual),
                          'predicted_count': len(predicted), 'idle_window': len(actual) == 0,
                          'scored_seconds': hi - lo - sum(b - a for a, b in reference['ignored_intervals_s'])}
    return result


def summarize(rows):
    counts = {key: sum(r['contacts'][key] for r in rows if r['contacts'] is not None)
              for key in ('tp', 'fp', 'fn')}
    errors = [e for r in rows if r['contacts'] is not None for e in r['contacts']['timing_errors_s']]
    checkpoints = sum(r['target_checkpoints'] for r in rows)
    hits = sum(r['target_hits'] for r in rows)
    return {'windows': len(rows), 'target_checkpoints': checkpoints, 'target_hits': hits,
            'target_coverage': hits / checkpoints if checkpoints else None,
            'target_missing': sum(r['target_missing'] for r in rows),
            'target_point_misses': sum(r['target_point_misses'] for r in rows),
            'correct_orientation_windows': sum(r['orientation_correct'] for r in rows),
            'contacts': {**counts, **rates(counts), 'mean_midpoint_error_s': mean(errors) if errors else None,
                         'rated_windows': sum(r['contacts'] is not None for r in rows),
                         'scored_seconds': sum(r['contacts']['scored_seconds'] for r in rows if r['contacts'] is not None),
                         'idle_false_positives': sum(r['contacts']['fp'] for r in rows
                             if r['contacts'] is not None and r['contacts']['idle_window'])}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--predictions', type=Path, required=True)
    parser.add_argument('--contacts', type=Path, required=True)
    parser.add_argument('--partition', choices=['development', 'test'], required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    document = json.loads(args.reference.read_text())
    references = document['windows']
    validate_split(references)
    contact_document = json.loads(args.contacts.read_text())
    contacts = {r['window_id']: r for r in contact_document['windows']}
    scored = []
    provenance = None
    for reference in references:
        if reference['split'] != args.partition:
            continue
        prediction = json.loads((args.predictions / f"{reference['window_id']}.json").read_text())
        current = {key: prediction[key] for key in
                   ('variant', 'sample_rate', 'sources_sha256', 'inputs_sha256', 'detector_sha256', 'pose_sha256')}
        if provenance is not None and provenance != current:
            raise ValueError('Mixed inference provenance')
        provenance = current
        scored.append(score_window(reference, prediction, contacts[reference['window_id']], document['contact_tolerance_s']))
    result = {'format': 'gurr-accuracy-result/1', 'partition': args.partition,
              'reference_sha256': sha256(args.reference), 'inference': provenance,
              'contact_method': contact_document.get('method', 'committed engine entry-phase boundary'),
              'contact_source_sha256': contact_document.get('source_sha256'),
              'scorer_sha256': sha256(Path(__file__)), 'aggregate': summarize(scored), 'windows': scored,
              'limitations': ['Single Codex visual reviewer; no independent coach signoff.',
                              'Sparse torso-point containment is not full multi-object tracking accuracy.',
                              'Source-disjoint within this corpus; not a session- or athlete-independent trial.',
                              'Contact intervals are timing references, not technique feedback.',
                              'Rear-view crowded windows are tracking-only; underhand has one test source.']}
    write_json(args.output, result)
    print(json.dumps(result['aggregate'], indent=2))


if __name__ == '__main__':
    main()
