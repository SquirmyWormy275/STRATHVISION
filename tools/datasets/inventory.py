"""Read-only local footage inventory. Linux/POSIX; Python standard library + ffprobe."""
import argparse
from collections import Counter
from contextlib import contextmanager
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

FORMAT = 'footage-inventory/1'
VIDEO = {'.mov', '.mp4', '.m4v', '.mkv', '.webm', '.avi', '.mts', '.m2ts', '.mpeg', '.mpg'}
AUDIO = {'.wav', '.m4a', '.mp3', '.flac', '.ogg', '.aac'}
COMPONENT = re.compile(r'\.(?:f\d+(?:-\d+)?|temp|partial)\.[^.]+$', re.I)
UPLOAD = re.compile(r'^([A-Za-z0-9_-]{11}) - ')


def utc():
    return datetime.now(timezone.utc).isoformat()


def sha256(path):
    with Path(path).open('rb') as stream:
        return hash_stream(stream)


def hash_stream(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()


def write_json(path, data):
    """Only called in a newly reserved output directory; publish complete JSON atomically."""
    temporary = path.with_suffix(path.suffix + '.tmp')
    with temporary.open('x', encoding='utf-8') as stream:
        json.dump(data, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def reserve_output(root, output):
    root = Path(root).resolve(strict=True)
    if not root.is_dir():
        raise ValueError('Source root must be a directory')
    output = Path(output).resolve()
    if output == root or root in output.parents:
        raise ValueError('Output must be outside the source tree')
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    return root, output


def mount_identity(root, expected_uuid=None):
    """Observe the filesystem containing root; never mount or repair a volume."""
    result = subprocess.run(['findmnt', '--json', '--target', str(root),
                             '--output', 'TARGET,SOURCE,FSTYPE,UUID,OPTIONS'],
                            capture_output=True, text=True, timeout=10, check=True)
    mounts = json.loads(result.stdout)['filesystems']
    if len(mounts) != 1:
        raise ValueError('Cannot establish one source mount')
    mount = mounts[0]
    if expected_uuid and (mount.get('uuid') or '').lower() != expected_uuid.lower():
        raise ValueError('Source is not on the expected mounted volume UUID')
    return mount


def signature(info):
    # Access time is deliberately excluded: a read can update it on a writable mount.
    return {key: getattr(info, 'st_' + key) for key in
            ('dev', 'ino', 'size', 'mtime_ns', 'ctime_ns', 'mode')}


def disposition(path):
    name = path.name.lower()
    if name.endswith(('.part', '.ytdl', '.tmp', '.crdownload')) or COMPONENT.search(name):
        return 'download_intermediate'
    if path.suffix.lower() in VIDEO:
        return 'video'
    if path.suffix.lower() in AUDIO:
        return 'audio'
    if path.suffix.lower() in {'.zip', '.7z', '.rar', '.tar', '.gz'}:
        return 'archive'
    return 'other'


@contextmanager
def open_source(root, relative):
    """Open each path component relative to a directory FD, refusing symlinks."""
    parts = Path(relative).parts
    if not parts or Path(relative).is_absolute() or any(p in {'.', '..'} for p in parts):
        raise ValueError('Invalid relative source path')
    directory = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        device = os.fstat(directory).st_dev
        for part in parts[:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = child
            if os.fstat(directory).st_dev != device:
                raise ValueError('Nested filesystem is excluded')
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(fd, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_dev != device:
                raise ValueError('Only regular files on the source filesystem are allowed')
            yield stream
    finally:
        os.close(directory)


def snapshot(root):
    rows, errors = [], []

    def walk(directory_fd, relative, device):
        try:
            with os.scandir(directory_fd) as entries:
                names = sorted(entry.name for entry in entries)
        except OSError as exc:
            errors.append({'path': relative.as_posix(), 'error': type(exc).__name__})
            return
        for name in names:
            path = relative / name
            row = {'path': path.as_posix()}
            try:
                info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                row['signature'] = signature(info)
                if stat.S_ISLNK(info.st_mode):
                    row.update(disposition='symlink', state='excluded')
                elif info.st_dev != device:
                    row.update(disposition='nested_filesystem', state='excluded')
                elif stat.S_ISDIR(info.st_mode):
                    child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                    dir_fd=directory_fd)
                    try:
                        actual = os.fstat(child)
                        if (actual.st_dev, actual.st_ino) != (info.st_dev, info.st_ino):
                            raise ValueError('Directory changed during traversal')
                        walk(child, path, device)
                    finally:
                        os.close(child)
                    continue
                elif stat.S_ISREG(info.st_mode):
                    kind = disposition(path)
                    row.update(disposition=kind, state='pending' if kind in {'video', 'audio'} else 'excluded')
                else:
                    row.update(disposition='special_file', state='excluded')
            except (OSError, ValueError) as exc:
                row.update(disposition='unknown', state='error', error=type(exc).__name__)
            rows.append(row)
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        walk(fd, Path('.'), os.fstat(fd).st_dev)
    finally:
        os.close(fd)
    return sorted(rows, key=lambda r: r['path']), errors


def number(value):
    try:
        result = float(Fraction(str(value)))
        return result if math.isfinite(result) else None
    except (ValueError, ZeroDivisionError, OverflowError):
        return None


def metadata(document):
    streams = []
    for source in document.get('streams', []):
        kind = source.get('codec_type')
        if kind not in {'video', 'audio'}:
            continue
        # Cover art is not footage.
        if kind == 'video' and source.get('disposition', {}).get('attached_pic'):
            continue
        row = {key: source.get(key) for key in
               ('index', 'codec_type', 'codec_name', 'profile', 'time_base', 'pix_fmt',
                'color_space', 'color_transfer', 'color_primaries', 'sample_rate', 'channels')}
        row['duration_s'] = number(source.get('duration'))
        row['creation_time_tag'] = source.get('tags', {}).get('creation_time')
        if kind == 'video':
            width, height = source.get('width'), source.get('height')
            if not isinstance(width, int) or not isinstance(height, int) or min(width, height) <= 0:
                raise ValueError('Invalid video dimensions')
            rotation = next((s['rotation'] for s in source.get('side_data_list', []) if 'rotation' in s),
                            source.get('tags', {}).get('rotate'))
            rotation = number(rotation)
            row.update(width=width, height=height, rotation_degrees=rotation,
                       display_width=height if rotation is not None and abs(rotation) % 180 == 90 else width,
                       display_height=width if rotation is not None and abs(rotation) % 180 == 90 else height,
                       avg_frame_rate=source.get('avg_frame_rate'),
                       nominal_frame_rate=source.get('r_frame_rate'),
                       fps=number(source.get('avg_frame_rate')),
                       frame_count=number(source.get('nb_frames')))
        streams.append(row)
    if not streams:
        raise ValueError('No audio/video streams')
    container = document.get('format', {})
    return {'container': container.get('format_name'), 'duration_s': number(container.get('duration')),
            'bit_rate': number(container.get('bit_rate')), 'streams': streams,
            'creation_time_tag': container.get('tags', {}).get('creation_time')}


def probe(stream):
    # Probe the same open inode that was hashed, never a reopened pathname or URL.
    result = subprocess.run(['ffprobe', '-v', 'error', '-protocol_whitelist', 'file,pipe',
                             '-show_format', '-show_streams', '-of', 'json',
                             f'/proc/self/fd/{stream.fileno()}'],
                            pass_fds=(stream.fileno(),), capture_output=True, text=True,
                            timeout=60, check=True)
    return metadata(json.loads(result.stdout))


def inspect(root, original):
    row = dict(original)
    try:
        with open_source(root, row['path']) as stream:
            if signature(os.fstat(stream.fileno())) != row['signature']:
                return {**row, 'state': 'changed', 'error': 'changed_before_read'}
            digest = hash_stream(stream)
            media = probe(stream)
            if signature(os.fstat(stream.fileno())) != row['signature']:
                return {**row, 'state': 'changed', 'error': 'changed_during_read'}
        if row['disposition'] == 'video' and not any(s['codec_type'] == 'video' for s in media['streams']):
            raise ValueError('Video candidate has no video stream')
        return {**row, 'state': 'verified', 'sha256': digest, 'media': media}
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        return {**row, 'state': 'error', 'error': type(exc).__name__, 'detail': str(exc)[:300]}


def finalize(rows, final_rows):
    final = {r['path']: r for r in final_rows}
    result = []
    for row in rows:
        current = final.pop(row['path'], None)
        if current is None or current.get('signature') != row.get('signature'):
            row = {**row, 'state': 'changed', 'error': 'removed_or_changed_at_final_check'}
            row.pop('sha256', None)
            row.pop('media', None)
        result.append(row)
    result.extend({**r, 'state': 'arrived_after_snapshot'} for r in final.values())
    return sorted(result, key=lambda r: r['path'])


def sources_from(rows):
    sources = {}
    for row in rows:
        if row['state'] != 'verified':
            continue
        source = sources.setdefault(row['sha256'], {'sha256': row['sha256'], 'aliases': [],
                    'bytes': row['signature']['size'], 'media': row['media'], 'upload_hints': []})
        source['aliases'].append(row['path'])
        match = UPLOAD.match(Path(row['path']).name)
        if match:
            source['upload_hints'].append('youtube:' + match[1])
    for source in sources.values():
        source['upload_hints'] = sorted(set(source['upload_hints']))
    return sorted(sources.values(), key=lambda s: s['sha256'])


def summarize(rows, sources):
    videos = [s for s in sources if any(v['codec_type'] == 'video' for v in s['media']['streams'])]
    return {'files': len(rows), 'states': dict(Counter(r['state'] for r in rows)),
            'dispositions': dict(Counter(r['disposition'] for r in rows)),
            'unique_sources': len(sources), 'unique_videos': len(videos),
            'unique_audio_only': len(sources) - len(videos),
            'duplicate_files': sum(r['state'] == 'verified' for r in rows) - len(sources),
            'unique_bytes': sum(s['bytes'] for s in sources),
            'unique_video_duration_s': sum(s['media']['duration_s'] or 0 for s in videos),
            'videos_without_duration': sum(s['media']['duration_s'] is None for s in videos)}


def run(root, output, expected_uuid=None):
    root = Path(root).resolve(strict=True)
    mount = mount_identity(root, expected_uuid)
    version = subprocess.run(['ffprobe', '-version'], capture_output=True, text=True,
                             timeout=10, check=True).stdout.splitlines()[0]
    root, output = reserve_output(root, output)
    rows, errors = snapshot(root)
    document = {'format': FORMAT, 'root': str(root), 'started_utc': utc(), 'mount': mount,
                'expected_volume_uuid': expected_uuid, 'tool_sha256': sha256(Path(__file__)),
                'python_version': sys.version.split()[0], 'ffprobe_version': version,
                'files': rows, 'scan_errors': errors}
    write_json(output / 'snapshot.json', document)
    results = []
    with (output / 'progress.jsonl').open('x', encoding='utf-8') as progress:
        for index, row in enumerate(rows):
            result = inspect(root, row) if row['state'] == 'pending' else row
            results.append(result)
            progress.write(json.dumps(result, allow_nan=False) + '\n')
            progress.flush()
            if index % 20 == 0 or index == len(rows) - 1:
                print(f'Inventoried {index + 1}/{len(rows)} paths', flush=True)
    final_mount = mount_identity(root, expected_uuid)
    if final_mount != mount:
        raise ValueError('Mount changed during inventory; no completed manifest written')
    final_rows, final_errors = snapshot(root)
    rows = finalize(results, final_rows)
    sources = sources_from(rows)
    errors.extend(final_errors)
    complete = not errors and all(r['state'] in {'verified', 'excluded'} for r in rows)
    document.update(files=rows, sources=sources, scan_errors=errors, completed_utc=utc(),
                    complete=complete, summary=summarize(rows, sources))
    write_json(output / 'inventory.json', document)
    # A deliberately unreviewed starting point, not fabricated session labels.
    provenance = {'format': 'footage-provenance/1', 'sources': {
        s['sha256']: {'reviewed': False, 'reviewer': '', 'evidence': '', 'recording_ids': [],
                      'session_ids': [], 'parent_sha256': [], 'exposure': 'unknown',
                      'requested_split': 'quarantine'} for s in sources}}
    write_json(output / 'provenance-template.json', provenance)
    write_json(output / 'summary.json', {'format': 'footage-inventory-summary/1',
        'inventory_sha256': sha256(output / 'inventory.json'), 'tool_sha256': document['tool_sha256'],
        'started_utc': document['started_utc'], 'completed_utc': document['completed_utc'],
        'complete': complete, 'summary': document['summary'], 'raw_media_published': False})
    print(json.dumps(document['summary'], indent=2), flush=True)
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path, help='New private directory outside source tree')
    parser.add_argument('--expected-volume-uuid', help='Require this already-mounted source volume')
    args = parser.parse_args()
    try:
        result = run(args.root, args.output, args.expected_volume_uuid)
        return 0 if result['complete'] else 2
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print(f'Inventory failed: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
