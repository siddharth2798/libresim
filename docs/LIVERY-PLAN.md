# Livery builder: plan

Goal: the pilot picks colours for the main areas of the aircraft and adds a few small images (a logo on the
fin, a badge on the fuselage), sees the result on a live 3D preview on the start screen, saves it as a named
preset, and flies with it. Everything is local; nothing the pilot adds ever enters the repository.

Status: researched, decisions made (section 9), livery phases not started. Written 2026-10-31 from three code surveys
(start-screen UI and saving, textures and UV layouts of both aircraft, the existing registration painter).
The wing-underside registration the owner asked for (section 10) is done and shipped on its own.

## 1. What the models give us (facts, not assumptions)

- **No paint layer exists.** All paint is baked into a few atlases with ambient occlusion and dirt in the
  albedo; materials have no mask, emissive or ORM map and the glb has no UV2 or vertex colours.
  No `Decal` or `albedo_color` is used on the aircraft today.
- **C172** (`game/aircraft/c172/models/`): three 2048 px atlases (`exterior_fuselage`, `_wing`, `_tail`).
  White base with blue and grey stripes; blue is saturated, so a colour threshold (b - r > 40) gives a clean
  mask. The fuselage atlas is shared with the tyres, propeller and struts, so a plain tint is wrong. The fin
  carries a baked "Cessna" logo and "SKYHAWK"; the wing undersides carried a baked `4X-CHV` (now repainted from the call sign, section 10).
- **A320** (`game/aircraft/a320/models/`): one 4096 px atlas (`a320_fuselage`) holds fuselage, wings, fin,
  tailplane and every control surface; a separate 2048 px engine atlas has the nacelles as tiled copies.
  Wing tops and bottoms overlap in UV space (they cannot be painted apart). `tools/24_a320_textures.py`
  already holds the boolean masks it used to make the white livery (`paint`, `fin`, `black`, `CHEAT`).
- **Registration painter** (`aircraft/common/registration_paint.gd`): copies the atlas, erases the old
  number, stamps the new one, caches an `ImageTexture` per `"<aircraft>|<TEXT>"` and sets surface override
  materials on surfaces whose `albedo_texture.resource_path` equals the atlas path. Gotcha: after one override
  the active texture has no path, so a second painter pass finds nothing. Livery and registration therefore
  have to be composited in one pass into the same texture.
- **Start screen**: Free flight steps are `STEPS` in `ui/menu/start_flow.gd` (Aircraft is step 1); the
  setup lives in `Session.setup` and is saved to `last_flight.json`. There is no 3D aircraft preview in the
  menu yet (`AircraftModel.build` needs an `FdmNode`; `tests/render_aircraft_previews.gd` shows how to load
  the exterior glb on its own).

## 2. Approach

**Bake, do not shade.** Colours and stickers are composited once at flight start (and in the preview) into a
copy of each atlas, exactly where `RegistrationPaint` already works. Rejected: a recolour shader on the
live material (loses the normal map and glass `next_pass`), per-material `albedo_color` (tints stripes, tyres
and the A320 fin), and `Decal` stickers (project through the airframe and do not follow animated parts).

**Recolour keeps the shading.** For a region with colour C: `out = lerp(orig, C * (luma(orig) / luma_base), mask)`
where `luma_base` is the region's mean luminance under the mask (stored with the mask), so baked AO, panel
lines and dirt survive. Stripes, tyres, propeller, glass and the registration box are outside every mask.

**Offline masks.** `tools/25_livery_masks.py` writes one 8-bit grey PNG per region per atlas next to the
atlas (`game/aircraft/<id>/livery/*.png`), from colour thresholds (C172) and from the arrays already in
`tools/24_a320_textures.py` (A320), with soft edges. Hand-authored masks from the Blender UV layout would be
cleaner at the edges but cost much more; start with thresholds and review each mask visually.

