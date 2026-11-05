from collections import defaultdict

import pytest

from new_dataset import split, prepare, validate_plan


def fixture():
    clips = [{'sha256': str(i) * 64, 'capture_day': f'2024-01-{i+1:02}',
              'duration_s': 10, 'previously_inventoried': False, 'archive_sha256': 'archive'}
             for i in range(9)]
    clips.append({**clips[0], 'sha256': 'other-same-day'})
    clips.append({**clips[0], 'sha256': 'old-copy', 'previously_inventoried': True})
    clips.append({**clips[0], 'sha256': 'undated', 'capture_day': None})
    return {'clips': clips}


def test_entire_capture_day_stays_together_and_exposed_days_cannot_be_holdouts():
    result = split(fixture(), [{'capture_day': '2024-01-01'}])
    groups = defaultdict(set)
    for row in result['sources']:
        groups[row['group']].add(row['split'])
    assert all(len(partitions) == 1 for partitions in groups.values())
    assert groups['2024-01-01'] == {'train'}
    assert next(r for r in result['sources'] if r['sha256'] == 'undated')['split'] == 'train'
    assert not any(r['sha256'] == 'old-copy' for r in result['sources'])
    assert {r['split'] for r in result['sources']} == {'train', 'validation', 'test'}
    assert result == split(fixture(), [{'capture_day': '2024-01-01'}])


def test_test_frame_preparation_requires_a_matching_model_freeze(tmp_path):
    import json
    (tmp_path/'plan.json').write_text(json.dumps({'sources': []}))
    with pytest.raises(ValueError, match='unopened'):
        prepare(tmp_path, 'test', None, 1)


def test_test_pixels_stay_closed_if_actual_weights_changed(tmp_path):
    import json
    from footage import sha256
    plan = tmp_path/'plan.json';plan.write_text(json.dumps({'sources': []}))
    frozen = tmp_path/'freeze.json';frozen.write_text(json.dumps({'plan_sha256':sha256(plan),'model_sha256':'old'}))
    model = tmp_path/'model.pt';model.write_bytes(b'changed')
    with pytest.raises(ValueError, match='Actual model weights'):
        prepare(tmp_path, 'test', frozen, 1, model)
    assert not (tmp_path/'frames/test').exists()


def annotated_plan(tmp_path):
    import json
    from footage import sha256
    sources = [{'sha256': name, 'split': part, 'frames': [{'time_s': t} for t in [1., 3., 5., 7.]]}
               for name, part in [('a', 'train'), ('b', 'validation'), ('c', 'test')]]
    path = tmp_path/'plan.json';path.write_text(json.dumps({'sources': sources}))
    return {'source_plan_sha256': sha256(path), 'windows': [
        {'clip_sha256': r['sha256'], 'split': r['split'], 'frames': [
            {**f, 'visibility': 'unreviewed' if r['split']=='test' else 'uncertain'} for f in r['frames']]}
        for r in sources]}


def test_fit_guard_allows_unopened_test_but_requires_complete_fit_review(tmp_path):
    document = annotated_plan(tmp_path)
    validate_plan(tmp_path, document, True)
    document['windows'][1]['frames'][0]['visibility'] = 'unreviewed'
    with pytest.raises(ValueError, match='Review all'):
        validate_plan(tmp_path, document, True)


@pytest.mark.parametrize('change', ['split', 'time', 'missing', 'duplicate'])
def test_fit_guard_rejects_source_or_sampling_changes(tmp_path, change):
    document = annotated_plan(tmp_path)
    if change == 'split': document['windows'][0]['split'] = 'test'
    if change == 'time': document['windows'][1]['frames'][0]['time_s'] += .1
    if change == 'missing': document['windows'].pop()
    if change == 'duplicate': document['windows'].append(document['windows'][0])
    with pytest.raises(ValueError): validate_plan(tmp_path, document, True)


def test_only_frozen_training_burst_times_can_be_added(tmp_path):
    import json
    from footage import sha256
    document = annotated_plan(tmp_path)
    path = tmp_path/'training-augmentation-plan.json'
    augmentation = {'partition': 'train', 'source_plan_sha256': document['source_plan_sha256'],
                    'candidates': [{'clip_sha256': 'a', 'time_s': 5.2}]}
    path.write_text(json.dumps(augmentation));document['training_augmentation_sha256'] = sha256(path)
    document['windows'][0]['frames'].append({'time_s': 5.2, 'visibility': 'visible'})
    validate_plan(tmp_path, document, True)
    document['windows'][1]['frames'].append({'time_s': 5.2, 'visibility': 'visible'})
    with pytest.raises(ValueError, match='Temporal samples'): validate_plan(tmp_path, document, True)
    document['windows'][1]['frames'].pop()
    augmentation['candidates'].append({'clip_sha256': 'c', 'time_s': 5.2})
    path.write_text(json.dumps(augmentation));document['training_augmentation_sha256'] = sha256(path)
    with pytest.raises(ValueError, match='leaks'): validate_plan(tmp_path, document, True)
