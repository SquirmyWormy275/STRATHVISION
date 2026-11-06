"""Inventory a private multi-sport library without counting downloader intermediates.

The manifest is a snapshot, not a claim of full video decoding or coaching labels.
Files are hashed to EOF and probed; changed files are deferred. Originals are read only.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

VIDEO = {'.mov', '.mp4', '.m4v', '.mkv', '.webm', '.avi'}
COMPONENT = re.compile(r'\.(?:f\d+(?:-\d+)?|temp|partial)\.[^.]+$', re.I)
YOUTUBE = re.compile(r'^([A-Za-z0-9_-]{11}) - ')


def disposition(path):
    name = path.name.lower()
    if name.endswith(('.part', '.ytdl', '.tmp', '.crdownload')) or COMPONENT.search(name):
        return 'download_intermediate'
    if path.suffix.lower() in VIDEO:
        return 'candidate_video'
    return 'archive' if path.suffix.lower() == '.zip' else 'nonvideo'


def signature(path):
    s = path.stat()
    return {'bytes': s.st_size, 'mtime_ns': s.st_mtime_ns}


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(4 * 1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(data, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def inspect(root, item, known):
    path = root / item['relative_path']
    try:
        if signature(path) != item['signature']:
            raise ValueError('changed since snapshot')
        sha = digest(path)
        process = subprocess.run(['ffprobe', '-v', 'error', '-show_format', '-show_streams',
                                  '-of', 'json', str(path)], capture_output=True, text=True,
                                 timeout=60, check=True)
        data = json.loads(process.stdout)
        v = next(s for s in data['streams'] if s['codec_type'] == 'video')
        duration = float(data['format']['duration'])
        n, d = map(float, v['avg_frame_rate'].split('/'))
        fps = n / d
        if not all(math.isfinite(x) and x > 0 for x in (duration, fps, v['width'], v['height'])):
            raise ValueError('invalid duration, rate or dimensions')
        if signature(path) != item['signature']:
            raise ValueError('changed during verification')
        rotation = next((s['rotation'] for s in v.get('side_data_list', []) if 'rotation' in s), 0)
        width, height = v['width'], v['height']
        if abs(rotation) % 180 == 90:
            width, height = height, width
        source_id = YOUTUBE.match(path.name)
        return {**item, 'state': 'verified', 'sha256': sha, 'duration_s': duration,
                'fps': fps, 'width': width, 'height': height, 'rotation': rotation,
                'codec': v['codec_name'], 'color_transfer': v.get('color_transfer'),
                'audio_streams': sum(s['codec_type'] == 'audio' for s in data['streams']),
                'previously_inventoried': sha in known,
                'source_group': 'youtube:' + source_id[1] if source_id else 'sha256:' + sha}
    except (OSError, ValueError, KeyError, StopIteration, ZeroDivisionError, subprocess.SubprocessError) as exc:
        return {**item, 'state': 'deferred', 'reason': type(exc).__name__ + ': ' + str(exc)[:300]}


def summarize(rows):
    verified = [r for r in rows if r.get('state') == 'verified']
    unique = {}
    for row in verified:
        unique.setdefault(row['sha256'], row)
    return {'files': len(rows), 'dispositions': dict(Counter(r['disposition'] for r in rows)),
            'verified_video_files': len(verified), 'unique_video_payloads': len(unique),
            'duplicate_video_files': len(verified)-len(unique),
            'previously_inventoried_unique': sum(r['previously_inventoried'] for r in unique.values()),
            'new_unique': sum(not r['previously_inventoried'] for r in unique.values()),
            'unique_duration_s': sum(r['duration_s'] for r in unique.values()),
            'unique_bytes': sum(r['signature']['bytes'] for r in unique.values()),
            'deferred': sum(r.get('state') == 'deferred' for r in rows),
            'sports': {sport: {'unique': sum(r['sport'] == sport for r in unique.values()),
                               'new': sum(r['sport'] == sport and not r['previously_inventoried'] for r in unique.values())}
                       for sport in sorted({r['sport'] for r in unique.values()})}}


def run(root, output, known_paths, workers, priority=None):
    if output.exists():
        raise ValueError('Inventory already exists; use a new snapshot output')
    known = {r['sha256'] for p in known_paths for r in json.loads(p.read_text())['clips']}
    snapshot = output.with_name(output.stem + '-snapshot.json')
    progress = output.with_name(output.stem + '-progress.json')
    if snapshot.exists():
        document = json.loads(snapshot.read_text())
        if document['root'] != str(root.resolve()):
            raise ValueError('Snapshot root mismatch')
    else:
        rows = []
        for path in sorted(root.rglob('*')):
            if not path.is_file():
                continue
            relative = str(path.relative_to(root))
            sport = 'olympic_weightlifting' if relative.startswith('Olympic Weightlifting/') else 'woodchopping'
            rows.append({'relative_path': relative, 'sport': sport,
                         'disposition': disposition(path), 'signature': signature(path)})
        document = {'format': 'private-library/1', 'root': str(root.resolve()),
                    'snapshot_utc': datetime.now(timezone.utc).isoformat(), 'files': rows}
        write(snapshot, document)
    prior = json.loads(progress.read_text()) if progress.exists() else {}
    jobs = [r for r in document['files'] if r['disposition'] == 'candidate_video']
    if priority:
        order = {name: i for i, name in enumerate(json.loads(priority.read_text()))}
        jobs.sort(key=lambda r: order.get(r['relative_path'], len(order)))
    # A resume reuses a completed hash only when the frozen snapshot signature still matches.
    cache = {r['relative_path']: prior[r['relative_path']] for r in jobs
             if r['relative_path'] in prior and prior[r['relative_path']].get('state') == 'verified'
             and signature(root/r['relative_path']) == r['signature']}
    print('Snapshot', len(document['files']), 'files;', len(jobs), 'video candidates;', len(cache), 'cached', flush=True)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(inspect, root, r, known): r for r in jobs if r['relative_path'] not in cache}
        for future in as_completed(futures):
            row = future.result();cache[row['relative_path']] = row
            write(progress, cache)
            if len(cache) % 20 == 0 or row['state'] != 'verified':
                print('Verified/deferred', len(cache), '/', len(jobs), row['state'], row['relative_path'], flush=True)
    rows = [cache.get(r['relative_path'], r) for r in document['files']]
    document.update(files=rows, summary=summarize(rows), code_sha256=digest(Path(__file__)),
                    known_manifest_sha256=[digest(p) for p in known_paths],
                    completed_utc=datetime.now(timezone.utc).isoformat())
    write(output, document)
    print(json.dumps(document['summary'], indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--known', type=Path, action='append', default=[])
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--priority', type=Path, help='Optional ordered relative paths; all snapshot videos are still verified')
    args = parser.parse_args()
    run(args.root, args.output, args.known, args.workers, args.priority)
