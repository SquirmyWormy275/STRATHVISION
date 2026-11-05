"""Create and serve a private local video review packet; no labels are invented."""
import argparse
from copy import deepcopy
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import re
import subprocess
import threading
from urllib.parse import unquote, urlparse
from uuid import uuid4

from axe_data import validate
from footage import sha256, write_json


def make_packet(reference,root,directory):
    validate(reference)
    directory.mkdir(parents=True,exist_ok=True)
    path=directory/'packet.json'
    if path.exists():raise ValueError('Packet already exists; refusing to overwrite real judgments')
    tasks=[]
    for row in reference['windows']:
        source=root/row['source_name']
        if sha256(source)!=row['clip_sha256']:raise ValueError('Source content changed')
        task_id=row['window_id'];media=directory/'media'/f'{task_id}-{row["clip_sha256"][:12]}-{row["start_s"]}.mp4'
        media.parent.mkdir(exist_ok=True)
        if not media.exists():
            filters=[]
            if row['rotation_cw']:
                filters.append({90:'transpose=1',180:'hflip,vflip',270:'transpose=2'}[row['rotation_cw']])
            tags=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0',
                '-show_entries','stream=color_transfer','-of','json',str(source)]))
            transfer=tags.get('streams',[{}])[0].get('color_transfer')
            if transfer in ('arib-std-b67','smpte2084'):
                filters.append('zscale=t=linear:npl=203,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p')
            filters.append('scale=960:960:force_original_aspect_ratio=decrease:force_divisible_by=2')
            subprocess.run(['ffmpeg','-v','error','-threads','2','-ss',str(row['start_s']),'-i',str(source),
                '-t',str(row['duration_s']),'-vf',','.join(filters),
                '-c:v','libx264','-preset','fast','-crf','23','-pix_fmt','yuv420p','-c:a','aac',
                '-movflags','+faststart','-threads','2',str(media)],check=True)
        tasks.append({'task_id':task_id,'clip_sha256':row['clip_sha256'],'display_name':row['source_name'],
                      'source_start_s':row['start_s'],'duration_s':row['duration_s'],
                      'rotation_cw':row['rotation_cw'],
                      'event_id':row['event_id'],'partition':'fit' if row['split']=='train' else 'evaluation',
                      'media':str(media.relative_to(directory)),'feedback':None})
    packet={'format':'coach-review-packet/1','tasks':tasks,'reference_sha256':__import__('hashlib').sha256(json.dumps(reference,sort_keys=True).encode()).hexdigest()}
    write_json(path,packet)
    return packet


def validated_feedback(task,body):
    if body.get('label') not in ('red','green'):raise ValueError('Choose red or green')
    if body.get('attribute') not in ('Slope','Spacing','Hinge','Path'):raise ValueError('Unknown attribute')
    if body.get('reviewed') is not True or body.get('single_stroke_confirmed') is not True:
        raise ValueError('Confirm one complete reviewed stroke')
    for key in ('author_id','reviewer_id'):
        if not isinstance(body.get(key),str) or not body[key].strip():raise ValueError('Reviewer name is required')
    if body.get('author_role')!='coach':raise ValueError('This packet collects coach judgments')
    event_id=task['event_id']
    if task.get('allowed_event_ids'):
        event_id=body.get('event_id')
        if event_id not in task['allowed_event_ids'] or body.get('event_confirmed') is not True:
            raise ValueError('Confirm the event for this stroke')
    span=body.get('stroke_span_s')
    if not isinstance(span,list) or len(span)!=2 or any(not isinstance(x,(float,int)) or not math.isfinite(x) for x in span):
        raise ValueError('Invalid stroke span')
    if not task['source_start_s']<=span[0]<span[1]<=task['source_start_s']+task['duration_s']+.01:
        raise ValueError('Stroke span lies outside the review clip')
    return {'feedback_id':task['task_id'],'clip_sha256':task['clip_sha256'],'event_id':event_id,
            'partition':task['partition'],'stroke_span_s':span,'attribute':body['attribute'],
            'label':body['label'],'author_id':body['author_id'].strip(),'author_role':'coach',
            'reviewer_id':body['reviewer_id'].strip(),'reviewed':True,'single_stroke_confirmed':True,
            'notes':str(body.get('notes','')),'created_at':datetime.now(timezone.utc).isoformat(),
            'provenance':'human-entered judgment; credentials are not automatically verified'}


def export_feedback(packet):
    return {'format':'coach-feedback/1','packet_reference_sha256':packet['reference_sha256'],
            'entries':[t['feedback'] for t in packet['tasks'] if t.get('feedback')],
            'pending_tasks':sum(not t.get('feedback') for t in packet['tasks'])}


