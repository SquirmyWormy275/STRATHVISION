"""Full-frame, one-foreground-barbell Faster R-CNN research baseline."""
import argparse
import json
from pathlib import Path
import time

import numpy as np
import torch
import torchvision
from torchvision.models.detection import fasterrcnn_resnet50_fpn_v2, FasterRCNN_ResNet50_FPN_V2_Weights
from torchvision.models.detection.anchor_utils import AnchorGenerator
from torchvision.models.detection.faster_rcnn import FastRCNNPredictor

from axe_faster import augment, fit_reference, inputs, predictions, save_delta, threshold_for
from axe_detector import score
import barbell_data
from footage import sha256, write_json

SETTINGS = {'seed': 365, 'steps': 1000, 'batch_size': 2, 'checkpoint_every': 200,
            'learning_rate': .002, 'momentum': .9, 'weight_decay': .0005,
            'frozen_resnet_body': True, 'min_size': 640, 'max_size': 1024,
            'anchor_sizes': [16, 32, 64, 128, 256], 'anchor_aspect_ratios': [.125, .5, 2.],
            'iou_threshold': .5, 'max_candidates_per_frame': 1, 'input': 'full frame',
            'target': 'foreground demonstration barbell, including shaft and attached plates'}


def code_hashes():
    return {n: sha256(Path(__file__).with_name(n)) for n in
            ['barbell_detector.py', 'barbell_data.py', 'axe_faster.py', 'axe_data.py',
             'axe_detector.py', 'new_dataset.py', 'footage.py']}


def build(parent):
    torch.hub.set_dir(str(parent/'model-cache'))
    model = fasterrcnn_resnet50_fpn_v2(weights=FasterRCNN_ResNet50_FPN_V2_Weights.COCO_V1,
                                      trainable_backbone_layers=0, min_size=640, max_size=1024)
    model.roi_heads.box_predictor = FastRCNNPredictor(model.roi_heads.box_predictor.cls_score.in_features, 2)
    model.rpn.anchor_generator = AnchorGenerator(tuple((s,) for s in SETTINGS['anchor_sizes']),
                                                 (tuple(SETTINGS['anchor_aspect_ratios']),)*5)
    for p in model.backbone.body.parameters(): p.requires_grad = False
    return model


def fit(parent, public, model_path, metadata_path, output):
    document = barbell_data.validate(parent, public, True)
    all_train = inputs(parent, document, 'train');validation = inputs(parent, document, 'validation')
    examples = [r for r in all_train if r['head_box'] or r['visibility'] == 'empty']
    if not any(r['head_box'] for r in examples): raise ValueError('No positive training labels')
    device = 'cuda' if torch.cuda.is_available() else 'cpu';model = build(parent).to(device)
    optimizer = torch.optim.SGD([p for p in model.parameters() if p.requires_grad], lr=.002, momentum=.9, weight_decay=.0005)
    rng = np.random.default_rng(365);start = time.monotonic();best = None;history = []
    print('Device', device, 'fit examples', len(examples), 'positive', sum(bool(r['head_box']) for r in examples), flush=True)
    for step in range(1, 1001):
        model.train();model.backbone.body.eval()
        for group in optimizer.param_groups: group['lr'] = .002*min(1., .1+step/30)*(.3 if step>800 else 1.)
        batch = [augment(examples[int(rng.integers(len(examples)))], rng) for _ in range(2)]
        loss = sum(model([x.to(device) for x, _ in batch], [{k:v.to(device) for k,v in y.items()} for _,y in batch]).values())
        if not torch.isfinite(loss): raise ValueError('Nonfinite loss')
        optimizer.zero_grad();loss.backward();torch.nn.utils.clip_grad_norm_(model.parameters(), 10.);optimizer.step()
        if step % 50 == 0: print('step', step, 'loss', round(float(loss.detach()),4), 'seconds',round(time.monotonic()-start,1),flush=True)
        if step % 200: continue
        predicted = predictions(validation, model, device);threshold, metrics = threshold_for(document, predicted)
        item = {'step':step, 'threshold':threshold, 'metrics':metrics};history.append(item)
        print('Validation',step,json.dumps({k:metrics[k] for k in ['tp','fp','fn','f1']}),flush=True)
        quality = (metrics['f1'] or 0, metrics['precision'] or 0, metrics['recall'] or 0, -step)
        if best is None or quality > best[0]:
            save_delta(model, model_path);best=(quality,item,predicted)
    metadata = {'format':'barbell-model/1', 'settings':SETTINGS,
                'architecture':'TorchVision Faster R-CNN ResNet50 FPN v2',
                'pretrained_url':FasterRCNN_ResNet50_FPN_V2_Weights.COCO_V1.url,
                'pretrained_sha256':sha256(parent/'model-cache/checkpoints/fasterrcnn_resnet50_fpn_v2_coco-dd69338a.pth'),
                'delta_sha256':sha256(model_path), 'state_scope':'All tensors except frozen backbone.body',
                'chosen_step':best[1]['step'], 'threshold':best[1]['threshold'],
                'plan_sha256':sha256(parent/'plan.json'), 'fit_reference_sha256':fit_reference(document),
                'fit_sources':sorted({r['clip_sha256'] for r in document['windows'] if r['split']!='test'}),
                'training_positive_frames':sum(bool(r['head_box']) for r in examples),
                'training_empty_frames':sum(r['visibility']=='empty' for r in examples),
                'training_unrated_frames':len(all_train)-len(examples), 'validation_history':history,
                'training_frame_sha256':{r['window_id']+':'+str(r['time_s']):r['pixels_sha256'] for r in examples},
                'validation_frame_sha256':{r['window_id']+':'+str(r['time_s']):r['pixels_sha256'] for r in validation},
                'code_sha256':code_hashes(), 'torch':torch.__version__, 'torchvision':torchvision.__version__,
                'device':device, 'elapsed_s':time.monotonic()-start, 'promoted_for_coaching':False}
    write_json(metadata_path,metadata)
    write_json(output,{'format':'barbell-detection/1','partition':'validation','model_sha256':sha256(model_path),
                       'threshold':metadata['threshold'],'metrics':best[1]['metrics'],'predictions':best[2]})


