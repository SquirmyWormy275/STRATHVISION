"""Replay private native poses through pinned base/current engines, with a span control."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

from footage import sha256,write_json


def signature(rows):
    return [(r['start_frame'],r['end_frame'],r['usable'],tuple(sorted(r['issues']))) for r in rows]


def engine_metadata(snapshot):
    paths=[*sorted((snapshot/'packages/analysis_engine/lib').rglob('*.dart')),
           snapshot/'packages/analysis_engine/tool/population_replay.dart',
           snapshot/'apps/strathvision/assets/packs/timber.json']
    result={'revision':(snapshot/'source-revision.txt').read_text().strip(),
            'binary_sha256':sha256(snapshot/'replay'),
            'sources_sha256':{str(p.relative_to(snapshot)):sha256(p) for p in paths}}
    result['fingerprint']=hashlib.sha256(json.dumps(result,sort_keys=True).encode()).hexdigest()
    return result


def execute(parent,follow):
    versions={label:parent/('engine-replay-'+label) for label in ['base','current']}
    metadata={k:engine_metadata(p) for k,p in versions.items()}
    if metadata['base']['binary_sha256']==metadata['current']['binary_sha256']:
        raise ValueError('Base and current executables unexpectedly identical')
    root=parent/'bounded/engine-replays';root.mkdir(exist_ok=True);write_json(root/'engines.json',metadata)
    count=0
    while True:
        new=0;available=0
        for batch in sorted((parent/'bounded/batches').glob('batch-*')):
            p=batch/'inputs.json'
            if not p.exists():continue
            for row in json.loads(p.read_text())['clips']:
                native=batch/'native'/row['sha256'];r=native/'result.json'
                if not r.exists():continue
                record=json.loads(r.read_text())
                if record['status']!='complete':continue
                available+=1;track=native/'private-track.json';expected_track=sha256(track)
                for label,snapshot in versions.items():
                    output=root/label/(row['sha256']+'.json');meta=output.with_suffix('.meta.json')
                    expected={'engine_fingerprint':metadata[label]['fingerprint'],
                        'native_runtime_key':record['runtime_key'],'track_sha256':expected_track}
                    if output.exists() and meta.exists():
                        if json.loads(meta.read_text())!=expected:raise ValueError('Engine replay provenance changed')
                        continue
                    output.parent.mkdir(exist_ok=True)
                    with output.with_suffix('.log').open('w') as log:
                        subprocess.run([str(snapshot/'replay'),str(r),str(track),
                            str(snapshot/'apps/strathvision/assets/packs/timber.json'),str(output)],
                            stdout=log,stderr=subprocess.STDOUT,check=True)
                    replay=json.loads(output.read_text())
                    if replay['clip_sha256']!=row['sha256'] or replay['native_runtime_key']!=record['runtime_key']:
                        raise ValueError('Replay input mismatch')
                    if label=='base':
                        original=json.loads((native/'private-measurements.json').read_text())
                        if any(signature(replay['measurements'][e])!=signature(v) for e,v in original.items()):
                            raise ValueError('Base replay did not reproduce native stroke spans/quality decisions')
                    write_json(meta,expected);new+=1
        count=available
        write_json(root/'status.json',{'native_windows_available':available,
            'base_span_control_required':True,'engine_revisions':{k:v['revision'] for k,v in metadata.items()}})
        if new:print(f'REPLAY {available} available windows; {new} new engine outputs; baseline span checks passed',flush=True)
        if not follow or ((parent/'bounded/batches-complete.json').exists() and not new):break
        time.sleep(10)
    print(f'Engine replay caught up with {count} completed native windows.',flush=True)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parent',type=Path,required=True)
    p.add_argument('--follow',action='store_true');a=p.parse_args();execute(a.parent,a.follow)


if __name__=='__main__':main()
