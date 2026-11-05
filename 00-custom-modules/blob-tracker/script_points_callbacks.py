# Written by Save Module from blob_tracker.tox so git shows readable diffs. Edit this
# DAT inside blob_tracker in TouchDesigner, then press Save Module; edits here change nothing.

# Tracker of the blob tracker. Each cook it turns the detection mask (OpenCV engines) or
# MediaPipe's landmarks into up to Maxpoints tracked points with stable IDs, sizes their
# boxes and links them.
#
# Output: SLOTS samples per channel, live points packed first in ID order.
#   u v w h            box centre and size, 0..1 of the frame, origin bottom-left
#   id age active conf tracking ID, frames tracked, 1 = live point, detection strength 0..1
#   x1 y1 x2 y2        one link line per sample (0..1); x1 = -1 where there is none
# choptotop_points packs these into a SLOTS x 3 texture for the shaders (one row per 4 channels).
# Input 0 is constant_tick (absTime.frame): it makes this CHOP cook every frame it is demanded.

import math
import numpy as np
import cv2

SLOTS = 256  # samples per channel: Maxpoints stops at 128, links at SLOTS
_CHANNELS = ('u', 'v', 'w', 'h', 'id', 'age', 'active', 'conf', 'x1', 'y1', 'x2', 'y2')
_KERNEL = np.ones((3, 3), np.uint8)
_state = {'tracks': {}, 'nextid': 1, 'engine': None, 'reuse': True}


def resetTracking():
	"""Forget every track, so IDs start again at 1."""
	_state['tracks'] = {}
	_state['nextid'] = 1


def _detectBlobs(T, mask):
	"""Connected regions of the mask, largest first: [u, v, w, h, conf, key]."""
	h, w = mask.shape[:2]
	m = (mask[:, :, 0] > 0.5).astype(np.uint8)
	merge = int(T.par.Merge)
	if merge > 0:
		m = cv2.dilate(m, _KERNEL, iterations=merge)  # joins fragments of one shape
	count, _, stats, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
	total = float(w * h)
	lo, hi = float(T.par.Minarea), float(T.par.Maxarea)
	found = []
	for x, y, bw, bh, area in stats[1:count]:
		share = area / total
		if lo <= share <= hi:
			found.append([(x + bw * 0.5) / w, (y + bh * 0.5) / h, bw / w, bh / h,
				min(1.0, share / max(hi, 1e-6)), None])
	found.sort(key=lambda d: -d[2] * d[3])
	return found


def _detectFeatures(T, mask):
	"""Strong corners of the picture (Shi-Tomasi), optionally only inside the mask."""
	h, w = mask.shape[:2]
	gray = (np.clip(mask[:, :, 1], 0.0, 1.0) * 255.0).astype(np.uint8)
	region = (mask[:, :, 0] > 0.5).astype(np.uint8) if T.par.Featuremask else None
	corners = cv2.goodFeaturesToTrack(gray, maxCorners=int(T.par.Maxpoints),
		qualityLevel=float(T.par.Featurequality),
		minDistance=max(1.0, float(T.par.Featuredistance) * h), mask=region)
	if corners is None:
		return []
	return [[x / w, y / h, 0.0, 0.0, 1.0, None] for x, y in corners.reshape(-1, 2)]


def _detectMediapipe(T):
	"""Landmarks from the MediaPipe component named on the MediaPipe page."""
	return []


def _newTrack(d):
	tracks = _state['tracks']
	if _state['reuse']:
		tid = 1
		while tid in tracks:
			tid += 1  # the lowest free ID, so labels stay short
	else:
		tid = _state['nextid']
		_state['nextid'] += 1
	tracks[tid] = {'id': tid, 'u': d[0], 'v': d[1], 'w': d[2], 'h': d[3],
		'conf': d[4], 'key': d[5], 'age': 0, 'lost': 0, 'seen': True}


def _follow(t, d, keep):
	"""Move a track toward its new detection; keep is the share of the old value (smoothing)."""
	for i, name in enumerate(('u', 'v', 'w', 'h')):
		t[name] = t[name] * keep + d[i] * (1.0 - keep)
	t['conf'] = d[4]
	t['seen'] = True