**One compositor, used by preview and flight.** A one-shot GPU pass (SubViewport + shader, the way
`render_glyphs` already draws text) takes the atlas, the region masks, the colours and the sticker images and
returns one `Image`; the registration text is stamped on the result, mipmaps are generated, and the
`ImageTexture` is cached under `aircraft|TEXT|livery-hash`. Native `Image.blend_rect_mask` places stickers.

## 3. Data (all per aircraft, in `aircraft.json`, no code per aircraft)

```json
"livery": {
  "atlases": [{"id": "fuselage", "texture": "models/exterior_fuselage.png"}, ...],
  "regions": [{"key": "body", "label": "Fuselage", "atlas": "fuselage",
               "mask": "livery/fuselage_body.png", "default": [0.93, 0.93, 0.94], "luma": 0.91}, ...],
  "stickers": [{"key": "fin", "label": "Tail logo", "atlas": "fuselage", "box": [x, y, w, h],
                "mirror_box": [x, y, w, h], "rotate": 0}, ...]
}
```

- Regions offered: C172 fuselage, stripe 1, stripe 2 (the two blues/greys), wings and tail; A320 fuselage,
  fin and rudder, engines, cheat line. A320 wings are not offered (top and bottom share UV space).
- Stickers are fixed slots (2 per aircraft to start: fuselage side pair, fin), each with scale, offset and
  mirror sliders. Free placement is a later option.
- `Session.setup.livery` is `{<aircraft id>: {colors: {region: "#rrggbb"}, stickers: {slot: {image, scale, dx, dy}}}}`,
  small enough to live in `last_flight.json`; a missing entry is the factory livery.
- On disk (never in `res://`): `user://liveries/<aircraft>/<preset>.json` and `user://liveries/images/<sha1>.png`.

## 4. Code layout (files under 300 lines, one job each)

| File | Job |
|---|---|
| `aircraft/common/livery.gd` | pure logic: parse the section, defaults, cache hash, sticker box fitting, validation |
| `aircraft/common/livery.gdshader` + `livery_paint.gd` | the compositing pass, registration stamping inside it |
| `aircraft/common/livery_store.gd` | presets and images in `user://liveries/`, import and validation of pictures |
| `ui/menu/livery_page.gd` (+ `livery_regions.gd`) | the start-screen step |
| `ui/menu/livery_preview.gd` | SubViewport with the exterior glb, drag to turn, debounced live update |
| `tools/25_livery_masks.py` | masks per aircraft, written next to the textures |

`RegistrationPaint.texture/apply` is refactored into the compositor's pipeline (base atlas, then livery,
then registration), looping over every atlas of the aircraft; its public behaviour and tests stay.

## 5. UI

A **Livery (optional)** step right after Aircraft (the preview needs the aircraft first; the step is skipped
by Next like Failures and Recording). Left: the turntable preview. Right: one row per region (name, swatch
row of about 12 preset colours, a `ColorPickerButton` for any colour), one block per sticker slot (Load image,
scale, offset, mirror, Remove), then Save preset / Load preset / Reset to factory. The Aircraft page picture
and chips can show the chosen livery later (the same compositor).

Picture import: PNG, JPG or WebP picked with the native file dialog, at most 4 MB, decoded with
`Image.load_from_file`, scaled down to 512 px on the long side, re-encoded as PNG (this drops metadata), named
by its hash. Anything else is refused with a one-line message.

## 6. Phases

| Phase | Content | Done when |
|---|---|---|
| L0 | `livery.gd` logic, masks tool for the C172, compositor, colours only | a coloured C172 atlas renders in a probe scene; identity livery equals the original (+/- 1) |
| L1 | flight integration (one pass with registration), cache key, `Session.setup.livery`, `--livery` for probes | the C172 flies in a chosen colour with the right tail number, parked and in flight |
| L2 | Livery step: preview, colours, presets, Reset | menu tests plus a screenshot; preset round trip |
| L3 | stickers and picture import | a picture lands in its slot box, mirrored on the right side |
| L4 | A320: masks from `tools/24`, engine atlas, fin and cheat line | both aircraft pass the same tests |
| L5 | docs (`USAGE.md`, `SOURCE.md` change log for derived masks), README images, backup scripts include `liveries/`, e2e | full suite and e2e green |

