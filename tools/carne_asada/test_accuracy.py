import pytest
import json
from pathlib import Path
import subprocess
import sys

from motion_contacts import extension_peaks
from score_accuracy import contact_matches, rates, score_window, validate_split
from target import SpatialTarget, rotate_box, rotate_point


def test_rotation_coordinates_round_trip():
    for rotation in (0, 90, 180, 270):
        assert rotate_point(rotate_point([.2, .7], rotation), (360 - rotation) % 360) == pytest.approx([.2, .7])
        assert rotate_box(rotate_box([.1, .2, .4, .8], rotation), (360 - rotation) % 360) == pytest.approx([.1, .2, .4, .8])


def test_static_handling_is_not_counted_as_a_stroke():
    times = [i / 15 for i in range(120)]
    assert extension_peaks(times, [.2] * len(times)) == []
    values = [max(0, 1 - abs(t - 2)) for t in times]
    predicted = extension_peaks(times, values)
    assert len(predicted) == 1 and 1.7 <= predicted[0] <= 2.1


def test_target_ignores_nearby_spectator_and_cuts_start_new_segment():
    target = SpatialTarget([.3, .5])
    actor = [.2, .1, .4, .9, .8]
    spectator = [.7, .2, .9, .9, .99]
    assert target.update(0, [actor, spectator])[1] == actor
    assert target.update(.2, [spectator]) is None
    assert target.update(.4, [actor, spectator])[0] == 1
    assert target.update(.6, [actor], cut=True) is None
    target.reseed([.3, .5])
    assert target.update(.6, [actor])[0] == 2
    assert target.update(2, [actor]) is None
    target.reseed([.3, .5])
    assert target.update(2, [actor])[0] == 3


def test_returning_detection_after_loss_cannot_silently_select_a_bystander():
    target = SpatialTarget([.3, .5])
    target.update(0, [[.2, .1, .4, .9, .8]])
    assert target.update(1, [[.2, .1, .4, .9, .99]]) is None
    assert target.lost


def test_target_abstains_on_ambiguous_overlap():
    target = SpatialTarget([.3, .5])
    assert target.update(0, [[.2, .1, .4, .9, .8], [.21, .1, .41, .9, .81]]) is None


def test_duplicate_predictions_never_count_as_multiple_true_contacts():
    result = contact_matches([1, 1.1, 3], [[.95, 1.05], [1.95, 2.05]], .2)
    assert (result['tp'], result['fp'], result['fn']) == (1, 2, 1)


def test_contact_matching_maximizes_count_instead_of_greedy_nearest():
    result = contact_matches([1.15, 1.35], [[1, 1], [1.2, 1.2]], .2)
    assert result['tp'] == 2
    assert rates({'tp': 0, 'fp': 0, 'fn': 0})['f1'] is None


def test_duplicate_download_cannot_leak_across_partitions():
    with pytest.raises(ValueError, match='leaks'):
        validate_split([{'window_id': 'a', 'clip_sha256': 'same', 'split': 'development'},
                        {'window_id': 'b', 'clip_sha256': 'same', 'split': 'test'}])


def fixture():
    reference = {'window_id': 'one', 'clip_sha256': 'sha', 'split': 'test',
                 'target_anchors': [{'time_s': 1, 'visible': True, 'point': [.3, .5]}],
                 'reference_rotation_cw': 0, 'score_interval_s': [.3, 7.7],
                 'ignored_intervals_s': [], 'contact_intervals_s': []}
    prediction = {'window_id': 'one', 'clip_sha256': 'sha', 'sample_rate': 5,
                  'rotation_cw': 0, 'observations': [{'time_s': 0, 'segment': 1, 'box_raw': [.2, .1, .4, .9]}]}
    contacts = {'window_id': 'one', 'candidate_strokes': 0, 'usable_strokes': 0,
                'failures': {}, 'contact_times_s': [1]}
    return reference, prediction, contacts


def test_missing_frame_is_not_filled_with_stale_selection():
    result = score_window(*fixture(), .2)
    assert result['target_missing'] == 1 and result['target_hits'] == 0
    assert result['contacts']['fp'] == 1


def test_hidden_contacts_are_unrated_not_negative_examples():
    reference, prediction, contacts = fixture()
    reference['contact_intervals_s'] = None
    assert score_window(reference, prediction, contacts, .2)['contacts'] is None


def test_source_mismatch_is_rejected():
    reference, prediction, contacts = fixture()
    prediction['clip_sha256'] = 'wrong'
    with pytest.raises(ValueError, match='source'):
        score_window(reference, prediction, contacts, .2)


def test_stale_contact_replay_is_rejected():
    reference, prediction, contacts = fixture()
    prediction['sources_sha256'] = {'target.py': 'new'}
    contacts['prediction_sources_sha256'] = {'target.py': 'old'}
    with pytest.raises(ValueError, match='different inference'):
        score_window(reference, prediction, contacts, .2)


def test_test_inference_refuses_changed_source_before_loading_models(tmp_path):
    inputs, detector, pose, freeze = [tmp_path / n for n in ('inputs.json', 'detector', 'pose', 'freeze.json')]
    inputs.write_text('{}')
    detector.write_bytes(b'not a model')
    pose.write_bytes(b'not a model')
    freeze.write_text(json.dumps({'inference': {}}))
    result = subprocess.run([sys.executable, str(Path(__file__).with_name('predict_accuracy.py')),
        '--inputs', str(inputs), '--detector', str(detector), '--pose', str(pose),
        '--root', str(tmp_path), '--output', str(tmp_path / 'results'),
        '--variant', 'revised', '--partition', 'test', '--freeze', str(freeze)], capture_output=True, text=True)
    assert result.returncode == 2
    assert 'Frozen inference source, inputs or models changed' in result.stderr
    assert not (tmp_path / 'results').exists()
