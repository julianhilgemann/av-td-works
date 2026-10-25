# Written by Save Module from output_deck.tox so git shows readable diffs. Edit this
# DAT inside output_deck in TouchDesigner, then press Save Module; edits here change nothing.

# Output size of the output deck (Format page): the Output Format preset or the custom size,
# turned on its side by Swap Width and Height, then scaled down to the licence's limit with
# its shape kept. glsl_frame, fit_bg and the recorder read it.

_FORMATS = {
	'hd720': (1280, 720),
	'hd1080': (1920, 1080),
	'uhd4k': (3840, 2160),
	'phone': (1080, 1920),
	'iphone': (1179, 2556),
	'square': (1080, 1080),
	'portrait45': (1080, 1350),
}
_NONCOMMERCIAL_LIMIT = 1280  # longest side a Non-Commercial licence renders

def TargetSize(comp):
	"""The size the Output Format asks for, before the licence limit."""
	name = comp.par.Outputformat.eval()
	if name == 'input':
		picture = comp.op('null_in')
		w, h = picture.width, picture.height
	elif name == 'custom':
		w, h = comp.par.Outputwidth.eval(), comp.par.Outputheight.eval()
	else:
		w, h = _FORMATS[name]
	if comp.par.Swapsize.eval():
		w, h = h, w
	return max(int(w), 2), max(int(h), 2)

def RenderSize(comp):
	"""TargetSize scaled down to the licence's limit, shape kept, both sides even (H.264 and
	H.265 need even sizes)."""
	w, h = TargetSize(comp)
	scale = min(1.0, _NONCOMMERCIAL_LIMIT / max(w, h)) if licenses.isNonCommercial else 1.0
	return _even(w * scale), _even(h * scale)

def LimitScale(comp):
	"""Rendered width over requested width: 1 unless the licence limit shrinks the output."""
	return RenderSize(comp)[0] / TargetSize(comp)[0]

def Describe(comp):
	"""The Output Size readout: the size asked for, and the size rendered when the licence limits it."""
	w, h = TargetSize(comp)
	rw, rh = RenderSize(comp)
	if (rw, rh) == (w, h):
		return '%d x %d' % (w, h)
	return '%d x %d, rendered at %d x %d (Non-Commercial limit)' % (w, h, rw, rh)

def _even(x):
	return max(2, int(round(x / 2.0)) * 2)