def _track(found, aspect, keep, maxmove, hold):
	"""Match detections to tracks: keyed ones (MediaPipe landmarks) by key, the rest greedily
	by distance, closest pairs first, within maxmove frame heights."""
	tracks = _state['tracks']
	for t in tracks.values():
		t['seen'] = False
	bykey = {t['key']: t for t in tracks.values() if t['key'] is not None}
	free = []
	for d in found:
		if d[5] is None:
			free.append(d)
		elif d[5] in bykey:
			_follow(bykey[d[5]], d, keep)
		else:
			_newTrack(d)
	waiting = [t for t in tracks.values() if not t['seen'] and t['key'] is None]
	taken_t, taken_d = set(), set()
	if waiting and free:
		tp = np.array([[t['u'], t['v']] for t in waiting])
		dp = np.array([[d[0], d[1]] for d in free])
		dx = (dp[None, :, 0] - tp[:, None, 0]) * aspect
		dy = dp[None, :, 1] - tp[:, None, 1]
		dist = np.hypot(dx, dy)
		for flat in np.argsort(dist, axis=None):
			ti, di = divmod(int(flat), len(free))
			if dist[ti, di] > maxmove:
				break
			if ti in taken_t or di in taken_d:
				continue
			taken_t.add(ti)
			taken_d.add(di)
			_follow(waiting[ti], free[di], keep)
			if len(taken_t) == len(waiting) or len(taken_d) == len(free):
				break
	for di, d in enumerate(free):
		if di not in taken_d:
			_newTrack(d)
	for tid in list(tracks):
		t = tracks[tid]
		if t['seen']:
			t['lost'] = 0
			t['age'] += 1
		else:
			t['lost'] += 1
			if t['lost'] > hold:
				del tracks[tid]


def _boxSize(T, t, W, H):
	"""Box width and height (0..1 of the frame) for one track, per Box Size."""
	mode = T.par.Boxsize.eval()
	if mode == 'random':
		r = (math.sin(t['id'] * 12.9898) * 43758.5453) % 1.0
		lo, hi = float(T.par.Randommin), float(T.par.Randommax)
		bw = bh = (lo + (hi - lo) * r) * H
	elif mode == 'fixed' or t['w'] <= 0.0:
		bw = bh = float(T.par.Fixedsize) * H
	else:
		pad = 2.0 * float(T.par.Boxpad)
		bw = t['w'] * W * float(T.par.Boxscale) + pad
		bh = t['h'] * H * float(T.par.Boxscale) + pad
	if T.par.Square:
		bw = bh = max(bw, bh)
	least = float(T.par.Boxmin)
	return max(bw, least) / W, max(bh, least) / H


def _links(T, pts, aspect):
	"""Index pairs to draw as lines, per Line Mode, no longer than Link Distance."""
	mode = T.par.Linemode.eval()
	n = len(pts)
	if mode == 'off' or n < 2:
		return []
	xy = np.array([[p['u'] * aspect, p['v']] for p in pts])  # in frame heights
	dist = np.hypot(xy[:, None, 0] - xy[None, :, 0], xy[:, None, 1] - xy[None, :, 1])
	reach = float(T.par.Linkdistance)
	if mode == 'chain':
		pairs = [(i, i + 1) for i in range(n - 1)]
	elif mode == 'hub':
		pairs = [(0, i) for i in range(1, n)]
	elif mode == 'nearest':
		np.fill_diagonal(dist, np.inf)
		k = min(int(T.par.Linksperpoint), n - 1)
		near = np.argsort(dist, axis=1)[:, :k]
		pairs = sorted({(min(i, int(j)), max(i, int(j))) for i in range(n) for j in near[i]})
	else:  # proximity: every pair within reach, shortest first
		iu, ju = np.triu_indices(n, 1)
		order = np.argsort(dist[iu, ju])
		pairs = [(int(iu[k]), int(ju[k])) for k in order]
	return [(a, b) for a, b in pairs if dist[a, b] <= reach][:SLOTS]


def onCook(scriptOp):
	T = parent.BlobTracker
	scriptOp.clear()
	scriptOp.numSamples = SLOTS
	chans = [scriptOp.appendChan(name) for name in _CHANNELS]
	video = op('null_video')
	W, H = float(max(video.width, 1)), float(max(video.height, 1))
	aspect = W / H
	engine = T.par.Engine.eval()
	if engine != _state['engine']:
		resetTracking()  # IDs from another engine mean nothing here
		_state['engine'] = engine
	maxp = int(T.par.Maxpoints)
	found = None
	if engine == 'mediapipe':
		found = _detectMediapipe(T)
	else:
		mask = op('null_mask').numpyArray(delayed=True)  # last frame's mask: no GPU stall
		if mask is not None and mask.size:
			found = _detectBlobs(T, mask) if engine == 'blobs' else _detectFeatures(T, mask)
	if found is not None:
		_state['reuse'] = bool(T.par.Reuseids)
		_track(found[:maxp], aspect, float(T.par.Smoothing), float(T.par.Maxmove), int(T.par.Hold))
	minage = int(T.par.Minage)
	live = sorted((t for t in _state['tracks'].values() if t['age'] >= minage),
		key=lambda t: t['id'])[:maxp]
	data = np.zeros((len(_CHANNELS), SLOTS), dtype=np.float32)
	data[8:12, :] = -1.0
	for k, t in enumerate(live):
		bw, bh = _boxSize(T, t, W, H)
		data[0:8, k] = (t['u'], t['v'], bw, bh, t['id'], t['age'], 1.0, t['conf'])
	for k, (a, b) in enumerate(_links(T, live, aspect)):
		data[8:12, k] = (live[a]['u'], live[a]['v'], live[b]['u'], live[b]['v'])
	for i, ch in enumerate(chans):
		ch.copyNumpyArray(data[i])
	return
