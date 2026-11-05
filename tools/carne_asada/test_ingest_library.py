from pathlib import Path
import ingest_library as lib


def test_download_components_are_not_independent_videos():
    for name in ('id - title.f401.mp4', 'id - title.f140-19.m4a', 'id - title.temp.mp4',
                 'id - title.mp4.part', 'id - title.webm.ytdl'):
        assert lib.disposition(Path(name)) == 'download_intermediate'
    assert lib.disposition(Path('IMG_1234.MOV')) == 'candidate_video'
    assert lib.disposition(Path('abc - temperature.mp4')) == 'candidate_video'
    assert lib.disposition(Path('source.zip')) == 'archive'


def test_changed_snapshot_is_deferred_before_hashing(tmp_path, monkeypatch):
    path = tmp_path/'a.mp4';path.write_bytes(b'changed')
    monkeypatch.setattr(lib, 'digest', lambda p: (_ for _ in ()).throw(AssertionError('must not hash')))
    row = lib.inspect(tmp_path, {'relative_path': 'a.mp4', 'signature': {'bytes': 1, 'mtime_ns': 0}}, set())
    assert row['state'] == 'deferred'
    assert 'changed since snapshot' in row['reason']


def test_summary_counts_payloads_not_aliases():
    base = {'disposition': 'candidate_video', 'state': 'verified', 'sha256': 'same',
            'sport': 'woodchopping', 'duration_s': 10, 'signature': {'bytes': 100},
            'previously_inventoried': True}
    result = lib.summarize([base, dict(base), {**base, 'sha256': 'new',
                            'sport': 'olympic_weightlifting', 'previously_inventoried': False}])
    assert result['unique_video_payloads'] == 2
    assert result['duplicate_video_files'] == 1
    assert result['new_unique'] == 1
    assert result['unique_duration_s'] == 20
