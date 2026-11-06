"""Experimental wrist-extension timing proxy; does not detect an axe head."""
import argparse
import json
from pathlib import Path
from statistics import median

from footage import sha256, write_json


def extension_peaks(times, values, prominence=.12, separation=.6):
    if len(times) < 5:
        return []
    # Short smoothing in time; never smooth across a missing segment.
    smoothed = [sum(values[max(0, i - 1):i + 2]) / len(values[max(0, i - 1):i + 2])
                for i in range(len(values))]
    candidates = []
    for i in range(1, len(times) - 1):
        if not (smoothed[i] > smoothed[i - 1] and smoothed[i] >= smoothed[i + 1]):
            continue
        left = [j for j in range(i) if times[i] - times[j] <= 3]
        right = [j for j in range(i + 1, len(times)) if times[j] - times[i] <= 3]
        if not left or not right:
            continue
        low = min(left, key=lambda j: smoothed[j])
        depth = min(smoothed[i] - smoothed[low], smoothed[i] - min(smoothed[j] for j in right))
        if depth < prominence:
            continue
        level = smoothed[i] - .15 * depth
        arrival = next(j for j in range(low + 1, i + 1) if smoothed[j] >= level)
        candidates.append((depth, times[arrival]))
    accepted = []
    for depth, t in sorted(candidates, reverse=True):
        if all(abs(t - other) >= separation for other in accepted):
            accepted.append(t)
    return sorted(accepted)


def predict_contacts(data):
    contacts = []
    for samples in data['pose_samples'].values():
        groups = []
        for sample in samples:
            if not groups or sample['time_s'] - groups[-1][-1]['time_s'] > .3:
                groups.append([])
            groups[-1].append(sample)
        for group in groups:
            if len(group) < 5 or 'xy' not in group[0]:
                continue
            scale = median(s['box'][3] - s['box'][1] for s in group)
            if scale <= 0:
                continue
            # Underhand is downward. Standing-block direction is supplied
            # solely by the initial hands relative to hips, before scoring.
            axis = 1 if data['event_id'] == 'underhand' else 0
            first = group[0]['xy']
            initial = (first[15][axis] + first[16][axis] - first[23][axis] - first[24][axis]) / 2
            direction = 1 if axis == 1 or initial >= 0 else -1
            values = []
            for s in group:
                xy = s['xy']
                relative = (xy[15][axis] + xy[16][axis] - xy[23][axis] - xy[24][axis]) / 2
                values.append(direction * relative / scale)
            contacts.extend(extension_peaks([s['time_s'] for s in group], values))
    # Separate segments can border each other; a repeated candidate is one
    # prediction, never extra evidence.
    return sorted(set(contacts))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('predictions', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    rows = []
    for path in sorted(args.predictions.glob('*.json')):
        data = json.loads(path.read_text())
        if data.get('format') != 'gurr-accuracy-prediction/1':
            continue
        if data['sources_sha256']['motion_contacts.py'] != sha256(Path(__file__)):
            raise ValueError('Timing source changed since pose prediction; rerun before scoring')
        times = predict_contacts(data)
        rows.append({'window_id': data['window_id'], 'variant': 'wrist-extension-proxy',
                     'prediction_sources_sha256': data['sources_sha256'],
                     'contact_times_s': times, 'candidate_strokes': len(times),
                     'usable_strokes': 0, 'failures': {}})
    write_json(args.output, {'format': 'gurr-accuracy-contacts/1',
                            'method': 'experimental image-wrist extension proxy, not measured axe contacts',
                            'source_sha256': sha256(Path(__file__)), 'windows': rows})


if __name__ == '__main__':
    main()
