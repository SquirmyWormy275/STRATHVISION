"""Add fixed-offset training candidates without touching validation/test times."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

from footage import sha256, write_json
from new_dataset import TONE

OFFSETS = [-.6, -.4, -.2, .2, .4, .6]


def mine(parent, workers):
    plan = json.loads((parent/'plan.json').read_text());jobs = []
    for source in plan['sources']:
        if source['split'] != 'train': continue
        if sha256(parent/'media'/source['relative_path']) != source['sha256']:
            raise ValueError('Training source changed since ingestion')
        for i, offset in enumerate(OFFSETS):
            t = round(source['duration_s']*.55+offset, 6)
            if 0 <= t < source['duration_s']:
                jobs.append((source, {'frame_id': source['sha256'][:16]+'-extra-'+str(i), 'time_s': t}))
    extra_plan = {'format': 'axe-training-augmentation/1', 'source_plan_sha256': sha256(parent/'plan.json'),
                  'offsets_s': OFFSETS, 'anchor_fraction': .55, 'partition': 'train',
                  'candidates': [{'clip_sha256': s['sha256'], 'source_name': s['member'], **f} for s, f in jobs]}
    frozen = parent/'training-augmentation-plan.json'
    if frozen.exists() and json.loads(frozen.read_text()) != extra_plan:
        raise ValueError('Existing training augmentation plan changed')
    write_json(frozen, extra_plan)
    def one(job):
        source, frame = job;path = parent/'frames/train-extra'/(frame['frame_id']+'.png');path.parent.mkdir(parents=True, exist_ok=True)
        filters = [TONE] if source['color_transfer'] in ('arib-std-b67', 'smpte2084') else []
        filters.append('scale=1600:1600:force_original_aspect_ratio=decrease:force_divisible_by=2')
        subprocess.run(['ffmpeg', '-y', '-v', 'error', '-threads', '1', '-ss', str(frame['time_s']),
                        '-i', str(parent/'media'/source['relative_path']), '-frames:v', '1', '-vf', ','.join(filters),
                        '-threads', '1', str(path)], check=True)
        with Image.open(path) as image:w, h = image.size
        return {**frame, 'clip_sha256': source['sha256'], 'source_name': source['member'], 'split': 'train',
                'group': source['group'], 'path': str(path.relative_to(parent)), 'sha256': sha256(path), 'width': w, 'height': h}
    with ThreadPoolExecutor(max_workers=workers) as pool:rows = list(pool.map(one, jobs))
    write_json(parent/'frames-training-extra.json', {'frames': rows, 'plan_sha256': sha256(parent/'plan.json'),
                                                   'augmentation_plan_sha256': sha256(frozen), 'preprocessing_sha256': sha256(Path(__file__))})
    folder = parent/'annotation-sheets/train-extra';folder.mkdir(parents=True, exist_ok=True)
    for source in dict.fromkeys(r['source_name'] for r in rows):
        sheet = Image.new('RGB', (1800, 1800), '#111');draw = ImageDraw.Draw(sheet)
        for k, row in enumerate(r for r in rows if r['source_name']==source):
            image = Image.open(parent/row['path']).convert('RGB');w,h = image.size
            box = (0, round(.18*h), w, round(.88*h)) if h>w else (0, round(.05*h), w, round(.95*h))
            image = image.crop(box);image.thumbnail((590, 820));x=k%3*600;y=k//3*900
            sheet.paste(image, (x, y+45));sx=image.width/(box[2]-box[0]);sy=image.height/(box[3]-box[1])
            draw.text((x+4,y+4),row['frame_id']+' '+f'{row["time_s"]:.3f}s',fill='white')
            for xx in range(0,w,100):
                px=x+round(xx*sx);draw.line((px,y+45,px,y+45+image.height),fill='#555');draw.text((px+2,y+28),str(xx),fill='yellow')
            for yy in range(box[1]//100*100+100,box[3],100):
                py=y+45+round((yy-box[1])*sy);draw.line((x,py,x+image.width,py),fill='#555');draw.text((x+2,py),str(yy),fill='yellow')
        sheet.save(folder/(source+'.jpg'),quality=96)
    print('Prepared',len(rows),'training-only motion candidates',flush=True)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--parent',type=Path,required=True)
    parser.add_argument('--workers',type=int,default=2);args=parser.parse_args();mine(args.parent,args.workers)
