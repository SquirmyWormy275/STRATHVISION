from copy import deepcopy
import json
import threading
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import pytest

import feedback_review
from feedback_review import export_feedback, server, validated_feedback


def task():
    return {'task_id':'fixture','clip_sha256':'a'*64,'display_name':'Synthetic UI fixture',
            'event_id':'standing_block','partition':'fit','source_start_s':10,
            'duration_s':8,'media':'media.mp4','feedback':None}


def judgment():
    return {'author_id':'Synthetic test author','reviewer_id':'Synthetic test author',
            'author_role':'coach','label':'green','attribute':'Slope',
            'reviewed':True,'single_stroke_confirmed':True,'stroke_span_s':[11,12]}


def test_draft_or_unreviewed_feedback_cannot_become_a_judgment():
    for key in ['reviewed','single_stroke_confirmed','author_id','reviewer_id','label']:
        j=judgment();j[key]=None
        with pytest.raises(ValueError):validated_feedback(task(),j)
    j=judgment();j['stroke_span_s']=[9,11]
    with pytest.raises(ValueError,match='outside'):validated_feedback(task(),j)


def test_judgment_source_and_partition_are_set_by_the_packet():
    j=judgment();j.update(clip_sha256='forged',partition='evaluation')
    result=validated_feedback(task(),j)
    assert result['clip_sha256']=='a'*64 and result['partition']=='fit'
    assert export_feedback({'reference_sha256':'ref','tasks':[task()]})['entries']==[]


@pytest.fixture
def http(tmp_path):
    packet={'format':'coach-review-packet/1','reference_sha256':'test-fixture','tasks':[task()]}
    (tmp_path/'packet.json').write_text(json.dumps(packet));(tmp_path/'media.mp4').write_bytes(b'0123456789')
    service=server(tmp_path);worker=threading.Thread(target=service.serve_forever,daemon=True);worker.start()
    yield f'http://127.0.0.1:{service.server_port}',tmp_path
    service.shutdown();service.server_close();worker.join()


def test_local_review_saves_atomically_exports_and_streams_ranges(http):
    base,path=http
    req=Request(base+'/api/feedback/fixture',data=json.dumps(judgment()).encode(),headers={'Content-Type':'application/json'})
    assert json.load(urlopen(req))['feedback']['reviewed']
    exported=json.load(urlopen(base+'/api/export'))
    assert len(exported['entries'])==1 and exported['pending_tasks']==0
    assert json.loads((path/'packet.json').read_text())['tasks'][0]['feedback']['label']=='green'
    with urlopen(Request(base+'/media/fixture',headers={'Range':'bytes=2-5'})) as r:
        assert r.status==206 and r.read()==b'2345' and r.headers['Content-Range']=='bytes 2-5/10'
    with pytest.raises(HTTPError) as e:
        urlopen(Request(base+'/api/feedback/fixture',data=b'{}',headers={'Content-Type':'application/json','Origin':'https://example.com'}))
    assert e.value.code==403


def test_failed_disk_write_does_not_publish_a_saved_judgment(http,monkeypatch):
    base,path=http
    def fail(*args):raise OSError('synthetic disk failure')
    monkeypatch.setattr(feedback_review,'write_json',fail)
    with pytest.raises(HTTPError) as e:
        urlopen(Request(base+'/api/feedback/fixture',data=json.dumps(judgment()).encode(),headers={'Content-Type':'application/json'}))
    assert e.value.code==500
    assert json.load(urlopen(base+'/api/export'))['entries']==[]
    assert json.loads((path/'packet.json').read_text())['tasks'][0]['feedback'] is None


def test_another_stroke_preserves_source_partition_and_starts_unlabelled(http):
    base,path=http
    req=Request(base+'/api/another/fixture',data=b'{}',headers={'Content-Type':'application/json'})
    another=json.load(urlopen(req))['task']
    assert another['task_id']!='fixture' and another['feedback'] is None
    assert another['clip_sha256']=='a'*64 and another['partition']=='fit'
    assert json.load(urlopen(base+'/api/export'))['pending_tasks']==2


def test_live_candidates_preserve_judgments_and_reject_out_of_range_updates(http):
    base,path=http
    req=Request(base+'/api/feedback/fixture',data=json.dumps(judgment()).encode(),headers={'Content-Type':'application/json'})
    saved=json.load(urlopen(req))['feedback']
    body={'clip_sha256':'a'*64,'candidate_spans_s':[[13,14]],'runtime_key':'synthetic-only',
          'label':'red','partition':'forged'}
    req=Request(base+'/api/candidates',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
    assert json.load(urlopen(req))['candidate_count']==1
    packet=json.loads((path/'packet.json').read_text());t=packet['tasks'][0]
    assert t['feedback']==saved and t['partition']=='fit'
    assert t['candidate_spans_s']==[[13,14]]
    candidates=json.load(urlopen(base+'/api/candidates'))['tasks'][0]
    assert candidates['candidate_runtime_key']=='synthetic-only'
    body['candidate_spans_s']=[[0,50]]
    with pytest.raises(HTTPError) as error:
        urlopen(Request(base+'/api/candidates',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'}))
    assert error.value.code==400
    assert json.loads((path/'packet.json').read_text())['tasks'][0]['feedback']==saved
    assert json.load(urlopen(base+'/api/candidates'))['tasks'][0]['candidate_spans_s']==[[13,14]]
