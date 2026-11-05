# blob_tracker

A tracking-overlay look for any picture: boxes, link lines and labels that follow bright, dark, moving or edge regions, or the strongest corners, with the background and the inside of the boxes treated separately. TOP in, TOP out, plus the tracked points as a CHOP for other effects to use.

## Connectors

| Connector | |
|---|---|
| Input 1 (TOP) | The picture. With nothing wired the module shows black. |
| Output 1 (TOP) | The picture with the overlay, at the input's size. |
| Output 2 (CHOP) | The tracked points, one sample per point (256 samples, live points first in ID order): `u` `v` `w` `h` (box centre and size, 0 to 1 of the frame, origin bottom-left), `id`, `age` (frames tracked), `active` (1 for a live point), `conf` (detection strength), and `x1` `y1` `x2` `y2`, one link line per sample (`x1` is -1 where there is none). |

## Parameters

- **Tracking.** Engine, Max Points (up to 128), Smoothing, Max Move (the largest jump that keeps a point's ID), Hold Frames (how long a lost point stays), Min Age (frames before a new point is drawn), Reuse IDs (a new point takes the lowest free ID, so labels stay short) and Reset Tracking. The engines:
  - Blobs: regions of the detection mask (Detect page).
  - Features: the strongest corners of the picture.
  - MediaPipe: listed but not wired up yet; it finds no points.
- **Detect.**
  - Source (Bright, Dark, Motion, Edges), Threshold, and Gain for Motion and Edges.
  - Detect Size (the long side of the small copy that is analysed), Blur, and Merge (joins fragments of one shape).
  - Min Area and Max Area, as a share of the frame.
  - Corner Quality, Corner Spacing and Corners In Mask, for the Features engine.
  - Show Mask: the detection view, for tuning (red is the mask, green the brightness, blue the value before the threshold).
- **MediaPipe.** A MediaPipe component and the landmarks to use: Hands, Face, Pose, Face Step, Min Visibility and Flip X. These are reserved for the MediaPipe engine and do nothing yet.
- **Boxes.**
  - Box Style (Outline, Corners, Dashed, Filled, None).
  - Box Size (Blob Bounds, Fixed, Random per ID) with Box Scale, Box Padding, Fixed Size, Random Min and Max, Min Box and Square.
  - Line Width, Corner Length, Dash Length, Fill Alpha, Box Color and Alpha.
  - Crosshair and Centre Dot.
- **Lines.** Line Mode (Off, Nearest, Proximity, Chain by ID, Hub to the first point), Link Distance, Links Per Point, Line Width, Dash Length, Fade With Length, Line Color and Alpha.
- **Labels.** Label (Off, ID, Coordinates, Size in pixels, ID + Coordinates, Hex Code, Confidence), Position (Above, Inside, Below, Centre), Size, Offset, Color and Alpha.
- **Look.**
  - Background (Original, Monochrome, Threshold, Inverted, Black) with Brightness, Contrast, Saturation and Background Threshold.
  - Inside Boxes (None, Original Colour, Invert, Threshold, Tint, Pixelate, Zoom) with Inside Amount, Inside Threshold, Pixel Size, Zoom and Tint.
  - Trails: how much of the last frame's boxes and lines stays, as a fading trail.
- **Module.** Save Module.

The default look:
- a monochrome background
- outlined boxes with their insides inverted
- ID and coordinate labels above each box
- every point linked to its two nearest neighbours within Link Distance

## How it works

- **Detection:** `res_detect` and `blur_detect` make a small, blurred copy of the picture. `glsl_mask` turns it into a mask by Source and Threshold. `feedback_prev` holds the last frame for Motion.
- **Tracking:** `script_points`, a Script CHOP, reads the mask with the OpenCV that ships with TouchDesigner: connected regions for Blobs, corners (`goodFeaturesToTrack`) for Features.
  - It matches each detection to the points of the last frame, then smooths their positions, assigns IDs, sizes the boxes and finds the links.
  - `constant_tick` makes it cook every frame. A Script CHOP that reads a TOP doesn't recook on its own.
- **Drawing:**
  - `choptotop_points` packs the points into a small texture for the shaders.
  - `glsl_overlay` draws the boxes, crosshairs and lines, with `feedback_trails` for trails.
  - `glsl_look` treats the background and the inside of each box, then lays the overlay on top.
  - `script_labels` writes the label text, which `text_labels` renders.
- **Show Mask:** `switch_view` swaps in the detection view.
- **Why not the Blob Track TOP:** on a Non-Commercial licence it tracks only 2 blobs. OpenCV has no limit and needs no install.
- **Cost:** with a 720 x 1280 clip, the project's frame time went from 2.7 ms to 4.8 ms, still at 60 fps. Most of that is the OpenCV step, about 2 ms of CPU per frame.

## Requirements

- TouchDesigner 2025 (built and tested on 2025.32820, Windows). OpenCV and numpy come with TouchDesigner.

## Files

| File | |
|---|---|
| `blob_tracker.tox` | The module. Projects load this through External .tox. |
| `blob_tracker.tdxn` | Its network as text, written by Save Module. |
| `glsl_mask_pixel.glsl`, `glsl_overlay_pixel.glsl`, `glsl_look_pixel.glsl`, `script_points_callbacks.py`, `script_labels_callbacks.py`, `module_callbacks.py` | Its shaders and scripts as text, written by Save Module. Edit them inside TouchDesigner, not here. |
