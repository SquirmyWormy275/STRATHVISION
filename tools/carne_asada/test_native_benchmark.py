import pytest
from native_benchmark import score_contacts, publish


def fixture():
    reference={'window_id':'one','clip_sha256':'source','score_interval_s':[0,4],
               'ignored_intervals_s':[],'contact_intervals_s':[[1,1.1],[2,2.1]]}
    result={'window_id':'one','clip_sha256':'source','contact_times_s':[1.05,1.06],
            'paused_for_selection':False}
    return reference,result


def test_native_repeated_predictions_do_not_inflate_matches():
    ref,pred=fixture();counts=score_contacts(ref,pred)
    assert (counts['tp'],counts['fp'],counts['fn'])==(1,1,1)


def test_native_selection_deferral_counts_as_missing_contacts():
    ref,pred=fixture();pred.update(paused_for_selection=True,contact_times_s=[])
    assert score_contacts(ref,pred)['fn']==2
    pred['contact_times_s']=[1]
    with pytest.raises(ValueError,match='Paused'):score_contacts(ref,pred)


def test_unknown_native_contacts_are_unrated_and_changed_sources_rejected():
    ref,pred=fixture();ref['contact_intervals_s']=None
    assert score_contacts(ref,pred) is None
    pred['clip_sha256']='changed'
    with pytest.raises(ValueError,match='source'):score_contacts(ref,pred)


def test_incomplete_or_duplicate_native_runs_cannot_be_published(tmp_path):
    ref,pred=fixture()
    with pytest.raises(ValueError,match='incomplete'):
        publish({'windows':[pred]},[ref],tmp_path)
    with pytest.raises(ValueError,match='missing or duplicated'):
        publish({'complete':True,'expected_windows':1,'windows':[pred,pred]},[ref],tmp_path)
