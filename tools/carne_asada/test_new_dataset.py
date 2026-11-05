from collections import defaultdict

import pytest

from new_dataset import split, prepare


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
