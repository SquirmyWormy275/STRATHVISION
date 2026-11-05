"""Run prepared full-coverage windows in frozen batches while encoding proceeds."""
import argparse
import json
from pathlib import Path
import subprocess
import time

from footage import sha256,write_json
from population import freeze,run
from window_population import intervals


def execute(parent,workers,batch_size):
    directory=parent/'bounded';root=json.loads((parent/'inputs.json').read_text())
    reference=json.loads((parent/'freeze.json').read_text())
    plans=[]
    for i,s in enumerate(root['clips']):
        for k,w in enumerate(intervals(s['duration_s'])):
            plans.append((i,k,s,w,f'{s["sha256"][:16]}-{k:04d}'))
    plans.sort(key=lambda r:(r[1],r[0]))
    batches=directory/'batches';batches.mkdir(exist_ok=True);assigned=set();records=[]
    for path in sorted(batches.glob('batch-*')):
        if not (path/'inputs.json').exists():continue
        document=json.loads((path/'inputs.json').read_text())
        assigned.update(c['window_name'] for c in document['clips']);records.append(path)
    def process(path):
        f=freeze(path)
        if f['binary_sha256']!=reference['binary_sha256'] or f['source_sha256']!=reference['source_sha256']:
            raise ValueError('Native algorithm/model changed between batches')
        for attempt in range(3):
            run(path,workers,':93')
            rows=json.loads((path/'inputs.json').read_text())['clips']
            failed=[r for r in rows if json.loads((path/'native'/r['sha256']/'result.json').read_text())['status']!='complete']
            if not failed:return
            print(f'BATCH retry {path.name}: {len(failed)} incomplete windows',flush=True)
    for path in records:process(path)
    while len(assigned)<len(plans):
        ready=[]
        for i,k,source,window,name in plans:
            media=directory/'media'/(name+'.mkv')
            if name in assigned or not media.exists():continue
            actual=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(media)]))
            requested=window['window_end_s']-window['window_start_s']
            if actual<requested-.12:raise ValueError('Truncated prepared window')
            ready.append({'sha256':sha256(media),'path':str(media.resolve()),'relative_path':source['relative_path']+'#'+name,
                'duration_s':actual,'supported_event_hint':source['supported_event_hint'],
                'event_hint_provenance':source['event_hint_provenance'],'source_index':i,'window_index':k,
                'original_clip_sha256':source['sha256'],'window_name':name,**window})
            if len(ready)>=batch_size:break
        if not ready:
            if (directory/'prepare-errors.json').exists():raise ValueError('Window preparation failed; inspect prepare-errors.json')
            time.sleep(3);continue
        # Small early batches start inference promptly; every prepared input is
        # hashed and frozen before its model process starts.
        path=batches/f'batch-{len(records):04d}';path.mkdir()
        (path/'runtime').symlink_to(parent/'runtime',target_is_directory=True)
        (path/'runtime-base.txt').write_text((parent/'runtime-base.txt').read_text())
        write_json(path/'inputs.json',{'format':'gurr-population-input/1','clips':ready,
            'dispatch_order':list(range(len(ready))),'processing_variant':'bounded-full-coverage-45s-cores-4s-context'})
        assigned.update(r['window_name'] for r in ready);records.append(path)
        write_json(directory/'batch-ledger.json',{'expected_windows':len(plans),'assigned_windows':len(assigned),
            'batches':[str(p.relative_to(directory)) for p in records],
            'shared_native_binary_sha256':reference['binary_sha256']})
        print(f'BATCH {path.name}: {len(ready)} windows, assigned {len(assigned)}/{len(plans)}',flush=True)
        process(path)
    write_json(directory/'batches-complete.json',{'windows':len(plans),'batches':len(records)})
    print('All bounded native batches finished.',flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parent',type=Path,required=True)
    p.add_argument('--workers',type=int,default=4);p.add_argument('--batch-size',type=int,default=12)
    a=p.parse_args();execute(a.parent,a.workers,a.batch_size)


if __name__=='__main__':main()
