from copy import deepcopy

import numpy as np
import pytest

from axe_data import validate
from axe_detector import features, fit_linear, predict, score, train


def dataset():
    return {'format':'axe-reference/1','windows':[{
        'window_id':'one','clip_sha256':'source','split':'train',
        'duration_s':8,'rotation_cw':0,'search_roi':[0,0,1,1],
        'frames':[{'time_s':1,'head_box':[.2,.3,.3,.4],'visibility':'visible'}]}]}


def test_source_content_cannot_cross_axe_partitions():
    d=dataset();other=deepcopy(d['windows'][0]);other.update(window_id='other',split='test')
    d['windows'].append(other)
    with pytest.raises(ValueError,match='leaks'):validate(d)


def test_unknown_axe_visibility_cannot_become_a_negative():
    d=dataset();f=d['windows'][0]['frames'][0];f['head_box']=None;f['visibility']='guessed'
    with pytest.raises(ValueError,match='visibility'):validate(d)
    f['visibility']='occluded'
    predicted=[{'window_id':'one','clip_sha256':'source','time_s':1,
                'candidate':{'box':[.2,.3,.3,.4],'margin':2}}]
    result=score(d,predicted,0)
    assert result['unrated_frames']==1 and result['fp']==0
    with pytest.raises(ValueError,match='No visible'):train(d,'not-read')


def test_real_object_matching_penalizes_wrong_locations_and_checks_sources():
    d=dataset();p=[{'window_id':'one','clip_sha256':'source','time_s':1,
                  'candidate':{'box':[.7,.7,.8,.8],'margin':2}}]
    result=score(d,p,0)
    assert (result['tp'],result['fp'],result['fn'])==(0,1,1)
    p[0]['candidate']['box']=[.2,.3,.3,.4]
    assert score(d,p,0)['tp']==1
    with pytest.raises(ValueError,match='Duplicate'):score(d,p+p,0)
    p[0]['clip_sha256']='changed'
    with pytest.raises(ValueError,match='source'):score(d,p,0)


def test_linear_hinge_training_learns_a_separable_feature_problem():
    x=np.array([[2,1],[1,2],[-2,-1],[-1,-2]],dtype=np.float32)
    y=np.array([1,1,-1,-1],dtype=np.float32)
    coef,bias=fit_linear(x,y,100)
    assert np.all(y*(x@coef+bias)>.9)
    with pytest.raises(ValueError,match='positive and negative'):fit_linear(x,[1]*4)


def test_hog_features_preserve_edges_and_are_finite_on_empty_patches():
    empty=np.zeros((32,32),np.uint8);edge=empty.copy();edge[:,16:]=255
    assert features(empty).shape==(324,)
    assert np.isfinite(features(empty)).all()
    assert np.linalg.norm(features(edge))>1


def test_test_inference_requires_freeze_before_reading_images():
    with pytest.raises(ValueError,match='frozen'):predict(dataset(),'not-read',{},'test')
