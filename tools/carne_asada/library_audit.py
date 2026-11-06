"""Sample every verified lifting source for decode/person coverage; keep reserved tests sealed.

This is automatic sampling coverage, not localization accuracy or full-duration inference.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import threading

import cv2
import numpy as np

from footage import Detector, sha256, write_json
from ingest_library import signature
from new_dataset import TONE


def reserved(selection, files):
    paths = {r['relative_path'] for r in selection['sources'] if r['study_split'] == 'test'}
    # A second filename for the same payload must not bypass the test seal.
    return {r['sha256'] for r in files if r.get('sha256') and r['relative_path'] in paths}


def open_seal(selection, frozen, weights, plan):
    lock = json.loads(frozen.read_text())
    if weights is None or sha256(weights) != lock['model_sha256']:
        raise ValueError('Actual frozen weights required to open reserved test sources')
    if plan is None or sha256(plan) != lock['plan_sha256']:
        raise ValueError('Actual frozen source plan required')
    planned = json.loads(plan.read_text())
    expected = {(r['relative_path'], r['study_split']) for r in selection['sources']}
    actual = {(r['relative_path'], r['split']) for r in planned['sources']}
    if actual != expected:
        raise ValueError('Freeze belongs to a different source selection')


def unchanged(path, expected):
    try:
        return signature(path) == expected
    except OSError:
        return False


def audit(inventory, selection_path, model, output, frozen=None, weights=None, plan=None, workers=3):
    doc=json.loads(inventory.read_text());root=Path(doc['root'])
    selection=json.loads(selection_path.read_text());sealed=reserved(selection, doc['files'])
    if frozen:
        open_seal(selection, frozen, weights, plan)
        sealed=set()
    output.mkdir(parents=True,exist_ok=True);model_sha=sha256(model);local=threading.local()
    unique={}
    for r in doc['files']:
        if r.get('state')=='verified' and r['sport']=='olympic_weightlifting':unique.setdefault(r['sha256'],r)
    def one(source):
        path=output/(source['sha256']+'.json')
        if source['sha256'] in sealed:
            return {'clip_sha256':source['sha256'],'state':'reserved_test_unopened'}
        if path.exists():
            row=json.loads(path.read_text())
            if row['detector_sha256']!=model_sha or row['source_signature']!=source['signature']:
                raise ValueError('Audit resume model/source mismatch')
            if row['state']=='complete' and unchanged(root/source['relative_path'], source['signature']):
                return row
        row={'clip_sha256':source['sha256'],'source_signature':source['signature'],
             'detector_sha256':model_sha,'samples':[],'state':'complete'}
        try:
            if not hasattr(local, 'detector'):local.detector=Detector(model)
            source_path=root/source['relative_path']
            if signature(source_path)!=source['signature']:raise ValueError('Source changed after hash verification')
            for fraction in [.1,.5,.9]:
                t=round(source['duration_s']*fraction,6)
                filters=([TONE] if source.get('color_transfer') in ('arib-std-b67','smpte2084') else [])
                filters+=['scale=960:960:force_original_aspect_ratio=decrease:force_divisible_by=2']
                process=subprocess.run(['ffmpeg','-v','error','-threads','1','-ss',str(t),'-i',str(source_path),
                                        '-frames:v','1','-vf',','.join(filters),'-threads','1',
                                        '-f','image2pipe','-vcodec','png','-'],capture_output=True,check=True,timeout=90)
                im=cv2.imdecode(np.frombuffer(process.stdout,np.uint8),cv2.IMREAD_COLOR)
                if im is None:raise ValueError('Empty decoded image')
                detections=local.detector.detect(im)
                row['samples'].append({'time_s':t,'width':im.shape[1],'height':im.shape[0],
                                       'people':len(detections),'person_boxes':detections})
            if signature(source_path)!=source['signature']:raise ValueError('Source changed during sampling')
        except (OSError,ValueError,cv2.error,subprocess.SubprocessError) as exc:
            row.update(state='failed',reason=type(exc).__name__+': '+str(exc)[:200])
        write_json(path,row)
        return row
    rows=[]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for k,row in enumerate(pool.map(one,unique.values())):
            rows.append(row)
            if (k+1)%20==0 or row['state']=='failed':print('Audit',k+1,'/',len(unique),row['state'],flush=True)
    summary={'format':'library-sample-audit/1','inventory_sha256':sha256(inventory),'detector_sha256':model_sha,
             'sampling_fractions':[.1,.5,.9],'source_count':len(unique),
             'detector':'YOLOX Nano COCO person', 'score_threshold': .4,
             'code_sha256':sha256(Path(__file__)),
             'complete':sum(r['state']=='complete' for r in rows),
             'failed':sum(r['state']=='failed' for r in rows),
             'reserved':sum(r['state']=='reserved_test_unopened' for r in rows),
             'sampled_frames':sum(len(r.get('samples',[])) for r in rows),
             'frames_with_people':sum(f['people']>0 for r in rows for f in r.get('samples',[])),
             'frames_with_multiple_people':sum(f['people']>1 for r in rows for f in r.get('samples',[])),
             'accuracy_claim':False,'full_duration_inference':False,'sources':rows}
    write_json(output/'summary.json',summary)
    print(json.dumps({k:v for k,v in summary.items() if k!='sources'},indent=2),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['inventory','selection','model','output']:parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--freeze',type=Path);parser.add_argument('--weights',type=Path)
    parser.add_argument('--plan',type=Path)
    parser.add_argument('--workers',type=int,default=3)
    a=parser.parse_args();audit(a.inventory,a.selection,a.model,a.output,a.freeze,a.weights,a.plan,a.workers)
