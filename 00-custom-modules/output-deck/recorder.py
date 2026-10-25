# Written by Save Module from output_deck.tox so git shows readable diffs. Edit this
# DAT inside output_deck in TouchDesigner, then press Save Module; edits here change nothing.

# Recording for the output deck (Record page). Record starts and stops movie_out; each take
# is a new file named after Recording Name (or the project) and the time it started.
# Frame-Exact turns TD's Realtime flag off while recording, so every frame is rendered and
# none is repeated in the movie, and restores it afterwards. deck_clock calls Tick at the end
# of every frame and Reset when the project or the deck starts.

import datetime
import os
import re

# What each Quality step sets, per codec. H.264 and H.265 take a bit rate (bits per pixel, scaled
# to the record size and frame rate); MPEG-4 ignores bit rates, so it takes TD's Quality Scale
# (measured on a grainy 1280 x 720 picture at 60 fps: about 4, 5.5, 9, 12 and 20 Mb/s); ProRes
# takes a profile. GIF has no quality setting: its size follows Record Size and Frame Rate.
_BITS_PER_PIXEL = {'smallest': 0.03, 'small': 0.05, 'standard': 0.1, 'high': 0.2, 'max': 0.35}
_QUALITY_SCALE = {'smallest': 0.15, 'small': 0.3, 'standard': 0.45, 'high': 0.6, 'max': 0.8}
_PRORES = {'smallest': 'prores422proxy', 'small': 'prores422lt', 'standard': 'prores422',
	'high': 'prores422hq', 'max': 'prores4444'}
_EXTENSIONS = {'prores': '.mov', 'gif': '.gif'}  # every other codec writes .mp4
_SCALES = {'half': 1 / 2.0, 'third': 1 / 3.0, 'quarter': 1 / 4.0}
_GIF_SIDE = 480  # longest side of a GIF on Auto Record Size
_GIF_RATE = 20  # frame rate of a GIF on Auto
_GIF_MAX_RATE = 50  # GIF delays are in 1/100 s, and browsers play a 1/100 s delay as 1/10 s
_NVIDIA_CODECS = ('h264', 'h265')  # GPU encoders, which need a Commercial or Pro licence
_STATUS_EVERY = 15  # frames between Recording readout updates

def Tick(comp):
	"""Start or stop the take when Record changes, stop after Stop After or on an encoder error,
	and keep the readouts current."""
	movie = comp.op('movie_out')
	wanted = bool(comp.par.Record.eval())
	recording = bool(movie.par.record.eval())
	if wanted and not recording:
		_start(comp, movie)
	elif recording and not wanted:
		_stop(comp, movie)
	elif recording:
		seconds = _elapsed(comp)
		limit = comp.par.Recordlength.eval()
		if limit > 0 and seconds >= limit:
			comp.par.Record.val = 0  # writes through to a host parameter it is bound to
			_stop(comp, movie)
		elif absTime.frame % _STATUS_EVERY == 0:
			_write(comp.par.Recordstatus, 'Recording %s to %s%s' % (
				_clock(seconds), movie.par.file.eval(), comp.fetch('takeNote', '', search=False)))
	if movie.par.record.eval():
		error = movie.errors()  # a Movie File Out cooks itself every frame while it records
		if error:
			comp.par.Record.val = 0
			_stop(comp, movie, failure=error)
	if absTime.frame % _STATUS_EVERY == 0:
		_write(comp.par.Outputsize, comp.op('framing').module.Describe(comp))

def Reset(comp):
	"""Never resume a take on start: a project saved while recording would otherwise begin a
	new one the moment it opens."""
	if comp.par.Record.eval():
		comp.par.Record.val = 0
	_write(comp.par.Outputsize, comp.op('framing').module.Describe(comp))

