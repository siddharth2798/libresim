"""Derive the livery region masks of the C172 from its three exterior atlases (colour thresholds + island rectangles).

Input: the FlightGear c172p atlases (GPL-2.0-or-later, third_party/c172p/SOURCE.md). They are
never changed; the game recolours a copy in memory (aircraft/common/livery_paint.gd).
Output: game/aircraft/c172/livery/<atlas>_<region>.png (8-bit grey, atlas size, 0 = untouched,
255 = fully recoloured, soft edges), and the "livery" section of game/aircraft/c172/aircraft.json
(atlases, regions: key, label, default colour, masks [{atlas, mask, luma}]).
`luma` = mean Rec.709 luminance (sRGB, 0..1) of the atlas under pixels with mask >= 242 (the soft
edge would drag it down): the shading reference of Livery.recolor. `default` = median colour of
the same pixels. Regions:
  body    white paint (fuselage, wing, fin, tailplane): light pixels that are not blue or grey stripe
  accent  blue paint (nose and cowl, side sweeps, deck stripe, wing-tip caps, fin/tailplane stripes)
  stripe  grey pin stripe (fuselage sides, fin)
  struts  white wing struts and main gear legs (fuselage atlas only, optional). Found with the glb
          UV islands: two diagonal strips (distance to a line) and the gear-leg capsule (flood fill,
          cut from the neighbouring fairing). The nose gear leg is bare steel: left as it is.
Kept out of every mask: tyres, propeller, spinner, hub, lamps, glass, antennas, the registration
boxes of aircraft.json "registration" (livery.gd paints before RegistrationPaint re-stamps the
number) and the baked "Cessna" logo and "SKYHAWK" on the fin.
Needs Pillow + numpy. Usage: tools/.venv/bin/python -I tools/25_livery_masks.py [--preview <dir>]
(--preview writes overlay PNGs outside the repo)
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
AC = ROOT / "game/aircraft/c172"
ATLASES = {"fuselage": "models/exterior_fuselage.png", "wing": "models/exterior_wing.png", "tail": "models/exterior_tail.png"}
LABELS = {"body": "Body paint", "accent": "Main accent", "stripe": "Pin stripe", "struts": "Struts and gear legs"}
FEATHER = 1.6  # px sigma of the soft edge on rectangle borders (colour edges are soft already)

# (x0, y0, x1, y1) in atlas pixels (CUT, LOGO: x, y, w, h). KEEP = atlas islands the paint is on
# (their white background is recoloured too, so bilinear taps at the silhouette meet no untouched
# texel); CUT = non-paint parts inside those boxes. Found by eye (see the overlay previews).
KEEP = {
    "fuselage": [(0, 191, 482, 498), (482, 72, 2030, 470), (772, 700, 1880, 958), (0, 665, 468, 1010),
                 (0, 1338, 922, 1570), (922, 1160, 1900, 1570), (80, 1670, 1180, 2020)],  # last: the wheel fairings (white, AO shaded)
    "wing": [(0, 0, 2048, 2048)],
    "tail": [(0, 0, 2048, 2048)],
}
CUT = {
    "fuselage": [(860, 72, 440, 50), (1380, 950, 350, 335), (880, 1100, 130, 150)],  # antenna tube, propeller hub, red disc
    "wing": [(1655, 30, 365, 880), (1780, 1775, 268, 273)],  # scratched metal tiles, landing-lamp disc
    "tail": [],
}
# the baked "Cessna" logo and "SKYHAWK" on both fin sides: dark navy glyphs are kept (out of
# accent and stripe), the white box around them is body paint
LOGO = {"tail": [(1125, 86, 60, 56), (955, 280, 125, 30), (208, 918, 60, 58), (314, 1114, 125, 32)]}
# where the grey pin stripe lives (the neutral grey window below is only applied inside these boxes)
STRIPE_BOX = {"fuselage": [(620, 285, 1100, 395), (790, 1395, 1270, 1500)], "wing": [], "tail": [(768, 294, 1240, 400), (156, 1118, 650, 1232)]}


# struts, fuselage atlas (from the UV layout of exterior.glb): axis of each wing strut strip
# (top, bottom) and its half width incl. margin; the capsule island of the main gear legs (seed
# inside it, its region, the fairing next to it starts at x = box end). Nose gear leg: not paint.
STRUT_AXES = {"fuselage": [((1235, 1690), (1140, 2025)), ((1463, 1690), (1558, 2017))]}
STRUT_HALF = 28
CAPSULE = {"fuselage": {"seed": (330, 1850), "box": (40, 1660, 470, 2040), "grow": 10}}


def xyxy(r):
    return r[0], r[1], r[0] + r[2], r[1] + r[3]


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def box_field(shape, boxes, feather=FEATHER):
    f = np.zeros(shape, np.float32)
    for r in boxes:
        x0, y0, x1, y1 = r
        f[y0:y1, x0:x1] = 1.0
    img = Image.fromarray((f * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(feather))
    return np.asarray(img, np.float32) / 255.0


def strut_field(atlas_id, luma):
    """Weight 0..1 of the struts region on this atlas (zeros when it has none)."""
    f = np.zeros(luma.shape, np.float32)
    h, w = luma.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    for (ax, ay), (bx, by) in STRUT_AXES.get(atlas_id, []):
        dx, dy = bx - ax, by - ay
        t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
        d = np.hypot(xx - (ax + t * dx), yy - (ay + t * dy))
        f = np.maximum(f, (d < STRUT_HALF).astype(np.float32))
    c = CAPSULE.get(atlas_id)
    if c:
        x0, y0, x1, y1 = c["box"]
        solid = Image.new("L", (w, h), 0)
        solid.paste(Image.fromarray(((luma[y0:y1, x0:x1] < 0.985) * 255).astype(np.uint8)), (x0, y0))
        ImageDraw.floodfill(solid, (x0 + 1, y0 + 1), 64)  # the background of the box; what it does not reach is island (shading, rim, the
        # white highlight in the middle of the capsule)
        shapes = Image.fromarray(((np.asarray(solid) != 64) * 255).astype(np.uint8))
        shapes.paste(0, (0, 0, w, y0))
        shapes.paste(0, (0, y1, w, h))
        shapes.paste(0, (0, y0, x0, y1))
        shapes.paste(0, (x1, y0, w, y1))  # outside the box: not part of it
        if shapes.getpixel(c["seed"]) != 255:
            raise SystemExit("capsule seed is on the background")
        ImageDraw.floodfill(shapes, c["seed"], 128)  # the capsule alone (the other capsule is a separate island)
        island = Image.fromarray(((np.asarray(shapes) == 128) * 255).astype(np.uint8))
        grown = island.filter(ImageFilter.MaxFilter(2 * c["grow"] + 1))
        f = np.maximum(f, np.asarray(grown, np.float32) / 255.0)
    img = Image.fromarray((f * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(FEATHER))
    return (np.asarray(img, np.float32) / 255.0) * smooth(luma, 0.15, 0.35)  # black rims and seams stay as they are


def registration_boxes(atlas_id):
    sec = json.loads((AC / "aircraft.json").read_text()).get("registration", {})
    out = []
    for t in sec.get("targets", []):
        if Path(t.get("texture", sec.get("texture", ""))).name == Path(ATLASES[atlas_id]).name:
            out.append(tuple(t["erase"]))
    return out


def masks_for(atlas_id):
    im = np.asarray(Image.open(AC / ATLASES[atlas_id]).convert("RGB"), np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
    keep = box_field(luma.shape, KEEP[atlas_id])
    for c in CUT[atlas_id]:
        x0, y0, x1, y1 = xyxy(c)
        keep[y0:y1, x0:x1] = 0.0
    # blue: on an edge pixel (blue t, white 1-t) b - r = t * 94, so the ramp is the blue share itself
    accent = smooth(b - r, 6.0, 66.0)
    for c in LOGO.get(atlas_id, []):
        x0, y0, x1, y1 = xyxy(c)
        accent[y0:y1, x0:x1] = 0.0
    stripe = np.zeros_like(luma)
    sb = STRIPE_BOX[atlas_id]
    if sb:
        neutral = 1.0 - smooth(np.abs(b - r), 6.0, 24.0)
        grey = smooth(luma, 0.30, 0.38) * (1.0 - smooth(luma, 0.60, 0.655)) * neutral
        stripe = grey * box_field(luma.shape, sb) * (1.0 - accent)
        for c in LOGO.get(atlas_id, []):
            x0, y0, x1, y1 = xyxy(c)
            stripe[y0:y1, x0:x1] = 0.0
    lit = smooth(luma, 0.14 if atlas_id == "tail" else 0.30, 0.45 if atlas_id == "tail" else 0.60)  # shadows, seams stay
    struts = strut_field(atlas_id, luma)
    body = np.clip(1.0 - accent - stripe, 0.0, 1.0) * lit
    out = {"body": body, "accent": accent, "stripe": stripe}
    for k in out:
        out[k] = out[k] * keep * (1.0 - struts)  # a strut is never half body paint
    out["struts"] = struts
    for k in out:
        for x, y, w, h in registration_boxes(atlas_id):
            out[k][y:y + h, x:x + w] = 0.0  # exactly 0: the registration boxes stay out of every mask
    return im, luma, out


def main():
    preview = Path(sys.argv[sys.argv.index("--preview") + 1]) if "--preview" in sys.argv else None
    (AC / "livery").mkdir(exist_ok=True)
    regions = {k: {"key": k, "label": LABELS[k], "masks": [], "pix": []} for k in LABELS}
    for aid in ATLASES:
        im, luma, ms = masks_for(aid)
        for key, m in ms.items():
            m8 = np.round(np.clip(m, 0, 1) * 255).astype(np.uint8)
            core = m8 >= 242
            if core.sum() < 200:
                continue  # the region has no paint on this atlas
            name = f"livery/{aid}_{key}.png"
            Image.fromarray(m8).save(AC / name, optimize=True)
            regions[key]["masks"].append({"atlas": aid, "mask": name, "luma": round(float(luma[core].mean()), 3)})
            regions[key]["pix"].append(im[core].reshape(-1, 3))
            print(f"{name:34s} coverage {100.0 * (m8 >= 128).mean():5.2f} %  luma {luma[core].mean():.3f}  {(AC / name).stat().st_size / 1024:5.0f} KB")
        if preview:
            preview.mkdir(parents=True, exist_ok=True)
            col = {"body": (255, 0, 0), "accent": (0, 255, 0), "stripe": (255, 0, 255), "struts": (0, 200, 255)}
            ov = im * 0.35
            for key, m in ms.items():
                ov = ov * (1 - m[..., None]) + np.array(col[key], np.float32) * m[..., None] * 0.9
            Image.fromarray(np.clip(ov, 0, 255).astype(np.uint8)).save(preview / f"mask_{aid}.png")
    out = []
    for key, rg in regions.items():
        px = np.concatenate(rg.pop("pix"))
        rg["default"] = [round(float(v) / 255.0, 3) for v in np.median(px, axis=0)]
        print(f"{key:7s} default {rg['default']}")
        out.append({"key": rg["key"], "label": rg["label"], "default": rg["default"], "masks": rg["masks"]})
    section = {"atlases": [{"id": a, "texture": t} for a, t in ATLASES.items()], "regions": out}
    write_section(section)


def fmt(section):
    """One region per line group, like the rest of aircraft.json (a tab-indented, hand-readable file)."""
    j = json.dumps
    a = ",\n\t\t\t".join(j(x) for x in section["atlases"])
    rs = ",\n\t\t\t".join(j(x) for x in section["regions"])
    return '"livery": {\n\t\t"atlases": [\n\t\t\t' + a + '],\n\t\t"regions": [\n\t\t\t' + rs + "]\n\t}"


def write_section(section):
    """Replace (or insert before "start") the "livery" key of aircraft.json by text, so nothing else is reformatted."""
    p = AC / "aircraft.json"
    s = p.read_text()
    block = fmt(section)
    i = s.find('\t"livery":')
    if i >= 0:
        j = s.index("{", i)
        depth = 0
        for k in range(j, len(s)):
            depth += (s[k] == "{") - (s[k] == "}")
            if depth == 0:
                break
        s = s[:i] + "\t" + block + s[k + 1:]
    else:
        i = s.index('\t"start":')
        s = s[:i] + "\t" + block + ",\n" + s[i:]
    json.loads(s)  # still valid
    p.write_text(s)
    print("wrote the livery section of", p.relative_to(ROOT))


if __name__ == "__main__":
    main()
