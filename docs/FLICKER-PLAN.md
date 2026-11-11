# Flicker plan

Fixes for the frame-to-frame flicker seen at a gate (jetbridge, ground vehicles, distant roofs, trees, ND).
Diagnosis (2026-11-10, A320 at VOCI stand 2, Medium preset, Apple M4): bursts of consecutive frames from a
still camera were diffed pixel by pixel. Findings, each with its own phase below:

| # | Finding | Evidence |
|---|---------|----------|
| A | Mesh silhouettes and thin lines flip between the adjacent surfaces' colours on **Forward+** only; Mobile is steady | Forward+ 0.9-1.8 % of pixels change > 24/255 per frame at every preset, with FSR2 or bilinear, with every post effect off, shadows off, no clouds, Metal or Vulkan, depth prepass on or off, threaded or single cull, unshaded materials. Mobile 0.18-0.25 %, all of it UI. Roof-ridge edge wanders 0.4-1.0 px on Forward+, 0.05 px on Mobile; nothing translates (block phase correlation <= 0.07 px). Edge pixels take 3 states incl. one darker than both neighbours. |
| B | Medium (a Mobile preset) runs on Forward+ | `user://graphics.cfg` preset=medium, `game/override.cfg` forward_plus. |
| C | `RenderBudget` clamps every preset to scale 0.7 + FSR2, MSAA off | It evaluated a 1600x900 window as 3200x1800 (points/pixels heuristic in `frame_pixels`). FSR2 made no difference to A. |
| D | ND track line flashes at random angles while parked | Track from a ~0 ground velocity (spring/wind creep). Gone in calm air. |
| E | IAS digits jitter at standstill | Gust noise on the pitot. |
| F | Ground vehicles pulse | Beacon flashes light the vehicle and apron (on/off signature). Intended, harsh at 20-30 fps. |
| G | Tree canopies change nearly every frame (Forward+) | Alpha-scissor foliage edges; same as A, amplified. |

Not causes (measured, do not spend time here): FSR2 / TAA / FXAA mode, depth of field, motion blur, sun shafts,
bloom, sharpen, colour grading, film grain, heat shimmer, volumetric fog, sun shadows, clouds, haze, sun motion,
wind, the aircraft, pipeline compiles, the Metal backend, the depth prepass, threaded culling, the reflection probe.

Complexity: S = under half a day, M = 1-2 days, L = several days or open-ended.

## Phase 0 - Measurement harness (S) - done 2026-11-10

Make the diagnosis repeatable before touching anything.

1. `tools/flicker_metric.py` (from the scratchpad scripts): for a directory of consecutive frames, print the share of
   pixels changing > 24/255 per consecutive pair, the largest changing regions, a heat map, and the sub-pixel
   position (50 % crossing) of a named edge per frame. Exclude the UI band by y range.
2. `tests/debug_flicker.gd`: `--cam=` works only with `--view=free` today (aim() runs but chase re-takes the camera);
   make `--cam` imply the free camera. Allow several `--opt=` (already works) and add `--freeze` (`Engine.time_scale = 0`
   during the burst, as debug_perf has) so sim-driven motion is excluded.
3. Document the recipe in `docs/USAGE.md` ("Flicker / scenery check"): the still-camera gate burst on Forward+ and on
   `--rendering-method mobile`, and the acceptance numbers below.

Acceptance: the Mobile gate burst reports <= 0.3 % (all UI); the Forward+ one reports the current ~1.0-1.5 % so the
later phases have a baseline.

## Phase 1 - Preset and renderer consistency (S-M) - 1 and 2 done 2026-11-10, 3 decided

1. A manual renderer choice is meant to stand (`test_an_existing_override_is_left_alone`), so the mismatch is not
   rewritten: `Graphics.renderer_note` tells the player in the Options Graphics tab and the F10 menu that the preset is
   designed for the other renderer ("Medium is designed for the Mobile renderer; Forward+ was chosen by hand").
   Test: `tests/test_graphics_override.gd`.
2. `core/render_budget.gd` `pick_frame`: the viewport texture size is the frame; the points heuristic only applies
   when there is no texture yet. A 1600x900 window is 1.44 MP and is not clamped any more. Test:
   `tests/test_graphics_presets.gd` `test_budget_frame_is_the_viewport_texture_not_the_doubled_window`.
3. FSR2 stays: measured against bilinear 1.0 and TAA on the same still scene, it changes nothing in A (day) or in the
   night item below. It still replaces the preset's MSAA/TAA look on base Apple chips; revisit only for that reason.

Acceptance: a fresh Medium start runs Mobile; `godot --path game -s tests/probe_spec.gd` (Phase 0 helper) prints
the intended scale/fsr/msaa per preset for the current window.

## Phase 2 - Forward+ silhouette flicker - root cause found and fixed by day (2026-11-11); one night item open