def _start(comp, movie):
	"""Set up res_record and movie_out for the take (file, codec, size, frame rate, quality,
	audio), leave Realtime for Frame-Exact and start recording."""
	codec = comp.par.Recordcodec.eval()
	note = ''
	if codec in _NVIDIA_CODECS and licenses.isNonCommercial:
		codec = 'mpeg4'
		note = ' (H.264 and H.265 need a Commercial licence, so this take is MPEG-4)'
	gif = codec == 'gif'
	folder = comp.par.Recordfolder.eval() or 'media/exports'
	os.makedirs(_absolute(folder), exist_ok=True)
	name = comp.par.Recordname.eval().strip() or project.name.split('.')[0]
	stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
	extension = _EXTENSIONS.get(codec, '.mp4')
	movie.par.file = os.path.join(folder, name + '_' + stamp + extension).replace('\\', '/')
	movie.par.videocodec = codec
	if not gif:
		movie.par.moviecontainer = extension[1:]  # a GIF has no container setting
	movie.par.audiocodec = 'pcm24' if codec == 'prores' else 'aac'  # editing files keep lossless sound
	w, h = _recordSize(comp, gif)
	rate = _recordRate(comp, gif)
	resize = comp.op('res_record')
	resize.par.resolutionw = w
	resize.par.resolutionh = h
	movie.par.fps = rate
	movie.par.keyframeinterval = max(1, int(round(rate)))  # one a second: smaller than TD's 15 frames
	quality = comp.par.Recordquality.eval()
	bitrate = w * h * rate * _BITS_PER_PIXEL[quality] / 1000.0
	movie.par.avgbitrate = bitrate
	movie.par.peakbitrate = bitrate * 1.5
	movie.par.qualityscale = _QUALITY_SCALE[quality]
	if codec == 'prores':
		movie.par.videocodectype = _PRORES[quality]
	# Sound only from a wired audio input: the silence behind an unwired one is not an audio stream.
	wired = not gif and comp.par.Recordaudio.eval() and comp.inputConnectors[1].connections
	movie.par.audiochop = 'null_audio' if wired else ''
	if comp.par.Recordtiming.eval() == 'exact':
		comp.store('realtimeBefore', project.realTime)
		project.realTime = False
	note = ' at %d x %d, %g fps%s' % (w, h, rate, note)
	comp.store('startFrame', absTime.frame)
	comp.store('takeNote', note)
	movie.par.record = 1
	_write(comp.par.Recordstatus, 'Recording to ' + movie.par.file.eval() + note)

def _recordSize(comp, gif):
	"""Record Size: the output size, scaled down by the chosen fraction, or on Auto for a GIF
	to its longest side; shape kept, both sides even (H.264 and H.265 need even sizes)."""
	w, h = comp.op('framing').module.RenderSize(comp)
	choice = comp.par.Recordsize.eval()
	if choice in _SCALES:
		scale = _SCALES[choice]
	elif choice == 'auto' and gif:
		scale = min(1.0, _GIF_SIDE / max(w, h))
	else:
		scale = 1.0
	return _even(w * scale), _even(h * scale)

def _recordRate(comp, gif):
	"""Frame Rate: the chosen rate, or on Auto the project's (a GIF's own on Auto); never above
	the project's rate, and a GIF never above the fastest rate browsers play."""
	choice = comp.par.Recordrate.eval()
	if choice == 'auto':
		rate = _GIF_RATE if gif else project.cookRate
	else:
		rate = float(choice[3:])  # 'fps30' -> 30
	rate = min(rate, project.cookRate)
	return min(rate, _GIF_MAX_RATE) if gif else rate

def _stop(comp, movie, failure=''):
	"""Close the movie, restore Realtime and report the file, or why nothing was saved."""
	movie.par.record = 0
	info = comp.op('info_movie')
	written = _count(info, 'total_frames_written')
	repeated = _count(info, 'total_frames_dropped')
	before = comp.fetch('realtimeBefore', None, search=False)
	if before is not None:
		project.realTime = before
	length = _clock(_elapsed(comp))
	note = comp.fetch('takeNote', '', search=False)
	for key in ('realtimeBefore', 'startFrame', 'takeNote'):
		if key in comp.storage:
			comp.unstore(key)
	if failure or not written:
		reason = re.sub(r'\s*\(/[^)]*\)\s*$', '', failure).replace('Error:', '').strip()
		_write(comp.par.Recordstatus, 'Failed: ' + (reason or 'no frames were written'))
		return
	extra = ', %d frames repeated: use Frame-Exact' % repeated if repeated else ''
	_write(comp.par.Recordstatus, 'Saved %s (%s%s)%s' % (movie.par.file.eval(), length, extra, note))

def _elapsed(comp):
	"""Seconds of movie recorded in this take."""
	return (absTime.frame - comp.fetch('startFrame', absTime.frame, search=False)) / project.cookRate

def _count(info, channel):
	value = info[channel]
	return int(float(value)) if value is not None else 0

def _absolute(folder):
	return folder if os.path.isabs(folder) else os.path.join(project.folder, folder)

def _clock(seconds):
	minutes, seconds = divmod(int(seconds), 60)
	return '%d:%02d' % (minutes, seconds)

def _even(x):
	return max(2, int(round(x / 2.0)) * 2)

def _write(par, value):
	"""Set a readout only when it changes, so a bound host parameter is not touched every frame."""
	if par.eval() != value:
		par.val = value
