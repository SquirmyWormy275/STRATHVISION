"""Source-grouped Faster R-CNN active axe-head experiment, conditional on an athlete ROI."""
import argparse
import hashlib
import json
from pathlib import Path
import time

import cv2
import numpy as np
import torch
import torchvision
from torchvision.models.detection import fasterrcnn_resnet50_fpn_v2, FasterRCNN_ResNet50_FPN_V2_Weights
from torchvision.models.detection.anchor_utils import AnchorGenerator
from torchvision.models.detection.faster_rcnn import FastRCNNPredictor

from axe_data import validate
from axe_detector import pixels, score
from footage import sha256, write_json
from new_dataset import validate_plan

SETTINGS = {'seed': 365, 'steps': 1000, 'batch_size': 2, 'learning_rate': .002,
            'checkpoint_every': 200, 'momentum': .9, 'weight_decay': .0005,
            'frozen_resnet_body': True, 'min_size': 640, 'max_size': 1024,
            'anchor_sizes': [8, 16, 32, 64, 128], 'max_candidates_per_frame': 1,
            'iou_threshold': .5, 'input': 'manually supplied broad athlete search ROI'}


def code_hashes():
    return {name: sha256(Path(__file__).with_name(name)) for name in
            ['axe_faster.py', 'axe_data.py', 'axe_detector.py', 'footage.py', 'new_dataset.py', 'mine_training.py']}


def fit_reference(document):
    subset = {'format': document['format'], 'source_plan_sha256': document['source_plan_sha256'],
              'training_augmentation_sha256': document.get('training_augmentation_sha256'), 'windows': [r for r in document['windows'] if r['split'] != 'test']}
    return hashlib.sha256(json.dumps(subset, sort_keys=True).encode()).hexdigest()


def build(parent):
    torch.hub.set_dir(str(parent / 'model-cache'))
    model = fasterrcnn_resnet50_fpn_v2(weights=FasterRCNN_ResNet50_FPN_V2_Weights.COCO_V1,
                                      trainable_backbone_layers=0, min_size=640, max_size=1024)
    features = model.roi_heads.box_predictor.cls_score.in_features
    model.roi_heads.box_predictor = FastRCNNPredictor(features, 2)
    model.rpn.anchor_generator = AnchorGenerator(tuple((s,) for s in SETTINGS['anchor_sizes']),
                                                 ((.5, 1., 2.),) * 5)
    for parameter in model.backbone.body.parameters(): parameter.requires_grad = False
    return model



def inputs(parent, document, partition):
    frames = json.loads((parent / ('frames-' + partition + '.json')).read_text())['frames']
    if partition == 'train' and document.get('training_augmentation_sha256'):
        frames += json.loads((parent/'frames-training-extra.json').read_text())['frames']
    lookup = {(r['clip_sha256'], r['time_s']): r for r in frames};rows = []
    for row in document['windows']:
        if row['split'] != partition: continue
        for frame in row['frames']:
            source = lookup[(row['clip_sha256'], frame['time_s'])];path = parent / source['path']
            if sha256(path) != source['sha256']: raise ValueError('Prepared image changed')
            image = cv2.imread(str(path))
            if image is None: raise ValueError('Missing prepared image')
            h, w = image.shape[:2];a, b, c, d = pixels(row['search_roi'], w, h)
            crop = image[b:d, a:c].copy();box = None
            if frame['head_box']:
                x, y, r, bottom = pixels(frame['head_box'], w, h)
                if not (a <= x < r <= c and b <= y < bottom <= d): raise ValueError('Head outside supplied athlete ROI')
                box = [x-a, y-b, r-a, bottom-b]
            rows.append({'window_id': row['window_id'], 'clip_sha256': row['clip_sha256'],
                         'time_s': frame['time_s'], 'image': crop, 'head_box': box,
                         'visibility': frame['visibility'], 'offset': [a, b], 'full_size': [w, h],
                         'pixels_sha256': source['sha256']})
    return rows


def tensor(image):
    return torch.from_numpy(cv2.cvtColor(image, cv2.COLOR_BGR2RGB).copy()).permute(2, 0, 1).float()/255


