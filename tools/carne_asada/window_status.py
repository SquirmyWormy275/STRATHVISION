"""Read-only progress for the complete-source native window scan."""
import argparse
from collections import Counter
import json
import math
from pathlib import Path


def status(parent):
    root=json.loads((parent/'inputs.json').read_text());directory=parent/'bounded'
    expected={c['sha256']:math.ceil(c['duration_s']/45) for c in root['clips']}
    completed=Counter();reached=Counter();failed=0;assigned=0;seen=set()
    for batch in sorted((directory/'batches').glob('batch-*')):
        p=batch/'inputs.json'
        if not p.exists():continue
        for row in json.loads(p.read_text())['clips']:
            if row['sha256'] in seen:raise ValueError('Repeated scheduled window')
            seen.add(row['sha256']);assigned+=1
            result=batch/'native'/row['sha256']/'result.json'
            if not result.exists():continue
            r=json.loads(result.read_text())
            if r['status']!='complete':failed+=1;continue
            identity=row['original_clip_sha256'];completed[identity]+=1
            if row['window_start_s']+r['last_progress_fraction']*r['duration_s']>=row['core_end_s']-2/r['fps']:
                reached[identity]+=1
    prepared=sum(not p.name.endswith('.pending.mkv') for p in (directory/'media').glob('*.mkv'))
    return {'unique_recordings':len(expected),'source_duration_s':sum(c['duration_s'] for c in root['clips']),
        'expected_windows':sum(expected.values()),'prepared_windows':prepared,'assigned_windows':assigned,
        'completed_windows':sum(completed.values()),'cores_reached':sum(reached.values()),'failed_windows':failed,
        'completed_sources':sum(completed[k]==v for k,v in expected.items()),
        'sources_reaching_all_cores':sum(reached[k]==v for k,v in expected.items())}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--parent',type=Path,required=True);a=p.parse_args()
    print(json.dumps(status(a.parent),indent=2))


if __name__=='__main__':main()
