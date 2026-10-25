# Written by Save Module from output_deck.tox so git shows readable diffs. Edit this
# DAT inside output_deck in TouchDesigner, then press Save Module; edits here change nothing.

# Frame driver of the output deck: the recorder's Tick at the end of every frame, and its
# Reset when the project starts or the deck is loaded.

def onStart():
	op('recorder').module.Reset(parent())
	return

def onCreate():
	op('recorder').module.Reset(parent())
	return

def onFrameEnd(frame):
	op('recorder').module.Tick(parent())
	return
