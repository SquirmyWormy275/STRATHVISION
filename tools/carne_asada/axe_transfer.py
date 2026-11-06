"""A frozen-backbone SSDLite axe experiment; never fits on test sources."""
import argparse
from functools import partial
import hashlib
import json
from pathlib import Path
import time

import cv2
import numpy as np
import torch
from torch import nn
import torchvision
from torchvision.models.detection import ssdlite320_mobilenet_v3_large, SSDLite320_MobileNet_V3_Large_Weights
from torchvision.models.detection.ssdlite import SSDLiteClassificationHead

from axe_data import frame_path, validate
from axe_detector import pixels, score
from footage import sha256, write_json

SETTINGS={'seed':365,'steps':400,'batch_size':4,'learning_rate':.001,
          'frozen_backbone':True,'train_crop_px':[64,96,128,192,256],
          'inference_tiles_px':[128,256],'iou_threshold':.5,
          'max_candidates_per_frame':1}


def code_hashes():
    return {name:sha256(Path(__file__).with_name(name)) for name in
            ['axe_transfer.py','axe_data.py','axe_detector.py','footage.py']}


def fit_reference(document):
    subset={'format':document['format'],'windows':[r for r in document['windows'] if r['split'] in ('train','validation')]}
    return hashlib.sha256(json.dumps(subset,sort_keys=True).encode()).hexdigest()


def build(pretrained=False):
    weights=SSDLite320_MobileNet_V3_Large_Weights.COCO_V1 if pretrained else None
    model=ssdlite320_mobilenet_v3_large(weights=weights,weights_backbone=None)
    old=model.head.classification_head
    channels=[block[0][0].in_channels for block in old.module_list]
    model.head.classification_head=SSDLiteClassificationHead(
        channels,model.anchor_generator.num_anchors_per_location(),2,
        norm_layer=partial(nn.BatchNorm2d,eps=.001,momentum=.03))
    for p in model.backbone.parameters():p.requires_grad=False
    return model


def tensor(image):
    return torch.from_numpy(cv2.cvtColor(image,cv2.COLOR_BGR2RGB).copy()).permute(2,0,1).float()/255


def augment(image,box,rng):
    h,w=image.shape[:2];x,y,r,b=pixels(box,w,h)
    positive=bool(rng.random()<.7)
    for _ in range(100):
        side=min(int(rng.choice(SETTINGS['train_crop_px'])),w,h)
        if positive:
            xx=round(np.clip((x+r)/2-side/2+rng.uniform(-.22,.22)*side,0,w-side))
            yy=round(np.clip((y+b)/2-side/2+rng.uniform(-.22,.22)*side,0,h-side))
            if x<xx or y<yy or r>xx+side or b>yy+side:continue
        else:
            xx=int(rng.integers(0,w-side+1));yy=int(rng.integers(0,h-side+1))
            if xx<r and xx+side>x and yy<b and yy+side>y:continue
        break
    else:
        xx=max(0,x-10);yy=max(0,y-10);side=min(max(r-x,b-y)+20,w-xx,h-yy);positive=True
    patch=image[yy:yy+side,xx:xx+side].copy()
    boxes=np.array([[x-xx,y-yy,r-xx,b-yy]],np.float32) if positive else np.empty((0,4),np.float32)
    if rng.random()<.5:
        patch=patch[:,::-1].copy()
        if len(boxes):boxes[:,[0,2]]=side-boxes[:,[2,0]]
    patch=np.clip(patch.astype(np.float32)*rng.uniform(.85,1.15),0,255).astype(np.uint8)
    return tensor(patch),{'boxes':torch.from_numpy(boxes),'labels':torch.ones(len(boxes),dtype=torch.int64)}


