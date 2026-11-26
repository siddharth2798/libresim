# Performance and efficiency rules

Every rule here comes from something measured or broken while building libresim. Read the section that matches your change before you start, and check the "Check" line before you commit. The goal is a sim that loads fast and runs well on **low-end and mid-range machines of every make**, not only on the Apple M4 MacBook Air it is developed on. CLAUDE.md carries all 42 rules in short form with the same numbering; this file keeps the evidence and the checks. When a rule changes, change both.

Numbers marked "M4" were measured on an Apple M4 only. Reason about other hardware, say so, and never tune a value to this machine.

## 1. Loading and startup

1. **Work only for what is near the aircraft.** Never plan, build or register something for the whole region at flight start.
   - Evidence: pushback paths for all 44 airports (961 stands) cost 2.9 s per start; every runway and taxiway of the region were built (1,070 nodes). Per-airport and nearby-only cut the wait after Fly from about 19.8 s to 7.7 s (loaded M4) and the draw calls from 999 to 327 at 12,000 ft.
   - Pattern: the start airport (and anything within about 2 km) is built before the first frame; airports within about 15 km are prepared on a worker thread, nearest first, a few nodes a frame; far ones are freed with hysteresis (about 1.3 times the build range) so nothing flickers.
   - Check: a test that only nearby things exist at start, that a far one appears when approached and goes when far, and that a save loaded at another airport builds it first.
2. **Ranges come from visibility, not from timings.** Use the pixel rule (an object stays while it covers about 3 px at 1080p, 60 degree view; `world/vis_ranges.gd`), scaled by preset (Low 0.75 up to Max 1.5) and zoom.
3. **Stream under budgets.** Per-frame time and byte budgets, nearest first, a cap on work in flight, worker threads (`WorkerThreadPool`) for CPU generation, the main thread only for scene-tree changes and GPU uploads. Never read a file synchronously on a cache miss in the frame loop.
4. **Load in the background as soon as the intent is known.** Start `ResourceLoader.load_threaded_request` for the flight scene and the aircraft models when the aircraft is chosen; keep the loading film playing; decode film frames off the main thread (`ui/scene_preload.gd`, `ui/loader_frames.gd`). A synchronous step freezes the film.
5. **Cache deterministic, expensive results.** Bake once, near the camera, lazily (runway bakes within 15 km, freed beyond 20 km); persist to `user://` keyed by version and preset when a bake is slow at every start (tree impostor atlas: planned). Memory for a bake is bounded by "only what is near".
6. **Merge and share.** One mesh per airport for all its taxiways with a shared material, not one MeshInstance3D and one unique ShaderMaterial per item. Draw calls are the limit on Mobile and integrated GPUs.
7. **Parse each data file once** and share the result (runways.json was parsed three times at start).
8. **Do not ship what is not used** (the loader film shipped 720 frames of which 480 were used) and do not store assets lossless that the player never needs lossless.
9. **Heavy data work is offline Python in `tools/`,** cached by input hash in `run.sh`. Register a new step's inputs and dependencies there. Download external data at build time into `data/raw` rather than committing a copy (licensing, size).

## 2. Frame time

10. **Write a shader uniform or sky value only when it changed** (by about half a colour level). Godot rebuilds the sky's ambient and reflection after any write, even an unchanged one: 15 writes a frame cost 7 to 12.7 ms; write-on-change plus the INCREMENTAL sky mode cost 0.1 ms (M4). `world/sky_params.gd`.
11. **Tick rates.** Only the flight model and anything that feeds forces or surfaces back into it runs at 120 Hz. Systems run at 60 Hz, instruments, radios, GPS and annunciators at 30 Hz, through `core/tick_rate.gd`, which hands the true elapsed time to the work so integrators stay correct. Every script with `_physics_process` must declare its rate (a test fails otherwise).
12. **One edge filter, not two.** SMAA alone on Low and Medium, MSAA from High, TAA or FSR replace SMAA where active. MSAA plus SMAA on Medium cost about 14 ms of GPU (M4).
13. **Shadows cost.** Medium: one cascade, a 2048 map, terrain does not cast below High.
14. **Clouds are half-resolution on lower presets, but cloud alpha is capped by the pixel's own depth and cleared within 6 m of the camera** (otherwise cloud draws over the cockpit).
15. **Visibility ranges and stand-ins** for small or detailed objects; occlusion culling only where it pays (near terminals, below about 150 m AGL), because it costs CPU every frame.
16. **Particles:** no GPU collision (a heightfield follows the camera and costs a depth render). Counts per preset, none on Low, soft sprites, nothing near the camera.
17. **Fake lights and transparent surfaces need an explicit draw order** (`render_priority`): apron light pools draw after the see-through taxiways. Cockpit and other opaque materials must write depth.
18. **Floating origin:** keep positions in world coordinates, never loop over thousands of nodes on a shift, derive per-instance phases (sway) from a seed and never from a render position.
19. **Measure before optimising.** Script CPU was about 2 ms a frame on the M4; the cost was in the GPU passes, memory and one-off startup work. Use `tests/debug_perf.tscn`, `tests/debug_tick_cost.gd` and `tools/bench.sh`.

## 3. Memory

