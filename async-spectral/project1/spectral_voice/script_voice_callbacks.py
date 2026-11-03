# script_voice: the beams as sound. Every bin of topto_beams is a place on the frequency
# axis; its red, green and blue drive three partials an octave-band apart (red low, blue
# high), loudness = colour x beam coverage. The partial bank then runs through a ping-pong
# delay and an 8-line feedback-delay-network reverb, all in numpy.
# Input 0: slice_clock, a silent time-sliced 44.1 kHz oscillator that sets the block length.
# Input 1: topto_beams (r, g, b, a per bin). Input 2: the source audio: all of it during the
# Fade In / Fade Out seconds at the video's start and end, Original in between.
import numpy as np

_SR = 44100.0
_FDN_DELAYS = np.array([1031, 1327, 1523, 1871, 2113, 2437, 2729, 3049])
_state = {}  # per Script CHOP id: phases, smoothed spectrum, delay lines


def _hadamard(n: int) -> np.ndarray:
	"""Orthonormal Hadamard matrix: the lossless mixing matrix of the reverb."""
	h = np.array([[1.0]])
	while h.shape[0] < n:
		h = np.block([[h, h], [h, -h]])
	return h / np.sqrt(n)


class _Ring:
	"""Multi-channel circular buffer read at a per-channel delay."""

	def __init__(self, chans: int, size: int) -> None:
		self.buf = np.zeros((chans, size))
		self.size = size
		self.pos = 0

	def read(self, delay: np.ndarray, m: int) -> np.ndarray:
		"""The m samples written delay samples before the next m (needs m <= delay)."""
		idx = (self.pos - delay[:, None] + np.arange(m)[None, :]) % self.size
		return np.take_along_axis(self.buf, idx, axis=1)

	def write(self, x: np.ndarray) -> None:
		idx = (self.pos + np.arange(x.shape[1])) % self.size
		self.buf[:, idx] = x
		self.pos = (self.pos + x.shape[1]) % self.size


def _newState(bins: int) -> dict:
	rng = np.random.default_rng(7)
	partials = bins * 3
	return {
		'bins': bins,
		'phase': rng.uniform(0, 2 * np.pi, partials),
		'amp': np.zeros(partials),
		'target': np.zeros(partials),
		'drift_rate': rng.uniform(0.05, 0.25, partials),
		'drift_phase': rng.uniform(0, 2 * np.pi, partials),
		'time': 0.0,
		'echo': _Ring(2, int(_SR * 2.5)),
		'room': _Ring(8, 4096),
		'mix': _hadamard(8),
	}


def onSetupParameters(scriptOp: scriptCHOP) -> None:
	return


def onPulse(par: Par) -> None:
	return


def onGetCookLevel(scriptOp: scriptCHOP) -> CookLevel:
	return CookLevel.ALWAYS  # audio must advance every frame, viewed or not


