# output_deck

Where a project's picture goes: framed to the size of the screen it's for, sent to OBS over Spout or Syphon, and recorded to a movie with its sound. Put it after the project's last TOP.

## Connectors

| Connector | |
|---|---|
| Input 1 (TOP) | The picture. Black when nothing is wired. |
| Input 2 (CHOP) | The sound for recordings: time-sliced audio, such as a source_deck's audio output. Takes have no sound when nothing is wired. |
| Output 1 (TOP) | The framed picture, as shared and recorded. Nothing has to pull it, because sharing and recording run by themselves. |

## Parameters

- **Format.** Output Format: Same as Input, HD 720p, Full HD 1080p, 4K UHD TV, Phone 9:16 (1080 x 1920), iPhone Full Screen (1179 x 2556), Square, Portrait 4:5 or Custom Size (Custom Width and Height). Swap Width and Height turns any of them on its side. Output Size shows the size being sent.
- **Framing.** Picture Fit (Fit Inside, Fill, Stretch, Native Size), Picture Zoom and Picture Position. Soft Edge fades the picture into the background where the two meet, along a Rectangle or an Oval. Background: Solid Colour, Blurred Picture, Mirrored Picture or Transparent, with Background Colour and Picture in Background. Blend: Over, Add, Screen or Lighten.
- **Share.** Send to OBS (Spout/Syphon) and Sender Name.
- **Record.** Record, Timing (Frame-Exact or Live), Stop After, Codec (H.264, H.265, MPEG-4, ProRes), Quality, Record Audio, Recordings Folder (default `media/exports` in the project), Recording Name, Open Recordings Folder, and the Recording readout.
- **Module.** Save Module.

## Common setups

- **A phone video of a square or wide visual.** Output Format Phone 9:16, Picture Fit Fit Inside, Soft Edge 0.1 to 0.25, Background Solid Colour (black) or Blurred Picture. The picture keeps its shape and dissolves into the background instead of ending in a hard border. With Add or Screen, the picture's dark parts show the background through.
- **A 4K TV.** Output Format 4K UHD TV (with Swap Width and Height for a TV hung upright). Picture Fit Fill covers the screen; Fit Inside shows all of the picture.
- **OBS.** Turn on Send to OBS. On Windows, install the Spout2 plugin for OBS (obs-spout2-plugin) and add a Spout2 Capture source; on macOS, add a Syphon Client source. Then pick the Sender Name. OBS gets the framed picture at Output Size, and Background Transparent sends alpha for layering.
- **A music video.** Play the track from a file or YouTube source and record with Timing Frame-Exact. Stop After sets the length.

## Licences

- **Non-Commercial limits the longest side to 1280 pixels.** Larger formats are rendered at the same shape, only smaller: 4K becomes 1280 x 720 and Phone 9:16 becomes 720 x 1280, and Output Size says so. A Commercial or Pro licence renders the full size, so a project set to 4K on one machine records 4K on another without changes.
- **H.264 and H.265 need a Commercial or Pro licence.** TD encodes them on an NVIDIA GPU and refuses that on Non-Commercial, so a take set to either records as MPEG-4 (.mp4) there, and the Recording readout says so. MPEG-4 and ProRes record on any licence.
- **Spout works on Non-Commercial** (tested at 1280 x 720).

## How it works

- `glsl_frame` frames the picture in one shader: fit, zoom, position, soft edge, background and blend. A side of the picture that reaches the border of the output stays sharp, so a picture that already fills the output passes through unchanged (within 1/255).
- Blurred Picture is the picture fitted to cover the output at 1/8 size and blurred (`fit_bg` → `blur_bg`). `switch_bg` cooks that only while it's the chosen background.
- The output is 8-bit, so values brighter than white in a float picture are clipped, as Spout and the encoders would clip them anyway.
- **Frame-Exact** turns TD's Realtime flag off for the take and back to what it was afterwards. Every frame is rendered, as fast as the machine can: a light scene records faster than real time, a heavy one slower. The movie's picture and sound stay in step (a 3 s take had 180 frames and 132,300 samples at 44.1 kHz), but the speakers, a camera and a microphone don't, so use Live for live input. A Live take repeats each frame TD drops, and the Recording readout counts them.
- Each take is a new file, `<Recording Name or project>_<date>_<time>.mp4` (`.mov` for ProRes). The video bit rate follows Quality and the output size; the sound is AAC at 192 kb/s, or 24-bit PCM with ProRes.
- Record turns itself off after Stop After, or when the encoder reports an error; the readout then says Failed and why. A project saved while recording doesn't start a take when it opens.
- With Share and Record off, nothing in the deck cooks. The Spout Out TOP cooks itself while sharing, and the Movie File Out TOP while recording.

## Requirements

- TouchDesigner 2025 (built and tested on 2025.32820, Windows, Non-Commercial licence).
- For H.264 and H.265: an NVIDIA GPU and a Commercial or Pro licence. Not yet tested on Pro.
- For OBS on Windows: the Spout2 plugin. Syphon on macOS is untested.

## Files

| File | |
|---|---|
| `output_deck.tox` | The module. Projects load this through External .tox. |
| `output_deck.tdxn` | Its network as text, written by Save Module. |
| `framing.py`, `recorder.py`, `deck_clock.py`, `module_callbacks.py`, `glsl_frame_pixel.glsl` | Its scripts and shader as text, written by Save Module. Edit them inside TouchDesigner, not here. |
