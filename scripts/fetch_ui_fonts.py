#!/usr/bin/env python3
"""Provision pinned OFL fonts at build time; app runtime stays offline."""
from __future__ import annotations
import base64
import hashlib
import json
from pathlib import Path
import tempfile
import time
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1] / 'apps/strathvision/assets/fonts'
FILES = {
    'BarlowSemiCondensed-Bold.ttf': ('google/fonts', 'ee04b09e31e98d2509354d7003797ec6540e796f'),
    'BarlowSemiCondensed-ExtraBoldItalic.ttf': ('google/fonts', '37c54561dc3c728e07c0178de063fe7fac94c968'),
    'SourceSans3-Regular.ttf': ('adobe-fonts/source-sans', 'c5dd0b88cc8ff4edd7ebdcefee0290df15529657'),
    'SourceSans3-Semibold.ttf': ('adobe-fonts/source-sans', '4aff9a3aea9b5f1e746f03ed40e1b293740dc8a2'),
    'SourceSans3-Bold.ttf': ('adobe-fonts/source-sans', '85693ccc852fbd7fa4ae9d89d6ccbf6d38f8e0f0'),
    'OFL-Barlow.txt': ('google/fonts', '2f22ba6ca4dbc12145ae40b14c3368f387cba0e2'),
    'OFL-SourceSans.txt': ('adobe-fonts/source-sans', '22c601b82f29fc6bb801445098c9f23ffdca4f94'),
}

def blob_sha(data: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()

def fetch(repo: str, sha: str) -> bytes:
    request = Request(f'https://api.github.com/repos/{repo}/git/blobs/{sha}',
        headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'strathvision-font-build'})
    for attempt in range(3):
        try:
            with urlopen(request, timeout=30) as response:
                payload = json.loads(response.read(4 * 1024 * 1024))
            data = base64.b64decode(payload['content'])
            if payload.get('encoding') != 'base64' or blob_sha(data) != sha:
                raise ValueError('Font content does not match its pinned Git blob')
            return data
        except Exception:
            if attempt == 2:
                raise
            time.sleep(1 + attempt)
    raise RuntimeError('Unreachable')

def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    for name, (repo, sha) in FILES.items():
        target = ROOT / name
        if target.is_symlink():
            raise ValueError(f'Refusing symlink: {target}')
        if target.exists():
            if blob_sha(target.read_bytes()) != sha:
                raise ValueError(f'Refusing unexpected local font/license: {target}')
            continue
        data = fetch(repo, sha)
        if name.endswith('.ttf') and data[:4] not in (b'\x00\x01\x00\x00', b'OTTO', b'ttcf'):
            raise ValueError(f'Invalid font header: {name}')
        with tempfile.NamedTemporaryFile(dir=ROOT, delete=False) as output:
            temporary = Path(output.name)
            output.write(data)
        try:
            if target.exists():
                raise ValueError(f'Destination appeared during provisioning: {target}')
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    print(f'Verified {len(FILES)} pinned font/license assets; runtime remains offline.')

if __name__ == '__main__':
    main()