def onCook(scriptOp: scriptCHOP) -> None:
	comp = scriptOp.parent()
	clock = scriptOp.inputs[0] if len(scriptOp.inputs) > 0 else None
	beams = scriptOp.inputs[1] if len(scriptOp.inputs) > 1 else None
	n = clock.numSamples if clock is not None else int(_SR / 60)
	n = int(min(max(n, 1), _SR * 0.2))

	data = beams.numpyArray() if beams is not None and beams.numChans >= 4 else np.zeros((4, 64), np.float32)
	bins = data.shape[1]
	state = _state.get(scriptOp.id)
	if state is None or state['bins'] != bins:
		state = _state[scriptOp.id] = _newState(bins)

	# Spectrum: colour ^ contrast x coverage, red/green/blue -> low/mid/high band.
	colour = np.clip(np.nan_to_num(data[:3].astype(np.float64)), 0.0, 1.0)
	coverage = np.clip(np.nan_to_num(data[3].astype(np.float64)), 0.0, 1.0)
	contrast = float(comp.par.Contrast.eval())
	target = (colour ** contrast * coverage[None, :] ** 2).reshape(-1)  # squared: beams swell, live video stays faint
	if not comp.par.Active.eval():
		target[:] = 0.0
	glide = float(comp.par.Glide.eval())
	state['target'] = glide * state['target'] + (1.0 - glide) * target

	low = max(float(comp.par.Lowfreq.eval()), 10.0)
	high = max(float(comp.par.Highfreq.eval()), low * 2.0)
	span = np.log2(high / low)
	x = np.linspace(0.0, 1.0, bins)
	octave = np.concatenate([c * span / 4.0 + x * span / 2.0 for c in range(3)])
	freq = low * 2.0 ** octave
	t = state['time']
	cents = float(comp.par.Shimmer.eval()) * np.sin(2 * np.pi * state['drift_rate'] * t + state['drift_phase'])
	freq = np.minimum(freq * 2.0 ** (cents / 1200.0), _SR * 0.45)

	amp1 = state['target'] * (low / freq) ** 0.3
	amp1 = amp1 * (0.45 / (0.35 + np.sqrt(np.sum(amp1 ** 2))))
	amp0 = state['amp']

	# Partial bank, amplitudes ramped across the block, phases carried between blocks.
	steps = np.arange(1, n + 1)
	phase = state['phase'][:, None] + (2 * np.pi * freq / _SR)[:, None] * steps[None, :]
	ramp = steps / n
	voices = (amp0[:, None] + (amp1 - amp0)[:, None] * ramp[None, :]) * np.sin(phase)
	state['phase'] = phase[:, -1] % (2 * np.pi)
	state['amp'] = amp1
	state['time'] = t + n / _SR

	width = float(comp.par.Width.eval())
	pan = np.tile(0.5 + (x - 0.5) * width, 3) * (np.pi / 2)
	dry = np.stack([np.cos(pan) @ voices, np.sin(pan) @ voices])

	# Space: ping-pong delay, then the FDN reverb, in chunks no longer than the shortest delay.
	delay_s = min(max(float(comp.par.Delaytime.eval()), 0.05), 2.0)
	echo_d = np.array([int(delay_s * _SR)] * 2)
	echo_fb = min(max(float(comp.par.Delayfeedback.eval()), 0.0), 0.95)
	echo_mix = float(comp.par.Delaymix.eval())
	rt60 = 0.6 + float(comp.par.Roomsize.eval()) ** 2 * 14.0
	gains = 10.0 ** (-3.0 * _FDN_DELAYS / (rt60 * _SR))
	damp = min(max(float(comp.par.Damping.eval()), 0.0), 1.0)
	verb_mix = float(comp.par.Reverbmix.eval())
	echo, room, mix = state['echo'], state['room'], state['mix']

	out = np.zeros((2, n))
	chunk = int(min(_FDN_DELAYS.min(), echo_d.min()))
	for a in range(0, n, chunk):
		b = min(a + chunk, n)
		m = b - a
		block = dry[:, a:b]
		taps = echo.read(echo_d, m)
		echo.write(block + echo_fb * taps[::-1])
		wet = block + echo_mix * taps
		d0, d1, d2 = room.read(_FDN_DELAYS, m), room.read(_FDN_DELAYS + 1, m), room.read(_FDN_DELAYS + 2, m)
		lines = (1.0 - damp) * d0 + damp * (0.25 * d0 + 0.5 * d1 + 0.25 * d2)
		room.write(0.5 * wet.sum(axis=0)[None, :] + gains[:, None] * (mix @ lines))
		verb = 0.5 * np.stack([lines[0::2].sum(axis=0), lines[1::2].sum(axis=0)])
		out[:, a:b] = wet * (1.0 - 0.5 * verb_mix) + verb_mix * verb

	out = np.tanh(out * float(comp.par.Level.eval()) * 2.0) * 0.5

	# Fades: original audio for the first Fade In seconds of the video and the last Fade
	# Out seconds, the beam voice in between; equal-power, ramped across the block.
	at = float(comp.par.Videotime.eval())
	length = float(comp.par.Videolength.eval())
	fade_in, fade_out = float(comp.par.Fadein.eval()), float(comp.par.Fadeout.eval())
	mixin = min(max(at / fade_in, 0.0), 1.0) if fade_in > 0 else 1.0
	if length > 0 and fade_out > 0:
		mixin *= min(max((length - at) / fade_out, 0.0), 1.0)
	voice_gain = np.sin(mixin * np.pi / 2)
	original_gain = max(np.cos(mixin * np.pi / 2), float(comp.par.Original.eval()))
	gains0 = state.get('gains', (voice_gain, original_gain))
	state['gains'] = (voice_gain, original_gain)
	out = out * (gains0[0] + (voice_gain - gains0[0]) * ramp)[None, :]

	original = original_gain
	source = scriptOp.inputs[2] if len(scriptOp.inputs) > 2 else None
	# Read the source every block even while it is silent here: this read is what keeps the
	# source deck's audio player (and the video linked to it) advancing.
	src = source.numpyArray().astype(np.float64) if source is not None and source.numChans > 0 else None
	if max(original, gains0[1]) > 0.0 and src is not None:
		if src.shape[0] == 1:
			src = np.repeat(src, 2, axis=0)
		if src.shape[1] != n:
			grid = np.linspace(0.0, 1.0, src.shape[1])
			src = np.stack([np.interp(np.linspace(0.0, 1.0, n), grid, ch) for ch in src[:2]])
		out = out + (gains0[1] + (original - gains0[1]) * ramp)[None, :] * src[:2]

	if clock is not None:
		scriptOp.copy(clock)  # the clock's time slice: rate, length and slice flag
	scriptOp.clear()
	scriptOp.copyNumpyArray(out.astype(np.float32), baseName='chan')
	scriptOp.rate = _SR
