"""Freeze, resume and summarize full-recording native population runs."""
import argparse
import fcntl
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time

from footage import sha256, write_json


def prepare(directory,repo,manifest,root):
    if directory.exists() and any(directory.iterdir()):raise ValueError('Choose an empty output directory')
    directory.mkdir(parents=True,exist_ok=True)
    source=json.loads(manifest.read_text());rows=[]
    for clip in source['clips']:
        path=root/clip['relative_path']
        if sha256(path)!=clip['sha256']:raise ValueError('Source content changed')
        rows.append({**clip,'path':str(path.resolve()),
            'supported_event_hint':None if '/3-Board/' in clip['relative_path'] else
                'underhand' if path.stem=='IMG_3862' else 'standing_block',
            'event_hint_provenance':'Published Gurr-Pipeline-Findings catalog; not a reviewed technique judgment.'})
    document={'format':'gurr-population-input/1','max_sample_rate':30,'max_samples':90000,'clips':rows}
    validate_inputs(document)
    if len(rows)!=source['unique_video_count']:raise ValueError('Inventory source count mismatch')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
    document['runtime_base_commit']=revision
    snapshot=directory/'runtime';snapshot.mkdir()
    data=subprocess.check_output(['git','archive',revision],cwd=repo)
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:archive.extractall(snapshot,filter='data')
    if not (snapshot/'apps/strathvision/tool/population_runner.dart').exists():
        raise ValueError('The native runner must be committed before preparing its snapshot')
    write_json(directory/'inputs.json',document);(directory/'runtime-base.txt').write_text(revision+'\n')
    print(f'Prepared {len(rows)} full source recordings at {revision}')


def sources(repo):
    return [*sorted((repo/'apps/strathvision/lib/vision').glob('*.dart')),
            *sorted((repo/'packages/analysis_engine/lib').rglob('*.dart')),
            *sorted((repo/'apps/strathvision/assets/models').glob('*.onnx')),
            repo/'apps/strathvision/assets/packs/timber.json',
            repo/'apps/strathvision/lib/workbench/carne_athletes.dart',
            repo/'apps/strathvision/lib/profiles/clip_probe.dart',
            repo/'apps/strathvision/tool/population_runner.dart',
            repo/'apps/strathvision/pubspec.lock']


def validate_inputs(document):
    if document.get('format')!='gurr-population-input/1':raise ValueError('Unknown population input')
    clips=document['clips'];hashes=[c['sha256'] for c in clips]
    if not clips or len(set(hashes))!=len(hashes):raise ValueError('Population sources must be unique')
    if any(c['duration_s']<=0 for c in clips):raise ValueError('Invalid full recording duration')
    return clips


def freeze(directory):
    repo=directory/'runtime';inputs=directory/'inputs.json'
    validate_inputs(json.loads(inputs.read_text()))
    binary=repo/'apps/strathvision/build/linux/x64/release/bundle/strathvision'
    document={'format':'gurr-population-freeze/1',
              'runtime_base_commit':(directory/'runtime-base.txt').read_text().strip(),
              'inputs_sha256':sha256(inputs),'binary_sha256':sha256(binary),
              'source_sha256':{str(p.relative_to(repo)):sha256(p) for p in sources(repo)},
              'policy':{'max_sample_rate':30,'max_samples':90000,'full_duration_requested':True,
                        'selection':'Production four-second preflight; deferred sources continue as quarantined diagnostics.',
                        'event_handling':'Both packs are candidate passes; published catalog hints are unreviewed.',
                        'learning_execution':'Not run: no reviewed coach profile/judgments supplied.'}}
    document['runtime_key']=hashlib.sha256(json.dumps(document,sort_keys=True).encode()).hexdigest()
    path=directory/'freeze.json'
    if path.exists() and json.loads(path.read_text())!=document:raise ValueError('Refusing to replace a different runtime freeze')
    write_json(path,document);return document


def validate_result(row,result,key):
    if result.get('runtime_key')!=key or result.get('clip_sha256')!=row['sha256']:
        raise ValueError('Population result provenance mismatch')
    if abs(result.get('inventory_duration_s',0)-row['duration_s'])>.001:
        raise ValueError('Population result duration mismatch')
    if result.get('status')=='complete' and result.get('duration_s',0)<row['duration_s']-.1:
        raise ValueError('A truncated recording cannot count as complete')
    if result.get('status')=='complete':
        for event,counts in result['events'].items():
            if counts['gate_passing_candidates']>counts['candidate_strokes']:
                raise ValueError('Passing candidates exceed detections')
            if counts['production_eligible_strokes'] and (result['production_deferred'] or row['supported_event_hint']!=event):
                raise ValueError('Quarantined or unsupported candidates cannot become production eligible')


