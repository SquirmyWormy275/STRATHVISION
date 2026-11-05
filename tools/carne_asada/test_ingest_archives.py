import hashlib
from pathlib import Path
import stat
import zipfile

import pytest

from ingest_archives import extract, member_path


def test_crc_verified_archive_preserves_payload_and_original(tmp_path):
    archive = tmp_path / 'source.zip'
    payload = b'private synthetic bytes'
    with zipfile.ZipFile(archive, 'w') as z:
        z.writestr('training/clip.txt', payload)
    original = archive.read_bytes()
    result = extract(archive, tmp_path / 'media')
    row = result['members'][0]
    assert (tmp_path / 'media' / row['relative_path']).read_bytes() == payload
    assert row['sha256'] == hashlib.sha256(payload).hexdigest()
    assert row['bytes'] == len(payload) and archive.read_bytes() == original


@pytest.mark.parametrize('name', ['../outside.mov', '/absolute.mov', 'nested/../../outside.mov', r'..\outside.mov'])
def test_traversal_is_rejected_before_writing(name):
    with pytest.raises(ValueError, match='Unsafe'):
        member_path(name)


def test_archive_symlinks_are_rejected(tmp_path):
    archive = tmp_path / 'links.zip'
    info = zipfile.ZipInfo('link.mov')
    info.create_system = 3
    info.external_attr = (stat.S_IFLNK | 0o777) << 16
    with zipfile.ZipFile(archive, 'w') as z:
        z.writestr(info, '/outside.mov')
    with pytest.raises(ValueError, match='symlinks'):
        extract(archive, tmp_path / 'media')


def test_corrupt_member_does_not_become_an_extracted_clip(tmp_path):
    archive = tmp_path / 'broken.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_STORED) as z:
        z.writestr('clip.txt', b'unique-payload-for-crc')
    data = archive.read_bytes().replace(b'unique-payload-for-crc', b'broken-payload-for-crc')
    archive.write_bytes(data)
    with pytest.raises(zipfile.BadZipFile):
        extract(archive, tmp_path / 'media')
    assert not list((tmp_path / 'media').rglob('clip.txt'))
