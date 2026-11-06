"""Verify private footage ZIPs, preserve aliases, and inventory every video."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import stat
import subprocess
import zipfile

from deduplicate import deduplicate
from footage import sha256, write_json

VIDEO = {'.mov', '.mp4', '.m4v', '.mkv', '.webm', '.avi'}


def member_path(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name or not path.parts:
        raise ValueError('Unsafe archive member path')
    return Path(*path.parts)


def extract(archive, root):
    before = archive.stat()
    archive_sha = sha256(archive)
    folder = archive.stem + '-' + archive_sha[:8]
    rows = []
    with zipfile.ZipFile(archive) as z:
        names = set()
        for info in z.infolist():
            relative = member_path(info.filename)
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError('Archive symlinks are unsupported')
            if info.is_dir():
                continue
            if relative in names:
                raise ValueError('Repeated archive member path')
            names.add(relative)
            destination = root / folder / relative
            if not destination.resolve().is_relative_to(root.resolve()):
                raise ValueError('Archive destination escapes private root')
            destination.parent.mkdir(parents=True, exist_ok=True)
            temporary = destination.with_name(destination.name + '.pending')
            digest = hashlib.sha256()
            size = 0
            # Reading to EOF also checks the member CRC. Original ZIPs stay intact.
            with z.open(info) as source, temporary.open('wb') as out:
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    digest.update(block);size += len(block);out.write(block)
            if size != info.file_size:
                raise ValueError('Truncated archive member')
            temporary.replace(destination)
            rows.append({'archive': archive.name, 'archive_sha256': archive_sha,
                         'member': info.filename, 'sha256': digest.hexdigest(),
                         'relative_path': str(destination.relative_to(root)), 'bytes': size,
                         'crc32': f'{info.CRC:08x}'})
    after = archive.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ValueError('Archive changed during verification; download is not stable')
    return {'name': archive.name, 'sha256': archive_sha, 'bytes': before.st_size, 'members': rows}


def metadata(path):
    doc = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-show_format',
                                            '-show_streams', '-of', 'json', str(path)]))
    video = next(s for s in doc['streams'] if s['codec_type'] == 'video')
    n, d = video['avg_frame_rate'].split('/')
    fps = float(n) / float(d)
    rotation = next((s['rotation'] for s in video.get('side_data_list', []) if 'rotation' in s), 0)
    width, height = video['width'], video['height']
    if abs(rotation) % 180 == 90:
        width, height = height, width
    tags = {**doc['format'].get('tags', {}), **video.get('tags', {})}
    # Preserve the recording's local calendar day when its offset is known.
    # UTC midnight can split a single daytime event in Australia/New Zealand.
    creation = tags.get('com.apple.quicktime.creationdate') or tags.get('creation_time')
    day = None
    if creation:
        try:
            parsed = datetime.fromisoformat(creation.replace('Z', '+00:00'))
            if 2000 <= parsed.year <= datetime.now().year:
                day = parsed.date().isoformat()
        except ValueError:
            pass
    return {'duration_s': float(doc['format']['duration']), 'fps': fps, 'width': width,
            'height': height, 'rotation': rotation, 'codec': video['codec_name'],
            'color_transfer': video.get('color_transfer'), 'capture_time': creation, 'capture_day': day}


def ingest(directory, output, known, workers):
    archives = sorted(p for p in directory.rglob('*') if p.is_file() and p.suffix.lower() == '.zip')
    if not archives:
        raise ValueError('No ZIP archives found')
    root = output / 'media';root.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        verified = list(pool.map(lambda path: extract(path, root), archives))
    write_json(output / 'archive-inventory.json', {'format': 'verified-footage-archives/1', 'archives': verified})
    old = {r['sha256'] for path in known for r in json.loads(path.read_text())['clips']}
    members = [r for a in verified for r in a['members']]
    clips = []
    for row in members:
        if Path(row['member']).suffix.lower() not in VIDEO:
            continue
        clips.append({**row, **metadata(root / row['relative_path']),
                      'event_id': None, 'assignments': {}, 'previously_inventoried': row['sha256'] in old})
    document = deduplicate({'format': 'carne-footage/1', 'clips': clips, 'athletes': []})
    for clip in document['clips']:
        clip['aliases'] = [r['relative_path'] for r in clips if r['sha256'] == clip['sha256']]
    document['archive_count'] = len(archives)
    document['known_unique_video_count'] = sum(r['previously_inventoried'] for r in document['clips'])
    document['new_unique_video_count'] = sum(not r['previously_inventoried'] for r in document['clips'])
    document['source_duration_s'] = sum(r['duration_s'] for r in document['clips'])
    document['nonvideo_members'] = [r for r in members if Path(r['member']).suffix.lower() not in VIDEO]
    document['ingest_code_sha256'] = sha256(Path(__file__))
    write_json(output / 'manifest.json', document)
    print(json.dumps({k: document[k] for k in ['archive_count', 'source_video_file_count', 'unique_video_count',
                                              'known_unique_video_count', 'new_unique_video_count', 'source_duration_s']}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--known', type=Path, action='append', default=[])
    parser.add_argument('--workers', type=int, default=2)
    args = parser.parse_args()
    ingest(args.directory, args.output, args.known, args.workers)


if __name__ == '__main__':
    main()