def run(directory,workers,display):
    frozen=json.loads((directory/'freeze.json').read_text())
    if freeze(directory)!=frozen:raise ValueError('Frozen runtime changed')
    document=json.loads((directory/'inputs.json').read_text())
    clips=validate_inputs(document)
    original=directory/'runtime/apps/strathvision/build/linux/x64/release/bundle/strathvision'
    bundle=directory/'worker-bundle'
    if not bundle.exists():
        shutil.copytree(original.parent,bundle)
        (bundle/'strathvision').rename(bundle/'carne-pop-worker')
    binary=bundle/'carne-pop-worker'
    if sha256(binary)!=frozen['binary_sha256']:raise ValueError('Worker binary changed')
    output=directory/'native';output.mkdir(exist_ok=True)
    existing=[]
    for row in clips:
        path=output/row['sha256']/'result.json'
        if not path.exists():break
        record=json.loads(path.read_text());validate_result(row,record,frozen['runtime_key'])
        if record['status']!='complete':break
        existing.append(record)
    if len(existing)==len(clips):
        print(f'Resume: all {len(clips)} same-runtime recordings already complete; original timing preserved.',flush=True)
        return
    def active(index):
        for process in Path('/proc').iterdir():
            if not process.name.isdigit():continue
            try:
                if process.joinpath('exe').resolve() not in (original,binary):continue
                values=process.joinpath('environ').read_bytes().split(b'\0')
                required=[f'SV_POP_INDEX={index}',f'SV_POP_RUNTIME_KEY={frozen["runtime_key"]}',
                          f'SV_POP_INPUT={directory/"inputs.json"}']
                if all(value.encode() in values for value in required):return True
            except OSError:continue
        unit=f'carne-pop-{frozen["runtime_key"][:8]}-{clips[index]["sha256"][:16]}'
        state=subprocess.run(['systemctl','--user','show',unit,'--property=ActiveState','--value'],
            stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True).stdout.strip()
        return state in ('active','activating','deactivating')
    def one(index):
        row=clips[index];folder=output/row['sha256'];folder.mkdir(exist_ok=True)
        # Dispatchers can resume without duplicating an in-flight recording.
        with (folder/'worker.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            return locked_one(index,row,folder)
    def locked_one(index,row,folder):
        result=folder/'result.json'
        if active(index):
            while active(index):time.sleep(2)
            if result.exists():
                record=json.loads(result.read_text());validate_result(row,record,frozen['runtime_key'])
                if record['status']=='complete':return {'source':row['relative_path'],'status':'adopted'}
        if result.exists():
            previous=json.loads(result.read_text());validate_result(row,previous,frozen['runtime_key'])
            if previous['status']=='complete':return {'source':row['relative_path'],'status':'resumed'}
            stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%f')
            result.rename(folder/f'failed-attempt-{stamp}.json')
        env={**os.environ,'GDK_BACKEND':'x11','DISPLAY':display,'SV_POP_INPUT':str(directory/'inputs.json'),
             'SV_POP_INDEX':str(index),'SV_POP_OUTPUT':str(output),'SV_POP_RUNTIME_KEY':frozen['runtime_key']}
        log_path=(folder/'native.log').resolve()
        unit=f'carne-pop-{frozen["runtime_key"][:8]}-{row["sha256"][:16]}'
        command=['systemd-run','--user','--collect','--wait','--quiet','--unit='+unit,
                 '--property=Description=CARNE ASADA full recording '+row['relative_path'],
                 '--property=StandardOutput=append:'+str(log_path),
                 '--property=StandardError=append:'+str(log_path)]
        for name in ['GDK_BACKEND','DISPLAY','SV_POP_INPUT','SV_POP_INDEX','SV_POP_OUTPUT','SV_POP_RUNTIME_KEY']:
            command.append('--setenv='+name+'='+env[name])
        command.append(str(binary.resolve()))
        with log_path.open('a') as log:
            process=subprocess.run(command,env=env,stdout=log,stderr=subprocess.STDOUT)
        if not result.exists():
            write_json(result,{'format':'gurr-population-clip/1','runtime_key':frozen['runtime_key'],
                'clip_sha256':row['sha256'],'inventory_duration_s':row['duration_s'],
                'source_name':row['relative_path'],'status':'failed','exit_code':process.returncode,
                'error':'Native process exited before writing a result'})
        record=json.loads(result.read_text());validate_result(row,record,frozen['runtime_key'])
        return {'source':row['relative_path'],'status':record['status'],'exit_code':process.returncode}
    start=time.monotonic();epoch=directory/'run-start.json'
    if not epoch.exists():
        began=[p.stat().st_mtime-json.loads(p.read_text())['elapsed_s'] for p in output.glob('*/progress.json')]
        write_json(epoch,{'epoch_s':min(began,default=time.time()),'runtime_key':frozen['runtime_key']})
    with ThreadPoolExecutor(max_workers=workers) as pool:
        order=document.get('dispatch_order',sorted(range(len(clips)),key=lambda i:-clips[i]['duration_s']))
        if sorted(order)!=list(range(len(clips))):raise ValueError('Invalid dispatch order')
        futures=[pool.submit(one,i) for i in order]
        for count,future in enumerate(as_completed(futures),1):
            print(json.dumps({'finished':count,'total':len(clips),'elapsed_s':round(time.monotonic()-start,1),**future.result()}),flush=True)
    write_json(directory/'run-execution.json',{'workers':workers,'wall_s':time.time()-json.loads(epoch.read_text())['epoch_s'],
        'dispatcher_wall_s':time.monotonic()-start,
        'expected_sources':len(clips),'runtime_key':frozen['runtime_key']})


def summarize(clips,records,key):
    expected={c['sha256']:c for c in clips};byhash={}
    for result in records:
        identity=result['clip_sha256']
        if identity not in expected or identity in byhash:raise ValueError('Unexpected or repeated population source')
        validate_result(expected[identity],result,key);byhash[identity]=result
    if set(byhash)!=set(expected):raise ValueError('Population is incomplete')
    complete=[r for r in records if r['status']=='complete']
    events={}
    for event in ['underhand','standing_block']:
        events[event]={k:sum(r['events'][event][k] for r in complete) for k in
            ['candidate_strokes','gate_passing_candidates','gate_passing_seconds','production_eligible_strokes']}
    return {'recordings':len(clips),'inventory_duration_s':sum(c['duration_s'] for c in clips),
        'native_completed':len(complete),'native_failed':len(records)-len(complete),
        'full_span_reached':sum(r['full_span_reached'] for r in complete),
        'production_deferred':sum(r['production_deferred'] for r in complete),
        'unsupported_catalog_event':sum(c['supported_event_hint'] is None for c in clips),
        'pose_samples':sum(r['pose_samples'] for r in complete),
        'expected_samples':sum(r['expected_sample_count'] for r in complete),'candidate_event_passes':events}


def publish(directory,output):
    frozen=json.loads((directory/'freeze.json').read_text());clips=validate_inputs(json.loads((directory/'inputs.json').read_text()))
    records=[json.loads((directory/'native'/c['sha256']/'result.json').read_text()) for c in clips]
    for row,record in zip(clips,records):
        previous=sorted((directory/'native'/row['sha256']).glob('failed-attempt-*.json'))
        record['previous_failed_attempts']=[{k:d.get(k) for k in ['status','exit_code','error']}
            for d in [json.loads(path.read_text()) for path in previous]]
        if record.get('error'):
            record['error']=record['error'].replace(row['path'],row['relative_path']).replace(str(directory),'<private analysis>')
    result={'format':'gurr-full-population/1','freeze':frozen,
        'orchestration_sha256':sha256(Path(__file__)),
        'summary':summarize(clips,records,frozen['runtime_key']),'clips':records,
        'limitations':['Full recording durations requested; pipeline failures/early stops are retained explicitly.',
            'Unlabelled population coverage is not contact accuracy or correct-athlete identity evidence.',
            'Deferred-source diagnostics are quarantined from production-eligible counts.',
            'Candidate event passes and unreviewed catalog hints are not confirmed event assignments.',
            'No coaching judgments, identity recognition or learning improvement are invented.'],
        'learning_execution':'not_run_no_reviewed_coach_profile_or_feedback',
        'claimed_technique_improvement':False,'raw_footage_published':False}
    if (directory/'run-execution.json').exists():result['execution']=json.loads((directory/'run-execution.json').read_text())
    write_json(output,result);print(json.dumps(result['summary'],indent=2))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['prepare','freeze','run','publish'])
    p.add_argument('--directory',type=Path,required=True);p.add_argument('--workers',type=int,default=3)
    p.add_argument('--display',default=':93');p.add_argument('--output',type=Path)
    for name in ['repo','manifest','root']:p.add_argument('--'+name,type=Path)
    a=p.parse_args()
    if a.action=='prepare':
        if not a.repo or not a.manifest or not a.root:p.error('prepare requires --repo, --manifest and --root')
        prepare(a.directory,a.repo,a.manifest,a.root)
    elif a.action=='freeze':print(freeze(a.directory)['runtime_key'])
    elif a.action=='run':run(a.directory,a.workers,a.display)
    else:
        if not a.output:p.error('publish requires --output')
        publish(a.directory,a.output)


if __name__=='__main__':main()
