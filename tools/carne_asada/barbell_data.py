"""Source-grouped barbell localization references, separate from axe and coaching labels."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

from footage import sha256, write_json
from new_dataset import prepare, validate_plan

VISIBILITY = {'visible', 'empty', 'uncertain', 'occluded', 'blurred', 'out_of_frame', 'unreviewed'}


def compatible_reference(document):
    """Adapt to the established box-scoring implementation; never change the public target."""
    if document.get('format') != 'barbell-reference/1':
        raise ValueError('Expected barbell-reference/1')
    result = copy.deepcopy(document)
    result['format'] = 'axe-reference/1'
    for row in result['windows']:
        if row['search_roi'] != [0., 0., 1., 1.]:
            raise ValueError('Barbell study requires full-frame inference')
        for frame in row['frames']:
            if frame['visibility'] not in VISIBILITY:
                raise ValueError('Unknown visibility')
            frame['head_box'] = frame.pop('barbell_box')
            if (frame['head_box'] is not None) != (frame['visibility'] == 'visible'):
                raise ValueError('Visible barbell requires exactly one box; unrated/empty cannot have a box')
    from axe_data import validate
    return validate(result)


def validate(parent, document, fitting):
    result = compatible_reference(document)
    validate_plan(parent, result, fitting)
    plan = json.loads((parent/'plan.json').read_text())
    groups = {}
    for source in plan['sources']:
        prior = groups.setdefault(source['group'], source['split'])
        if prior != source['split']:
            raise ValueError('Original upload crosses partitions')
    return result


def plan(selection_path, inventory_path, parent):
    if (parent/'plan.json').exists():
        raise ValueError('Preserve the frozen plan; use a new study directory')
    selection = json.loads(selection_path.read_text())
    inventory = json.loads(inventory_path.read_text())
    lookup = ({r['relative_path']: r for r in inventory['files']}
              if 'files' in inventory else inventory)
    rows = []
    for selected in selection['sources']:
        source = lookup.get(selected['relative_path'])
        if not source or source.get('state') != 'verified' or source['signature'] != selected['signature']:
            raise ValueError('Every selected source must match a verified snapshot record')
        rows.append({**source, 'split': selected['study_split'], 'group': source['source_group'],
                     'member': Path(source['relative_path']).name,
                     'frames': [{'frame_id': source['sha256'][:16]+'-'+str(i),
                                 'time_s': round(source['duration_s']*fraction, 6)}
                                for i, fraction in enumerate(selection['fractions'])]})
    if len({r['sha256'] for r in rows}) != len(rows):
        raise ValueError('Selected files include duplicate payloads; revise the study before pixels')
    write_json(parent/'plan.json', {'format': 'barbell-plan/1', 'sources': rows,
                                   'selection_sha256': sha256(selection_path),
                                   'inventory_sha256': sha256(inventory_path),
                                   'sampling_fractions': selection['fractions'],
                                   'target': selection['target'],
                                   'limitations': ['Upload-disjoint, not verified session/athlete independent.',
                                                   'Edited demonstrations may reuse scenes across different uploads.',
                                                   'Instructional pilot; not a representative competition benchmark.']})


def reference(parent, output):
    source_plan = json.loads((parent/'plan.json').read_text())
    annotations = json.loads((parent/'annotations.json').read_text())
    rows = []
    for s in source_plan['sources']:
        marks = annotations.get(s['sha256'], [None]*len(s['frames']))
        if len(marks) != len(s['frames']):
            raise ValueError('One annotation entry is required per planned frame')
        frames = []
        for f, mark in zip(s['frames'], marks):
            if mark is None:
                frames.append({'time_s': f['time_s'], 'barbell_box': None, 'visibility': 'unreviewed'})
            else:
                frames.append({'time_s': f['time_s'], **mark})
        rows.append({'window_id': 'barbell-'+s['sha256'][:16], 'clip_sha256': s['sha256'],
                     'source_name': s['relative_path'], 'split': s['split'], 'start_s': 0.,
                     'duration_s': s['duration_s'], 'rotation_cw': 0,
                     'search_roi': [0., 0., 1., 1.], 'frames': frames})
    document = {'format': 'barbell-reference/1', 'source_plan_sha256': sha256(parent/'plan.json'),
                'target': source_plan['target'], 'reviewer': 'Codex visual engineering references; no coaching labels',
                'windows': rows}
    compatible_reference(document)
    write_json(output, document)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['plan', 'sample', 'reference'])
    parser.add_argument('--parent', type=Path, required=True)
    parser.add_argument('--selection', type=Path)
    parser.add_argument('--inventory', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--partition', choices=['train', 'validation', 'test'])
    parser.add_argument('--freeze', type=Path)
    parser.add_argument('--model', type=Path)
    parser.add_argument('--workers', type=int, default=2)
    args = parser.parse_args()
    if args.action == 'plan':
        if not args.selection or not args.inventory: parser.error('plan needs --selection and --inventory')
        plan(args.selection, args.inventory, args.parent)
    elif args.action == 'reference':
        if not args.output: parser.error('reference needs --output')
        reference(args.parent, args.output)
    else:
        if not args.partition: parser.error('sample needs --partition')
        prepare(args.parent, args.partition, args.freeze, args.workers, args.model)
