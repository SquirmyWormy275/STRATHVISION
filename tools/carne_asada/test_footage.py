from footage import Tracker, iou


def test_tracks_are_independent_and_survive_motion():
    tracker = Tracker()
    first = tracker.update(0, [[.1, .1, .3, .9, .9], [.6, .1, .8, .9, .9]])
    second = tracker.update(.2, [[.11, .1, .31, .9, .9], [.61, .1, .81, .9, .9]])
    assert [k for k, _ in first] == [k for k, _ in second] == [1, 2]


def test_cut_and_expiry_never_reuse_identity():
    tracker = Tracker()
    assert tracker.update(0, [[.1, .1, .3, .9, .9]])[0][0] == 1
    assert tracker.update(.2, [[.1, .1, .3, .9, .9]], cut=True)[0][0] == 2
    assert tracker.update(2, [[.1, .1, .3, .9, .9]])[0][0] == 3


def test_ambiguous_overlap_starts_unassigned_track():
    tracker = Tracker()
    tracker.update(0, [[.1, .1, .4, .9, .9]])
    assert all(k != 1 for k, _ in tracker.update(.2, [
        [.09, .1, .39, .9, .9], [.11, .1, .41, .9, .9]]))


def test_iou_does_not_match_disjoint_people():
    assert iou([0, 0, .2, .8], [.8, 0, 1, .8]) == 0


def test_two_competing_tracks_cannot_pass_a_name_to_one_detection():
    tracker = Tracker()
    tracker.update(0, [[.09, .1, .39, .9, .9], [.11, .1, .41, .9, .9]])
    assert tracker.update(.2, [[.1, .1, .4, .9, .9]])[0][0] not in (1, 2)
