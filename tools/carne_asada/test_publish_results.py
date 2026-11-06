import hashlib
import json
import subprocess
import sys
from pathlib import Path


def publish_fixture(tmp_path, scope=None):
    directory = Path(__file__).parent
    pipeline_hash = hashlib.sha256((directory / 'footage.py').read_bytes()).hexdigest()
    (tmp_path / 'tracks').mkdir()
    (tmp_path / 'tracks' / 'one.json').write_text(json.dumps({
        'pipeline_sha256': pipeline_hash,
        'detector_sha256': 'a' * 64,
        'pose_sha256': 'b' * 64,
    }))
    result = {
        'format': 'gurr-experiment/1', 'date': '2026-11-04',
        'experiment': 'test fixture', 'clip_count': 1, 'duration_s': 1,
        'sample_rate': 5, 'sampled_frames': 5, 'frames_with_people': 1,
        'frames_with_multiple_people': 0, 'person_detections': 1, 'pose_samples': 1,
        'pipeline_elapsed_s': 1, 'named_athlete_profiles_built': 0,
        'confirmed_coach_marks': 0, 'claimed_technique_improvement': False,
        'events_are_candidate_passes': True, 'caveats': [], 'aggregate': {}, 'clips': [],
        'track_quality': [{'private': 'DO_NOT_PUBLISH'}],
    }
    source, destination = tmp_path / 'input.json', tmp_path / 'public.json'
    source.write_text(json.dumps(result))
    command = [sys.executable, str(directory / 'publish_results.py'), str(source), str(destination)]
    if scope is not None:
        scope_file = tmp_path / 'scope.json'
        scope_file.write_text(json.dumps(scope))
        command.extend(['--scope', str(scope_file)])
    subprocess.run(command, check=True, capture_output=True)
    return json.loads(destination.read_text()), destination.read_text()


def test_unknown_collection_completeness_defaults_to_partial(tmp_path):
    result, text = publish_fixture(tmp_path)
    assert result['corpus_scope']['collection_complete'] is False
    assert 'DO_NOT_PUBLISH' not in text
    assert 'track_quality' not in result


def test_exact_archive_scope_is_retained(tmp_path):
    scope = {'collection_complete': False, 'archive_name': 'collection-001.zip',
             'archive_sha256': 'c' * 64, 'archive_video_entries': 1}
    result, _ = publish_fixture(tmp_path, scope)
    assert result['corpus_scope'] == scope
