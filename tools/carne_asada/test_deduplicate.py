from copy import deepcopy

import pytest

from deduplicate import deduplicate


def fixture():
    clip = {'index': 1, 'relative_path': 'Competition/IMG_8055.MOV',
            'sha256': 'a' * 64, 'bytes': 100, 'duration_s': 32.0017,
            'fps': 30, 'width': 1920, 'height': 1080, 'rotation': 0,
            'event_id': None, 'assignments': {}}
    copy = {**deepcopy(clip), 'index': 2,
            'relative_path': 'Competition/IMG_8055(1).MOV'}
    other = {**deepcopy(clip), 'index': 3,
             'relative_path': 'Training/other.MOV', 'sha256': 'b' * 64}
    return {'format': 'carne-footage/1', 'clips': [copy, clip, other]}


def test_duplicate_download_cannot_double_analysis_duration():
    source = fixture()
    before = deepcopy(source)
    result = deduplicate(source)
    assert source == before
    assert result['source_video_file_count'] == 3
    assert result['unique_video_count'] == 2
    assert sum(c['duration_s'] for c in result['clips']) == 64.0034
    assert [c['index'] for c in result['clips']] == [1, 2]
    assert result['duplicate_files'] == [{
        'relative_path': 'Competition/IMG_8055(1).MOV',
        'sha256': 'a' * 64, 'duplicate_of': 'Competition/IMG_8055.MOV'}]


def test_conflicting_annotations_on_identical_content_require_resolution():
    source = fixture()
    source['clips'][0]['event_id'] = 'underhand'
    with pytest.raises(ValueError, match='Conflicting event_id'):
        deduplicate(source)
