# Livery builder: plan

Goal: the pilot picks colours for the main areas of the aircraft and adds a few small images (a logo on the fin, a badge on the fuselage), sees a live 3D preview on the start screen, saves it as a named preset, and flies with it. Everything is local; nothing the pilot adds enters the repository.

Status: L0 to L5 done. Colours, the Livery step, sticker slots, presets, the A320 masks and the docs are in. The wing-underside registration (§10) is done. The turntable preview is windowed only; headless shows a note.

## 1. What the models give us

- **No paint layer exists.** All paint is baked into atlases with ambient occlusion and dirt in the albedo. Materials have no mask, emissive or ORM map; the glb has no UV2 or vertex colours. No `Decal` or `albedo_color` is used on the aircraft.
- **C172** (`game/aircraft/c172/models/`): three 2048 px atlases (`exterior_fuselage`, `_wing`, `_tail`). White base with blue and grey stripes; blue is saturated, so a colour threshold (b - r > 40) gives a clean mask. The fuselage atlas is shared with tyres, propeller and struts, so a plain tint is wrong. The fin carries a baked "Cessna" logo and "SKYHAWK".
- **A320** (`game/aircraft/a320/models/`): one 4096 px atlas (`a320_fuselage`) holds fuselage, wings, fin, tailplane and all control surfaces; a separate 2048 px engine atlas has the nacelles as tiled copies. Wing tops and bottoms overlap in UV space, so they cannot be painted apart. `tools/24_a320_textures.py` holds the boolean masks used for the white livery (`paint`, `fin`, `black`, `CHEAT`).
- **Registration painter** (`aircraft/common/registration_paint.gd`): copies the atlas, erases the old number, stamps the new one, caches an `ImageTexture` per `"<aircraft>|<TEXT>"` and sets surface override materials on surfaces whose `albedo_texture.resource_path` equals the atlas path. After one override the active texture has no path, so a second painter pass finds nothing. So livery and registration are composited in one pass into the same texture.
- **Start screen:** Free flight steps are `STEPS` in `ui/menu/start_flow.gd` (Aircraft is step 1). Setup lives in `Session.setup` and is saved to `last_flight.json`. The menu has no 3D aircraft preview yet (`AircraftModel.build` needs an `FdmNode`; `tests/render_aircraft_previews.gd` shows how to load the exterior glb alone).

## 2. Approach

**Bake, do not shade.** Colours and stickers are composited once at flight start (and in the preview) into a copy of each atlas, where `RegistrationPaint` already works. Rejected: a recolour shader on the live material (loses the normal map and glass `next_pass`), per-material `albedo_color` (tints stripes, tyres and the A320 fin), `Decal` stickers (project through the airframe, do not follow animated parts).

**Recolour keeps the shading.** For a region with colour C: `out = lerp(orig, C * (luma(orig) / luma_base), mask)`, where `luma_base` is the region's mean luminance under the mask (stored with the mask). Baked AO, panel lines and dirt survive. Stripes, tyres, propeller, glass and the registration box are outside every mask.

**Offline masks.** `tools/25_livery_masks.py` writes one 8-bit grey PNG per region per atlas (`game/aircraft/<id>/livery/*.png`) from colour thresholds (C172) and from the arrays in `tools/24_a320_textures.py` (A320), with soft edges. Hand-authored masks from the Blender UV layout would be cleaner at the edges but cost far more; review each mask visually.

**One compositor for preview and flight.** A one-shot GPU pass (SubViewport + shader, as `render_glyphs` draws text) takes the atlas, region masks, colours and sticker images and returns one `Image`. Registration text is stamped on the result, mipmaps are generated, and the `ImageTexture` is cached under `aircraft|TEXT|livery-hash`. `Image.blend_rect_mask` places stickers.

## 3. Data (per aircraft, in `aircraft.json`, no code per aircraft)

```json
"livery": {
  "atlases": [{"id": "fuselage", "texture": "models/exterior_fuselage.png"}, ...],
  "regions": [{"key": "body", "label": "Fuselage", "atlas": "fuselage",
               "mask": "livery/fuselage_body.png", "default": [0.93, 0.93, 0.94], "luma": 0.91}, ...],
  "stickers": [{"key": "fin", "label": "Tail logo", "atlas": "fuselage", "box": [x, y, w, h],
                "mirror_box": [x, y, w, h], "rotate": 0}, ...]
}
```
(As built, a region has `masks: [{atlas, mask, luma}]` instead of one `atlas` / `mask` / `luma`; see §6.)