def augment(row, rng):
    image = row['image'].copy();boxes = np.asarray([row['head_box']] if row['head_box'] else [], np.float32).reshape(-1, 4)
    if rng.random() < .5:
        image = image[:, ::-1].copy()
        if len(boxes): boxes[:, [0, 2]] = image.shape[1] - boxes[:, [2, 0]]
    image = np.clip(image.astype(np.float32)*rng.uniform(.85, 1.15), 0, 255).astype(np.uint8)
    return tensor(image), {'boxes': torch.from_numpy(boxes), 'labels': torch.ones(len(boxes), dtype=torch.int64)}


def predictions(rows, model, device):
    model.eval();results = []
    with torch.inference_mode():
        for row in rows:
            output = model([tensor(row['image']).to(device)])[0];candidate = None
            if len(output['scores']):
                k = int(output['scores'].argmax());x, y, r, b = output['boxes'][k].cpu().tolist()
                a, top = row['offset'];w, h = row['full_size']
                candidate = {'box': [(a+x)/w, (top+y)/h, (a+r)/w, (top+b)/h],
                             'margin': float(output['scores'][k])}
            results.append({k: row[k] for k in ('window_id', 'clip_sha256', 'time_s')} | {'candidate': candidate})
    return results


def threshold_for(document, predicted):
    thresholds = sorted({r['candidate']['margin'] for r in predicted if r['candidate']}) + [1.001]
    value = max(thresholds, key=lambda t: ((score(document, predicted, t)['f1'] or 0), t))
    return value, score(document, predicted, value)


