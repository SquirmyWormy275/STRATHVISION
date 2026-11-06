"""Native regression: blank opening must not hide later licensed action.

Requires two built population_runner bundles; outputs are private fixtures only.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess

from footage import sha256, write_json


def check(before,after,licensed,directory,display):
    directory.mkdir(parents=True,exist_ok=True);movie=directory/'late-entrant-fixture.mp4'
    subprocess.run(['ffmpeg','-y','-v','error','-threads','1','-f','lavfi','-i',
        'color=black:s=640x360:r=30:d=14','-i',str(licensed),'-filter_complex',
        '[1:v]trim=duration=5,scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2,fps=30,setsar=1[v];[0:v][v]concat=n=2:v=1:a=0[out]',
        '-map','[out]','-an','-c:v','libx264','-preset','veryfast','-threads','1',str(movie)],check=True)
    duration=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration',
        '-of','default=nw=1:nk=1',str(movie)]))
    row={'sha256':sha256(movie),'path':str(movie.resolve()),'relative_path':'synthetic-late-entrant.mp4',
        'duration_s':duration,'supported_event_hint':'standing_block',
        'event_hint_provenance':'Synthetic regression; licensed cleave; no coaching judgments'}
    inputs=directory/'inputs.json';write_json(inputs,{'clips':[row]})
    def run(pair):
        name,binary=pair;output=directory/name
        env={**os.environ,'GDK_BACKEND':'x11','DISPLAY':display,'SV_POP_INPUT':str(inputs.resolve()),
             'SV_POP_INDEX':'0','SV_POP_OUTPUT':str(output.resolve()),'SV_POP_RUNTIME_KEY':'synthetic-'+name}
        with (directory/f'{name}.log').open('w') as log:
            subprocess.run([str(binary.resolve())],env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
        return json.loads((output/row['sha256']/'result.json').read_text())
    with ThreadPoolExecutor(max_workers=2) as pool:
        old,new=list(pool.map(run,[('before',before),('after',after)]))
    if old['pose_samples']!=0 or old['full_span_reached']:raise AssertionError('Baseline did not reproduce early exit')
    if new['pose_samples']<=0 or not new['full_span_reached'] or not new['production_deferred']:
        raise AssertionError('Late athlete not recovered, or blank preflight unexpectedly accepted')
    result={'passed':True,'fixture':'Synthetic blank intro plus licensed action; no coaching judgments',
        'before':{k:old[k] for k in ['pose_samples','full_span_reached','last_progress_fraction']},
        'after':{k:new[k] for k in ['pose_samples','full_span_reached','last_progress_fraction','production_deferred']}}
    write_json(directory/'regression-result.json',result);print(json.dumps(result,indent=2))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['before','after','licensed','directory']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--display',default=':93');a=p.parse_args()
    check(a.before,a.after,a.licensed,a.directory,a.display)


if __name__=='__main__':main()
