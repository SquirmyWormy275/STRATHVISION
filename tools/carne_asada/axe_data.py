"""Private frame preparation and strict source-disjoint axe data contracts."""
import argparse
from collections import defaultdict
import hashlib
import io
import json
from pathlib import Path
import subprocess

import cv2
import numpy as np
from PIL import Image, ImageDraw

from footage import sha256, write_json


def validate(document):
    if document.get('format') != 'axe-reference/1':
        raise ValueError('Expected axe-reference/1')
    groups, ids = {}, set()
    for row in document['windows']:
        if row['window_id'] in ids:
            raise ValueError('Duplicate window ID')
        ids.add(row['window_id'])
        source, split = row['clip_sha256'], row['split']
        if split not in ('train', 'validation', 'test'):
            raise ValueError('Unknown split')
        if source in groups and groups[source] != split:
            raise ValueError('Source content leaks across partitions')
        groups[source] = split
        if row['duration_s'] <= 0 or row['rotation_cw'] not in (0, 90, 180, 270):
            raise ValueError('Invalid duration or rotation')
        for box in [row['search_roi'], *[f['head_box'] for f in row['frames'] if f['head_box'] is not None]]:
            if not (0 <= box[0] < box[2] <= 1 and 0 <= box[1] < box[3] <= 1):
                raise ValueError('Invalid image box')
        for f in row['frames']:
            if not 0 <= f['time_s'] < row['duration_s']:
                raise ValueError('Frame outside window')
            if f['head_box'] is None and f.get('visibility') not in ('occluded', 'blurred', 'out_of_frame', 'empty', 'uncertain', 'unreviewed'):
                raise ValueError('Missing axe requires an explicit visibility state')
    return document


def read_frame(path, time_s, rotation=0, max_edge=960):
    filters = []
    if rotation:
        filters.append({90: 'transpose=1', 180: 'hflip,vflip', 270: 'transpose=2'}[rotation])
    filters.append(f'scale={max_edge}:{max_edge}:force_original_aspect_ratio=decrease')
    data = subprocess.check_output(['ffmpeg', '-v', 'error', '-threads', '1', '-ss', str(time_s),
        '-i', str(path), '-frames:v', '1', '-vf', ','.join(filters), '-f', 'image2pipe',
        '-vcodec', 'png', '-threads', '1', '-'])
    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError('Could not decode source frame')
    return image


def frame_path(directory, row, time_s):
    return Path(directory) / row['window_id'] / f'{round(time_s * 1000):06d}.png'


def prepare(document, root, output, rate):
    validate(document)
    for row in document['windows']:
        source = root / row['source_name']
        if sha256(source) != row['clip_sha256']:
            raise ValueError(f'Source content changed: {row["window_id"]}')
        # An initial spatial search ROI is an inference input, not an axe label.
        times = sorted({round(i / rate, 6) for i in range(round(row['duration_s'] * rate))}
                       | {f['time_s'] for f in row['frames']})
        for time in times:
            path = frame_path(output, row, time)
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.exists():
                image = read_frame(source, row['start_s'] + time, row['rotation_cw'])
                cv2.imwrite(str(path), image)
        print(row['window_id'], len(times), 'frames', flush=True)


def sheet(document, directory, output, rate, crop=False):
    output.mkdir(parents=True, exist_ok=True)
    for row in document['windows']:
        times = [round(i / rate, 6) for i in range(round(row['duration_s'] * rate))]
        for page in range(0, len(times), 20):
            canvas = Image.new('RGB', (1600, 1000), '#141414')
            draw = ImageDraw.Draw(canvas)
            for slot, time in enumerate(times[page:page+20]):
                path = frame_path(directory, row, time)
                if not path.exists():
                    continue
                im = Image.open(path).convert('RGB')
                if crop:
                    a,b,c,d = row['search_roi']; w,h=im.size
                    im=im.crop((round(a*w),round(b*h),round(c*w),round(d*h)))
                im.thumbnail((400, 170))
                x,y=slot % 4 * 400,slot // 4 * 200
                canvas.paste(im,(x+(400-im.width)//2,y+25))
                draw.text((x+4,y+4),f'{row["window_id"]} +{time:.3f}s',fill='white')
            canvas.save(output / f'{row["window_id"]}-{page//20}.jpg',quality=94)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference',type=Path)
    parser.add_argument('--root',type=Path)
    parser.add_argument('--frames',type=Path,required=True)
    parser.add_argument('--rate',type=float,default=2)
    parser.add_argument('--sheets',type=Path)
    parser.add_argument('--crop',action='store_true')
    args=parser.parse_args()
    data=json.loads(args.reference.read_text())
    if args.root:
        prepare(data,args.root,args.frames,args.rate)
    if args.sheets:
        sheet(data,args.frames,args.sheets,args.rate,args.crop)


if __name__=='__main__':
    main()
