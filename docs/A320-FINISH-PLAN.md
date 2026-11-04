# A320: body and flight-deck finishing touches: plan

Goal: make the A320 look like a finished airliner up close and from the chase view, without touching
the cockpit-button work (paused by the owner) and without changing the FDM. Written 2026-11-03; not started.
Everything stays generic (shared code in game/aircraft/common/, per-aircraft data in aircraft.json), so
the C172 and future aircraft benefit wherever the same feature applies.

## 1. What the model has today (facts)

- `exterior.glb`: 9 materials (fuselage atlas 4096 px, engine, gear, wheel, glass, 3 lens colours,
  plain grey), **colour textures only**: no normal, roughness/metal or AO maps, no UV2, no vertex
  colours. So paint, metal and rubber all shade the same and the body looks flat white.
- `interior.glb`: 16 materials, colour only, same limits; flat shading; seats, headsets, the cabin
  behind the flight deck were dropped by the converter.
- A320-STATUS.md lists more: cabin interior not modelled, fly-by camera too close for an airliner,
  upstream's `Support` pole 3 m above the jetway tunnel.
- The upstream source model is not on this machine (data/raw/fg missing); Blender 5.2 is installed.
  Everything below works from our own glb, so the upstream fetch is not needed.

## 2. Exterior (in order: biggest visible gain, least risk first)

1. **Material split + PBR values (½ day).** Masks from the atlas (paint vs. bare metal vs. black
   rubber vs. walkway / de-icing boots) in a `tools/` Python step, like the livery masks in
   tools/24_a320_textures.py: glossy clear-coated paint (roughness ~0.25), polished leading edges and
   the engine inlet lip (metallic), satin grey wing top, matte radome, rubber tyres. One ORM texture.
2. **Baked ambient occlusion (½ day, Blender script in tools/blender/).** Generate a non-overlapping
   UV2 and bake AO for the exterior: under the wing roots, belly fairing, gear bays, engine pylons,
   flap tracks. Godot reads it as the AO map; much less "floating plastic".
3. **Normal map details (1 day).** Panel lines, door outlines, rivet rows on the leading edges, window
   frames, access panels, painted from the existing atlas layout (procedural in the bake script).
4. **Small parts that read from the chase view (1 day):** pitot probes and AoA vanes, antennas, static
   wicks, wing-fence / sharklet trailing edge, APU exhaust, gear-door hinges, engine fan with spinner
   swirl mark, a slightly visible fan blade blur when spinning (shared with the motion-blur work).
5. **Cabin windows (½ day):** dark tinted glass with reflections; at night a warm cabin glow through
   the windows using an interior-mapping shader (fake rooms behind the glass, no geometry), dimmed
   during take-off and landing as airlines do. Generic: any aircraft with cabin windows can switch it on.
6. **Weathering (½ day):** light exhaust staining behind the engines and APU, gear-bay grime,
   leading-edge bug / dirt line, all procedural in the shader with a per-aircraft amount.
7. **Jetway `Support` pole (fix, ¼ day)** sticking 3 m above the tunnel.
8. **Fly-by camera for big aircraft (¼ day):** distances scaled by aircraft size instead of fixed 250 m.

## 3. Flight deck

1. **Baked AO and better shading (½ day):** UV2 + AO bake for interior.glb (glareshield, pedestal
   sides, overhead corners), roughness per material (leather, plastic panels, metal frames).
2. **Seats and the cockpit back wall (1 day):** our own simple seats (Blender script) and a back wall /
   door so the view behind the pilot isn't empty; the dropped upstream seats stay dropped.
3. **Glareshield and panel lighting at night (½ day):** integral panel backlighting on the existing
   textures (emissive mask from the legend colours), dome and flood lights.
4. **Window frames and glass:** reflections of the panel in the windscreen at night (faint), rain and
   wipers already exist.

Out of scope here: interactive buttons (paused), cabin interior beyond the window effect, FDM changes.

## 4. Checks

- Before/after renders: a320_gate, a320_chase, a320_final, a320_cockpit, plus new close-ups (nose,
  wing root, engine, main gear, tail) by day and night, Ultra and Medium.
- Triangle and texture budget recorded (today 71.9k exterior / 94.6k flight deck, 4096 px atlas).
- Headless tests and the A320 suite stay green; licence notes for any new texture in
  third_party/a320-family/SOURCE.md change log (derived files stay GPL-2.0).

About 1–1.5 weeks in total; items 2.1, 2.2, 2.5 and 3.1 give most of the visible gain (~2 days).
