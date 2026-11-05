# A320: body and flight-deck finish: plan

Goal: make the A320 look like a finished airliner up close and from the chase view. No cockpit-button work (paused by the owner) and no FDM changes. Not started.

Everything stays generic (shared code in `game/aircraft/common/`, per-aircraft data in `aircraft.json`), so the C172 and future aircraft gain wherever the feature applies.

## Today
- `exterior.glb`: 9 materials (fuselage atlas 4096 px, engine, gear, wheel, glass, 3 lens colours, plain grey). Colour textures only: no normal, roughness/metal or AO maps, no UV2, no vertex colours. Paint, metal and rubber shade the same, so the body looks flat white.
- `interior.glb`: 16 materials, colour only, flat shading. Seats, headsets and the cabin behind the flight deck were dropped by the converter.
- Also open (see [A320-STATUS.md](A320-STATUS.md)): no cabin interior, fly-by camera too close for an airliner, upstream's `Support` pole 3 m above the jetway tunnel.
- The upstream model is not on this machine (`data/raw/fg` missing); Blender 5.2 is installed. All steps below work from our own glb.

## Exterior (biggest gain and least risk first)
1. **Material split and PBR values (½ day).** Masks from the atlas (paint, bare metal, black rubber, walkway / de-icing boots) in a `tools/` Python step, like the livery masks in `tools/24_a320_textures.py`. Clear-coated paint (roughness ~0.25), polished leading edges and engine inlet lip (metallic), satin grey wing top, matte radome, rubber tyres. One ORM texture.
2. **Baked ambient occlusion (½ day, Blender script in `tools/blender/`).** Non-overlapping UV2 and an AO bake: wing roots, belly fairing, gear bays, engine pylons, flap tracks.
3. **Normal-map details (1 day).** Panel lines, door outlines, rivet rows on leading edges, window frames, access panels, procedural in the bake script.
4. **Small parts (1 day).** Pitot probes, AoA vanes, antennas, static wicks, wing-fence / sharklet trailing edge, APU exhaust, gear-door hinges, fan spinner swirl mark, fan blade blur when spinning (shared with the motion-blur work).
5. **Cabin windows (½ day).** Dark tinted glass with reflections. At night a warm cabin glow through an interior-mapping shader (fake rooms, no geometry), dimmed for take-off and landing. Generic: any aircraft with cabin windows can use it.
6. **Weathering (½ day).** Exhaust staining behind engines and APU, gear-bay grime, leading-edge dirt line; procedural in the shader, amount per aircraft.
7. **Jetway `Support` pole fix (¼ day).**
8. **Fly-by camera for big aircraft (¼ day).** Distances scaled by aircraft size instead of a fixed 250 m.

## Flight deck
1. **Baked AO and shading (½ day).** UV2 and AO bake for `interior.glb` (glareshield, pedestal sides, overhead corners); roughness per material (leather, plastic, metal).
2. **Seats and back wall (1 day).** Own simple seats (Blender script) and a back wall / door; the dropped upstream seats stay dropped.
3. **Night panel lighting (½ day).** Backlighting on the existing textures (emissive mask from the legend colours), dome and flood lights.
4. **Windscreen.** Faint panel reflections at night. Rain and wipers already exist.

Out of scope: interactive buttons, cabin interior beyond the window effect, FDM changes.

## Checks
- Before/after renders: a320_gate, a320_chase, a320_final, a320_cockpit, plus close-ups (nose, wing root, engine, main gear, tail) by day and night, Ultra and Medium.
- Record the triangle and texture budget (today 71.9k exterior / 94.6k flight deck, 4096 px atlas).
- Headless tests and the A320 suite stay green. Log any new texture in the `third_party/a320-family/SOURCE.md` change log (derived files stay GPL-2.0).

Total about 1–1.5 weeks; items 2.1, 2.2, 2.5 and 3.1 give most of the visible gain (~2 days).
