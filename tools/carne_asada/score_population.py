"""Check population phase boundaries on already-opened timing references."""
import argparse
import json
from pathlib import Path

from compare_population import compare
from footage import sha256, write_json
from score_accuracy import contact_matches, rates


def score(reference, window, strokes, tolerance, selection_required):
    if reference['clip_sha256'] != window['clip_sha256'] or reference['window_id'] != window['window_id']:
        raise ValueError('Reference/input identity mismatch')
    if reference['contact_intervals_s'] is None:
        return None
    lo, hi = reference['score_interval_s']

    def included(t):
        return lo <= t <= hi and not any(a <= t <= b for a, b in reference['ignored_intervals_s'])

    predictions = []
    for stroke in strokes:
        if not stroke['usable'] or (selection_required and not stroke['selection_eligible']):
            continue
        frame = stroke['measurement']['phases']['entry']['start_frame']
        t = stroke['window_start_s'] + frame / stroke['native_fps'] - window['start_s']
        if included(t):
            predictions.append(t)
    actual = [pair for pair in reference['contact_intervals_s'] if included(sum(pair) / 2)]
    result = contact_matches(predictions, actual, tolerance)
    return {**result, **rates(result), 'reference_count': len(actual),
            'predicted_count': len(predictions), 'predicted_times_s': sorted(predictions)}


def execute(parent, artifacts, evaluation):
    documents = {k: json.loads(p.read_text()) for k, p in artifacts.items()}
    compare(documents['native'], documents['base'], documents['current'])
    sources = {s['clip_sha256'] for s in documents['native']['sources']}
    studies = {}; input_hashes = {}; measurement_hashes = {}
    for name, prefix in [('original', 'gurr'), ('followup', 'gurr-phase')]:
        inputs_path = evaluation / (prefix + '-inputs.json')
        reference_path = evaluation / (prefix + '-reference.json')
        inputs = {w['window_id']: w for w in json.loads(inputs_path.read_text())['windows']}
        references = json.loads(reference_path.read_text())
        input_hashes[name] = {'inputs_sha256': sha256(inputs_path), 'reference_sha256': sha256(reference_path)}
        versions = {}
        for label in ('base', 'current'):
            rows = []
            for ref in references['windows']:
                if ref['clip_sha256'] not in sources:
                    raise ValueError('Reference source absent from completed population')
                path = parent / ('bounded/source-measurements-' + label) / (ref['clip_sha256'] + '.json')
                measurement_hashes[label + ':' + ref['clip_sha256']] = sha256(path)
                window = inputs[ref['window_id']]
                strokes = json.loads(path.read_text())[window['event_id']]
                rows.append({'window_id': ref['window_id'], 'clip_sha256': ref['clip_sha256'], 'split': ref['split'],
                             'phase_gate_only': score(ref, window, strokes, references['contact_tolerance_s'], False),
                             'selection_eligible': score(ref, window, strokes, references['contact_tolerance_s'], True)})
            aggregate = {}
            for split in sorted({r['split'] for r in rows}):
                aggregate[split] = {}
                for mode in ('phase_gate_only', 'selection_eligible'):
                    rated = [r[mode] for r in rows if r['split'] == split and r[mode] is not None]
                    counts = {k: sum(r[k] for r in rated) for k in ('tp', 'fp', 'fn')}
                    aggregate[split][mode] = {**counts, **rates(counts), 'rated_windows': len(rated),
                                             'reference_count': sum(r['reference_count'] for r in rated)}
            versions[label] = {'aggregate': aggregate, 'windows': rows}
        studies[name] = versions
    return {'format': 'gurr-population-opened-reference-diagnostic/1', 'studies': studies,
            'artifacts_sha256': {k: sha256(p) for k, p in artifacts.items()}, 'references': input_hashes,
            'private_measurement_sha256': measurement_hashes, 'scorer_sha256': sha256(Path(__file__)),
            'matcher_sha256': sha256(Path(__file__).with_name('score_accuracy.py')),
            'limitations': ['These references were already opened; this is not a new held-out evaluation.',
                            'Whole-source windows change selection/context compared with the original eight-second pilots.',
                            'Phase-gate-only predictions include quarantined selection diagnostics.',
                            'Selection-eligible mode requires nondeferred, orientation-sure selection; event comes from the timing reference.',
                            'Single-reviewer contact timing is not athlete identity or coaching-effectiveness validation.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('parent', 'native', 'base', 'current', 'evaluation', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    result = execute(args.parent, {k: getattr(args, k) for k in ('native', 'base', 'current')}, args.evaluation)
    write_json(args.output, result)
    print(json.dumps({study: {v: r['aggregate'] for v, r in versions.items()}
                      for study, versions in result['studies'].items()}, indent=2))


if __name__ == '__main__':
    main()
