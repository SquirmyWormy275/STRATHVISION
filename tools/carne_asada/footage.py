"""Local footage inventory, anonymous geometric person tracks and 3D pose.

No face recognition, appearance embeddings or identity inference. Names come
only from explicit user annotations in the generated manifest.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
import time
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw, ImageFont


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(data, indent=2, allow_nan=False) + '\n')
    temp.replace(path)


def probe(path):
    d = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)]))
    v = next(s for s in d['streams'] if s['codec_type'] == 'video')
    n, den = v['avg_frame_rate'].split('/')
    rotation = next((s['rotation'] for s in v.get('side_data_list', []) if 'rotation' in s), 0)
    w, h = v['width'], v['height']
    if abs(rotation) % 180 == 90:
        w, h = h, w
    return {'duration_s': float(d['format']['duration']), 'fps': float(n) / float(den),
            'width': w, 'height': h, 'rotation': rotation}


def iou(a, b):
    x, y = max(a[0], b[0]), max(a[1], b[1])
    r, bot = min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, r - x) * max(0, bot - y)
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union > 0 else 0.0


class Tracker:
    """Conservative overlap linking. Expired/cut tracks never regain names."""
    def __init__(self, max_gap=0.8):
        self.max_gap = max_gap
        self.active = {}
        self.next_id = 1

    def update(self, t, detections, cut=False):
        if cut:
            self.active.clear()
        self.active = {k: v for k, v in self.active.items() if t - v[0] <= self.max_gap}
        pairs = []
        for k, (_, box) in self.active.items():
            scores = sorted([(iou(box, d[:4]), j) for j, d in enumerate(detections)], reverse=True)
            if scores and scores[0][0] >= .25:
                if len(scores) == 1 or scores[0][0] - scores[1][0] >= .12:
                    pairs.append((scores[0][0], k, scores[0][1]))
        used, matched = set(), {}
        for score, k, j in sorted(pairs, reverse=True):
            if any(other_j == j and other_k != k and abs(other_score - score) < .12
                   for other_score, other_k, other_j in pairs):
                continue
            if j not in used:
                matched[j] = k
                used.add(j)
        out = []
        for j, d in enumerate(detections):
            k = matched.get(j)
            if k is None:
                k, self.next_id = self.next_id, self.next_id + 1
            self.active[k] = (t, list(d[:4]))
            out.append((k, d))
        return out


def session(path):
    opts = ort.SessionOptions()
    opts.intra_op_num_threads = 2
    return ort.InferenceSession(str(path), opts, providers=['CPUExecutionProvider'])


class Detector:
    """YOLOX Nano COCO person class; upstream Apache-2.0 model."""
    def __init__(self, path, threshold=.4):
        self.model = session(path)
        self.threshold = threshold

    def detect(self, frame):
        h, w = frame.shape[:2]
        ratio = min(416 / h, 416 / w)
        img = np.full((416, 416, 3), 114, dtype=np.uint8)
        small = cv2.resize(frame, (int(w * ratio), int(h * ratio)))
        img[:small.shape[0], :small.shape[1]] = small
        pred = self.model.run(None, {self.model.get_inputs()[0].name:
            img.transpose(2, 0, 1)[None].astype(np.float32)})[0][0].copy()
        grids, strides = [], []
        for stride in (8, 16, 32):
            y, x = np.meshgrid(np.arange(416 // stride), np.arange(416 // stride), indexing='ij')
            grids.append(np.stack([x, y], axis=-1).reshape(-1, 2))
            strides.append(np.full((x.size, 1), stride))
        grid, stride = np.concatenate(grids), np.concatenate(strides)
        pred[:, :2] = (pred[:, :2] + grid) * stride
        pred[:, 2:4] = np.exp(pred[:, 2:4]) * stride
        scores = pred[:, 4] * pred[:, 5]
        ids = np.where(scores >= self.threshold)[0]
        boxes = []
        for i in ids:
            cx, cy, bw, bh = pred[i, :4] / ratio
            boxes.append([max(0, float(cx - bw / 2)) / w, max(0, float(cy - bh / 2)) / h,
                          min(w, float(cx + bw / 2)) / w, min(h, float(cy + bh / 2)) / h,
                          float(scores[i])])
        keep = []
        for b in sorted(boxes, key=lambda b: -b[4]):
            if all(iou(b, other) < .45 for other in keep):
                keep.append(b)
        return keep


class Pose:
    def __init__(self, path):
        self.model = session(path)

    def infer(self, frame, box):
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = box[:4]
        cx, cy = (x1 + x2) * w / 2, (y1 + y2) * h / 2
        side = max((x2 - x1) * w, (y2 - y1) * h) * 1.2
        transform = np.array([[256 / side, 0, 128 - cx * 256 / side],
                              [0, 256 / side, 128 - cy * 256 / side]], dtype=np.float32)
        crop = cv2.warpAffine(frame, transform, (256, 256))
        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB).astype(np.float32) / 255
        land, presence, world = self.model.run(['Identity', 'Identity_1', 'Identity_4'],
            {self.model.get_inputs()[0].name: rgb[None]})
        lm = land.reshape(-1, 5)
        return {'presence': float(presence.flat[0]), 'w': world.reshape(-1).tolist(),
                'v': lm[:, 3].tolist(), 'p': lm[:, 4].tolist()}


def frames(path, info, rate):
    scale = min(1, 960 / max(info['width'], info['height']))
    w, h = int(info['width'] * scale) // 2 * 2, int(info['height'] * scale) // 2 * 2
    process = subprocess.Popen(['ffmpeg', '-v', 'error', '-threads', '2', '-i', str(path),
        '-vf', f'fps={rate},scale={w}:{h}', '-an', '-f', 'rawvideo', '-pix_fmt', 'bgr24', '-'],
        stdout=subprocess.PIPE)
    try:
        i, n = 0, w * h * 3
        while True:
            data = process.stdout.read(n)
            if len(data) != n:
                break
            yield i / rate, np.frombuffer(data, np.uint8).reshape(h, w, 3)
            i += 1
        if process.wait() != 0:
            raise RuntimeError('ffmpeg decode failed')
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.terminate()
            process.wait()


def inventory(root, output):
    rows = []
    paths = sorted(p for p in root.rglob('*') if p.suffix.lower() in ('.mov', '.mp4', '.m4v', '.mkv', '.webm'))
    for i, path in enumerate(paths, 1):
        rows.append({'index': i, 'relative_path': str(path.relative_to(root)),
            'sha256': sha256(path), 'bytes': path.stat().st_size, **probe(path),
            'event_id': None, 'assignments': {}})
    write_json(output / 'manifest.json', {'format': 'carne-footage/1', 'clips': rows,
        'athletes': [{'athlete_id': k, 'name': v} for k, v in [
            ('matthew-gurr', 'Matthew Gurr'), ('daniel-gurr', 'Daniel Gurr'), ('alex', 'Alex'), ('ian', 'Ian')]]})
    font = ImageFont.truetype('/usr/share/fonts/liberation/LiberationSans-Regular.ttf', 18)
    sheet = Image.new('RGB', (960, len(rows) * 230), '#17221e')
    draw = ImageDraw.Draw(sheet)
    for i, row in enumerate(rows):
        draw.text((8, i * 230 + 5), f"{row['index']:02}  {Path(row['relative_path']).name}  {row['duration_s']:.1f}s", font=font)
        for j, frac in enumerate((.15, .5, .8)):
            data = subprocess.check_output(['ffmpeg', '-v', 'error', '-ss', str(row['duration_s'] * frac),
                '-i', str(root / row['relative_path']), '-frames:v', '1', '-vf', 'scale=304:190:force_original_aspect_ratio=decrease',
                '-f', 'image2pipe', '-vcodec', 'png', '-'])
            import io
            image = Image.open(io.BytesIO(data))
            sheet.paste(image, (j * 320 + (320 - image.width) // 2, i * 230 + 32))
    sheet.save(output / 'contact-sheet.jpg', quality=90)
    print(f'Inventoried {len(rows)} videos; {sum(r["duration_s"] for r in rows):.3f} seconds', flush=True)


def analyze(root, output, detector_path, pose_path, rate):
    manifest = json.loads((output / 'manifest.json').read_text())
    detector, pose = Detector(detector_path), Pose(pose_path)
    for clip in manifest['clips']:
        destination = output / 'tracks' / f"{clip['sha256']}.json"
        pipeline_hash = sha256(Path(__file__))
        cache = json.loads(destination.read_text()) if destination.exists() else {}
        if (cache.get('pipeline_sha256') == pipeline_hash and cache.get('sample_rate') == rate
                and cache.get('detector_sha256') == sha256(detector_path)
                and cache.get('pose_sha256') == sha256(pose_path)):
            print('Cached', clip['relative_path'], flush=True)
            continue
        started = time.monotonic()
        tracker = Tracker()
        observations, samples, previous_hist = [], {}, None
        counts, cuts = [], 0
        for t, frame in frames(root / clip['relative_path'], clip, rate):
            hist = cv2.calcHist([frame], [0, 1], None, [16, 16], [0, 256, 0, 256])
            hist /= max(float(hist.sum()), 1)
            cut = previous_hist is not None and float(np.abs(hist - previous_hist).sum()) > 1.1
            previous_hist = hist
            cuts += int(cut)
            detections = detector.detect(frame)
            counts.append(len(detections))
            for track_id, box in tracker.update(t, detections, cut):
                observation = {'time_s': round(t, 6), 'track_id': track_id, 'box': box[:4], 'confidence': box[4]}
                observations.append(observation)
                result = pose.infer(frame, box)
                if result['presence'] >= .5:
                    samples.setdefault(str(track_id), []).append({'f': round(t * clip['fps']),
                        'time_s': t, 'box': box[:4], **result})
        data = {'format': 'athlete_tracks/1', 'clip_sha256': clip['sha256'],
            'source_name': Path(clip['relative_path']).name, 'duration_s': clip['duration_s'],
            'fps': clip['fps'], 'width': clip['width'], 'height': clip['height'],
            'sample_rate': rate, 'pipeline_sha256': pipeline_hash,
            'detector_sha256': sha256(detector_path), 'pose_sha256': sha256(pose_path),
            'observations': observations, 'pose_samples': samples, 'assignments': clip['assignments'],
            'scene_cuts': cuts, 'sampled_frames': len(counts), 'frames_with_people': sum(n > 0 for n in counts),
            'frames_with_multiple_people': sum(n > 1 for n in counts),
            'max_people': max(counts, default=0), 'elapsed_s': time.monotonic() - started}
        write_json(destination, data)
        print(f"{data['source_name']}: {len(counts)} frames, {len(observations)} detections, "
              f"{len(samples)} posed tracks, {data['elapsed_s']:.1f}s", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['inventory', 'analyze'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--detector', type=Path)
    parser.add_argument('--pose', type=Path)
    parser.add_argument('--rate', type=float, default=5)
    args = parser.parse_args()
    if args.command == 'inventory':
        inventory(args.root, args.output)
    else:
        if not args.detector or not args.pose or args.rate <= 0:
            parser.error('analyze requires --detector, --pose and a positive --rate')
        analyze(args.root, args.output, args.detector, args.pose, args.rate)


if __name__ == '__main__':
    main()