def test(parent, public, model_path, metadata_path, freeze_path, output):
    if output.exists(): raise ValueError('Preserve the first frozen test result')
    document=barbell_data.validate(parent,public,False);metadata=json.loads(metadata_path.read_text())
    frozen=json.loads(freeze_path.read_text())
    expected={'plan_sha256':sha256(parent/'plan.json'),'model_sha256':sha256(model_path),
              'metadata_sha256':sha256(metadata_path),'code_sha256':code_hashes()}
    if frozen != expected or metadata['code_sha256'] != code_hashes() or metadata['fit_reference_sha256'] != fit_reference(document):
        raise ValueError('Frozen model, references, plan or code changed')
    sources={r['clip_sha256'] for r in document['windows'] if r['split']=='test'}
    if sources & set(metadata['fit_sources']):raise ValueError('Test source in fitting')
    if any(f['visibility']=='unreviewed' for r in document['windows'] if r['split']=='test' for f in r['frames']):
        raise ValueError('Finish held-out annotations before predictions')
    if sha256(parent/'model-cache/checkpoints/fasterrcnn_resnet50_fpn_v2_coco-dd69338a.pth')!=metadata['pretrained_sha256']:
        raise ValueError('Pretrained body changed')
    model=build(parent);missing,unexpected=model.load_state_dict(torch.load(model_path,map_location='cpu',weights_only=True),strict=False)
    if unexpected or any(not k.startswith('backbone.body.') for k in missing):raise ValueError('Incomplete delta')
    device='cuda' if torch.cuda.is_available() else 'cpu';model.to(device).eval()
    predicted=predictions(inputs(parent,document,'test'),model,device)
    write_json(output,{'format':'barbell-detection/1','partition':'test','model_sha256':sha256(model_path),
                       'metadata_sha256':sha256(metadata_path),'threshold':metadata['threshold'],
                       'metrics':score(document,predicted,metadata['threshold']),'predictions':predicted,
                       'claimed_coaching_improvement':False})


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('action',choices=['fit','test'])
    for name in ('parent','reference','model','metadata','output'):parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--freeze',type=Path);args=parser.parse_args()
    torch.set_num_threads(4);torch.manual_seed(365);np.random.seed(365)
    document=json.loads(args.reference.read_text())
    if args.action=='fit':fit(args.parent,document,args.model,args.metadata,args.output)
    else:
        if not args.freeze:parser.error('test needs --freeze')
        test(args.parent,document,args.model,args.metadata,args.freeze,args.output)
