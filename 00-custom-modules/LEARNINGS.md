# Learnings: turning a project feature into a shared module

Notes from turning ferroscope's sources and transport into `source-deck/`, so the next extraction starts from the answers instead of rediscovering them. Every TD fact below was measured on TouchDesigner 2025.32820 with Embody 6.2.72, using scratch COMPs that were deleted afterwards.

## 1. The fast path

Decisions already made (section 5 says why). Steps in order:

1. **Map the feature.** List its operators, the host parameters they read (`parent.Host.par.*` in expressions), the host operators that read its outputs, its script DATs and their Embody tags, and which host parameters presets write (the `presets` table rows).
2. **Baseline.** Pause at a fixed position and save the output as a numpy array in the scratchpad (`np.save(path, op('null_video').numpyArray())`). Record every parameter value you're about to touch.
3. **Create the module inside the host**, next to the feature: a Base COMP with `parentshortcut` set to one CamelCase word (`SourceDeck`). Set `allowCooking = False` while building, or the copies start webcams and play audio twice.
4. **Parameters.** `page.appendPar(name, par=hostPar)` copies style, label, default, range, menu and read-only, **but not the help text**: set help again, in wording that doesn't name the host. Get-or-create with `comp.par['Name'] is None`; `comp.par.Name` raises when it's missing.
5. **Operators.** `module.copyOPs([...])` keeps the wires between copied ops. Then, in the same call:
   - rewrite `parent.Host.` to `parent.Module.` in every expression;
   - on copied script DATs, clear `file` and `syncfile` and remove the Embody tags (they still point into the host's folder);
   - add `outTOP` / `outCHOP` (set `connectorder` for the second connector) and `inTOP` / `inCHOP` fed by a constant for when nothing is wired;
   - make the host keep its own In ops and output Nulls, so nothing downstream changes.
6. **Switch over.** Untrack the host's moved DATs first (`remove_externalization_tag(op, delete_file=True)`). Then in one call:
   - set `active = False` on the host's old frame-driven script (two transports on the same parameters fight);
   - bind each module parameter to the host's: `module.par.X.bindExpr = 'parent.Host.par.X'`;
   - destroy the host's originals;
   - wire host In ops into the module, and the module's outputs into the host Nulls (`null.inputConnectors[0].connect(module.outputConnectors[1])`; connecting to the COMP itself fails);
   - turn cooking on.
7. **Pulses don't bind.** The host's parameter callback presses the module's pulse; see `_deckPulse` in `ferroscope/project1/ferroscope/controls_callbacks.py`.
8. **Verify.** The baseline frame must match exactly (`np.abs(now - base).max() == 0.0`). Then test behaviour through the **host's** parameters, because those are what the user touches.
9. **Release.** Give the module a Save Module pulse (copy `_saveModule` and `_writeSnapshot` from `source-deck/deck_callbacks.py`). Set the External .tox Path on the instance while Enable External .tox is still off, press Save Module, then turn on Enable External .tox, turn off Reload Custom and Reload Built-In Parameters, and reload. Check that the binds survived.
10. **Fresh-load test.** `op('/project1').loadTox(path)` with nothing bound: `get_op_errors` must be 0 and the outputs must carry signal. Delete it.
11. **Document and commit.** Add the module's README and a row in `README.md`. The user saves the host `.toe` (Ctrl+S) before the commit, because the instance's binds and External .tox setting live only there.

## 2. External .tox, measured

| Setting or action | What happens |
|---|---|
| Reload Custom Parameters **on** (the default) | Every reload resets the instance's custom parameters to the `.tox` values and drops its binds. The project's settings are lost. |
| Reload Custom Parameters **off** | The instance keeps its values and binds across reloads, and parameters newly added to the `.tox` still appear. |
| Tags on the module COMP | They come from the `.tox` on every reload; tags added on the instance are wiped. Ship tags the host needs (`tdxn_exclude`) inside the `.tox`. |
| `par.val = x` on a bound parameter | Stays in BIND mode and writes through to the master. Works in both directions, so a module script can write its own bound parameters. |
| Switching a parameter to CONSTANT | TD keeps the old `bindExpr` and `expr` text. A `.tox` saved that way makes every new project report "Error occurred while evaluating bind parameter". Clear `bindExpr` and `expr` before saving. |
| `Par.bindMaster` | The host parameter a bound one points at. Use it for attributes that don't bind, such as `normMax` (the slider range). |
| Relative External .tox Path | Resolved against `project.folder`, so `../00-custom-modules/<module>/<name>.tox` works for every project in this repo. |
| `COMP.save(path)` | Keeps the COMP's tags, comment and color in the `.tox`. |

## 3. Embody, measured

- **Embody ignores External .tox.** Its `.tdxn` export copies the child's whole network into the host's file and drops `externaltox` and the reload toggles. The bare `tdxn_exclude` tag removes the module from the host's `.tdxn`, but the wires to and from it are still written (`inputs: [source_deck]`, `- source: source_deck` / `out: 1`).
- **This repo runs Embody in `export` mode** (`op.Embody.par.Tdxnmode`). The `.toe` is the source of truth, and nothing is stripped or rebuilt on save or open; strip-on-save and create-on-start only exist in `full` mode. A test that rebuilds a COMP from its `.tdxn` doesn't reflect what the user experiences.
- **Don't test with `ext.TDXN.importNetworkFromFile(..., clear_first=True)`.** It restored the nested CRT COMP as an empty shell, so its two wires failed. It also re-spawned the GLSL TOPs' default `*_compute` DATs that the network had deleted, and reset `tdxn_exclude:<par>` parameters to their defaults. An autosave then wrote all of that to disk. Repairing it took a careful diff against `git HEAD`.
- **`ExportNetwork` skips anything under `/sys`.** A copy staged in `/sys/quiet` exports as `operators: []`. Load the saved `.tox` into a normal network for the export, then delete it (`_writeSnapshot` does this).
- **Tab-indented DAT text** is written as one escaped YAML line, which makes a useless diff. Write each script as its own `.py` and tag the temporary copy's DATs `tdxn_exclude:dat_content`.
- **Drop `source_file`, `exported_at` and `network_path`** from the snapshot; they change with every save and host.
- **`tdxn_exclude:<par>`** on a COMP keeps runtime values (playheads, time readouts, audio cue points) out of its `.tdxn`, so playback doesn't show up in diffs.
- **Envoy draws its mascot** (`envoy_bot_*` annotations) inside whichever COMP it's working on. Delete them from the release copy. Embody's exporter already leaves them out.

## 4. TouchDesigner gotchas hit on the way

- **Pulse callbacks run after your script returns.** A Save Module pulse followed by a reload pulse in the same call reloaded the old `.tox` first, and the new code was lost. Pulse in one call and check in the next; never pulse save and reload together.
- **Edits inside an External .tox COMP are lost on the next reload** unless Save Module ran. Saving the `.toe` doesn't save the module.
- **`Par.page` and `Par.order` are writable**, so parameters move between pages without being recreated. `comp.sortCustomPages(*names)` orders pages.
- **`/sys/quiet`** (cooking disabled) is the right place for a clean copy to save as `.tox`, but not for the Embody export.
- **Audio File In:**
  - Specify Index mode is sample-exact (zero residual against Sequential, with a constant 0.2 s latency). But a stopped index loops the last 735-sample chunk as a buzz, and it can't play backwards.
  - Sequential with `play` and cue fades pauses and jumps cleanly; a cue lands on the target sample in the next frame. Use Sequential and cue it.
  - Sequential audio only advances while something cooks it.
  - The Info CHOP gives `sample`, `file_length` and `open`; Audio File In has no Python members for position or length.
- **Movie File In:** use Specify Index with Index Unit seconds. `numSeconds`, `index` and `rate` are Python members. Each jump to a new spot in a 720p H.264 file costs 25–53 ms; an audio cue costs nothing.
- **A frame-start Execute DAT** that reads about 20 parameters and writes a few costs about 0.02 ms per frame.

## 5. Design choices, and why

- **The host's parameters are the masters; the module's bind to them.** The host panel and presets stay unchanged, the host's `.tdxn` keeps readable values, and the same module still works on its own values in a project that binds nothing.
- **No extension.** Module DATs plus one parexec dispatcher, matching the repo's style. The module's interface is its parameters, pulses included.
- **The code lives only in the `.tox`.** The `.tdxn` and `.py` files are generated by Save Module, for reading and diffing.
- **Reload Built-In Parameters is off too**, as a precaution. The released `.tox` is saved with Enable External .tox off, and with built-in reloads on, that value might be applied to the instance. This wasn't tested.

## 6. Checks before you commit

- Load the released `.tox` into `/sys/quiet`, then delete it. Expect the right tags (`tdxn_exclude`), the right child count (`findChildren(maxDepth=1, includeUtility=True)`), and an empty `[p for p in comp.customPars if p.bindExpr or p.expr]`.
- Each generated `.py` minus its 3 header lines equals the live DAT text.
- `get_op_errors` on the host returns 0 errors and 0 warnings. (Ferroscope's old `glsl_fluid` cook-loop warning is fixed: a uniform read `me.width / me.height`, its own output size; it now reads `me.par.resolutionw / me.par.resolutionh`.)
- `get_project_performance`: fps and dropped frames unchanged. Memory can briefly rise after test loads and comes back down.
- After the user's Ctrl+S, `diff_tdxn` returns `changed_count: 0`.

## 7. Nested modules and per-project data

From splitting the input layer of `octatrack-av-setup` into four modules: `audio-analyzer/` (with a source_deck inside), `midi-analyzer/`, `modulator/` and `av-rig/`, which nests the other three. Measured on the same TD build with Embody 6.2.75:

| What | What happens |
|---|---|
| A COMP with External .tox enabled, inside a COMP saved as `.tox` | Its contents are written into the outer `.tox` (93.9 KB against the inner module's 99.4 KB), but on load the inner COMP reloads from its own file: a marker op added to the embedded copy was gone. So nested modules stay live. |
| The inner instance's parameter values (Reload Custom off) | Kept from the outer `.tox` across the load. |
| A custom parameter created on an instance after it loaded | Dropped on the next reload. Sliders made at run time (the modulator's Bases) must live on a COMP the host saves. |
| Module storage | Replaced on every reload. The MIDI analyzer keeps the last knob values in `root` storage, keyed by its path. |
| A bind chain A ← B ← C (C binds to B, B to A) | Values pass down two levels, and a script writing `C.par.X.val` (a status readout) writes through to A. |
| An OP parameter on a COMP, value `name` | Resolved beside the COMP (its siblings), not inside it. So a nested module gets a table from the outer COMP as an expression that hands over the OP: `(parent.Rig.par.Mapping.eval() or me).op('routes')`, which falls back to the module's own table. |
| A new instance with Reload Built-In off | Has no Parent Shortcut until it is set by hand (every nested instance too). |
| `run(function, arg, delayFrames=1)` | Accepts a callable. The matrix uses it to create parameters outside its cook. |
| `COMP.copyOPs()` | Kept the wires and the docked DATs, and shifted the copies up by 400. Reposition them after. |

Choices that followed:

- **Each project owns its mapping.** The modules take their tables as DAT parameters and fall back to their own examples. `av_rig`'s Create Mapping pulse makes a `<rig>_mapping` COMP beside the rig, with copies of the example tables and the Bases sliders. The host's Embody externalizes it, so a project's routing shows up in its own git diff.
- **Save Module writes tables as `.tsv`** next to the `.py` files, and skips DATs tagged `tdxn_exclude:dat_content` (MIDI logs, generated channel names).
- **The rig shows the modules' parameters on its own pages** (copied with `appendPar(name, par=...)`, so style, range and menu match) and binds the modules to them. Pulses are pressed from the rig's `module_callbacks`. OP-type parameters use expressions, not binds.
- **One fresh-load test per module before the next one depends on it**: load the saved `.tox`, expect 0 errors and signal at the outputs, delete it. Then a reload of the host's rig instance (`enableexternaltoxpulse`) to prove the project's values, mapping, bases and knob memory survive.

## 8. Output modules: sharing and recording

From building `output-deck/` as a new module (not an extraction) in ferroscope. Measured on TouchDesigner 2025.32820 with a Non-Commercial licence and an NVIDIA RTX 5060 laptop GPU:

| What | What happens |
|---|---|
| H.264, H.265 or AV1 in a Movie File Out on Non-Commercial | Refused while recording: "GPU Accelerated H.264/H.265 Encoding requires a Commercial license". No file is written, and nothing is reported until the TOP cooks with Record on. Derivative's Licensing page suggests otherwise; trust the operator. |
| MPEG-4 (Part 2), ProRes, VP9, Motion JPEG, Hap or CineForm on Non-Commercial | Records. |
| The Non-Commercial resolution limit | 1280 x 1280, per the Licensing page; what TD does to a larger TOP wasn't measured, because the deck never asks for one. `licenses.isNonCommercial` and `licenses.isPro` tell the licence from Python. |
| Syphon Spout Out TOP, Non-Commercial | Works: a Syphon Spout In TOP in the same TD received the 1280 x 720 sender. |
| Syphon Spout Out TOP with Active on | Cooks itself every frame, so the chain feeding it cooks with nothing downstream. |
| Movie File Out TOP with Record on | Cooks itself every frame too. Forcing an extra `cook(force=True)` from a frame-end Execute DAT wrote one frame too many per take. |
| Reading a Movie File Out's Info CHOP | `total_frames_written`, `total_frames_dropped` (frames repeated to cover drops), audio sample counts, `resx`/`resy` (128 x 128 until it really cooks). |
| `project.realTime = False` during a take | Frames render as fast as the machine allows, faster than real time for a light scene. Audio File In (sequential) and a transport that steps by `absTime.seconds` stay in step with the picture: 180 frames held exactly 132,300 samples at 44.1 kHz. Audio Device Out, cameras and microphones don't. |
| Realtime on, while tools probe TD | A 2 s take repeated 5 frames. |
| AAC in a Movie File Out | 96, 128 or 192 kb/s only; 256 fails the take ("AAC must have a bit rate of 96, 128, or 192 kb/s"). |
| ProRes .mov with AAC sound | The sound track came out short (0.95 s in a 1 s take). 24-bit PCM is exact. |
| `page.appendPar(name, par=...)` for an XY or RGB parameter | Needs the first component Par (`parGroup[0]`) and creates the whole tuplet; passing the ParGroup raises. |
| Wires into a COMP tagged `tdxn_exclude` | Not in the host's `.tdxn`, because they belong to the excluded entry. Wires out of it are kept. Harmless in `export` mode, where the `.toe` is the source of truth. |
| An annotation's widget after Envoy renames it on creation | A warning for an invalid `.../annotate/annotation` path until the widget's `back` op recooks. |

Choices that followed:

- **Recording settings are applied when a take starts.** The recorder writes the file name, codec, container, frame rate, bit rate and audio onto the Movie File Out then, instead of keeping per-frame expressions on it. It falls back to MPEG-4 when the licence refuses NVIDIA encoding, and reports Failed when the operator errors or writes no frames.
- **Size follows the licence.** The deck computes the requested size, scales it to the 1280 limit on Non-Commercial with its shape kept, and says so in a readout. The same project settings then render the full size on a Pro machine.
- **Runtime readouts stay out of git.** The deck ships `tdxn_exclude:Outputsize` and `tdxn_exclude:Recordstatus`, and the host tags its bound copies the same way.

## 9. Promoting a COMP that is already self-contained

From turning ferroscope's CRT filter into `crt-filter/`. The CRT already had its own parameters, presets table and callback, and nothing in the host read or bound its parameters, so the COMP itself became the module: steps 3 to 6 of the fast path fall away (no new COMP, no copied ops, no binds). Measured on TouchDesigner 2025.32820 with Embody 6.2.72:

| What | What happens |
|---|---|
| A COMP the host's Embody tracks as its own `.tdxn` | `remove_externalization_tag(op, delete_file=True)` removes the tag, the `externalizations.tsv` row, the `_tdn_rel_path` storage entry and the file. |
| Reload Custom Parameters off, nothing bound | The instance kept all 47 of its non-default values across a reload from a `.tox` saved with defaults. The project's look now lives only on the instance in the `.toe`: the instance is `tdxn_exclude`, so no text file holds it. |
| Renaming an operator in an `execute_python` that then fails | Envoy's rollback takes the new name for an operator the script created, and destroys it. `ui.undo.undoStack` names the steps; one `ui.undo.undo()`, run a frame later outside Envoy's own undo block, brought the COMP back with its wires and values. Tags, comment and DAT text kept the failed call's edits, the colour went to TD's default grey, and values came back rounded to their displayed text (0.073, not 0.0729999989). Rename with `rename_op`, in a call of its own, after the other edits succeed, and resolve and check every lookup before the first change. |
| `comp.op('annotate1')` | Returns `None`: `op()` doesn't find annotations. `comp.findChildren(name='annotate1', maxDepth=1, includeUtility=True)` does. |
| Annotations after a `.tox` save and load | Their `utility` flag is off (`copy()` keeps it). Every module's annotations show this; nothing visible changes. |

Choices that followed:

- **The parent shortcut stays `CRT`**, so none of the expressions inside changed. The COMP is renamed `crt_filter`, like the other module instances.
- **The Apply Preset callback became the module's one dispatcher**, `module_callbacks`, with Save Module beside it.
- **ferroscope keeps its CRT look on the instance**, not on a host page. Binding all 59 parameters to a ferroscope page would put the look back in the host's `.tdxn`, at the cost of a new panel page and about 500 lines (the size of the parameter block `CRT.tdxn` had).

## 10. Recording size and GIF

From adding GIF, Quality steps, Record Size and Frame Rate to `output-deck/`. Measured on TouchDesigner 2025.32820, Non-Commercial, with 2-second takes of ferroscope's grainy 1280 x 720 picture at 60 fps, checked out of process:

| What | What happens |
|---|---|
| TD's `bin` folder | Holds `ffmpeg.exe` and `ffprobe.exe`. They check a take without disturbing TD: frame count and duration (`ffprobe -count_frames`), repeated frames (`ffmpeg -f framemd5`), quality against a reference (`ssim` and `psnr` filters). |
| Which Movie File Out parameters a codec uses | TD disables the rest: read `par.enable` with the codec selected. MPEG-4 uses Quality Scale and Keyframe Interval, not Average or Peak Bitrate; GIF uses Quality Scale and Movie FPS; H.264 uses the bit rates. |
| MPEG-4's bit rate | Ignored: a take set to 11 Mb/s wrote 54 Mb/s, because Quality Scale was at its default of 1. Quality Scale 0.8, 0.6, 0.45, 0.3, 0.15 and 0 wrote 19.5, 11.6, 8.8, 5.5, 4.4 and 3.4 Mb/s. |
| Quality Scale on a GIF | No effect: 1, 0.5 and 0.1 wrote byte-identical files. |
| ProRes | `videocodectype` picks the profile (`prores422proxy`, `prores422lt`, `prores422`, `prores422hq`, `prores4444`, `prores4444xq`). Proxy wrote a fifth of HQ. |
| Movie FPS below the cook rate | Frames are dropped by time: 30 fps from a 60 fps cook wrote 60 frames in 2 s, with AAC sound of 1.997 s, and `total_frames_dropped` stayed 0. Stop-Frame Movie with Add Frame wrote the same frames. |
| A GIF | Codec `gif`, a `.gif` file name, no container parameter; records on Non-Commercial. Delays are in 1/100 s: 60 fps wrote alternating delays of 1 and 2, and browsers play a delay of 1 as 10. 20 fps wrote 5 throughout. TD uses a fixed palette. |
| The Movie File Out's own Output Resolution | Sets the recorded size, but ignores Input Smoothness (linear and mipmap wrote identical files) and aliases fine patterns: SSIM 0.915 against an area-averaged reference at 1/4 size. A Resolution TOP with High Quality Resize in front of it scored 0.999. |
| Keyframe Interval | TD's default is 15 frames. 60 at 60 fps made MPEG-4 8% smaller. |
| Changing a menu parameter's `menuNames` | The value keeps its index, not its name: `high`, second of three, became `small`, second of five. Set the value again after changing a menu. |
| A parameter created on an instance and then saved into the `.tox` | Kept its bind across the next reload (unlike one the `.tox` doesn't have; section 7). |

Choices that followed:

- **One Quality menu sets whatever each codec responds to**: bits per pixel for H.264 and H.265, Quality Scale for MPEG-4, a profile for ProRes. The H.264 and H.265 steps are untested here, for want of a Commercial licence.
- **Record Size and Frame Rate have an Auto** that is right for both: the output size and project rate for video, 480 pixels and 20 fps for a GIF, so choosing GIF alone gives a file that plays correctly and stays small.
- **`res_record` does the scaling**, and the recorder keeps setting everything when a take starts, so `movie_out` ships with its old values.
