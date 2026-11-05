"""Prepare private native-runtime windows and score diagnostic contact replay."""
import argparse
import json
from pathlib import Path
from statistics import mean
import subprocess

from footage import sha256, write_json
from score_accuracy import contact_matches, rates


def references(directory):
    rows=[]
    for inputs,reference in [('gurr-inputs.json','gurr-reference.json'),('gurr-phase-inputs.json','gurr-phase-reference.json')]:
        byid={r['window_id']:r for r in json.loads((directory/inputs).read_text())['windows']}
        for row in json.loads((directory/reference).read_text())['windows']:
            rows.append({**byid[row['window_id']],**row,
                         'study':'pilot' if inputs=='gurr-inputs.json' else 'followup'})
    return rows


def prepare(rows,root,directory):
    directory.mkdir(parents=True,exist_ok=True)
    for row in rows:
        source=root/row['source_name']
        if sha256(source)!=row['clip_sha256']:raise ValueError('Source content mismatch')
        output=directory/(row['window_id']+'.mkv')
        if not output.exists():
            subprocess.run(['ffmpeg','-v','error','-threads','1','-ss',str(row['start_s']),
                '-i',str(source),'-t',str(row['duration_s']),'-map','0:v:0','-an',
                '-vf','scale=960:960:force_original_aspect_ratio=decrease',
                '-c:v','ffv1','-level','3','-threads','1',str(output)],check=True)
        row['prepared_path']=str(output.resolve())
    write_json(directory/'inputs.json',{'windows':rows})


def score_contacts(reference,result,tolerance=.2):
    if reference['window_id']!=result['window_id'] or reference['clip_sha256']!=result['clip_sha256']:
        raise ValueError('Native result source mismatch')
    if reference['contact_intervals_s'] is None:return None
    lo,hi=reference['score_interval_s']
    def included(t):
        return lo<=t<=hi and not any(a<=t<=b for a,b in reference['ignored_intervals_s'])
    actual=[r for r in reference['contact_intervals_s'] if included(sum(r)/2)]
    predicted=[t for t in result['contact_times_s'] if included(t)]
    if result['paused_for_selection'] and predicted:
        raise ValueError('Paused selections must not produce coaching contacts')
    counts=contact_matches(predicted,actual,tolerance)
    return {**counts,**rates(counts),'reference_count':len(actual),'idle':not actual}


def summarize(rows):
    counts={k:sum(r['contacts'][k] for r in rows if r['contacts'] is not None) for k in ['tp','fp','fn']}
    timing=[e for r in rows if r['contacts'] is not None for e in r['contacts']['timing_errors_s']]
    torso=[e['error_frame_diagonal'] for r in rows for e in r['torso_errors'] if e['error_frame_diagonal'] is not None]
    missing=sum(e['error_frame_diagonal'] is None for r in rows for e in r['torso_errors'])
    return {'windows':len(rows),'paused_for_selection':sum(r['paused_for_selection'] for r in rows),
            'correct_orientation':sum(r['orientation_correct'] for r in rows),
            'torso_observed_checkpoints':len(torso),'torso_missing_or_deferred_checkpoints':missing,
            'mean_observed_torso_error_frame_diagonal':mean(torso) if torso else None,
            'contacts':{**counts,**rates(counts),'mean_matched_midpoint_error_s':mean(timing) if timing else None,
                        'idle_false_positives':sum(r['contacts']['fp'] for r in rows if r['contacts'] is not None and r['contacts']['idle'])}}


def publish(document,rows,repo):
    if document.get('complete') is not True:
        raise ValueError('Native benchmark is incomplete')
    expected={r['window_id'] for r in rows}
    observed=[r['window_id'] for r in document['windows']]
    if set(observed)!=expected or len(observed)!=len(expected) or document.get('expected_windows')!=len(expected):
        raise ValueError('Native benchmark windows are missing or duplicated')
    byid={r['window_id']:r for r in rows};scored=[]
    for result in document['windows']:
        ref=byid[result['window_id']]
        scored.append({**result,'study':ref['study'],'partition':ref['split'],
                       'contacts':score_contacts(ref,result)})
    source_paths=[*sorted((repo/'apps/strathvision/lib/vision').glob('*.dart')),
                  *sorted((repo/'packages/analysis_engine/lib').rglob('*.dart')),
                  *sorted((repo/'apps/strathvision/assets/models').glob('*.onnx')),
                  repo/'apps/strathvision/assets/packs/timber.json',
                  repo/'apps/strathvision/integration_test/carne_gurr_benchmark_test.dart']
    return {'format':'gurr-native-diagnostic/1','runtime_base_commit':document['source_revision'],
            'prepared_input_manifest_sha256':document['input_sha256'],
            'evaluation_use':'Previously opened pilot/follow-up references; not a new holdout.',
            'preparation':'8-second FFV1 windows, maximum edge 960; original HDR transfer metadata retained.',
            'sample_rate_limit':30,'pipeline_sources_sha256':{str(p.relative_to(repo)):sha256(p) for p in source_paths},
            'groups':{name:summarize([r for r in scored if r['study']==study and r['partition']==split])
                      for name,study,split in [('pilot_development','pilot','development'),('pilot_test','pilot','test'),('followup','followup','test')]},
            'windows':scored,'claimed_technique_improvement':False,
            'limitations':['Single-reviewer old references; diagnostics only.',
                           'Automatic ambiguities/orientation doubts defer measurement; deferrals count as missing contacts.',
                           'Torso centre error is a different metric from the original detector-box checkpoint coverage.',
                           'Reduced-resolution windows do not establish whole-recording throughput or field coaching accuracy.',
                           'The implement remains a grip proxy; no genuine technique judgments were supplied.']}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['prepare','score'])
    p.add_argument('--references',type=Path,required=True);p.add_argument('--root',type=Path)
    p.add_argument('--directory',type=Path);p.add_argument('--native',type=Path)
    p.add_argument('--repo',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
    rows=references(a.references)
    if a.action=='prepare':
        if not a.root or not a.directory:p.error('prepare requires --root and --directory')
        prepare(rows,a.root,a.directory)
    else:
        if not a.native or not a.repo or not a.output:p.error('score requires --native, --repo and --output')
        result=publish(json.loads(a.native.read_text()),rows,a.repo)
        write_json(a.output,result);print(json.dumps(result['groups'],indent=2))


if __name__=='__main__':main()
