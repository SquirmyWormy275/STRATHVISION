"""Population provenance/completeness guards, using synthetic records only."""
from copy import deepcopy
import pytest
from population import summarize, validate_inputs, validate_result
from population_review import task
from feedback_review import validated_feedback


def fixture():
    row={'sha256':'a'*64,'duration_s':100,'relative_path':'synthetic.mov',
         'supported_event_hint':'standing_block','event_hint_provenance':'synthetic fixture'}
    events={id:{'candidate_strokes':3,'gate_passing_candidates':2,'gate_passing_seconds':1.5,
                'production_eligible_strokes':0} for id in ['underhand','standing_block']}
    record={'clip_sha256':row['sha256'],'runtime_key':'frozen','inventory_duration_s':100,
            'duration_s':100,'status':'complete','production_deferred':True,
            'full_span_reached':True,'pose_samples':2500,'expected_sample_count':3000,'events':events}
    return row,record


def test_all_sources_must_be_present_once_before_population_publication():
    row,record=fixture()
    with pytest.raises(ValueError,match='incomplete'):summarize([row],[],'frozen')
    with pytest.raises(ValueError,match='repeated'):summarize([row],[record,record],'frozen')
    result=summarize([row],[record],'frozen')
    assert result['recordings']==1 and result['inventory_duration_s']==100
    assert result['production_deferred']==1
    assert result['candidate_event_passes']['standing_block']['production_eligible_strokes']==0
    assert result['candidate_event_passes']['standing_block']['gate_passing_candidates']==2


def test_truncation_and_changed_runtime_cannot_count_as_population_completion():
    row,record=fixture();record['duration_s']=8
    with pytest.raises(ValueError,match='truncated'):validate_result(row,record,'frozen')
    record['duration_s']=100;record['runtime_key']='changed'
    with pytest.raises(ValueError,match='provenance'):validate_result(row,record,'frozen')


def test_uncertain_and_unsupported_diagnostics_stay_quarantined():
    row,record=fixture();record['events']['standing_block']['production_eligible_strokes']=1
    with pytest.raises(ValueError,match='Quarantined'):validate_result(row,record,'frozen')
    record['production_deferred']=False;row['supported_event_hint']=None
    with pytest.raises(ValueError,match='unsupported'):validate_result(row,record,'frozen')


def test_duplicate_downloads_cannot_inflate_population():
    row,_=fixture()
    with pytest.raises(ValueError,match='unique'):
        validate_inputs({'format':'gurr-population-input/1','clips':[row,deepcopy(row)]})


def test_full_review_preserves_entire_duration_and_requires_confirmed_event():
    row,_=fixture();t=task(row,270,'evaluation')
    assert t['duration_s']==100 and t['source_start_s']==0 and t['feedback'] is None
    j={'author_id':'Synthetic reviewer','reviewer_id':'Synthetic reviewer','author_role':'coach',
       'label':'green','attribute':'Slope','reviewed':True,'single_stroke_confirmed':True,
       'stroke_span_s':[95,96],'event_id':'underhand','event_confirmed':False,
       'clip_sha256':'forged','partition':'fit'}
    with pytest.raises(ValueError,match='Confirm the event'):validated_feedback(t,j)
    j['event_confirmed']=True
    result=validated_feedback(t,j)
    assert result['event_id']=='underhand' and result['clip_sha256']==row['sha256']
    assert result['partition']=='evaluation' and result['stroke_span_s']==[95,96]
    j['event_id']='invented'
    with pytest.raises(ValueError,match='Confirm the event'):validated_feedback(t,j)


def test_bounded_windows_cover_the_full_tail_and_context_does_not_duplicate_strokes():
    from window_population import intervals,verify_coverage,deduplicate
    plan=intervals(1718.928333)
    verify_coverage(plan,1718.928333)
    assert sum(r['core_end_s']-r['core_start_s'] for r in plan)==pytest.approx(1718.928333)
    assert plan[-1]['core_end_s']==1718.928333
    broken=deepcopy(plan);broken[1]['core_start_s']+=.1
    with pytest.raises(ValueError,match='Gap'):verify_coverage(broken,1718.928333)
    rows=[{'window_index':0,'span_s':[44,46],'usable':True,'context_margin_s':3},
          {'window_index':1,'span_s':[44.1,46.1],'usable':True,'context_margin_s':4},
          {'window_index':1,'span_s':[47,48],'usable':True,'context_margin_s':2}]
    result,removed=deduplicate(rows)
    assert len(result)==2 and removed==1 and result[0]['window_index']==1
