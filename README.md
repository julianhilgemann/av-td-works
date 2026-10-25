# av-td-works

Audiovisual TouchDesigner works. Each folder is a standalone project: open the `.toe` named after it in TouchDesigner 2025.

| Project | What it is |
|---|---|
| `time-series-wavetable/` | The Bundesbank housing-loan series turned into a playable wavetable synth with a live dashboard. |
| `touch-the-sonogram/` | An installation: the same wavetable drone, shaped by a camera and a microphone and drawn as a point-cloud sonogram. |
| `caleidoscopic-sonogram-video/` | A square music video: the sonogram point cloud driven by an audio track and a modulator video. |
| `ferroscope/` | Sound as ferrofluid: a spike lattice raised by a kaleidoscope-folded sonogram, leaning toward the viewer on camera, through the shared CRT filter. Its Output page frames, shares and records the picture. |
| `audioreactive-pointcloud/` | An audio-reactive point cloud. |
| `color-ribbon-butterfly/` | 250,000 instanced hexagons placed by animated 4D simplex noise, smeared into colored ribbons by feedback, RGBA delay and a radial blur. |
| `infinite-hypercube/` | 262,144 points carried by a self-displacing noise field inside a cube whose faces wrap around, with trails, depth blur and RGBA delay. |
| `iridiscent-viz/` | A music visualizer: a turbulent particle stream lit by an audio track (kick to bloom, rhythm to glow, highs to color and rotation), with feedback, mirroring and tiling. |
| `noise-attractor-landscape/` | A GPU particle swarm in turbulence, wind and force fields, with three presets of each spread across the swarm. |
| `octatrack-av-setup/` | The live AV set: an Elektron Octatrack drives a noise-field particle generator, out at 1920×1080 over Syphon/Spout. See its README. |
| `octatrack-audio-modulation/` | An Octatrack sketch: audio and MIDI read in and shaped, with a million instanced points still moved by LFOs. |
| `octatrack-heat-midi-audio-mapping/` | Octatrack audio through an Analog Heat MKII split into three bands, plus the note triggers of four MIDI tracks. No visuals. |

## Shared modules

`00-custom-modules/` holds components that projects load as External .tox: `source_deck` (camera, file and YouTube sources with a transport), `audio_analyzer`, `midi_analyzer`, `modulator`, `av_rig`, which combines those three, `output_deck` (framing for a phone, a TV or any size, Spout/Syphon to OBS, and movie and GIF recording) and `crt_filter` (a CRT tube and analog-signal look for any TOP). Projects find them at `../00-custom-modules/`, so keep the folder beside them. Its README covers using and changing modules.

## Embody

The projects with a `project1/` folder use [Embody](https://github.com/dylanroscover/Embody): their networks are also saved as `.tdxn`, `.py` and `.tsv` text that git can diff, and its MCP server, Envoy, lets an AI client work in the open project. Embody keeps its agent files (`CLAUDE.md`, `AGENTS.md`, `.claude/`) and the `.mcp.json` it writes on open at the repo root, so start Claude Code here.

Not in git: `.venv/`, `Backup/`, `logs/`, `.mcp.json`, TouchDesigner's numbered saves, and `media/` (YouTube downloads, fetched on demand, and recordings in `media/exports/`).
