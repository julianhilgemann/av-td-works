# output_deck

Where a project's picture goes: framed to the size of the screen it's for, sent to OBS over Spout or Syphon, and recorded to a movie with its sound or to a GIF, at a quality, size and frame rate that keep files small. Put it after the project's last TOP.

## Connectors

| Connector | |
|---|---|
| Input 1 (TOP) | The picture. Black when nothing is wired. |
| Input 2 (CHOP) | The sound for recordings: time-sliced audio, such as a source_deck's audio output. Takes have no sound when nothing is wired. |
| Output 1 (TOP) | The framed picture, as shared and recorded. Nothing has to pull it, because sharing and recording run by themselves. |

## Parameters

- **Format.** Output Format: Same as Input, HD 720p, Full HD 1080p, 4K UHD TV, Phone 9:16 (1080 x 1920), iPhone Full Screen (1179 x 2556), Square, Portrait 4:5 or Custom Size (Custom Width and Height). Swap Width and Height turns any of them on its side. Output Size shows the size being sent.
- **Framing.** Picture Fit (Fit Inside, Fill, Stretch, Native Size), Picture Zoom and Picture Position. Soft Edge fades the picture into the background where the two meet, along a Rectangle or an Oval. Background: Solid Colour, Blurred Picture, Mirrored Picture or Transparent, with Background Colour and Picture in Background. Blend: Over, Add, Screen or Lighten.
- **Watermark.** Watermark (on by default), Watermark Text (`hyperadapted`), Watermark Opacity (0.3), Watermark Color (white), Watermark Size (a fraction of the picture height, 0.06) and Watermark Position (an offset from the middle: 0, 0 is middle centre and ±0.5 reaches the edges). It is in everything the deck shows, shares and records.
- **Share.** Send to OBS (Spout/Syphon) and Sender Name.
- **Record.** Record, Timing (Frame-Exact or Live), Stop After, Codec (H.264, H.265, MPEG-4, ProRes, GIF), Quality (Smallest File, Small, Standard, High, Very High), Record Size (Auto, Output Size, 1/2, 1/3, 1/4), Frame Rate (Auto, or 50 down to 10 fps), Record Audio, Recordings Folder (default `media/exports` in the project), Recording Name, Open Recordings Folder, and the Recording readout, which also gives each take's size and frame rate.
- **Module.** Save Module.

## Common setups

- **A phone video of a square or wide visual.** Output Format Phone 9:16, Picture Fit Fit Inside, Soft Edge 0.1 to 0.25, Background Solid Colour (black) or Blurred Picture. The picture keeps its shape and dissolves into the background instead of ending in a hard border. With Add or Screen, the picture's dark parts show the background through.
- **A 4K TV.** Output Format 4K UHD TV (with Swap Width and Height for a TV hung upright). Picture Fit Fill covers the screen; Fit Inside shows all of the picture.
- **OBS.** Turn on Send to OBS. On Windows, install the Spout2 plugin for OBS (obs-spout2-plugin) and add a Spout2 Capture source; on macOS, add a Syphon Client source. Then pick the Sender Name. OBS gets the framed picture at Output Size, and Background Transparent sends alpha for layering.
- **A music video.** Play the track from a file or YouTube source and record with Timing Frame-Exact. Stop After sets the length.
- **A GIF.** Codec GIF, with Record Size and Frame Rate on Auto: 480 pixels on the longest side at 20 fps, about 0.5 to 1 MB per second depending on the picture (grain and noise make GIFs large). For a smaller file choose 1/4 Size or 15 or 10 fps; for a bigger, smoother one, 1/2 Size or 25 fps.
- **A small video to send.** MPEG-4 (or H.264 on Commercial), Quality Small, Record Size 1/2 and Frame Rate 30: a 1280 x 720 picture at 60 fps became 640 x 360 at 30 fps and about 6.5 MB a minute, with sound.

## Licences

