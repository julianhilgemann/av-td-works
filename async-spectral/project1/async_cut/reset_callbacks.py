def onPulse(par: Par) -> None:
	"""Reset Streaks clears the streak memory; Restart Sweep sends the cut back to the start."""
	comp = par.owner
	if par.name == 'Restart':
		comp.op('speed_progress').par.resetpulse.pulse()
	comp.op('feedback_prev').par.resetpulse.pulse()
