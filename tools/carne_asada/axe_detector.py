"""Train/validate/freeze a small image-only HOG + linear-SVM axe prototype.

This detector does not use pose, wrists, contact labels or test-source fitting.
The reference supplies an initial fixed search region, not future axe positions.
"""
import argparse
import json
from pathlib import Path

import cv2
import numpy as np

from axe_data import frame_path, validate
from footage import iou, sha256, write_json


SETTINGS = {'patch_px': 32, 'cell_px': 8, 'bins': 9,
            'window_sizes_px': [12, 20, 32, 48, 72], 'stride_fraction': .5,
            'iou_threshold': .5, 'seed': 365, 'epochs': 300, 'l2': .001,
            'one_candidate_per_frame': True}


def features(patch):
    """Unsigned gradients; 4x4 cells, 2x2 L2-normalized blocks (324 values)."""
    gray=cv2.cvtColor(patch,cv2.COLOR_BGR2GRAY) if patch.ndim==3 else patch
    gray=cv2.resize(gray,(32,32),interpolation=cv2.INTER_AREA).astype(np.float32)/255
    dx=cv2.Sobel(gray,cv2.CV_32F,1,0,ksize=1)
    dy=cv2.Sobel(gray,cv2.CV_32F,0,1,ksize=1)
    magnitude,angle=cv2.cartToPolar(dx,dy,angleInDegrees=True)
    bins=(angle%180/20).astype(np.int32).clip(0,8)
    yy,xx=np.indices((32,32))
    index=((yy//8)*4+xx//8)*9+bins
    cells=np.bincount(index.ravel(),weights=magnitude.ravel(),minlength=144).reshape(4,4,9)
    blocks=[]
    for y in range(3):
        for x in range(3):
            block=cells[y:y+2,x:x+2].ravel()
            block=np.minimum(block/np.sqrt(np.dot(block,block)+1e-6),.2)
            blocks.append(block/np.sqrt(np.dot(block,block)+1e-6))
    return np.concatenate(blocks).astype(np.float32)


def pixels(box,w,h):
    return [round(box[0]*w),round(box[1]*h),round(box[2]*w),round(box[3]*h)]


def crop(image,box):
    x,y,r,b=pixels(box,image.shape[1],image.shape[0])
    if r<=x or b<=y:
        raise ValueError('Empty image patch')
    return image[y:b,x:r]


def square(box,w,h,padding=1):
    cx=(box[0]+box[2])*w/2;cy=(box[1]+box[3])*h/2
    size=max((box[2]-box[0])*w,(box[3]-box[1])*h)*padding
    return [max(0,(cx-size/2)/w),max(0,(cy-size/2)/h),
            min(1,(cx+size/2)/w),min(1,(cy+size/2)/h)]


def fit_linear(x,y,epochs=300):
    """Deterministic balanced hinge loss with L2 regularization."""
    x=np.asarray(x,np.float32);y=np.asarray(y,np.float32)
    if set(y.tolist())!={-1.,1.}:
        raise ValueError('Training requires positive and negative image patches')
    weights=np.where(y>0,len(y)/(2*(y>0).sum()),len(y)/(2*(y<0).sum())).astype(np.float32)
    coef=np.zeros(x.shape[1],np.float32);bias=0.
    for epoch in range(epochs):
        active=(y*(x@coef+bias)<1).astype(np.float32)*weights*y
        rate=.1/(1+epoch/100)
        coef-=rate*(SETTINGS['l2']*coef-x.T@active/len(y))
        bias+=rate*float(active.mean())
    return coef,bias


def train(document,frames):
    validate(document)
    rng=np.random.default_rng(SETTINGS['seed'])
    x,y,used=[],[],[]
    for row in document['windows']:
        if row['split']!='train':continue
        for annotation in row['frames']:
            box=annotation['head_box']
            # Hidden/unreviewed axes cannot generate background labels.
            if box is None:continue
            used.append(row['clip_sha256'])
            image=cv2.imread(str(frame_path(frames,row,annotation['time_s'])))
            if image is None:raise ValueError('Missing prepared training image')
            h,w=image.shape[:2];base=square(box,w,h,1.15)
            for scale in [.9,1.,1.1]:
                for dx,dy in [(0,0),(-.1,0),(.1,0),(0,-.1),(0,.1)]:
                    cx=(base[0]+base[2])/2;cy=(base[1]+base[3])/2
                    sw=(base[2]-base[0])*scale;sh=(base[3]-base[1])*scale
                    jitter=[max(0,cx+dx*sw-sw/2),max(0,cy+dy*sh-sh/2),
                            min(1,cx+dx*sw+sw/2),min(1,cy+dy*sh+sh/2)]
                    x.append(features(crop(image,jitter)));y.append(1.)
            a,b,c,d=row['search_roi']
            ignored=annotation.get('ignored_boxes',[])
            for _ in range(160):
                side=int(rng.choice(SETTINGS['window_sizes_px']))
                if (c-a)*w<=side or (d-b)*h<=side:continue
                px=rng.uniform(a*w,c*w-side);py=rng.uniform(b*h,d*h-side)
                negative=[px/w,py/h,(px+side)/w,(py+side)/h]
                if iou(negative,base)>.05 or any(iou(negative,z)>.01 for z in ignored):continue
                x.append(features(crop(image,negative)));y.append(-1.)
    if not x:raise ValueError('No visible training axe annotations')
    coef,bias=fit_linear(x,y,SETTINGS['epochs'])
    return {'format':'axe-model/1','method':'image HOG plus linear hinge-loss SVM',
            'settings':SETTINGS,'coef':coef.tolist(),'bias':bias,
            'threshold':None,'training_sources':sorted(set(used)),
            'training_patches':{'positive':y.count(1.),'negative':y.count(-1.)},
            'dependencies':{'numpy':np.__version__,'opencv':cv2.__version__},
            'code_sha256':sha256(Path(__file__))}


def detect(image,roi,model):
    h,w=image.shape[:2];a,b,c,d=pixels(roi,w,h)
    coef=np.asarray(model['coef'],np.float32)
    descriptors,boxes=[],[]
    for size in model['settings']['window_sizes_px']:
        step=max(4,round(size*model['settings']['stride_fraction']))
        for yy in range(b,d-size+1,step):
            for xx in range(a,c-size+1,step):
                descriptors.append(features(image[yy:yy+size,xx:xx+size]))
                boxes.append([xx/w,yy/h,(xx+size)/w,(yy+size)/h])
    if not descriptors:return None
    scores=np.asarray(descriptors)@coef+model['bias'];best=int(np.argmax(scores))
    return {'box':boxes[best],'margin':float(scores[best])}


def predict(document,frames,model,split):
    if split=='test' and model.get('freeze') is None:
        raise ValueError('Test inference requires a frozen model')
    result=[]
    for row in document['windows']:
        if row['split']!=split:continue
        for f in row['frames']:
            image=cv2.imread(str(frame_path(frames,row,f['time_s'])))
            if image is None:raise ValueError('Missing prepared inference image')
            hit=detect(image,row['search_roi'],model)
            result.append({'window_id':row['window_id'],'clip_sha256':row['clip_sha256'],
                           'time_s':f['time_s'],'candidate':hit})
        print('Predicted',row['window_id'],flush=True)
    return result


def score(document,predictions,threshold):
    byid={(r['window_id'],r['time_s']):r for r in predictions}
    if len(byid)!=len(predictions):
        raise ValueError('Duplicate predicted frame')
    tp=fp=fn=unknown=0;ious=[];per_window=[]
    for row in document['windows']:
        counts={'tp':0,'fp':0,'fn':0,'unrated':0}
        for f in row['frames']:
            predicted=byid.get((row['window_id'],f['time_s']))
            if predicted is None:continue
            if predicted['clip_sha256']!=row['clip_sha256']:
                raise ValueError('Prediction source content mismatch')
            if f['head_box'] is None and f['visibility']!='empty':
                unknown+=1;counts['unrated']+=1;continue
            hit=predicted['candidate'];box=hit['box'] if hit and hit['margin']>=threshold else None
            overlap=iou(box,f['head_box']) if box and f['head_box'] else 0
            if overlap>=SETTINGS['iou_threshold']:
                tp+=1;counts['tp']+=1;ious.append(overlap)
            else:
                if box:fp+=1;counts['fp']+=1
                if f['head_box']:fn+=1;counts['fn']+=1
        if any((row['window_id'],f['time_s']) in byid for f in row['frames']):
            per_window.append({'window_id':row['window_id'],**counts})
    return {'tp':tp,'fp':fp,'fn':fn,'unrated_frames':unknown,
            'precision':tp/(tp+fp) if tp+fp else None,'recall':tp/(tp+fn) if tp+fn else None,
            'f1':2*tp/(2*tp+fp+fn) if 2*tp+fp+fn else None,
            'mean_matched_iou':float(np.mean(ious)) if ious else None,'windows':per_window}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['fit','test'])
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--frames',type=Path,required=True)
    p.add_argument('--model',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args();document=validate(json.loads(args.reference.read_text()))
    if args.action=='fit':
        model=train(document,args.frames)
        # Only training/validation references are hashed during fitting.
        subset={'format':document['format'],'windows':[r for r in document['windows'] if r['split']!='test']}
        model['fit_reference_sha256']=__import__('hashlib').sha256(json.dumps(subset,sort_keys=True).encode()).hexdigest()
        predictions=predict(document,args.frames,model,'validation')
        thresholds=sorted({r['candidate']['margin'] for r in predictions if r['candidate']})
        thresholds+=[max(thresholds,default=0)+1]
        best=max(thresholds,key=lambda t:((score(document,predictions,t)['f1'] or 0),t))
        model['threshold']=best
        model['validation_sources']=sorted({r['clip_sha256'] for r in document['windows'] if r['split']=='validation'})
        model['freeze']={'reference_sha256':sha256(args.reference),'code_sha256':sha256(Path(__file__)),
                         'data_code_sha256':sha256(Path(__file__).with_name('axe_data.py'))}
        write_json(args.model,model)
        report={'format':'axe-detection/1','partition':'validation','model_sha256':sha256(args.model),
                'threshold':best,'metrics':score(document,predictions,best),'predictions':predictions}
    else:
        model=json.loads(args.model.read_text())
        expected={'reference_sha256':sha256(args.reference),'code_sha256':sha256(Path(__file__)),
                  'data_code_sha256':sha256(Path(__file__).with_name('axe_data.py'))}
        if model.get('freeze')!=expected:raise ValueError('Frozen reference/code changed before test')
        if set(model['training_sources']+model['validation_sources']) & {r['clip_sha256'] for r in document['windows'] if r['split']=='test'}:
            raise ValueError('Test source leaked into fitting')
        predictions=predict(document,args.frames,model,'test')
        report={'format':'axe-detection/1','partition':'test','model_sha256':sha256(args.model),
                'threshold':model['threshold'],'metrics':score(document,predictions,model['threshold']),'predictions':predictions}
    write_json(args.output,report)
    print(json.dumps(report['metrics'],indent=2))


if __name__=='__main__':main()