def detect(image,roi,model,device):
    h,w=image.shape[:2];a,b,c,d=pixels(roi,w,h)
    locations=[(a,b,c,d)]
    for side in SETTINGS['inference_tiles_px']:
        if side>min(c-a,d-b):continue
        xs=sorted(set(range(a,c-side+1,side//2))|{c-side})
        ys=sorted(set(range(b,d-side+1,side//2))|{d-side})
        locations.extend((x,y,x+side,y+side) for y in ys for x in xs)
    best=None
    with torch.inference_mode():
        for start in range(0,len(locations),8):
            batch=locations[start:start+8]
            outputs=model([tensor(image[y:bb,x:rr]).to(device) for x,y,rr,bb in batch])
            for (x,y,rr,bb),out in zip(batch,outputs):
                if not len(out['scores']):continue
                scores=out['scores'].cpu().numpy();k=int(np.argmax(scores));value=float(scores[k])
                if best is None or value>best['margin']:
                    left,top,right,bottom=out['boxes'][k].cpu().tolist()
                    best={'box':[(x+left)/w,(y+top)/h,(x+right)/w,(y+bottom)/h],'margin':value}
    return best


def predictions(document,frames,model,device,split):
    rows=[]
    for row in document['windows']:
        if row['split']!=split:continue
        for f in row['frames']:
            image=cv2.imread(str(frame_path(frames,row,f['time_s'])))
            if image is None:raise ValueError('Missing prepared frame')
            rows.append({'window_id':row['window_id'],'clip_sha256':row['clip_sha256'],
                         'time_s':f['time_s'],'candidate':detect(image,row['search_roi'],model,device)})
        print('Predicted',row['window_id'],flush=True)
    return rows


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['fit','test'])
    for name in ['reference','frames','model','metadata','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--freeze',type=Path);a=p.parse_args();document=validate(json.loads(a.reference.read_text()))
    torch.set_num_threads(4);torch.manual_seed(365);np.random.seed(365)
    torch.use_deterministic_algorithms(True,warn_only=True)
    device='cuda' if torch.cuda.is_available() else 'cpu';print('Device',device,flush=True)
    if a.action=='fit':
        examples=[];pixel_hashes={}
        for row in document['windows']:
            if row['split']!='train':continue
            for f in row['frames']:
                if f['head_box'] is None:continue
                path=frame_path(a.frames,row,f['time_s']);image=cv2.imread(str(path))
                if image is None:raise ValueError('Missing training pixels')
                examples.append((image,f['head_box']))
                pixel_hashes[f'{row["window_id"]}:{f["time_s"]}']=sha256(path)
        if not examples:raise ValueError('No visible training examples')
        model=build(True).to(device);model.train();model.backbone.eval()
        optimizer=torch.optim.AdamW([x for x in model.parameters() if x.requires_grad],lr=.001)
        rng=np.random.default_rng(365);start=time.monotonic();losses=[]
        for step in range(400):
            batch=[augment(*examples[int(rng.integers(len(examples)))],rng) for _ in range(4)]
            loss=sum(model([x.to(device) for x,_ in batch],[{k:v.to(device) for k,v in y.items()} for _,y in batch]).values())
            if not torch.isfinite(loss):raise ValueError('Non-finite training loss')
            optimizer.zero_grad();loss.backward();optimizer.step();losses.append(float(loss.detach()))
            if (step+1)%50==0:print('step',step+1,'loss',round(losses[-1],4),'elapsed',round(time.monotonic()-start,1),flush=True)
        model.eval();a.model.parent.mkdir(parents=True,exist_ok=True)
        torch.save({k:v.cpu() for k,v in model.state_dict().items()},a.model)
        rows=predictions(document,a.frames,model,device,'validation')
        thresholds=sorted({r['candidate']['margin'] for r in rows if r['candidate']})
        thresholds+=[max(thresholds,default=0)+.001]
        threshold=max(thresholds,key=lambda t:((score(document,rows,t)['f1'] or 0),t))
        weight_file=Path(torch.hub.get_dir())/'checkpoints/ssdlite320_mobilenet_v3_large_coco-a79551df.pth'
        metadata={'format':'axe-transfer-model/1','architecture':'TorchVision ssdlite320_mobilenet_v3_large',
                  'pretrained_url':'https://download.pytorch.org/models/ssdlite320_mobilenet_v3_large_coco-a79551df.pth',
                  'pretrained_sha256':sha256(weight_file),'state_sha256':sha256(a.model),
                  'settings':SETTINGS,'threshold':threshold,'fit_reference_sha256':fit_reference(document),
                  'fit_sources':sorted({r['clip_sha256'] for r in document['windows'] if r['split']!='test'}),
                  'training_frame_sha256':pixel_hashes,'code_sha256':code_hashes(),
                  'device':device,'torch':torch.__version__,'torchvision':torchvision.__version__,
                  'unique_positive_frames':len(examples),'final_training_loss':losses[-1],
                  'training_elapsed_s':time.monotonic()-start,'promoted_for_coaching':False}
        write_json(a.metadata,metadata)
        result={'format':'axe-detection/1','partition':'validation','model_sha256':sha256(a.model),
                'threshold':threshold,'metrics':score(document,rows,threshold),'predictions':rows}
    else:
        if not a.freeze:raise ValueError('Test inference requires a separate committed freeze')
        metadata=json.loads(a.metadata.read_text());frozen=json.loads(a.freeze.read_text())
        expected={'reference_sha256':sha256(a.reference),'model_sha256':sha256(a.model),
                  'metadata_sha256':sha256(a.metadata),'code_sha256':code_hashes()}
        if frozen!=expected or metadata['fit_reference_sha256']!=fit_reference(document):
            raise ValueError('Frozen model/reference/code changed before test')
        if set(metadata['fit_sources']) & {r['clip_sha256'] for r in document['windows'] if r['split']=='test'}:
            raise ValueError('Test source leaked into fitting')
        model=build(False);model.load_state_dict(torch.load(a.model,map_location='cpu',weights_only=True));model.to(device).eval()
        rows=predictions(document,a.frames,model,device,'test');threshold=metadata['threshold']
        result={'format':'axe-detection/1','partition':'test','model_sha256':sha256(a.model),
                'threshold':threshold,'metrics':score(document,rows,threshold),'predictions':rows}
    write_json(a.output,result);print(json.dumps(result['metrics'],indent=2))


if __name__=='__main__':main()
