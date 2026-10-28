"""Derive the A320 model textures from the FlightGear A320-family textures (GPL-2.0-only; credits in
third_party/a320-family/SOURCE.md). Pillow + numpy only; the inputs are untrusted data, only decoded.

Changes made (change-log class "textures"):
  fuselage.png  Fuse-Main.png (4096) recoloured: the template's olive/khaki paint areas become plain white
                (luminance kept, so shading, panel lines and windows stay), the template's fixed registration
                "N680AW" (both sides) is erased, a plain slate cheat line is added, the template's black nose
                radome becomes light grey with a darker grey tip cap (RADOME_RECTS, 2026-10-29), the fin / rudder
                area (black field and tan stripes) is a plain deep blue (FIN_BLUE, 2026-10-29). Registration
                area: REG_RECTS.
  gear.png      LandingGears.png (2048) with the tyre sidewall lettering (tyre maker mark, "FlightGear") removed
                (each tyre annulus replaced by its per-radius median colour).
  engine.png    Liveries/CFM/2k/CFM56-white.png unchanged (clean white engine; generic placards only).
  fd_*.png ...  flight-deck textures reduced to <= 2048 px; the "Airbus A320 Family" legend on fd_main.png is
                painted over with the surrounding panel colour.
Usage: tools/.venv/bin/python -I tools/24_a320_textures.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data/raw/fg/a320/Models"
OUT = ROOT / "data/processed/a320/tex"  # derived (gitignored); the glb embeds them
# registration areas in fuselage.png pixels (x, y, w, h): where the template's N680AW was; the two fuselage sides
REG_RECTS = {"left": (2640, 440, 220, 80), "right": (2640, 1250, 220, 80)}
# (x0, x1, y0, y1, fin) in fuselage.png: black template areas; the belly fairing one becomes white, the fin / rudder one
# (fin = True) a plain deep blue together with the template's tan stripes inside that area (a solid blue fin and rudder, no logo)
BLACK_AREAS = [(1100, 2420, 480, 1130, False), (3100, 4096, 1740, 2640, True)]
FIN_BLUE = (24, 46, 96)
# the template's black radome in fuselage.png pixels (x0, y0, x1, y1): two side panels and the tip cap disc
RADOME_RECTS = {"panel": [(30, 430, 135, 640), (30, 1130, 135, 1345)], "tip": [(55, 640, 255, 835)]}
RADOME_GREY, TIP_GREY, TEMPLATE_BG = 214.0, 128.0, 242.0
STRIPE = (66, 82, 104)  # neutral slate cheat line
CHEAT = [(60, 4040, 548, 566), (60, 4040, 1222, 1240)]  # (x0, x1, y0, y1) of the stripes on the two side panels


def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / name, optimize=True)
    print("wrote", name, img.size)


def fuselage():
    im = np.array(Image.open(RAW / "Fuselage/res/Fuse-Main.png").convert("RGBA")).astype(np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    paint = (g - b > 18) & (r - b > 25) & (np.abs(r - g) < 40)  # olive / khaki / tan template paint
    paint |= (b - r > 30) & (b > g)  # the template's blue belly / wing-root fairing islands
    black = (r < 25) & (g < 25) & (b < 25)
    blk = np.zeros_like(black)
    fin = np.zeros_like(black)
    for x0, x1, y0, y1, is_fin in BLACK_AREAS:  # template placeholders (fin field, belly fairing) that must not stay black
        (fin if is_fin else blk)[y0:y1, x0:x1] = black[y0:y1, x0:x1]
    fin_area = np.zeros_like(black)
    for x0, x1, y0, y1, is_fin in BLACK_AREAS:
        fin_area[y0:y1, x0:x1] |= is_fin
    paint |= blk | fin
    y = 0.299 * r + 0.587 * g + 0.114 * b
    white = np.clip(244.0 - np.maximum(0.0, 168.0 - y) * 0.4, 0, 246)
    white = np.where(blk, 232.0, white)
    for c in range(3):
        im[..., c] = np.where(paint, white, im[..., c])
    fin = fin | (paint & fin_area)  # the tan stripes inside the fin area are blue too, keeping their light shading
    shade = np.where(black, 1.0, np.clip(y / 160.0, 0.75, 1.1))
    for c in range(3):
        im[..., c] = np.where(fin, np.clip(FIN_BLUE[c] * shade, 0, 255), im[..., c])
    arr = im.astype(np.uint8)
    for x0, x1, y0, y1 in CHEAT:  # cheat line, only on the template's paint area (not on the interior islands)
        m = paint[y0:y1, x0:x1]
        arr[y0:y1, x0:x1][m, :3] = STRIPE
    for x, yy, w, h in REG_RECTS.values():  # erase the template's registration
        base = np.median(arr[yy - 6:yy - 1, x:x + w].reshape(-1, 4), axis=0).astype(np.uint8)
        arr[yy:yy + h, x:x + w] = base  # flat fill: no antialiasing ghost of the old number is left
    radome(arr)
    out = Image.fromarray(arr, "RGBA")
    save(out, "fuselage.png")


def radome(arr):
    """Black template radome -> light grey panels and a mid-grey tip cap. The black-to-background edge gradient
    is kept by blending the new grey with the template background by luminance; tan paint and the red-ringed
    placard discs (not near-neutral dark pixels) are left alone."""
    for name, rects in RADOME_RECTS.items():
        grey = TIP_GREY if name == "tip" else RADOME_GREY
        for x0, y0, x1, y1 in rects:
            reg = arr[y0:y1, x0:x1, :3].astype(np.float32)
            lum = reg.mean(axis=2)
            neutral = (reg.max(axis=2) - reg.min(axis=2) < 14) & (lum < TEMPLATE_BG - 4)
            t = np.clip(lum / TEMPLATE_BG, 0.0, 1.0)[..., None]
            new = grey * (1.0 - t) + TEMPLATE_BG * t
            reg[neutral] = np.broadcast_to(new, reg.shape)[neutral]
            arr[y0:y1, x0:x1, :3] = reg.astype(np.uint8)


def gear():
    img = Image.open(RAW / "Fuselage/res/LandingGears.png").convert("RGBA")
    a = np.array(img)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    for cx, cy, rad in [(1920, 156, 110), (1920, 514, 110), (1898, 780, 132), (1898, 1312, 132)]:
        rr = np.hypot(xx - cx, yy - cy)
        ring = (rr > rad * 0.46) & (rr < rad * 0.985)
        for ri in range(int(rad * 0.46), int(rad * 0.985) + 1):
            m = (rr >= ri) & (rr < ri + 1)
            a[m] = np.median(a[m], axis=0).astype(np.uint8)
    save(Image.fromarray(a, "RGBA"), "gear.png")


def engine():
    save(Image.open(RAW / "Liveries/CFM/2k/CFM56-white.png").convert("RGB"), "engine.png")


def flightdeck():
    src = RAW / "FlightDeck/res"
    for stem in ["fd_main", "fd_other", "fd_buttons", "fd_glare", "fd_leather", "fabric2", "carpet2", "Pedestal_low",
                 "ECAM", "fcu", "fcu2", "glare_sw", "inop", "Radio"]:
        f = next(src.glob(stem + ".*"))
        im = Image.open(f)
        im = im.convert("RGBA") if "A" in im.mode or im.mode == "P" else im.convert("RGB")
        if stem == "fd_main":  # paint over the "Airbus A320 Family" legend (and the rule above it)
            a = np.array(im.convert("RGB"))
            box = (2740, 2495, 2850, 2690)
            patch = a[box[1] - 12:box[1], box[0]:box[2]].reshape(-1, 3)
            a[box[1]:box[3], box[0]:box[2]] = np.median(patch, axis=0).astype(np.uint8)
            im = Image.fromarray(a, "RGB")
        if max(im.size) > 2048:
            im = im.resize((2048, 2048 * im.size[1] // im.size[0]), Image.LANCZOS)
        save(im, stem.lower() + ".png")


if __name__ == "__main__":
    fuselage()
    gear()
    engine()
    flightdeck()
