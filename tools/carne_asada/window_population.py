"""Bounded native scan of every source second, with explicit context and dedup."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import hashlib
from pathlib import Path
import subprocess

from footage import sha256,write_json
from population import validate_inputs


def intervals(duration,core=45,context=4):
    if duration<=0 or core<=0 or context<0:raise ValueError('Invalid interval settings')
    rows=[];start=0.
    while start<duration:
        end=min(duration,start+core)
        rows.append({'core_start_s':start,'core_end_s':end,
            'window_start_s':max(0.,start-context),'window_end_s':min(duration,end+context)})
        start=end
    return rows


def verify_coverage(rows,duration):
    end=0.
    for row in sorted(rows,key=lambda r:r['core_start_s']):
        if abs(row['core_start_s']-end)>1e-6:raise ValueError('Gap or overlap in scored source coverage')
        if not row['window_start_s']<=row['core_start_s']<row['core_end_s']<=row['window_end_s']:
            raise ValueError('Core outside decoded context')
        end=row['core_end_s']
    if abs(end-duration)>1e-6:raise ValueError('Source tail omitted')


def prepare(parent,workers):
    original=json.loads((parent/'inputs.json').read_text());sources=validate_inputs(original)
    directory=parent/'bounded';directory.mkdir(exist_ok=True);media=directory/'media';media.mkdir(exist_ok=True)
    if (directory/'inputs.json').exists():raise ValueError('Window inputs already exist; resume the frozen run')
    runtime=directory/'runtime'
    if not runtime.exists():runtime.symlink_to(parent/'runtime',target_is_directory=True)
    (directory/'runtime-base.txt').write_text((parent/'runtime-base.txt').read_text())
    jobs=[]
    for source_index,source in enumerate(sources):
        plan=intervals(source['duration_s']);verify_coverage(plan,source['duration_s'])
        for window_index,window in enumerate(plan):jobs.append((source_index,window_index,source,window))
    def one(job):
        source_index,window_index,source,window=job
        name=f'{source["sha256"][:16]}-{window_index:04d}'
        output=media/(name+'.mkv');duration=window['window_end_s']-window['window_start_s']
        if not output.exists():
            temporary=output.with_suffix('.pending.mkv')
            # Lossless decoded pixels at the same 960-pixel study resolution
            # used by the original native diagnostic. HDR transfer is retained.
            with output.with_suffix('.ffmpeg.log').open('w') as log:
                subprocess.run(['ffmpeg','-y','-v','error','-threads','1','-ss',str(window['window_start_s']),
                    '-i',source['path'],'-t',str(duration),'-map','0:v:0','-an',
                    '-vf','scale=960:960:force_original_aspect_ratio=decrease:force_divisible_by=2',
                    '-c:v','ffv1','-level','3','-threads','1',str(temporary)],stdout=log,stderr=subprocess.STDOUT,check=True)
            temporary.replace(output)
        actual=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration',
            '-of','default=nw=1:nk=1',str(output)]))
        if actual<duration-.12:raise ValueError('Prepared window is truncated')
        return {'sha256':sha256(output),'path':str(output.resolve()),'relative_path':source['relative_path']+'#'+name,
            'duration_s':actual,'supported_event_hint':source['supported_event_hint'],
            'event_hint_provenance':source['event_hint_provenance'],'source_index':source_index,
            'window_index':window_index,'original_clip_sha256':source['sha256'],**window}
    rows=[];errors=[]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures=[pool.submit(one,job) for job in jobs]
        for n,future in enumerate(as_completed(futures),1):
            try:rows.append(future.result())
            except Exception as error:errors.append(str(error))
            if n%5==0 or n==len(jobs):print(f'WINDOWS {n}/{len(jobs)}, errors={len(errors)}',flush=True)
    if errors:
        write_json(directory/'prepare-errors.json',errors);raise ValueError('Window preparation failed; complete windows preserved')
    rows.sort(key=lambda r:(r['window_index'],r['source_index']))
    document={'format':'gurr-population-input/1','runtime_base_commit':original['runtime_base_commit'],
        'max_sample_rate':30,'max_samples':90000,'processing_variant':'bounded-full-coverage-45s-cores-4s-context',
        'original_sources':[{k:v for k,v in s.items() if k!='path'} for s in sources],
        'clips':rows,'dispatch_order':list(range(len(rows))),
        'preparation_code_sha256':sha256(Path(__file__))}
    validate_inputs(document);write_json(directory/'inputs.json',document)
    print(f'Prepared {len(rows)} native windows covering every source interval of {len(sources)} recordings.',flush=True)


def deduplicate(rows):
    # Only cross-window predictions compete. Keep the candidate with usable
    # phases first, then the one with more context around its midpoint.
    ordered=sorted(rows,key=lambda r:(not r['usable'],-r['context_margin_s'],r['span_s'][0]))
    kept=[];removed=0
    for row in ordered:
        lo,hi=row['span_s'];duplicate=False
        for other in kept:
            if other['window_index']==row['window_index']:continue
            a,b=other['span_s'];overlap=max(0,min(hi,b)-max(lo,a));union=max(hi,b)-min(lo,a)
            if union>0 and overlap/union>=.5:duplicate=True;break
        if duplicate:removed+=1
        else:kept.append(row)
    return sorted(kept,key=lambda r:r['span_s'][0]),removed


def span_union_seconds(spans):
    end=None;total=0.
    for lo,hi in sorted(spans):
        if end is None or lo>=end:total+=hi-lo;end=hi
        elif hi>end:total+=hi-end;end=hi
    return total


def collate(parent,output,replay_label=None):
    directory=parent/'bounded';inputs=json.loads((directory/'inputs.json').read_text())
    locations={};batch_freezes=[]
    for batch in sorted((directory/'batches').glob('batch-*')):
        binputs=json.loads((batch/'inputs.json').read_text());bfreeze=json.loads((batch/'freeze.json').read_text())
        if batch_freezes and (bfreeze['binary_sha256']!=batch_freezes[0]['binary_sha256'] or
                             bfreeze['source_sha256']!=batch_freezes[0]['source_sha256']):
            raise ValueError('Different native algorithms mixed between batches')
        batch_freezes.append(bfreeze)
        for row in binputs['clips']:
            if row['sha256'] in locations:raise ValueError('Repeated window between batches')
            locations[row['sha256']]=(batch,bfreeze['runtime_key'])
    if set(locations)!={r['sha256'] for r in inputs['clips']}:raise ValueError('Missing or unexpected native window')
    study_key=hashlib.sha256((sha256(directory/'inputs.json')+batch_freezes[0]['binary_sha256']).encode()).hexdigest()
    frozen={'format':'gurr-window-batch-freezes/1','study_key':study_key,
            'shared_native_binary_sha256':batch_freezes[0]['binary_sha256'],
            'shared_native_source_sha256':batch_freezes[0]['source_sha256'],
            'prepared_inputs_sha256':sha256(directory/'inputs.json'),'batches':batch_freezes}
    replay_meta=None;event_ids=['underhand','standing_block']
    if replay_label:
        replay_meta=json.loads((directory/'engine-replays/engines.json').read_text())[replay_label]
        first=json.loads((directory/'engine-replays'/replay_label/(inputs['clips'][0]['sha256']+'.json')).read_text())
        event_ids=list(first['measurements'])
        study_key=hashlib.sha256((study_key+replay_meta['fingerprint']).encode()).hexdigest()
    bysource={s['sha256']:[] for s in inputs['original_sources']}
    for window in inputs['clips']:
        batch,key=locations[window['sha256']]
        p=batch/'native'/window['sha256'];result=json.loads((p/'result.json').read_text())
        if result['runtime_key']!=key or result['clip_sha256']!=window['sha256']:
            raise ValueError('Window runtime/source mismatch')
        measurements=json.loads((p/'private-measurements.json').read_text()) if result['status']=='complete' else {}
        if replay_label and result['status']=='complete':
            replay_path=directory/'engine-replays'/replay_label/(window['sha256']+'.json')
            replay=json.loads(replay_path.read_text());meta=json.loads(replay_path.with_suffix('.meta.json').read_text())
            if (meta['engine_fingerprint']!=replay_meta['fingerprint'] or meta['native_runtime_key']!=key or
                meta['track_sha256']!=sha256(p/'private-track.json') or replay['clip_sha256']!=window['sha256']):
                raise ValueError('Engine replay provenance mismatch')
            measurements=replay['measurements']
        if result['status']=='complete':
            track=json.loads((p/'private-track.json').read_text())['track']
            result['core_pose_samples']=sum(window['core_start_s']<=window['window_start_s']+f['f']/result['fps']<window['core_end_s'] for f in track)
            result['core_reached']=window['window_start_s']+result['last_progress_fraction']*result['duration_s']>=window['core_end_s']-2/result['fps']
        result['retried_failures']=len(list(p.glob('failed-attempt-*.json')))
        bysource[window['original_clip_sha256']].append((window,result,measurements))
    sources=[];candidate_catalog=[]
    for source in inputs['original_sources']:
        windows=bysource[source['sha256']];verify_coverage([w for w,_,_ in windows],source['duration_s'])
        complete=[r for _,r,_ in windows if r['status']=='complete'];events={};private_events={}
        hint=source['supported_event_hint']
        if hint is None and 'springboard' in event_ids:hint='springboard'
        for event in event_ids:
            candidates=[]
            for window,result,measurements in windows:
                if result['status']!='complete':continue
                for stroke in measurements[event]:
                    start=window['window_start_s']+stroke['start_frame']/result['fps']
                    end=min(source['duration_s'],window['window_start_s']+(stroke['end_frame']+1)/result['fps'])
                    mid=(start+end)/2
                    if not window['core_start_s']<=mid<window['core_end_s'] or start>=end:continue
                    safe=not result['production_deferred'] and result['diagnostic_selection']['orientation_sure']
                    candidates.append({**stroke,'span_s':[start,end],'window_index':window['window_index'],
                        'window_start_s':window['window_start_s'],'native_fps':result['fps'],
                        'context_margin_s':min(mid-window['window_start_s'],window['window_end_s']-mid),
                        'selection_eligible':safe})
            selected,removed=deduplicate(candidates);usable=[r for r in selected if r['usable']]
            eligible=[r for r in usable if r['selection_eligible'] and hint==event]
            events[event]={'candidate_strokes':len(selected),'duplicate_predictions_removed':removed,
                'gate_passing_candidates':len(usable),'gate_passing_seconds':sum(r['span_s'][1]-r['span_s'][0] for r in usable),
                'gate_passing_union_seconds':span_union_seconds([r['span_s'] for r in usable]),
                'selection_and_pack_eligible_candidates':len(eligible)}
            private_events[event]=selected
        suffix='-'+replay_label if replay_label else ''
        private_path=directory/('source-measurements'+suffix)/(source['sha256']+'.json');write_json(private_path,private_events)
        candidate_catalog.append({'clip_sha256':source['sha256'],
            'candidate_spans_s':[r['span_s'] for r in private_events.get(hint,[]) if r['usable']],
            'runtime_key':'study:'+study_key})
        sources.append({'clip_sha256':source['sha256'],'source_name':source['relative_path'],'duration_s':source['duration_s'],
            'windows':len(windows),'native_completed_windows':len(complete),'native_failed_windows':len(windows)-len(complete),
            'windows_reaching_final_sample':sum(r['full_span_reached'] for r in complete),
            'core_intervals_reached':sum(r['core_reached'] for r in complete),
            'complete_source_coverage_requested':True,'successful_all_windows':len(complete)==len(windows),
            'scored_core_coverage_complete':all(r.get('core_reached',False) for _,r,_ in windows),
            'coverage_intervals':[{'core_s':[w['core_start_s'],w['core_end_s']],
                'context_s':[w['window_start_s'],w['window_end_s']],'prepared_sha256':w['sha256'],
                'native_status':r['status'],'core_reached':r.get('core_reached',False)}
                for w,r,_ in sorted(windows,key=lambda item:item[0]['core_start_s'])],
            'pose_samples_including_context':sum(r['pose_samples'] for r in complete),
            'pose_samples_in_scored_cores':sum(r['core_pose_samples'] for r in complete),
            'retried_failures':sum(r['retried_failures'] for _,r,_ in windows),
            'deferred_windows':sum(r['production_deferred'] for r in complete),'candidate_event_passes':events})
    result={'format':'gurr-windowed-population/1','processing_variant':inputs['processing_variant'],'freeze':frozen,
        'sources':sources,'summary':{'unique_recordings':len(sources),'source_duration_s':sum(s['duration_s'] for s in sources),
            'native_windows':len(inputs['clips']),'native_completed_windows':sum(s['native_completed_windows'] for s in sources),
            'native_failed_windows':sum(s['native_failed_windows'] for s in sources),
            'core_intervals_reached':sum(s['core_intervals_reached'] for s in sources),
            'sources_reaching_all_scored_cores':sum(s['scored_core_coverage_complete'] for s in sources),
            'pose_samples_in_scored_cores':sum(s['pose_samples_in_scored_cores'] for s in sources),
            'retried_failures':sum(s['retried_failures'] for s in sources),
            'complete_sources':sum(s['successful_all_windows'] for s in sources)},
        'limitations':['Every core source interval is scheduled, with four seconds context where available.',
            'FFV1 losslessly stores resized frames at maximum image edge960; resizing changes the original pixels. HDR transfer metadata is retained.',
            'Automatic athlete/orientation selection restarts per window; identity is not linked between windows.',
            'Midpoint core filtering and cross-window interval dedup prevent context from inflating counts.',
            'Coverage and phase candidates are not independent technique/contact-accuracy evidence.',
            'Continuous full-source worker failures are retained as a separate baseline; this is a different execution variant.'],
        'claimed_technique_improvement':False,'raw_footage_published':False}
    if replay_meta:
        result['engine_replay']={**replay_meta,'same_native_pose_inputs':True,
            'scope':'Engine/pack replay only. Later tracking changes were not re-inferred.'}
    write_json(directory/('candidate-catalog'+('-'+replay_label if replay_label else '')+'.json'),candidate_catalog);write_json(output,result)
    print(json.dumps(result['summary'],indent=2))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['prepare','publish'])
    p.add_argument('--parent',required=True,type=Path);p.add_argument('--workers',type=int,default=2)
    p.add_argument('--output',type=Path);p.add_argument('--engine-replay',choices=['base','current']);a=p.parse_args()
    if a.action=='prepare':prepare(a.parent,a.workers)
    else:
        if not a.output:p.error('publish requires --output')
        collate(a.parent,a.output,a.engine_replay)


if __name__=='__main__':main()
