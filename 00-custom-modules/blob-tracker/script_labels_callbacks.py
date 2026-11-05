# Written by Save Module from blob_tracker.tox so git shows readable diffs. Edit this
# DAT inside blob_tracker in TouchDesigner, then press Save Module; edits here change nothing.

# Labels of the blob tracker: one row per live point for text_labels' Specification DAT.
# x and y are pixels from the bottom-left of the frame, where the text's left end and baseline
# go. Input 0 (choptodat_points) only makes this DAT recook whenever the points change; the
# values are read straight from null_points.

_ADVANCE = 0.6  # PT Mono's character width per pixel of font size, for centring


def _text(mode, pid, u, v, w, h, W, H, conf):
	if mode == 'id':
		return '#%03d' % pid
	if mode == 'coords':
		return 'x%.3f y%.3f' % (u, v)
	if mode == 'size':
		return '%dx%d' % (round(w * W), round(h * H))
	if mode == 'idcoords':
		return '#%03d %.3f %.3f' % (pid, u, v)
	if mode == 'hex':
		return '0x%04X' % ((pid * 2654435761) & 0xFFFF)
	if mode == 'conf':
		return '%.2f' % conf
	return ''


def onCook(scriptOp):
	T = parent.BlobTracker
	scriptOp.clear()
	scriptOp.appendRow(['x', 'y', 'text'])
	mode = T.par.Labelmode.eval()
	if mode == 'off':
		return
	data = op('null_points').numpyArray()
	video = op('null_video')
	W, H = float(max(video.width, 1)), float(max(video.height, 1))
	size = float(T.par.Labelsize)
	ox, oy = float(T.par.Labeloffsetx), float(T.par.Labeloffsety)
	where = T.par.Labelposition.eval()
	for k in range(data.shape[1]):
		if data[6, k] < 0.5:
			break  # live points come first
		u, v, w, h, pid, conf = (float(x) for x in data[(0, 1, 2, 3, 4, 7), k])
		text = _text(mode, int(pid), u, v, w, h, W, H, conf)
		left, top, bottom = (u - w * 0.5) * W, (v + h * 0.5) * H, (v - h * 0.5) * H
		if where == 'inside':
			x, y = left + 3.0, top - size - 1.0
		elif where == 'below':
			x, y = left, bottom - size - oy
		elif where == 'center':
			x, y = u * W - len(text) * size * _ADVANCE * 0.5, v * H - size * 0.35
		else:  # above the top-left corner
			x, y = left, top + oy
		scriptOp.appendRow([round(x + ox, 1), round(y, 1), text])
	return