- Regions: C172 fuselage, stripe 1, stripe 2, wings and tail; A320 fuselage, fin and rudder, engines, cheat line. A320 wings are not offered.
- Stickers are fixed slots (2 per aircraft to start: fuselage side pair, fin), each with scale, offset and mirror sliders. Free placement is a later option.
- `Session.setup.livery` is `{<aircraft id>: {colors: {region: "#rrggbb"}, stickers: {slot: {image, scale, dx, dy}}}}`, small enough for `last_flight.json`. A missing entry is the factory livery.
- On disk (never in `res://`): `user://liveries/<aircraft>/<preset>.json` and `user://liveries/images/<sha1>.png`.

## 4. Code layout

| File | Job |
|---|---|
| `aircraft/common/livery.gd` | pure logic: parse the section, defaults, cache hash, sticker box fitting, validation |
| `aircraft/common/livery.gdshader` + `livery_paint.gd` | the compositing pass, registration stamping inside it |
| `aircraft/common/livery_store.gd` | presets and images in `user://liveries/`, import and validation of pictures |
| `ui/menu/livery_page.gd` (+ `livery_regions.gd`) | the start-screen step |
| `ui/menu/livery_preview.gd` | SubViewport with the exterior glb, drag to turn, debounced live update |
| `tools/25_livery_masks.py` | masks per aircraft, written next to the textures |

`RegistrationPaint.texture/apply` runs inside the compositor's pipeline (base atlas, then livery, then registration, over every atlas of the aircraft). Its public behaviour and tests stay.

## 5. UI (L2, L3)

A **Livery (optional)** step right after Aircraft (the preview needs the aircraft; Next skips it like Failures and Recording). Left: the turntable preview. Right: one row per region (name, about 12 preset swatches, a `ColorPickerButton` for any colour), one block per sticker slot (Load image, scale, offset, mirror, Remove), then Save preset / Load preset / Reset to factory. The Aircraft page picture and chips can show the chosen livery later (same compositor).

Picture import: PNG, JPG or WebP from the native file dialog, at most 4 MB, decoded with `Image.load_from_file`, scaled to 512 px on the long side, re-encoded as PNG (drops metadata), named by its hash. Anything else is refused with a one-line message.

## 6. Phases

| Phase | Content | Done when |
|---|---|---|
| L0 | `livery.gd` logic, masks tool for the C172, compositor, colours only | a coloured C172 atlas renders in a probe scene; identity livery equals the original (±1). **Done** |
| L1 | flight integration (one pass with registration), cache key, `Session.setup.livery`, `--livery` for probes | the C172 flies in a chosen colour with the right tail number, parked and in flight. **Done** |
| L2 | Livery step: preview, colours, presets, Reset | menu tests plus a screenshot; preset round trip |
| L3 | stickers and picture import | a picture lands in its slot box, mirrored on the right side |
| L4 | A320: masks from `tools/24`, engine atlas, fin and cheat line | both aircraft pass the same tests |
| L5 | docs (`USAGE.md`, `SOURCE.md` change log for derived masks), README images, backup scripts include `liveries/`, e2e | full suite and e2e green |

L0 to L2 give the colour builder; L3 and L4 can be reordered.

### As built (L0, L1)
Details and how to run: `docs/USAGE.md` "Aircraft data: livery".
- `tools/25_livery_masks.py`: C172 masks by colour thresholds inside island rectangles, 9 PNGs in `game/aircraft/c172/livery/`, and the `livery` section of `aircraft.json`.
- `aircraft/common/livery.gd`: parse, colours, identity, cache key, the recolour rule. `livery.gdshader` + `livery_paint.gd`: one GPU pass per atlas, up to 4 regions.
- A region has `masks: [{atlas, mask, luma}]`, so one colour key spans fuselage, wing and tail; `luma` is per atlas (the tail atlas is shaded darker).
- C172 regions: `body`, `accent`, `stripe`, `struts` (optional: wing struts and main gear legs, found from the glb UV islands). The cowl and side sweeps are one blue paint. Wheel fairings are body paint. Propeller, spinner, tyres and the nose gear leg (bare steel, a metal tile shared with tie-down rings and cable hinges) are not recoloured.
- Where regions meet, weights are added and each region keeps the luminance left after the others' share (`recolor_multi`), which avoids a dark fringe at half-blue edge pixels.
- The identity livery returns `null` (use the original). Registration boxes and fin logo glyphs are out of the masks. Order is livery, registration, mipmaps; `compose` returns no mipmaps.
- `Session.setup.livery` (`{id: {colors: {key: "#hex"}}}`, saved in `last_flight.json`, repaired by `Livery.repair_setup`; `--livery=` and `c172:key=#hex` through `Livery.parse_cli`).
- `aircraft/common/paint_pipeline.gd` (`PaintPipeline`): one pass per atlas, livery -> registration -> mipmaps -> cached texture -> surface override. Cache key `aircraft|TEXT|atlas|livery key` of the regions on that atlas (a call sign never repaints the tail atlas); the cache keeps at most 9 textures. The exterior is hidden while the first paint runs (12 s watchdog); a headless run does not paint; no-pixel results fall back one step at a time. `RegistrationPaint` got `stamp_steps`, `glyph_set`, `is_baked`. `AircraftModel._build_glb` calls the pipeline. It applies to the player's aircraft only.
- A region at factory colour still goes through the shader when another region of the same atlas changed (skipping it would give stripe edges a halo), so it can be about 1 % darker. An atlas with nothing changed is skipped.
- `aircraft.json` `registration.baked` (optional): the number the atlas carries is never repainted.
- Test seams `PaintPipeline.test_compose / test_glyphs` run the pipeline headless without a GPU.
- Tests: `test_livery.gd`, `test_livery_struts.gd`, `test_paint_pipeline.gd`, `test_livery_session.gd`, `test_registration.gd`. Probes: `tests/debug_livery.tscn` (GPU result equals the CPU rule within 0.5 level), `tests/debug_livery_flight.tscn` (real flight scene, parked and `--air`). The probe window must be in front on macOS.

