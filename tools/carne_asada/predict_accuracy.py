"""Predict on frozen spatial inputs only. Scoring references are never read."""
import argparse
import json
import subprocess
from pathlib import Path

import cv2
import numpy as np

from footage import Detector, Pose, Tracker, probe, sha256, write_json
from target import ImagePose, SpatialTarget, choose_rotation, contains, rotate_box, rotate_frame, rotate_point


def code_hashes():
    directory = Path(__file__).resolve().parent
    return {name: sha256(directory / name)
            for name in ('footage.py', 'target.py', 'predict_accuracy.py', 'motion_contacts.py')}


def window_frames(path, start, duration, rate):
    info = probe(path)
    scale = min(1, 960 / max(info['width'], info['height']))
    width, height = (int(info[k] * scale) // 2 * 2 for k in ('width', 'height'))
    process = subprocess.Popen(['ffmpeg', '-v', 'error', '-threads', '2',
        '-ss', str(start), '-i', str(path), '-t', str(duration),
        '-vf', f'fps={rate},scale={width}:{height}', '-an', '-f', 'rawvideo',
        '-pix_fmt', 'bgr24', '-'], stdout=subprocess.PIPE)
    try:
        index, size = 0, width * height * 3
        while True:
            data = process.stdout.read(size)
            if not data:
                break
            if len(data) != size:
                raise RuntimeError('Truncated decoded frame')
            yield index / rate, np.frombuffer(data, np.uint8).reshape(height, width, 3)
            index += 1
        if process.wait():
            raise RuntimeError('Window decode failed')
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.terminate()
            process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--detector', type=Path, required=True)
    parser.add_argument('--pose', type=Path, required=True)
    parser.add_argument('--variant', choices=['baseline', 'revised'], required=True)
    parser.add_argument('--partition', choices=['development', 'test'], required=True)
    parser.add_argument('--freeze', type=Path)
    args = parser.parse_args()
    hashes = code_hashes()
    provenance = {'sources_sha256': hashes, 'inputs_sha256': sha256(args.inputs),
                  'detector_sha256': sha256(args.detector), 'pose_sha256': sha256(args.pose)}
    if args.partition == 'test':
        if args.freeze is None:
            parser.error('Test inference requires --freeze from the completed development run')
        frozen = json.loads(args.freeze.read_text())
        if frozen['inference'] != provenance:
            parser.error('Frozen inference source, inputs or models changed')
    inputs = json.loads(args.inputs.read_text())
    assert inputs['format'] == 'gurr-accuracy-inputs/1'
    detector = Detector(args.detector)
    pose = Pose(args.pose) if args.variant == 'baseline' else ImagePose(args.pose)
    rate = 5 if args.variant == 'baseline' else 15
    for row in inputs['windows']:
        if not row['window_id'].startswith('dev-' if args.partition == 'development' else 'test-'):
            continue
        path = args.root / row['source_name']
        assert sha256(path) == row['clip_sha256'], f'Source changed: {path}'
        original = Tracker()
        selected_id = None
        selector = None
        observations, samples, rotation_scores = [], {}, {}
        rotation, previous_hist, frame_count = 0, None, 0
        for time_s, raw in window_frames(path, row['start_s'], row['duration_s'], rate):
            if frame_count == 0:
                if args.variant == 'revised':
                    rotation, rotation_scores = choose_rotation(raw, detector, row['seed_raw'])
                seed = rotate_point(row['seed_raw'], rotation)
                selector = SpatialTarget(seed)
            frame_count += 1
            frame = rotate_frame(raw, rotation)
            detections = detector.detect(frame)
            hist = cv2.calcHist([frame], [0, 1], None, [16, 16], [0, 256, 0, 256])
            hist /= max(float(hist.sum()), 1)
            cut = previous_hist is not None and float(np.abs(hist - previous_hist).sum()) > 1.1
            previous_hist = hist
            if args.variant == 'baseline':
                tracked = original.update(time_s, detections, cut)
                if selected_id is None and time_s <= .6:
                    matches = [(k, b) for k, b in tracked if contains(b, seed)]
                    if matches:
                        selected_id = max(matches, key=lambda pair: pair[1][4])[0]
                selected = next(((k, b) for k, b in tracked if k == selected_id), None)
            else:
                selected = selector.update(time_s, detections, cut)
            if selected is None:
                continue
            segment, box = selected
            observations.append({'time_s': time_s, 'segment': segment,
                                 'box_raw': rotate_box(box, (360 - rotation) % 360)})
            result = pose.infer(frame, box)
            if result['presence'] >= .5:
                samples.setdefault(str(segment), []).append({
                    'f': round(time_s * row['fps']), 'time_s': time_s,
                    'box': list(box[:4]), **result})
        assert abs(frame_count / rate - row['duration_s']) < .25
        write_json(args.output / f"{row['window_id']}.json", {
            'format': 'gurr-accuracy-prediction/1', **row, **provenance,
            'variant': args.variant, 'sample_rate': rate, 'rotation_cw': rotation,
            'rotation_scores': rotation_scores, 'frame_count': frame_count,
            'needs_reselection': selector.lost if args.variant == 'revised' else None,
            'observations': observations, 'pose_samples': samples})
        print(args.variant, row['window_id'], 'rotation', rotation,
              'selected', len(observations), '/', frame_count,
              'pose', sum(map(len, samples.values())), flush=True)


if __name__ == '__main__':
    main()