- **Non-Commercial limits the longest side to 1280 pixels.** Larger formats are rendered at the same shape, only smaller: 4K becomes 1280 x 720 and Phone 9:16 becomes 720 x 1280, and Output Size says so. A Commercial or Pro licence renders the full size, so a project set to 4K on one machine records 4K on another without changes.
- **H.264 and H.265 need a Commercial or Pro licence.** TD encodes them on an NVIDIA GPU and refuses that on Non-Commercial, so a take set to either records as MPEG-4 (.mp4) there, and the Recording readout says so. MPEG-4 and ProRes record on any licence.
- **Spout works on Non-Commercial** (tested at 1280 x 720).

## How it works

- `glsl_frame` frames the picture in one shader: fit, zoom, position, soft edge, background and blend. A side of the picture that reaches the border of the output stays sharp, so a picture that already fills the output passes through unchanged (within 1/255).
- `text_watermark` writes the Watermark Text in Roboto Medium, which ships with TouchDesigner (`app.samplesFolder + '/Fonts/'`), so the watermark doesn't depend on the machine's fonts. `comp_watermark` lays it over the framed picture; with Watermark off its opacity is 0 and the picture passes through unchanged. The text redraws only when a Watermark setting or the output size changes.
- Blurred Picture is the picture fitted to cover the output at 1/8 size and blurred (`fit_bg` → `blur_bg`). `switch_bg` cooks that only while it's the chosen background.
- The output is 8-bit, so values brighter than white in a float picture are clipped, as Spout and the encoders would clip them anyway.
- **Frame-Exact** turns TD's Realtime flag off for the take and back to what it was afterwards. Every frame is rendered, as fast as the machine can: a light scene records faster than real time, a heavy one slower. The movie's picture and sound stay in step (a 3 s take had 180 frames and 132,300 samples at 44.1 kHz), but the speakers, a camera and a microphone don't, so use Live for live input. A Live take repeats each frame TD drops, and the Recording readout counts them.
- Each take is a new file, `<Recording Name or project>_<date>_<time>.mp4` (`.mov` for ProRes, `.gif` for GIF). The sound is AAC at 192 kb/s, or 24-bit PCM with ProRes; a GIF has none.
- Quality sets whatever the codec responds to. H.264 and H.265 get a bit rate of 0.03, 0.05, 0.1, 0.2 or 0.35 bits per pixel at the record size and frame rate (untested here: they need a Commercial licence). MPEG-4 ignores bit rates, so it gets TD's Quality Scale instead. ProRes gets a profile: 422 Proxy, LT, 422, 422 HQ or 4444 (Proxy was a fifth the size of HQ). A GIF has no setting that changes it; Record Size and Frame Rate set its size, and TD writes it in a fixed palette, which can tint the picture slightly.
- MPEG-4 at 1280 x 720 and 60 fps on ferroscope's grainy picture, scored against the same frames at Quality Scale 1 (SSIM, 1 = identical):

  | Quality | Quality Scale | Bit rate | Per minute | SSIM |
  |---|---|---|---|---|
  | Smallest File | 0.15 | 4.4 Mb/s | 33 MB | 0.932 |
  | Small | 0.3 | 5.5 Mb/s | 41 MB | 0.940 |
  | Standard | 0.45 | 8.8 Mb/s | 66 MB | 0.948 |
  | High | 0.6 | 11.6 Mb/s | 87 MB | 0.956 |
  | Very High | 0.8 | 19.5 Mb/s | 146 MB | 0.976 |

  Before these steps the deck recorded MPEG-4 at Quality Scale 1: 55 Mb/s, about 410 MB a minute, whichever Quality was chosen.
- `res_record` scales the picture to the Record Size with High Quality Resize, which averages pixels: at 1/4 size it matched an area-averaged reference (SSIM 0.999), where the Movie File Out's own resize made the phosphor mask sparkle (0.915). Half the width and height made about a fifth of the file.
- A lower Frame Rate keeps the movie's length and drops frames in between, with the sound in step: 30 instead of 60 fps made an MPEG-4 file about 40% smaller. A GIF never goes above 50 fps, because GIF delays are in 1/100 s and browsers play a 1/100 s delay as 1/10 s; at 20 fps every delay is exactly 5/100 s.
- Every take has a keyframe each second, which made MPEG-4 files about 8% smaller than TD's default of one every 15 frames.
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