Found by isolation (`debug_flicker --hide=...`, `--free=...`): the minimal scene (`tests/debug_still_mesh.tscn`: sky, sun,
one glb, still camera) renders bit-identical frames on Forward+, so the engine is deterministic and the trigger was in
this project. Hiding groups one at a time led to `RunwayLights/lights_<ICAO>/flood_pools`: the apron floodlight light
volumes (`world/light_pool.gdshader`). They are drawn by day too (with `level` 0) over the whole apron, the stands,
the jetways, the vehicles and the terminal facade, and they rebuild each pixel's position from the depth texture
(`hint_depth_texture`), which Mobile does not provide, hence Mobile was immune:

- Sky pixels sit on the far plane (reverse Z: depth 0, `view.w` 0): the division gave inf/NaN, the box test cannot
  reject NaN, and the pass added NaN to the frame. NaN blending is undefined on the GPU and differed from frame to
  frame; FXAA then spread it into the neighbouring edge pixels. That is every silhouette against the sky inside a pool's
  screen area: roof ridges, the fin, the jetway, vehicles, apron lines.
- Fix (`light_pool.gdshader`): discard at `level <= 0` (uniform, before any derivative), compute the position and its
  screen derivatives for every lane before any lane may discard (a quad with a discarded lane has undefined
  derivatives), give sky pixels a finite position, discard them, and fall back to an up normal across depth
  discontinuities or where the derivatives vanish.
- Result at the user's configuration (Forward+, Medium, A320 at VOCI stand 2, day, still camera, phase-swept burst):
  1.65 % -> 0.19-0.40 % of pixels changing between frames (Mobile 0.18 %). The tree scene near the origin went from
  1.16 % to 0.48 % (the rest is foliage, phase 5).

Also done on the way: the VOCI/VOGA Kerala roofs were built from pieces that overlapped by 2 x overhang with coplanar
slopes, ridges and soffits (13 pairs, 1 966 m2 at VOCI); `tools/terminal_styles.py` `PIECE_STEP` lifts alternate
pieces 1.5 cm (4 pairs, 137 m2 remain, from different roof calls). Not the flicker cause, but z-fighting material.
Regenerate with `python tools/16_terminal_models.py VOCI VOGA`.

Open: night on Forward+ with the pools lit (`level` > 0). Phase-swept bursts (`--sweep`) show 3.3-3.8 % of 3D pixels
changing, as per-pixel speckle with a constant mean on the pool-lit ground, Mobile 0.04 %. Excluded by measurement:
FSR2 / bilinear / TAA, every post effect, debanding, FXAA, the depth read (an analytic ground-plane pool has it too),
the instance set (a per-instance flat colour is steady), the vertex-stage factors (`fake`, `trans`, camera distance
are steady), uniforms (frozen with `--free=RunwayLights/ApronLamps`). It scales with how dim the added light is:
bright variants are steady, dim ones speckle. Next: extend `debug_still_mesh.gd` with one additive `cull_front`
volume adding a dim constant over a dark plane; if Forward+ speckles there too, file it upstream with that scene.
Mitigation meanwhile: Low / Medium on Mobile (phase 1).

Measurement lesson (recorded so it is not repeated): an uncapped burst samples at a nearly constant interval and a
periodic source aliases; several "findings" at night (an 11-frame period, trees, buildings, grain x sharpen) were
sampling artefacts that vanished with `--sweep`. Use `--sweep` for anything that may be periodic.

## Phase 3 - Instrument noise (S) - done 2026-11-10

1. ND track mark (`ui/displays/nd.gd` `track_shown`): below `TRACK_HOLD_KT` (2 kt) the mark sits on the heading.
   Test: `tests/test_displays.gd`.
2. HUD IAS (`Units.shown_kt`): 0 below 10 kt, rounded above. The PFD tape was not touched (its tape starts higher).
   Test: `tests/test_displays.gd`.

Acceptance: a parked burst shows no changing pixels inside the ND and the speed tape.

## Phase 4 - Vehicle beacons (S) - done 2026-11-10

Correction to finding F: the beacons do not light the apron (no real light); what pulsed was the lens flash itself
(`vehicle_surface.gdshaderinc` beacon_level), a cos^14 lobe at 80 rpm that lasted one or two frames at 25 fps. Now
~52 rpm and cos^5: the flash rises and falls over about eight frames with no step above 40 % of the peak. CPU twin
`VehicleLamps.beacon_flash`; test `tests/test_vehicles.gd`. The vehicle *outline* flicker in the heat maps is finding A.

## Phase 5 - Trees (M)

After the phase 2 fix the tree scene is at 0.48 % (from 1.16 %); the rest is foliage edges under FSR2. If it matters:
`world/tree.gdshader` / `tree_mesh.gdshader` alpha scissor -> alpha hash with FXAA, or alpha-to-coverage when MSAA
is on; measure with the Phase 0 metric on the tree scene (free camera at the origin, DOF off).

## Phase 6 - Frame rate (M, optional)

`debug_perf` at the stand: 37 ms/frame average, p95 73 ms, physics 12.6 ms/frame. The FDM at 120 Hz on a parked
aircraft is a third of the frame. Not a flicker cause, but low frame rate makes every change above look like a
blink. Separate plan if taken up.

## Order

Done: 0, 1, 2 (day), 3, 4. Open: 2 (night pools on Forward+, upstream repro), 5, 6.