def server(directory,port=0):
    directory=Path(directory);path=directory/'packet.json';lock=threading.Lock()
    packet=json.loads(path.read_text())
    html=Path(__file__).with_suffix('.html').read_bytes()
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def respond(self,status,data,kind='application/json'):
            payload=data if isinstance(data,bytes) else json.dumps(data).encode()
            self.send_response(status);self.send_header('Content-Type',kind)
            self.send_header('Content-Length',str(len(payload)))
            self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff')
            self.end_headers();self.wfile.write(payload)
        def do_GET(self):
            route=unquote(urlparse(self.path).path)
            if route=='/':return self.respond(200,html,'text/html; charset=utf-8')
            if route=='/api/tasks':return self.respond(200,packet)
            if route=='/api/export':return self.respond(200,export_feedback(packet))
            if route.startswith('/media/'):
                task=next((t for t in packet['tasks'] if t['task_id']==route[7:]),None)
                if task is None:return self.respond(404,{'error':'Unknown clip'})
                media=(directory/task['media']).resolve()
                if not media.is_relative_to(directory.resolve()):return self.respond(403,{'error':'Invalid media path'})
                size=media.stat().st_size;start,end=0,size-1;status=200
                requested=self.headers.get('Range')
                if requested:
                    match=re.fullmatch(r'bytes=(\d+)-(\d*)',requested)
                    if not match:return self.respond(416,{'error':'Invalid byte range'})
                    start=int(match[1]);end=min(int(match[2]) if match[2] else end,end);status=206
                    if start>end:return self.respond(416,{'error':'Range outside clip'})
                self.send_response(status);self.send_header('Content-Type','video/mp4')
                self.send_header('Accept-Ranges','bytes');self.send_header('Content-Length',str(end-start+1))
                if status==206:self.send_header('Content-Range',f'bytes {start}-{end}/{size}')
                self.end_headers()
                try:
                    with media.open('rb') as f:
                        f.seek(start);remaining=end-start+1
                        while remaining:
                            data=f.read(min(65536,remaining))
                            if not data:break
                            self.wfile.write(data);remaining-=len(data)
                except (BrokenPipeError,ConnectionResetError):pass
                return
            return self.respond(404,{'error':'Not found'})
        def do_POST(self):
            nonlocal packet
            route=unquote(urlparse(self.path).path)
            # Browser cross-origin form/fetch requests cannot create judgments.
            origin=self.headers.get('Origin')
            expected=f'http://{self.headers.get("Host")}'
            if origin and origin!=expected:return self.respond(403,{'error':'Unexpected request origin'})
            duplicate=route.startswith('/api/another/')
            if not duplicate and not route.startswith('/api/feedback/'):return self.respond(404,{'error':'Not found'})
            if self.headers.get('Content-Type')!='application/json':return self.respond(415,{'error':'Expected JSON'})
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<=65536:return self.respond(413,{'error':'Invalid judgment size'})
            try:
                body=json.loads(self.rfile.read(length))
                with lock:
                    updated=deepcopy(packet)
                    task_id=route[13:] if duplicate else route[14:]
                    task=next((t for t in updated['tasks'] if t['task_id']==task_id),None)
                    if task is None:raise ValueError('Unknown task')
                    if duplicate:
                        task=deepcopy(task);task['task_id']+='-'+uuid4().hex[:8];task['feedback']=None
                        updated['tasks'].append(task)
                        result={'task':task}
                    else:
                        feedback=validated_feedback(task,body)
                        task['feedback']=feedback
                        result={'feedback':feedback}
                    temporary=path.with_suffix('.pending.json')
                    write_json(temporary,updated);temporary.replace(path)
                    packet=updated
                return self.respond(200,result)
            except (ValueError,TypeError,KeyError) as e:return self.respond(400,{'error':str(e)})
            except OSError:return self.respond(500,{'error':'The judgment could not be saved. Please retry.'})
    return ThreadingHTTPServer(('127.0.0.1',port),Handler)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['prepare','serve'])
    p.add_argument('--directory',required=True,type=Path);p.add_argument('--reference',type=Path)
    p.add_argument('--root',type=Path);p.add_argument('--port',type=int,default=0);a=p.parse_args()
    if a.action=='prepare':
        if not a.reference or not a.root:p.error('prepare needs --reference and --root')
        packet=make_packet(json.loads(a.reference.read_text()),a.root,a.directory)
        print(f'Prepared {len(packet["tasks"])} unlabelled local review tasks.')
    else:
        http=server(a.directory,a.port);print(f'http://127.0.0.1:{http.server_port}',flush=True)
        try:http.serve_forever()
        except KeyboardInterrupt:pass
        finally:http.server_close()


if __name__=='__main__':main()
