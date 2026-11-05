"""Prepare complete private playback/review for every population recording."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import subprocess

from footage import sha256, write_json
from population import validate_inputs


def rotations(reference_root):
    values={}
    for p in [reference_root/'gurr-reference.json',reference_root/'gurr-phase-reference.json',
              reference_root/'round2/axe-reference.json',reference_root/'round2/axe-transfer-reference.json']:
        document=json.loads(p.read_text())
        for row in document['windows']:
            identity=row['clip_sha256'];rotation=row.get('rotation_cw',row.get('reference_rotation_cw'))
            if rotation is not None:
                if identity in values and values[identity]!=rotation:raise ValueError('Conflicting frozen rotations')
                values[identity]=rotation
    return values


def task(row,turn,partition):
    return {'task_id':'population-'+row['sha256'][:20],'clip_sha256':row['sha256'],
        'display_name':row['relative_path'],'source_start_s':0,'duration_s':row['duration_s'],
        'rotation_cw':turn,'event_id':None,'event_hint':row['supported_event_hint'] or 'springboard',
        'allowed_event_ids':['standing_block','underhand','springboard'],
        'event_hint_provenance':row['event_hint_provenance'],
        'partition':partition,'media':f'media/{row["sha256"]}-q{turn}.mp4',
        'candidate_spans_s':[],'feedback':None,'full_recording':True}


def prepare(directory,references,workers):
    inputs=json.loads((directory/'inputs.json').read_text());rows=validate_inputs(inputs)
    destination=directory/'review-all47';destination.mkdir(exist_ok=True)
    packet=destination/'packet.json'
    if packet.exists():raise ValueError('Review packet exists; preserving real judgments')
    turns=rotations(references);partitions={}
    # Preserve the first review study's fitting/evaluation source boundary.
    first=json.loads((references/'round2/axe-reference.json').read_text())
    for row in first['windows']:partitions[row['clip_sha256']]='fit' if row['split']=='train' else 'evaluation'
    tasks=[task(r,turns.get(r['sha256'],0),partitions.get(r['sha256'],
        'fit' if int(r['sha256'][:2],16)%2==0 else 'evaluation')) for r in rows]
    (destination/'media').mkdir(exist_ok=True)
    def one(pair):
        row,t=pair;source=Path(row['path']);media=destination/t['media']
        if sha256(source)!=row['sha256']:raise ValueError('Source content changed')
        if not media.exists():
            filters=[]
            if t['rotation_cw']:filters.append({90:'transpose=1',180:'hflip,vflip',270:'transpose=2'}[t['rotation_cw']])
            filters+=['scale=960:960:force_original_aspect_ratio=decrease:force_divisible_by=2','fps=30']
            tags=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0',
                '-show_entries','stream=color_transfer','-of','json',str(source)]))
            if tags.get('streams',[{}])[0].get('color_transfer') in ('arib-std-b67','smpte2084'):
                filters.append('zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p')
            temporary=media.with_suffix('.pending.mp4')
            with media.with_suffix('.ffmpeg.log').open('w') as log:
                subprocess.run(['ffmpeg','-y','-v','error','-threads','1','-i',str(source),
                    '-vf',','.join(filters),'-c:v','libx264','-preset','veryfast','-crf','24',
                    '-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart','-threads','1',str(temporary)],
                    stdout=log,stderr=subprocess.STDOUT,check=True)
            temporary.replace(media)
        duration=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration',
            '-of','default=nw=1:nk=1',str(media)]))
        if duration<row['duration_s']-.12:raise ValueError('Playback copy is truncated')
        return {'clip_sha256':row['sha256'],'media_sha256':sha256(media),'duration_s':duration}
    prepared=[];errors=[]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures=[pool.submit(one,pair) for pair in zip(rows,tasks)]
        for n,future in enumerate(as_completed(futures),1):
            try:prepared.append(future.result())
            except Exception as error:
                errors.append(str(error));print(f'PLAYBACK ERROR: {error}',flush=True)
            print(f'PLAYBACK {n}/{len(rows)} finished, {len(errors)} errors',flush=True)
    if errors:
        write_json(destination/'prepare-errors.json',errors)
        raise ValueError(f'{len(errors)} playback copies failed; complete copies retained for retry')
    document={'format':'coach-review-packet/1','reference_sha256':sha256(directory/'inputs.json'),
        'tasks':tasks,'population_sources':len(rows),'full_recordings':True,
        'prepare_code_sha256':sha256(Path(__file__)),'playback':prepared}
    write_json(packet,document)
    print('Ready:',packet,flush=True)


def add_candidates(directory):
    path=directory/'review-all47/packet.json';packet=json.loads(path.read_text())
    for t in packet['tasks']:
        source=directory/'native'/t['clip_sha256'];result=json.loads((source/'result.json').read_text())
        event=t['event_hint']
        if result['status']!='complete' or event not in ('standing_block','underhand'):continue
        data=json.loads((source/'private-measurements.json').read_text())[event]
        t['candidate_spans_s']=[[r['start_frame']/result['fps'],min(t['duration_s'],(r['end_frame']+1)/result['fps'])]
            for r in data if r['usable']]
        t['candidate_provenance']='Unreviewed phase candidates; verify person, event and bounds before judging.'
    # Server must be stopped before metadata enrichment to preserve its in-memory state.
    temporary=path.with_suffix('.pending.json');write_json(temporary,packet);temporary.replace(path)
    print('Added unreviewed candidate navigation; existing judgments preserved.')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['prepare','candidates'])
    p.add_argument('--directory',required=True,type=Path);p.add_argument('--references',type=Path)
    p.add_argument('--workers',type=int,default=2);a=p.parse_args()
    if a.action=='prepare':
        if not a.references:p.error('prepare requires --references')
        prepare(a.directory,a.references,a.workers)
    else:add_candidates(a.directory)


if __name__=='__main__':main()
