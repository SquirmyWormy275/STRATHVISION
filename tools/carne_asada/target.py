"""Anonymous within-shot selection from an initial point and box geometry."""
import math

import cv2
import numpy as np

from footage import Pose, iou


def rotate_point(point, clockwise):
    x, y = point
    if clockwise not in (0, 90, 180, 270):
        raise ValueError('Rotation must be a quarter turn')
    for _ in range(clockwise // 90):
        x, y = 1 - y, x
    return [x, y]


def rotate_box(box, clockwise):
    points = [rotate_point(p, clockwise) for p in
              [(box[0], box[1]), (box[2], box[1]),
               (box[0], box[3]), (box[2], box[3])]]
    return [min(p[0] for p in points), min(p[1] for p in points),
            max(p[0] for p in points), max(p[1] for p in points)]


def rotate_frame(frame, clockwise):
    if clockwise == 0:
        return frame
    return cv2.rotate(frame, {90: cv2.ROTATE_90_CLOCKWISE,
                             180: cv2.ROTATE_180,
                             270: cv2.ROTATE_90_COUNTERCLOCKWISE}[clockwise])


def contains(box, point):
    return box[0] <= point[0] <= box[2] and box[1] <= point[1] <= box[3]


def choose_rotation(frame, detector, seed):
    """Only person confidence at the clicked position; no reference labels."""
    scores = {}
    for angle in (0, 90, 180, 270):
        boxes = detector.detect(rotate_frame(frame, angle))
        point = rotate_point(seed, angle)
        scores[angle] = max((b[4] for b in boxes if contains(b, point)), default=0.)
    # Stable ties prefer unchanged orientation, including complete abstention.
    angle = max(scores, key=scores.get)
    return angle, scores


class ImagePose(Pose):
    """Same pose model with image coordinates retained for timing research."""
    def infer(self, frame, box):
        h, w = frame.shape[:2]
        cx, cy = (box[0] + box[2]) * w / 2, (box[1] + box[3]) * h / 2
        side = max((box[2] - box[0]) * w, (box[3] - box[1]) * h) * 1.2
        transform = np.array([[256 / side, 0, 128 - cx * 256 / side],
                              [0, 256 / side, 128 - cy * 256 / side]], dtype=np.float32)
        crop = cv2.warpAffine(frame, transform, (256, 256))
        rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB).astype(np.float32) / 255
        land, presence, world = self.model.run(['Identity', 'Identity_1', 'Identity_4'],
            {self.model.get_inputs()[0].name: rgb[None]})
        lm = land.reshape(-1, 5)
        xy = np.column_stack((((lm[:, 0] - 128) * side / 256 + cx) / w,
                              ((lm[:, 1] - 128) * side / 256 + cy) / h))
        return {'presence': float(presence.flat[0]), 'w': world.reshape(-1).tolist(),
                'v': lm[:, 3].tolist(), 'p': lm[:, 4].tolist(), 'xy': xy.tolist()}


class SpatialTarget:
    """Conservative motion continuity; lost targets require explicit reselection.

    A segment is never a named identity. No appearance or cross-video matching.
    """
    def __init__(self, seed, max_gap=.6):
        self.seed, self.max_gap = seed, max_gap
        self.box = None
        self.last_t = None
        self.segment = 0
        self.lost = False

    def reseed(self, seed):
        """An explicit new spatial selection, never automatic identity recovery."""
        self.seed = seed
        self.box, self.last_t = None, None
        self.lost = False

    def update(self, time_s, detections, cut=False):
        if ((cut and self.segment > 0)
                or (self.last_t is not None and time_s - self.last_t > self.max_gap)
                or (self.segment == 0 and time_s > .6)):
            self.lost = True
        if self.lost:
            return None
        if self.box is None:
            choices = sorted((d for d in detections if contains(d, self.seed)),
                             key=lambda d: -d[4])
            if not choices or (len(choices) > 1 and choices[0][4] - choices[1][4] < .12):
                return None
            self.segment += 1
            selected = choices[0]
        else:
            b = self.box
            width, height = b[2] - b[0], b[3] - b[1]
            ranked = []
            for d in detections:
                size_ratio = (d[3] - d[1]) / max(height, .001)
                if not .5 <= size_ratio <= 2:
                    continue
                distance = math.hypot(((d[0] + d[2]) - (b[0] + b[2])) / 2 / max(width, .05),
                                      ((d[1] + d[3]) - (b[1] + b[3])) / 2 / max(height, .05))
                overlap = iou(b, d)
                if overlap < .15 and distance > .65:
                    continue
                score = overlap + .35 * max(0, 1 - distance) + .1 * d[4]
                ranked.append((score, d))
            ranked.sort(key=lambda pair: -pair[0])
            if not ranked or (len(ranked) > 1 and ranked[0][0] - ranked[1][0] < .12):
                return None
            selected = ranked[0][1]
        self.box, self.last_t = list(selected[:4]), time_s
        return self.segment, selected