20. **Budget per preset.** 2 GB video-memory cards and 8 GB laptops must fit. Per-preset cache sizes (ground tile cache 120 Low, 150 Medium, 400 High and up).
21. **Compress.** VRAM-compressed textures with mipmaps for 3D models (exceptions: textures that liveries or registrations repaint at run time; keep their uncompressed copy). Share duplicate textures between the exterior and the cockpit model. Block-compress baked atlases (tree atlas 53 MB down to 7.5 MB).
22. **Right-size helper data.** Categorical maps (land class, WorldCover) shrink by nearest texel, never blended; smooth maps (shore distance) shrink bilinear. Half size for coarse tiles. Keep CPU copies only for the tiles that code actually reads (ground helper maps: video memory 479 to 228 MB on Low).
23. **Free what you build,** including RIDs made with `RenderingServer.*_create`. The test run fails on leaked nodes (`leak_check`).

## 4. Every device, every renderer

24. **Every change must work well in every graphics form and on every chip,** not only graphics changes: a gameplay, UI, cockpit or world change that looks or runs badly on one preset, renderer or GPU is a defect.
    - **Forms:** every preset (Low, Medium, High, Ultra, Max), every renderer (Mobile, Forward+, Compatibility fallback), every render scale and the Auto resolution, every UI scale, the cockpit and the outside cameras, day and night.
    - **Chips:** integrated and discrete, Apple, NVIDIA, AMD and Intel, on macOS (Metal), Windows (Vulkan or Direct3D 12) and Linux (Vulkan), from a 2 GB card to a high-end one.
    - **How to check:** run the change on at least Low (Mobile), High (Forward+) and the Compatibility fallback, look at the result (screenshots, muted), compare cost per preset, and write down which combinations you could not run and why the result should hold. A feature that cannot work on the lowest form must degrade gracefully (fewer, simpler, or off), never break.
25. **One rule for all machines.** No brand, vendor, OS or processor checks in graphics code (a test fails if it names one). Defaults come from the preset and the cost of the feature. Platform-only features (MetalFX) are optional extras beside an equivalent path.
26. **Check all three renderers:** Mobile (Low, Medium), Forward+ (High and up) and the Compatibility fallback. Guard shader code with `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY` (no `dFdxFine`, no per-instance uniforms above the 4,096 limit, no fog shaders).
27. **Do not depend on GPU timestamps.** Metal reports none. Auto resolution falls back to frame time; benchmark through Vulkan (`DRIVER=vulkan`) to get GPU passes.
28. **Below about 15 fps the 120 Hz sim runs in slow motion** (Godot catches up at most 8 physics steps a frame). Keep per-frame cost low; do not raise the cap blindly.
29. **Say what could not be tested** (an M5, Windows, an integrated GPU) and why the result should hold.

## 5. Tests

30. **Run the suite in parallel with `tools/test_all.sh`.** It sizes itself from the machine (cores minus one, capped by free memory, longest jobs first, `TEST_JOBS=N` forces). The single process (14.5 min) is the reference only. Split any test longer than about a minute into independent parts (the every-stand pushback test is 13 parts and checks the same 1,922 stand and aircraft pairs).
31. **Tests are independent and clean.** No order dependence (put back props you set, even to unset), no shared `user://` files between concurrent runs, free every node, a new `_physics_process` needs a declared tick rate.
32. **Fail on the old behaviour.** Rendering cannot be tested on the dummy renderer, so test the structure (materials write depth, ranges, counts, shader constants twin the script) and keep a muted frame-capture check for visual regressions (`tools/check_cockpit_clouds.py`).
33. **Measure properly.** Interleave old and new builds, on a quiet machine, several runs, report the noise, and label "measured on Apple M4 only". Whole-frame times drift by up to 25 % on a fanless laptop; prefer GPU pass timestamps (Vulkan) and counts (objects, draw calls, triangles, memory).
34. **Headless runs are muted too:** every Godot launch passes `--audio-driver Dummy` (the OS voice bypasses Godot's audio driver; muted runs skip it).

## 6. Code and repository

35. **Files stay under 300 lines, one job each.** Split helpers early.
36. **Find code with `grep -i "<word>" .cache/code_map.md`** (refreshed by the git hooks) before exploring; use `graphify query` for tools and docs. Never read `data/` into context.
37. **Plain shell commands** (see CLAUDE.md): dedicated tools for edits and search, absolute paths, one command per call, no globs or heredocs into interpreters.
38. **Commit hygiene:** fetch before pushing (others push to main); run the full suite on the tree being committed; never commit screenshots, caches or generated data; revert unrelated edits that tool installers make to tracked files (graphify touched `.gitattributes`).
39. **Update the docs and the player handbook** with every change (`docs/USAGE.md`, `docs/site/index.html`).

## 7. Working with agents

40. **Short briefs** that point to CLAUDE.md for the standing rules; two or three agents at a time; resume a stopped agent instead of starting a new one.
41. **Screenshots are temporary:** tidy, only the key before and after pairs in `review_screenshots/<task>/`, deleted after checking unless the user asks to keep them. Delete large scratch copies when done.
42. **Stay off files another running agent owns,** and re-read shared files (`tests/run_tests.gd`, docs, the handbook) right before editing them.

## Before you commit (checklist)

- Did this add startup work for the whole region, a per-frame write, a per-frame allocation, a new 120 Hz script or an uncompressed texture? Fix it or justify it here.
- Does it work well in every graphics form (all presets, Mobile, Forward+ and the Compatibility fallback, every render and UI scale, day and night, cockpit and outside views) and on every kind of chip (integrated and discrete; Apple, NVIDIA, AMD, Intel; Metal, Vulkan, Direct3D 12), with the same rule on every device? Which combinations did you run, and which could you not?
- Is there a test that fails on the old behaviour, and does `tools/test_all.sh` pass on the tree being committed?
- Are the docs and the handbook updated, and the screenshots deleted?
