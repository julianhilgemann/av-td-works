# crt_filter

A CRT look for any picture: the faults of an analog signal (line jitter, tracking noise, smear, ghosting, grain) and a curved tube with scanlines, a phosphor mask, halation and afterglow. TOP in, TOP out; put it after the project's last TOP, before the output.

## Connectors

| Connector | |
|---|---|
| Input 1 (TOP) | The picture. |
| Output 1 (TOP) | The picture through the tube, at the input's size. |

## Parameters

- **Tube.** Enable (off passes the input through untouched), Curvature, Corner Radius, Edge Softness, Screen Size (below 1 shows the bezel, above 1 overscans), Vignette, Glass Glare and Bezel Color.
- **Scan.** Scanlines and Scan Direction (horizontal, or vertical for a rotated arcade monitor), Scanline Depth, Beam Bloom (bright colours widen their line), Convergence Error, Interlace Flicker, Hum Bar and Hum Speed.
- **Mask.** Phosphor Mask (Off, Shadow Mask, Aperture Grille, Slot Mask), Mask Pitch in pixels, Mask Depth, Dot Softness, and Mask Follows Glass to bend the pattern with the curvature.
- **Signal.** Source Columns (pixelate to a low-resolution source), Smear, Chroma Delay, Ghost and Ghost Offset, Line Jitter, Wave and Wave Frequency, Head Switching, Tracking Noise with its Speed and Height, Vertical Roll, Dropouts, Grain, Colour Noise and Flicker.
- **Glow.** Halation with its Tint, Size and Threshold, Glass Diffusion, Phosphor Persistence (afterglow trails).
- **Color.** Phosphor (Colour, or a Green, Amber or White monochrome monitor), Brightness, Contrast, Gamma, Saturation, Colour Tint (white point) and Black Level.
- **Presets.** Preset and Apply Preset.
- **Module.** Save Module.

## Presets

Default (consumer TV), Arcade Monitor, PC Monitor (Trinitron), Broken VHS, Green Terminal and Amber Terminal. Choose one and press Apply Preset: it overwrites every setting the preset lists, so a project's own look is gone once you apply one.

The values are in the `presets` table inside the module (`presets.tsv` here), one column per look and one row per parameter (colours as their r, g and b parts). A blank cell leaves that parameter alone. To add a look, add a column inside the module, add its name to the Preset menu (Component Editor) and press Save Module. A project that already has the module keeps its own copy of the menu (Reload Custom Parameters is off), so the new name may only show there after the module is added again.

## How it works

- `glsl_signal` is the analog signal: roll, tracking band, head-switching tear, wave and jitter shift each line; the smear trails colour (I, Q) further than brightness (Y); then ghost, dropouts, grain, colour noise and flicker. With a vertical scan direction it all runs along columns.
- `blur_halo` blurs the signal at half size as the halation source.
- `glsl_tube` draws the tube from the signal: curved glass, rounded edge, vignette and glare, convergence error, scanlines whose beam widens on bright colours, interlace and hum bar, the phosphor mask, halation and diffusion, the grade and the monochrome phosphors. `feedback_persist` feeds its last frame back for persistence; it keeps the brighter of the new and the faded old frame, so it never builds up.
- `switch_enable` passes the input straight through when Enable is off.
- Its cost in ferroscope at 1280 x 720: about 0.15 ms of CPU and 0.2 ms of GPU per frame, and 26 MB of GPU memory (RTX 5060 laptop GPU).

## Requirements

- TouchDesigner 2025 (built and tested on 2025.32820, Windows).

## Files

| File | |
|---|---|
| `crt_filter.tox` | The module. Projects load this through External .tox. |
| `crt_filter.tdxn` | Its network as text, written by Save Module. |
| `glsl_signal_pixel.glsl`, `glsl_tube_pixel.glsl`, `module_callbacks.py`, `presets.tsv` | Its shaders, script and preset table as text, written by Save Module. Edit them inside TouchDesigner, not here. |