L0 to L2 give the colour builder; L3 and L4 can be reordered.

## 7. Tests

Pure logic in headless suites (as for registration): defaults and validation, cache hash changes with any
colour or image, sticker box fitting and mirroring, preset save/load round trip, import limits (size, type,
downscale), `Session.setup` save and repair of a malformed livery entry, step order (Livery follows Aircraft,
is skippable). Pixel results (the GPU pass) cannot run headless, so a windowed probe in the style of
`render_aircraft_previews.gd` checks: identity livery equals the original, a region colour changes only
inside its mask, stickers land inside their box, and the registration box is untouched. Masks get a size and
coverage check (same size as the atlas, coverage within a sane range).

## 8. Risks and limits

- **Memory**: a recoloured A320 atlas is 64 to 85 MB with mipmaps and C172 is 3 x about 21 MB, replacing the
  original in the materials; acceptable on the target machine, noted in USAGE.
- **Mask quality** on shaded or stained areas (C172 white-to-grey belly, A320 wing root): review each mask
  against screenshots; soft edges and a luminance floor avoid halos.
- **Baked marks** (C172 "Cessna" logo and "SKYHAWK" on the fin): left as they are in the first version;
  an optional "cover" region can paint over them later. The wing registration is already replaced (section 10).
- **Licence and trademarks**: masks and recoloured copies are derived from GPL-2.0 art, so they get a dated
  entry in the existing `SOURCE.md` change logs; the runtime recolour of a copy in memory changes no repo file.
  Shipped sample presets are plain colour schemes only, never airline or manufacturer marks. Pictures the
  pilot adds stay on their machine.
- **Out of scope for now**: other aircraft in the scene (parked or AI) wearing a livery, sharing presets as
  files, free sticker placement, per-surface weathering.

## 9. Decisions (owner, 2026-11-02)

1. One livery per aircraft type (`Session.setup.livery` is keyed by aircraft id).
2. Fixed sticker slots (2 per aircraft to start), each with scale, offset and mirror; no free placement.
3. Presets stay on the machine (`user://liveries/`); no export or import file.
4. A320 wings stay unpainted (top and bottom share UV space).
5. The registration number printed on the wing must be replaced when the call sign / tail number changes: see 10.

## 10. Registration on the wing (done, independent of the livery)

The C172 wing atlas has the baked registration "4X-CHV" on both wing undersides (vertical strips, reading down
the strip, dark blue). `RegistrationPaint` now handles it from data (`game/aircraft/c172/aircraft.json`
"registration"), the same way as the fuselage sides, whenever the call sign changes at flight start:

- a target can name its own atlas (`texture`), so the wing atlas is painted next to the fuselage atlas, each
  cached per (aircraft, text, atlas) and applied to every surface that uses it (12 wing surfaces on the C172);
- `rotate` takes 90 and 270 as well as 180, `erase_axis: "x"` wipes a vertical number between the clean columns
  beside it (the wing gradient runs along the strip), and each target now draws with its own italic flag
  (the fuselage is italic, the wing is upright);
- the erase rectangles start on the first clean column (the small circle marker next to the lower strip is
  kept out of the interpolation), and shorter or longer numbers are scaled to the strip and centred;
- tests: plan fields, the x-axis wipe, turned glyphs, "every target atlas is on the exterior model";
  `tests/debug_registration.gd` (windowed) saves the repainted regions and counts the overridden surfaces.

Consequence for the livery compositor (section 2): registration text is part of the same pass for every atlas
of the aircraft, wing atlas included, and the "cover" region idea for baked marks stays limited to the
manufacturer logo and "SKYHAWK" on the fin; the wing numbers are no longer a baked mark to hide.
