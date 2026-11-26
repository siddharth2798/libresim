# libresim — Claude guide
Local desktop C172 flight sim, Mumbai–Pune region, Godot 4 (Mobile renderer), GDScript. Full plan: PLAN.md.

## Conventions
- Files < 300 lines, one responsibility each. snake_case files/functions, PascalCase class_name.
- SI units internally (m, s, kg, rad, Pa). Convert only at instruments/UI (units.gd).
- World frame: local ENU metres, origin 18.75N 73.40E. Data projection = local TM centred there (tools/common.py WORLD_PROJ), so projected metres == ENU. Render = Vector3(e-ox, up, -(n-oy)) via FloatingOrigin autoload (shifts every 5 km).
- FDM at fixed 120 Hz in _physics_process; rendering interpolates. All sim state lives in the property tree (e.g. /fdm/ias_mps, /systems/electrical/bus_volts); modules talk only via properties.
- Aircraft behaviour is data (game/aircraft/<id>/*.json, read through AircraftDef), not code.
- Heavy data work = Python in tools/, run locally. Never read files in data/ into context.

## Layout
tools/ offline pipeline · data/raw, data/processed (gitignored) · game/{core,fdm,systems,avionics,instruments,world,aircraft,input,ui,atc,tests}
Aircraft are folders under game/aircraft/<id>/ (aircraft.json, config.json, aero.json, ...) read through AircraftDef; generic aircraft code is in game/aircraft/common/ (docs/USAGE.md, "Adding an aircraft").

## Status
Done (details in docs/USAGE.md, plans in docs/):
- Pipeline tools/0*.py (run order in docs/USAGE.md), region packs (tools/01d, regions.py, osm_regions.py, meta_*.json; Mumbai–Pune plus the konkan_kerala corridor), OSM roads/rivers (tools/20: 4 m SDF tiles; tools/21: shore foam, depth colour; 13 new airfields in the corridor), WorldCover land classes (tools/19, terrain/wc, per-class ground shader), 3D OSM buildings (tools/10), outer ring (tools/12), simulated ILS (tools/14_ils.py), terminals (tools/15-16, terminal_*.py, world/terminals.gd, docs/TERMINALS.md), terrain textures (tools/26-27), jetways (tools/jetway_net.py), branding (tools/branding/make_logo.py), packaging (tools/package/make_release.sh, packaging/), e2e sweep (tools/e2e.sh), `./run.sh`.
- Sim: terrain viewer (game/world), FDM (game/fdm, tests/test_fdm_cards.gd), c172p model and cockpit (tools/blender), 8 cameras, credits/GPL screen, instruments, systems, failures (systems/failure_*.gd, F9), radios (game/avionics: VOR/ILS/DME/ADF, GPS, moving map), damage model, weather/night/moon, save/load (core/situation*.gd), replay (systems/replay*.gd), session recording (ui/session_recorder.gd, core/mkv_writer.gd, F8), joystick/gamepad and keyboard rebinding, audio/options, sound (every aircraft sound is data in aircraft.json audio.layers; distance/Doppler, PTU, APU, chimes, turbulence, thunder, airport vehicles and jetways; docs/AUDIO-PLAN.md, tools/29_generated_sounds.py).
- World: airport stands, taxi and follow-me, pushback, vehicles and ramp crew (world/ramp_*.gd), jetways (world/jetway_*.gd), apron floodlights (world/apron_*.gd), airport lighting, tyre contact (docs/TYRE-CONTACT-PLAN.md), aircraft lights (aircraft_lights.gd, light_parts.gd).
- Graphics G0–G6 (docs/GRAPHICS-PLAN.md): bench (tools/bench.sh), Max preset, Forward+ on High+, AgX, post effects (core/post_fx*.gd, world/postfx/), clouds, water, horizon curvature and haze LUT, volumetric fog (world/vfog_*.gd).
- UI: home (Free flight | Training), start flow with rail and footer chips, Fly anyway confirm (core/setup_checks.gd), airport search and map, wind dial, Options/Controls tabs, UI scale 100-200 % (tests/debug_ui_walk.tscn), in-flight notifications, optional callouts (K), touchdown smoke/marks, fly-by placement (ui/flyby_placement.gd). Route planner: optional Route step (ui/menu/route_*.gd; auto-route avionics/route_builder.gd; into the flight core/route_setup.gd, air start on a leg core/route_air_start.gd). Plan: docs/UI-IMPLEMENTATION-PLAN.md.
- Training mode (game/training: lessons.json, logic, markers, hud, session; ui/menu/training_page.gd). ATC A1 (game/atc: stateful controller, monitor, phraseology.json, panel; silent in lessons; docs/ATC.md). Stands, ATC text and checklists.
- A320: thrust at the fans, rudder x3 (docs/A320-STATUS.md).
- Game is named libresim; legacy user data is migrated (core/legacy_migrate.gd). Brand: runway "09/27" mark, Fira Sans wordmark (game/branding, one brand, no variants).
- Docs: FDM vs JSBSim in docs/FDM-VS-FLIGHTGEAR.md.

Next: finish the e2e re-run; ATC A2 (circuit traffic) and A3 (Piper voice, real radio sounds); radio UI = slim bar top-left + message card + short call list + History + radio assist option (docs/ATC.md "The radio on screen"); graphics G7–G10 (docs/GRAPHICS-PLAN.md); dawn mist and light shafts (G5 notes). A320 is paused (docs/A320-PLAN.md; overhead buttons with a system behind them are wired, the rest stay static; body and flight-deck finish in docs/A320-FINISH-PLAN.md).

Standing reqs: PLAN.md §8b.

Tests: when a change affects behaviour, add or update a test that fails on the old behaviour and passes on the new one. Before every commit, run the full suite on the tree being committed: `tools/test_all.sh` (parallel, sized to the machine; `TEST_JOBS=N` forces N workers; details in docs/USAGE.md "Automated tests"). The single process `~/.local/bin/godot --headless --audio-driver Dummy --path game res://tests/run_tests.tscn` is the reference run and also works. A new failure blocks the commit. A known unrelated failure may remain only when it is already recorded.
Godot 4.7.2 at ~/.local/bin/godot (not on PATH). Python: tools/.venv. Keep docs/USAGE.md updated each milestone.

Shell commands (agents and main session): every unanalysable command makes Claude Code ask the user, so keep them plain.
- Prefer Edit / Write / Read / Grep / Glob over shell. Never edit files with `python3 - <<EOF`, sed or awk.
- One simple command per call. Absolute paths or `$HOME`, never `~` in an assignment; no globs in paths (`*.gd`); no loops, `$()` or long `;` / `&&` chains. Multi-step logic goes in a script file.
- Every Godot launch, windowed or headless, passes `--audio-driver Dummy`.
- Run tests from the project root with `tools/test_all.sh` (`TEST_JOBS=3` while other agents share the machine). The exact allowed forms are in the local `.claude/settings.json`; agents must not edit `.claude/`, `tools/*.sh`, `run.sh` or this file without the user's approval.
- Before every commit, `git diff` the scripts the allow list trusts (`tools/test_all.sh`, `tools/bench.sh`, `game/tests/parallel/`) against HEAD and show the user.

## Performance and efficiency rules (every change obeys these; evidence, numbers and checks: docs/PERFORMANCE-RULES.md, same numbering)
Goal: fast loading and good frame rate on low-end and mid-range machines of every make, not only the Apple M4 this is developed on. Say "measured on Apple M4 only" for any number; reason about other hardware; never tune to this machine.

Loading and startup
1. Work only for what is near the aircraft. Never plan, build or register the whole region at flight start (pushback for 44 airports cost 2.9 s; 1,070 runway nodes were built). The start airport (and anything within about 2 km) is built before the first frame, airports within about 15 km are prepared on a worker thread nearest first, far ones are freed with hysteresis (about 1.3 times the build range).
2. Ranges come from visibility, not timings: the pixel rule (about 3 px at 1080p; `world/vis_ranges.gd`), scaled by preset (0.75 to 1.5) and zoom.
3. Stream under per-frame time and byte budgets, nearest first, with a cap on work in flight; `WorkerThreadPool` for CPU generation; the main thread only for scene-tree changes and GPU uploads; never read a file synchronously on a cache miss in the frame loop.
4. Load in the background as soon as the intent is known (`ResourceLoader.load_threaded_request` for the flight scene and aircraft; `ui/scene_preload.gd`); keep the loading film playing; decode its frames off the main thread.
5. Bake lazily near the camera and free far bakes; persist slow, deterministic bakes to `user://` keyed by version and preset (the tree atlas is planned).
6. Merge and share: one mesh per airport for all its taxiways with a shared material, not one MeshInstance3D and one ShaderMaterial per item (draw calls limit Mobile and integrated GPUs).
7. Parse each data file once and share the result.
8. Do not ship unused assets (480 of 720 loader frames were used) or store assets lossless that never need it.
9. Heavy data work is offline Python in `tools/`, cached by input hash in `run.sh` (register inputs and dependencies for a new step); download external data at build time into `data/raw`, do not commit copies.

Frame time
10. Write a shader uniform or sky value only when it changed (about half a colour level): Godot rebuilds the sky after any write (15 writes a frame cost 7 to 12.7 ms; write-on-change and INCREMENTAL cost 0.1 ms). `world/sky_params.gd`.
11. Tick rates: only the flight model and anything feeding forces or surfaces back into it runs at 120 Hz; systems 60 Hz; instruments, radios, GPS, annunciators 30 Hz, through `core/tick_rate.gd` (true elapsed time). Every `_physics_process` script must declare its rate (a test fails otherwise).
12. One edge filter, not two: SMAA on Low and Medium, MSAA from High, TAA or FSR replace SMAA where active.
13. Shadows: Medium has one cascade and a 2048 map; terrain does not cast below High.
14. Clouds are half-resolution on lower presets, with cloud alpha capped by the pixel's own depth and cleared within 6 m of the camera (otherwise cloud draws over the cockpit).
15. Visibility ranges and stand-ins for small or detailed objects; occlusion culling only where it pays (near terminals, below about 150 m AGL).
16. Particles: no GPU collision; counts per preset, none on Low, soft sprites, nothing near the camera.
17. Fake lights and transparent surfaces need an explicit draw order (`render_priority`); cockpit and other opaque materials must write depth.
18. Floating origin: positions in world coordinates, no per-node loops on a shift, per-instance phases from a seed, never from a render position.
19. Measure before optimising (`tests/debug_perf.tscn`, `tests/debug_tick_cost.gd`, `tools/bench.sh`): script CPU was about 2 ms; the cost was GPU passes, memory and one-off startup work.

Memory
20. Budget per preset: 2 GB video cards and 8 GB laptops must fit; per-preset caches (ground tiles 120 Low, 150 Medium, 400 High and up).
21. Compress: VRAM-compressed textures with mipmaps for 3D models (except textures repainted at run time), share duplicates between exterior and cockpit, block-compress baked atlases.
22. Right-size helper data: categorical maps shrink by nearest texel (never blended), smooth maps bilinear, half size for coarse tiles, CPU copies only where code reads them.
23. Free what you build, including RIDs from `RenderingServer.*_create` (the test run fails on leaked nodes).

Every graphics form, every chip, every renderer
24. Every change, not only graphics changes, must work well in every graphics form and on every chip. Forms: all presets (Low to Max), Mobile, Forward+ and the Compatibility fallback, every render scale and Auto resolution, every UI scale, cockpit and outside cameras, day and night. Chips: integrated and discrete; Apple, NVIDIA, AMD, Intel; Metal, Vulkan, Direct3D 12; macOS, Windows, Linux; 2 GB cards to high-end. Check at least Low (Mobile), High (Forward+) and the fallback, look at the result (muted screenshots), compare cost per preset, and say which combinations you could not run and why the result should hold. What cannot work on the lowest form must degrade gracefully (fewer, simpler, or off), never break.
25. One rule for all machines: no brand, vendor, OS or processor checks in graphics code (a test fails if it names one); defaults from the preset and the feature's cost; platform-only features (MetalFX) only as optional extras beside an equivalent path.
26. Guard shader code per renderer with `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY` (no `dFdxFine`, no per-instance uniforms past the 4,096 limit, no fog shaders there).
27. Do not depend on GPU timestamps (Metal reports none): auto resolution falls back to frame time; benchmark through Vulkan (`DRIVER=vulkan`) for GPU passes.
28. Below about 15 fps the 120 Hz sim runs in slow motion (Godot catches up at most 8 steps a frame); keep per-frame cost low, do not raise the cap blindly.
29. State what could not be tested (an M5, Windows, an integrated GPU) and why the result should hold.

Tests
30. Run the suite with `tools/test_all.sh` (parallel; cores minus one, capped by free memory, longest first; the single process, 14.5 min, is the reference only). Split any test over about a minute into independent parts (the every-stand pushback test is 13 parts covering the same 1,922 pairs).
31. Tests are independent and clean: no order dependence (restore props you set, even to unset), no shared `user://` files between concurrent runs, free every node, declare a tick rate for each new `_physics_process` script.
32. Fail on the old behaviour: rendering cannot be tested on the dummy renderer, so test the structure (materials write depth, ranges, counts, shader constants twin the script) and keep a muted frame-capture check for visual regressions (`tools/check_cockpit_clouds.py`).
33. Measure properly: interleave old and new builds on a quiet machine, several runs, report the noise, label "measured on Apple M4 only"; whole-frame times drift up to 25 % on a fanless laptop, so prefer GPU pass timestamps (Vulkan) and counts (objects, draw calls, triangles, memory).
34. Headless runs are muted too: every Godot launch passes `--audio-driver Dummy`.

Code and repository
35. Files under 300 lines, one job each; split helpers early.
36. Find code with `grep -i "<word>" .cache/code_map.md` (refreshed by the git hooks) before exploring; `graphify query` for tools and docs; never read `data/` into context.
37. Plain shell commands (see above).
38. Commit hygiene: fetch before pushing (others push to main); run the full suite on the tree being committed; never commit screenshots, caches or generated data; revert unrelated edits that tool installers make to tracked files (graphify touched `.gitattributes`).
39. Update `docs/USAGE.md` and the player handbook `docs/site/index.html` with every change.

Working with agents
40. Short briefs that point here for the standing rules; two or three agents at a time; resume a stopped agent instead of starting a new one.
41. Screenshots are temporary: tidy, only key before and after pairs in `review_screenshots/<task>/`, deleted after checking unless the user asks to keep them; delete large scratch copies when done.
42. Stay off files another running agent owns, and re-read shared files (`tests/run_tests.gd`, docs, the handbook) right before editing them.

Before you commit: did this add whole-region startup work, a per-frame write, a per-frame allocation, a new 120 Hz script or an uncompressed texture? Does it work in every graphics form and on every chip (rule 24), and which combinations did you run? Is there a test that fails on the old behaviour, did `tools/test_all.sh` pass on this tree, are the docs and handbook updated, and are the screenshots deleted?
