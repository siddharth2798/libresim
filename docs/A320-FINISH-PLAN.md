# A320: body and flight-deck finish: plan

Goal: make the A320 look like a finished airliner up close and from the chase view. Keyed FCU, overhead and pedestal controls already move with the property tree (see A320-STATUS). Mouse picking and the remaining unkeyed overhead buttons stay out of this plan, as do FDM changes. Shading, the small external parts, and the flight-deck seats are in.

Everything stays generic (shared code in `game/aircraft/common/`, per-aircraft data in `aircraft.json`), so the C172 and future aircraft gain wherever the feature applies.

## Today
- `exterior.glb`: 75.7k triangles (75,662), 12 materials, a second UV and a 2048 px occlusion map. Panel-line normals sit on the fuselage and engine atlases. Roughness, clearcoat and the night cabin glow are applied at runtime. Probes, antennas, wicks, the APU exhaust, a drain mast, a metal inlet lip, gear-door hinges, spinner swirls and fan-blur discs are in the glb.
- `interior.glb`: 95.7k triangles (95,715), with the same kind of UV2 occlusion map. Captain, first-officer and jump seats, and a rear door, are in. Legend textures glow at night.
- The jetway support already stands on the ground, and the fly-by camera already scales with the aircraft. No cabin beyond the door. The upstream model is not on this machine; further Blender work starts from these glbs.

## Exterior (biggest gain and least risk first)
1. **Material split and PBR values.** Done as numbers on the existing materials (`aircraft/common/material_finish.gd`), not a split atlas: fuselage paint roughness 0.48 with a soft clearcoat (0.22, roughness 0.4) so a low sun does not turn it into chrome, nacelle paint roughness 0.36 / metal 0.02 with a soft clearcoat (0.16, roughness 0.45), gear 0.55, tyres 0.9. The inlet lip is its own surface (`a320_inlet`, metallic 1, roughness 0.14). `tools/blender/a320_nacelle.py` measured it from the cowling; `tools/blender/a320_inlet_refine.py` replaces that tube in place with 48 segments by 12, adding 1,664 triangles.
2. **Baked ambient occlusion.** Done. Each mesh gets its own UV2 (`tools/blender/a320_bake.py`); a ray cast paints `exterior_ao.png` (`tools/blender/a320_ao_rays.py`, 2048 px, 12 rays, 2 m). Wing roots, the belly, gear bays, pylons and flap tracks darken. A fully blocked sample is kept at 0.72, unpainted texels stay open, and a wide blur turns the tint into one smooth shade along the skin. `MaterialFinish` binds it (light affect 0.15). Glass, screens and tyres are skipped.
3. **Normal-map details.** Done. `tools/a320_panel_normal.py` turns the fuselage and engine colour atlases into OpenGL tangent normals (`exterior_panels.png` 4096, `exterior_engine_panels.png` 2048): panel lines, door outlines, rivet rows, window frames, access panels. Windows, the blue fin and the registration stay flat. Strength 0.65 on the fuselage, 0.55 on the engine cowl. The fan blades are stamped separately (`a320_fan`, roughness 0.4, metal 0.72) so they do not take the cowl's paint or panel normal.
4. **Small parts.** Done in `tools/blender/a320_details.py` (was 71.9k, then 72.6k): three pitots, two AoA vanes, a TAT probe, upper and lower VHF blades, two GPS bumps, 15 static wicks, the right-side APU exhaust and a belly drain mast. `a320_nacelle.py` adds the inlet lips, three hinge barrels on each gear door, a two-arm spinner swirl and a static fan-blur disc; `a320_inlet_refine.py` rounds those lips (75.7k triangles). The blur disc fades in with N1 (`aircraft/common/fan_blur.gd`, clear at 25 percent, full at 58). Flap, aileron, elevator and rudder wicks are parented to those meshes (`a320_wick_parent.py`); the elevator and upper-rudder rods are pulled onto the trailing edge so they move with the surface. The sharklet wicks stay on the wing.
5. **Cabin windows.** Done as a warm emission on the exterior `a320_glass` at night (`MaterialFinish.cabin_glow`, off in daylight, dimmer on the ground with the engines stopped). No fake-room interior mapping.
6. **Weathering.** Done as a transparent next pass (`weathering.gdshader`): a leading-edge dirt line and soot along the two engine exhausts. No APU stain and no gear-bay grime.
7. **Jetway `Support` pole.** Already done (`world/jetway_legs.gd`: the bogie stays on the ground and the columns meet the tunnel).
8. **Fly-by camera.** Already scaled by aircraft size (`ui/flyby_placement.gd`).

## Flight deck
1. **Baked AO and shading.** Roughness is in: leather 0.65, glareshield 0.7. The flight deck has the same UV2 bake (`interior_ao.png`, 2048 px, rays 0.4 m so the panels keep local contact shadow). Glass and screens are skipped.
2. **Seats and back wall.** Done in `tools/blender/a320_seats.py` (95.7k triangles, was 94.6k): captain and first-officer seats, a jump seat, and a rear door with a small window. The dropped upstream seats stay dropped. Every `pivot_*` is unchanged.
3. **Night panel lighting.** Done: `a320_fd_buttons`, `a320_fcu` and `a320_radio` use their albedo as a dim emission when the bus is powered and the sun is down. The C172 glareshield flood stays off on this deck so it does not wash the displays. No separate dome light.
4. **Windscreen.** `a320_glass` roughness 0.08 and metallic 0.05, rain drops unchanged. No extra reflection pass.

Out of scope: mouse picking and the unkeyed overhead buttons, cabin interior beyond the window effect, FDM changes.

## Checks
- Before/after renders: a320_gate, a320_chase, a320_final, a320_cockpit, plus close-ups (nose, wing root, engine, main gear, tail) by day and night, Ultra and Medium.
- Record the triangle and texture budget (now 75.7k exterior / 95.7k flight deck, 4096 px atlas, 2048 px occlusion).
- Headless tests and the A320 suite stay green. Log any new texture in the `third_party/a320-family/SOURCE.md` change log (derived files stay GPL-2.0).

The render pass was run on the current model (there is no saved "before" frame): `a320_gate`, `a320_chase`, `a320_final` and `a320_cockpit` at Ultra and Medium, plus nose, wing root, engine, main gear and tail by day and night at both presets. Output: `/tmp/libresim-finish/`.
