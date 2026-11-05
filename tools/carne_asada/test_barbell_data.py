import copy
import json

import pytest

import barbell_data as data
from footage import sha256


def reference():
    return {'format': 'barbell-reference/1', 'source_plan_sha256': 'pending', 'windows': [
        {'window_id': 'barbell-a', 'clip_sha256': 'a', 'source_name': 'a.mp4',
         'split': 'train', 'start_s': 0., 'duration_s': 10., 'rotation_cw': 0,
         'search_roi': [0., 0., 1., 1.],
         'frames': [{'time_s': 3.5, 'barbell_box': [.1,.4,.9,.6], 'visibility': 'visible'}]}]}


def test_adapter_preserves_public_barbell_target_and_rejects_hidden_boxes():
    doc = reference();saved = copy.deepcopy(doc)
    adapted = data.compatible_reference(doc)
    assert doc == saved
    assert adapted['windows'][0]['frames'][0]['head_box'] == [.1,.4,.9,.6]
    doc['windows'][0]['frames'][0]['visibility'] = 'uncertain'
    with pytest.raises(ValueError, match='requires exactly one box'):
        data.compatible_reference(doc)


def test_roi_cannot_be_tightened_to_ground_truth():
    doc = reference();doc['windows'][0]['search_roi'] = [.1,.4,.9,.6]
    with pytest.raises(ValueError, match='full-frame'):
        data.compatible_reference(doc)


def test_same_upload_cannot_cross_split_even_with_different_hashes(tmp_path):
    doc = reference();second = copy.deepcopy(doc['windows'][0]);second.update(window_id='barbell-b',clip_sha256='b',split='test')
    doc['windows'].append(second)
    plan = {'sources': [{'sha256': r['clip_sha256'], 'split': r['split'], 'group': 'youtube:same',
                          'frames': [{'time_s': 3.5}]} for r in doc['windows']]}
    (tmp_path/'plan.json').write_text(json.dumps(plan));doc['source_plan_sha256'] = sha256(tmp_path/'plan.json')
    with pytest.raises(ValueError, match='upload crosses'):
        data.validate(tmp_path, doc, True)


def test_unreviewed_validation_and_reassigned_time_rejected(tmp_path):
    doc = reference();row = doc['windows'][0];row['split'] = 'validation'
    plan = {'sources': [{'sha256': 'a', 'split': 'validation', 'group': 'youtube:a', 'frames':[{'time_s':3.5}]}]}
    (tmp_path/'plan.json').write_text(json.dumps(plan));doc['source_plan_sha256'] = sha256(tmp_path/'plan.json')
    row['frames'][0].update(barbell_box=None,visibility='unreviewed')
    with pytest.raises(ValueError,match='Review all'):
        data.validate(tmp_path,doc,True)
    row['frames'][0].update(visibility='empty',time_s=5.)
    with pytest.raises(ValueError,match='Temporal samples'):
        data.validate(tmp_path,doc,True)
