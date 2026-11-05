import json

import pytest

from footage import sha256
from library_audit import open_seal, reserved


def test_test_seal_follows_payload_aliases():
    selection = {'sources': [{'relative_path': 'test.mp4', 'study_split': 'test'},
                             {'relative_path': 'train.mp4', 'study_split': 'train'}]}
    files = [{'relative_path': 'test.mp4', 'sha256': 'same'},
             {'relative_path': 'alias.mp4', 'sha256': 'same'},
             {'relative_path': 'train.mp4', 'sha256': 'different'}]
    sealed = reserved(selection, files)
    assert files[1]['sha256'] in sealed
    assert files[2]['sha256'] not in sealed


def test_seal_requires_actual_weights_and_matching_source_selection(tmp_path):
    weights = tmp_path/'model.pt';weights.write_bytes(b'frozen weights')
    plan = tmp_path/'plan.json'
    plan.write_text(json.dumps({'sources': [{'relative_path': 'test.mp4', 'split': 'test'}]}))
    freeze = tmp_path/'freeze.json'
    freeze.write_text(json.dumps({'model_sha256': sha256(weights), 'plan_sha256': sha256(plan)}))
    selection = {'sources': [{'relative_path': 'test.mp4', 'study_split': 'test'}]}
    open_seal(selection, freeze, weights, plan)
    with pytest.raises(ValueError, match='different source'):
        open_seal({'sources': []}, freeze, weights, plan)
    weights.write_bytes(b'changed weights')
    with pytest.raises(ValueError, match='Actual frozen weights'):
        open_seal(selection, freeze, weights, plan)