def save_delta(model, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    # The unchanged COCO ResNet body stays in the verified upstream checkpoint.
    torch.save({k: v.detach().cpu() for k, v in model.state_dict().items() if not k.startswith('backbone.body.')}, path)


def fit(parent, document, model_path, metadata_path, output):
    validate_plan(parent, document, True)
    train_all = inputs(parent, document, 'train');validation = inputs(parent, document, 'validation')
    examples = [r for r in train_all if r['head_box'] or r['visibility'] == 'empty']
    if not any(r['head_box'] for r in examples): raise ValueError('No visible training heads')
    device = 'cuda' if torch.cuda.is_available() else 'cpu';model = build(parent).to(device)
    optimizer = torch.optim.SGD([p for p in model.parameters() if p.requires_grad], lr=.002, momentum=.9, weight_decay=.0005)
    rng = np.random.default_rng(365);start = time.monotonic();best = None;history = []
    print('Device', device, 'training examples', len(examples), 'positive', sum(bool(r['head_box']) for r in examples), flush=True)
    for step in range(1, SETTINGS['steps']+1):
        model.train();model.backbone.body.eval()
        lr = .002 * min(1., .1 + step/30) * (.3 if step > 800 else 1.)
        for group in optimizer.param_groups: group['lr'] = lr
        batch = [augment(examples[int(rng.integers(len(examples)))], rng) for _ in range(SETTINGS['batch_size'])]
        loss = sum(model([x.to(device) for x, _ in batch], [{k: v.to(device) for k, v in y.items()} for _, y in batch]).values())
        if not torch.isfinite(loss): raise ValueError('Nonfinite training loss')
        optimizer.zero_grad();loss.backward();torch.nn.utils.clip_grad_norm_(model.parameters(), 10.);optimizer.step()
        if step % 50 == 0: print('step', step, 'loss', round(float(loss.detach()), 4), 'seconds', round(time.monotonic()-start, 1), flush=True)
        if step % SETTINGS['checkpoint_every']: continue
        predicted = predictions(validation, model, device);threshold, metrics = threshold_for(document, predicted)
        item = {'step': step, 'threshold': threshold, 'metrics': metrics};history.append(item)
        print('Validation', step, json.dumps({k: metrics[k] for k in ['tp', 'fp', 'fn', 'f1']}), flush=True)
        quality = (metrics['f1'] or 0, metrics['precision'] or 0, metrics['recall'] or 0, -step)
        if best is None or quality > best[0]:
            save_delta(model, model_path);best = (quality, item, predicted)
    pretrained = parent/'model-cache/checkpoints/fasterrcnn_resnet50_fpn_v2_coco-dd69338a.pth'
    metadata = {'format': 'axe-faster-model/1', 'architecture': 'TorchVision Faster R-CNN ResNet50 FPN v2',
                'pretrained_url': FasterRCNN_ResNet50_FPN_V2_Weights.COCO_V1.url, 'pretrained_sha256': sha256(pretrained),
                'delta_sha256': sha256(model_path), 'state_scope': 'All tensors except frozen backbone.body',
                'settings': SETTINGS, 'chosen_step': best[1]['step'], 'threshold': best[1]['threshold'],
                'fit_reference_sha256': fit_reference(document), 'plan_sha256': sha256(parent/'plan.json'),
                'training_augmentation_sha256': document.get('training_augmentation_sha256'),
                'fit_sources': sorted({r['clip_sha256'] for r in document['windows'] if r['split'] != 'test'}),
                'training_positive_frames': sum(bool(r['head_box']) for r in examples),
                'training_empty_frames': sum(r['visibility'] == 'empty' for r in examples),
                'training_unrated_frames': len(train_all)-len(examples), 'validation_history': history,
                'training_frame_sha256': {r['window_id']+':'+str(r['time_s']): r['pixels_sha256'] for r in examples},
                'validation_frame_sha256': {r['window_id']+':'+str(r['time_s']): r['pixels_sha256'] for r in validation},
                'code_sha256': code_hashes(), 'torch': torch.__version__, 'torchvision': torchvision.__version__,
                'device': device, 'elapsed_s': time.monotonic()-start, 'promoted_for_coaching': False}
    write_json(metadata_path, metadata)
    write_json(output, {'format': 'axe-detection/1', 'partition': 'validation', 'model_sha256': sha256(model_path),
                        'threshold': metadata['threshold'], 'metrics': best[1]['metrics'], 'predictions': best[2]})


def test(parent, document, model_path, metadata_path, freeze_path, output):
    validate_plan(parent, document, False)
    metadata = json.loads(metadata_path.read_text());frozen = json.loads(freeze_path.read_text())
    expected = {'plan_sha256': sha256(parent/'plan.json'), 'model_sha256': sha256(model_path),
                'metadata_sha256': sha256(metadata_path), 'code_sha256': code_hashes()}
    if (frozen != expected or metadata['fit_reference_sha256'] != fit_reference(document)
            or metadata['code_sha256'] != code_hashes()):
        raise ValueError('Frozen model, fit labels, code or source plan changed')
    test_sources = {r['clip_sha256'] for r in document['windows'] if r['split'] == 'test'}
    if test_sources & set(metadata['fit_sources']): raise ValueError('Test source leaked into fitting')
    if any(f['visibility']=='unreviewed' for r in document['windows'] if r['split']=='test' for f in r['frames']):
        raise ValueError('Complete held-out engineering annotations before test prediction')
    pretrained = parent/'model-cache/checkpoints/fasterrcnn_resnet50_fpn_v2_coco-dd69338a.pth'
    if sha256(pretrained) != metadata['pretrained_sha256']: raise ValueError('Pretrained frozen body changed')
    device = 'cuda' if torch.cuda.is_available() else 'cpu';model = build(parent)
    missing, unexpected = model.load_state_dict(torch.load(model_path, map_location='cpu', weights_only=True), strict=False)
    if unexpected or any(not k.startswith('backbone.body.') for k in missing): raise ValueError('Incomplete detector delta')
    model.to(device).eval();rows = predictions(inputs(parent, document, 'test'), model, device)
    write_json(output, {'format': 'axe-detection/1', 'partition': 'test', 'model_sha256': sha256(model_path),
                        'metadata_sha256': sha256(metadata_path), 'reference_sha256': hashlib.sha256(json.dumps(document, sort_keys=True).encode()).hexdigest(),
                        'threshold': metadata['threshold'], 'metrics': score(document, rows, metadata['threshold']),
                        'predictions': rows, 'claimed_coaching_improvement': False})


def main():
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('action', choices=['fit', 'test'])
    for name in ('parent', 'reference', 'model', 'metadata', 'output'): parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--freeze', type=Path);args = parser.parse_args()
    torch.set_num_threads(4);torch.manual_seed(365);np.random.seed(365)
    document = validate(json.loads(args.reference.read_text()))
    if args.action == 'fit': fit(args.parent, document, args.model, args.metadata, args.output)
    else:
        if not args.freeze: parser.error('test needs --freeze')
        test(args.parent, document, args.model, args.metadata, args.freeze, args.output)


if __name__ == '__main__': main()
