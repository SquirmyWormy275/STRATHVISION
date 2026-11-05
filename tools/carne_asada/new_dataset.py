"""Freeze capture-day groups, then prepare private HDR-corrected axe frames."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

from footage import sha256, write_json

FRACTIONS = [.15, .35, .55, .75]
TONE = 'zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p'


def split(manifest, previous):
    known_days = {r['capture_day'] for r in previous if r.get('capture_day')}
    fresh = [r for r in manifest['clips'] if not r['previously_inventoried']]
    days = {r['capture_day'] for r in fresh if r.get('capture_day')}
    eligible = sorted(days - known_days, key=lambda day: hashlib.sha256(('new-footage-365:' + day).encode()).hexdigest())
    if len(eligible) < 6:
        raise ValueError('Need six previously unexposed capture days for three validation/test groups each')
    test, validation = set(eligible[:3]), set(eligible[3:6])
    rows = []
    for source in fresh:
        day = source.get('capture_day')
        partition = 'test' if day in test else 'validation' if day in validation else 'train'
        rows.append({**source, 'split': partition, 'group': day or 'undated:' + source['archive_sha256'],
                     'frames': [{'frame_id': source['sha256'][:16] + '-' + str(i),
                                 'time_s': round(source['duration_s'] * fraction, 6)}
                                for i, fraction in enumerate(FRACTIONS)]})
    return {'format': 'new-footage-plan/1', 'seed': 365, 'sampling_fractions': FRACTIONS,
            'sources': rows, 'previous_capture_days_excluded_from_holdout': sorted(known_days),
            'test_capture_days': sorted(test), 'validation_capture_days': sorted(validation),
            'limitations': ['Capture-day-disjoint; dates are metadata proxies, not independently verified event/session labels.',
                            'Athletes and venues can recur across dates; this is not athlete-independent evaluation.',
                            'Four fixed temporal samples per new video; this is not full-duration native inference.',
                            'Early-training context is not a red/green technique label.']}


def prepare(parent, partition, freeze, workers):
    plan = json.loads((parent / 'plan.json').read_text())
    if partition == 'test':
        if not freeze:
            raise ValueError('Test pixels stay unopened until a model freeze exists')
        frozen = json.loads(freeze.read_text())
        if frozen['plan_sha256'] != sha256(parent / 'plan.json') or not frozen['model_sha256']:
            raise ValueError('Model freeze does not match source plan')
    jobs = [(s, f) for s in plan['sources'] if s['split'] == partition for f in s['frames']]
    def one(job):
        source, frame = job
        path = parent / 'frames' / partition / (frame['frame_id'] + '.png')
        path.parent.mkdir(parents=True, exist_ok=True)
        filters = [TONE] if source['color_transfer'] in ('arib-std-b67', 'smpte2084') else []
        filters.append('scale=1600:1600:force_original_aspect_ratio=decrease:force_divisible_by=2')
        command = ['ffmpeg', '-y', '-v', 'error', '-threads', '1', '-ss', str(frame['time_s']),
                   '-i', str(parent / 'media' / source['relative_path']), '-frames:v', '1',
                   '-vf', ','.join(filters), '-threads', '1', str(path)]
        subprocess.run(command, check=True)
        with Image.open(path) as image: width, height = image.size
        return {'frame_id': frame['frame_id'], 'clip_sha256': source['sha256'], 'source_name': source['member'],
                'split': partition, 'group': source['group'], 'time_s': frame['time_s'],
                'width': width, 'height': height, 'path': str(path.relative_to(parent)), 'sha256': sha256(path)}
    with ThreadPoolExecutor(max_workers=workers) as pool:
        rows = list(pool.map(one, jobs))
    write_json(parent / ('frames-' + partition + '.json'), {'frames': rows, 'plan_sha256': sha256(parent / 'plan.json'),
                                                         'preprocessing_sha256': sha256(Path(__file__))})
    folder = parent / 'sheets' / partition;folder.mkdir(parents=True, exist_ok=True)
    by_source = {}
    for row in rows: by_source.setdefault(row['clip_sha256'], []).append(row)
    for source_rows in by_source.values():
        sheet = Image.new('RGB', (1280, 850), '#151515');draw = ImageDraw.Draw(sheet)
        for i, row in enumerate(source_rows):
            image = Image.open(parent / row['path']).convert('RGB');image.thumbnail((630, 380))
            x, y = (i % 2) * 640, (i // 2) * 425
            sheet.paste(image, (x + (640-image.width)//2, y+30))
            draw.text((x+8, y+8), row['frame_id'] + ' ' + row['source_name'] + f' {row["time_s"]:.2f}s', fill='white')
        sheet.save(folder / (source_rows[0]['source_name'] + '.jpg'), quality=94)
    print(f'Prepared {len(rows)} {partition} frames from {len(by_source)} videos', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['plan', 'sample'])
    parser.add_argument('--parent', type=Path, required=True)
    parser.add_argument('--partition', choices=['train', 'validation', 'test'])
    parser.add_argument('--freeze', type=Path)
    parser.add_argument('--workers', type=int, default=2)
    args = parser.parse_args()
    if args.action == 'plan':
        output = args.parent / 'plan.json'
        if output.exists(): raise ValueError('Plan already exists; preserve its frozen groups')
        manifest = args.parent / 'manifest.json';previous = args.parent / 'known-source-metadata.json'
        result = split(json.loads(manifest.read_text()), json.loads(previous.read_text()))
        result.update(manifest_sha256=sha256(manifest), previous_metadata_sha256=sha256(previous),
                      split_code_sha256=sha256(Path(__file__)))
        write_json(output, result)
        print(json.dumps({p: {'sources': sum(r['split']==p for r in result['sources']),
                             'frames': sum(len(r['frames']) for r in result['sources'] if r['split']==p)}
                          for p in ('train', 'validation', 'test')}, indent=2))
    else:
        if not args.partition: parser.error('sample needs --partition')
        prepare(args.parent, args.partition, args.freeze, args.workers)


if __name__ == '__main__':
    main()