### Open
- Not checked: whether F11 quick-saves and replays carry `Session.setup.livery`.
- The baked grey tip of the pin stripe near the door glows slightly with dark colours.
- The nose leg stays silver. The A320 tailplane stays the factory white, with the wings.

## 7. Tests (planned)

Pure logic in headless suites: defaults and validation; the cache hash changes with any colour or image; sticker box fitting and mirroring; preset save/load round trip; import limits (size, type, downscale); `Session.setup` save and repair of a malformed livery entry; step order (Livery follows Aircraft, skippable). The GPU pass cannot run headless, so a windowed probe checks: identity livery equals the original, a region colour changes only inside its mask, stickers land inside their box, the registration box is untouched. Masks get a size and coverage check (same size as the atlas, sane coverage).

## 8. Risks and limits

- **Memory:** a recoloured A320 atlas is 64 to 85 MB with mipmaps; the C172 is 3 × about 21 MB. These replace the originals in the materials. Acceptable on the target machine, noted in USAGE.
- **Mask quality** on shaded or stained areas (C172 white-to-grey belly, A320 wing root): review each mask against screenshots; soft edges and a luminance floor avoid halos.
- **Baked marks** (C172 "Cessna" logo and "SKYHAWK" on the fin) stay as they are in the first version. An optional "cover" region can paint over them later.
- **Licence and trademarks:** masks and recoloured copies derive from GPL-2.0 art, so they get a dated entry in the `SOURCE.md` change logs. The runtime recolour of an in-memory copy changes no repo file. Shipped sample presets are plain colour schemes only, never airline or manufacturer marks. Pilot pictures stay on their machine.
- **Out of scope for now:** other aircraft in the scene (parked or AI) wearing a livery, sharing presets as files, free sticker placement, per-surface weathering.

## 9. Decisions (owner)

1. One livery per aircraft type (`Session.setup.livery` is keyed by aircraft id).
2. Fixed sticker slots (2 per aircraft to start), each with scale, offset and mirror; no free placement.
3. Presets stay on the machine (`user://liveries/`); no export or import file.
4. A320 wings stay unpainted (top and bottom share UV space).
5. The registration on the wing is replaced when the call sign changes (§10).

## 10. Registration on the wing (done, independent of the livery)

The C172 wing atlas has the baked registration "4X-CHV" on both wing undersides (vertical strips, dark blue, reading down the strip). `RegistrationPaint` replaces it from data (`game/aircraft/c172/aircraft.json` "registration"), like the fuselage sides, whenever the call sign changes at flight start.

- A target can name its own atlas (`texture`). The wing atlas is painted next to the fuselage atlas, cached per (aircraft, text, atlas), and applied to every surface that uses it (12 wing surfaces on the C172).
- `rotate` takes 90 and 270 as well as 180. `erase_axis: "x"` wipes a vertical number between the clean columns beside it (the wing gradient runs along the strip). Each target has its own italic flag (fuselage italic, wing upright).
- The erase rectangles start on the first clean column (the small circle marker next to the lower strip stays out of the interpolation). Shorter or longer numbers are scaled to the strip and centred.
- Tests: plan fields, the x-axis wipe, turned glyphs, "every target atlas is on the exterior model". `tests/debug_registration.gd` (windowed) saves the repainted regions and counts the overridden surfaces.

For the livery compositor: registration text is part of the same pass for every atlas of the aircraft, wing atlas included. The "cover" region idea stays limited to the manufacturer logo and "SKYHAWK" on the fin.
