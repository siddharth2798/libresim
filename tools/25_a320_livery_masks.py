"""Derive the A320 livery masks from the shipped white fuselage and engine atlases.

The atlases (tools/24_a320_textures.py, GPL-2.0-only, third_party/a320-family/SOURCE.md) are not
changed. Wings, slats, flaps, ailerons, spoilers and the tailplane stay out of every mask: their
UV islands are rasterised from exterior.glb and subtracted. The fin and rudder are the blue
pixels, the cheat line the slate pixels, the fuselage the remaining light paint on the tube.
Registration boxes stay at 0 so the number is stamped after the paint.
Needs Pillow + numpy. Usage: tools/.venv/bin/python -I tools/25_a320_livery_masks.py
"""
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
AC = ROOT / "game/aircraft/a320"
GLB = AC / "models/exterior.glb"
OUT = AC / "livery"
# Both sides of the registration, including the one aircraft.json has not wired up yet (rotate 180).
REG = [(2640, 440, 220, 80), (2640, 1250, 220, 80)]
SPAN = 2.6  # metres: the tube is inside this, the wing is outside (model X is lateral)


def glb_json_bin(path):
    data = path.read_bytes()
    off = 12
    clen, _ctype = struct.unpack_from("<II", data, off)
    js = json.loads(data[off + 8:off + 8 + clen])
    off2 = off + 8 + clen
    if off2 % 4:
        off2 += 4 - off2 % 4
    blen, _btype = struct.unpack_from("<II", data, off2)
    return js, data[off2 + 8:off2 + 8 + blen]


def accessor(js, blob, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    dt = {5123: np.uint16, 5125: np.uint32, 5126: np.float32}[a["componentType"]]
    item = ncomp * np.dtype(dt).itemsize
    stride = bv.get("byteStride", item)
    count = a["count"]
    if stride == item:
        return np.frombuffer(blob[start:start + count * item], dtype=dt).reshape(count, ncomp).copy()
    arr = np.empty((count, ncomp), dtype=dt)
    for k in range(count):
        arr[k] = np.frombuffer(blob[start + k * stride:start + k * stride + item], dtype=dt)
    return arr


def raster(h, w, uv, tris):
    mask = np.zeros((h, w), np.uint8)
    if len(tris) == 0:
        return mask
    pts = uv[tris]  # T,3,2
    xs = np.clip(pts[:, :, 0] * (w - 1), 0, w - 1)
    ys = np.clip(pts[:, :, 1] * (h - 1), 0, h - 1)
    for i in range(len(tris)):
        x0, x1, x2 = xs[i]
        y0, y1, y2 = ys[i]
        minx, maxx = int(min(x0, x1, x2)), int(max(x0, x1, x2)) + 1
        miny, maxy = int(min(y0, y1, y2)), int(max(y0, y1, y2)) + 1
        if maxx <= minx or maxy <= miny or maxx - minx > 2000:
            continue
        yy, xx = np.mgrid[miny:maxy, minx:maxx]
        d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(d) < 1e-6:
            continue
        a = ((y1 - y2) * (xx - x2) + (x2 - x1) * (yy - y2)) / d
        b = ((y2 - y0) * (xx - x2) + (x0 - x2) * (yy - y2)) / d
        inside = (a >= 0) & (b >= 0) & (a + b <= 1)
        mask[miny:maxy, minx:maxx][inside] = 255
    return mask


def islands(js, blob):
    """Fuselage-tube UVs and fin/rudder UVs, in glTF v (0 at the top of the image)."""
    fuse, fin = [], []
    wingish = ("Flap", "Slat", "Aileron", "Spoiler", "Hstab", "Elevator")
    for mesh in js["meshes"]:
        name = mesh.get("name") or ""
        for prim in mesh["primitives"]:
            if prim.get("material") != 0 or "TEXCOORD_0" not in prim["attributes"]:
                continue
            pos = accessor(js, blob, prim["attributes"]["POSITION"])
            uv = accessor(js, blob, prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
            tri = accessor(js, blob, prim["indices"]).reshape(-1, 3).astype(np.int64)
            if name == "Rudder":
                fin.append((uv, tri))
                continue
            if name.startswith(wingish) or name != "body":
                continue
            c = pos[tri].mean(1)
            tube = np.abs(c[:, 0]) <= SPAN
            fuse.append((uv, tri[tube]))
            # the fin is the blue part of the tube; the UV island is the whole tube, colour splits it
    return fuse, fin


def paint(uv_parts, h, w, flip):
    acc = np.zeros((h, w), np.uint8)
    for uv, tri in uv_parts:
        u = uv.copy()
        if flip:
            u[:, 1] = 1.0 - u[:, 1]
        acc = np.maximum(acc, raster(h, w, u, tri))
    return acc


def clear_reg(mask):
    for x, y, w, h in REG:
        mask[y:y + h, x:x + w] = 0


def luma_of(rgb, mask):
    sel = mask >= 242
    if not sel.any():
        return 0.0, [1, 1, 1]
    px = rgb[sel].astype(np.float64) / 255.0
    lum = 0.2126 * px[:, 0] + 0.7152 * px[:, 1] + 0.0722 * px[:, 2]
    med = np.median(rgb[sel], axis=0) / 255.0
    return float(lum.mean()), [round(float(v), 3) for v in med]


def save(mask, name):
    im = Image.fromarray(mask, "L")
    path = OUT / name
    im.save(path, optimize=True)
    print(f"{name}: {path.stat().st_size // 1024} KB, cover {100 * (mask >= 250).mean():.2f}%")


def main():
    fuse_im = np.array(Image.open(AC / "models/exterior_fuselage.png").convert("RGB"))
    eng_im = np.array(Image.open(AC / "models/exterior_engine.png").convert("RGB"))
    h, w = fuse_im.shape[:2]
    js, blob = glb_json_bin(GLB)
    fuse_parts, fin_parts = islands(js, blob)
    # The convention whose rudder samples land on the blue fin wins.
    blue = (fuse_im[:, :, 2] > fuse_im[:, :, 0] + 25) & (fuse_im[:, :, 2] > 50) & (fuse_im[:, :, 0] < 90)
    best, flip = -1, False
    for trial in (False, True):
        fin_uv = paint(fin_parts, h, w, trial)
        score = int((fin_uv > 0)[blue].sum()) if fin_uv.any() else 0
        # also count blue pixels covered
        score = int(((fin_uv > 0) & blue).sum())
        print("flip" if trial else "no flip", "blue covered", score)
        if score > best:
            best, flip = score, trial
    print("using", "flip" if flip else "no flip")
    tube = paint(fuse_parts, h, w, flip)
    fin_uv = paint(fin_parts, h, w, flip)
    r = fuse_im[:, :, 0].astype(np.int16)
    g = fuse_im[:, :, 1].astype(np.int16)
    b = fuse_im[:, :, 2].astype(np.int16)
    # Fin blue (24, 46, 96) is darker and less green than the slate cheat line (66, 82, 104).
    fin_col = (r < 50) & (b > 70) & (b > r + 40) & (b > g)
    cheat_col = (np.abs(r - 66) < 22) & (np.abs(g - 82) < 22) & (np.abs(b - 104) < 22) & ~fin_col
    light = (r > 170) & (g > 170) & (b > 170) & (np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b) < 40)
    on_tube = tube > 0
    fin = ((fin_col & on_tube) | ((fin_uv > 0) & fin_col)).astype(np.uint8) * 255
    cheat = (cheat_col & on_tube & (fin == 0)).astype(np.uint8) * 255
    body = (light & on_tube & (fin == 0) & (cheat == 0)).astype(np.uint8) * 255
    for m in (fin, cheat, body):
        clear_reg(m)
    OUT.mkdir(exist_ok=True)
    regions = []
    for key, label, mask in (
        ("body", "Fuselage paint", body),
        ("fin", "Fin", fin),
        ("cheat", "Cheat line", cheat),
    ):
        save(mask, f"fuselage_{key}.png")
        lum, default = luma_of(fuse_im, mask)
        regions.append({"key": key, "label": label, "default": default, "luma": round(lum, 3),
                        "mask": f"livery/fuselage_{key}.png"})
    er, eg, eb = (eng_im[:, :, i].astype(np.int16) for i in range(3))
    eng = ((er > 190) & (eg > 190) & (eb > 190)).astype(np.uint8) * 255
    save(eng, "engine_engines.png")
    lum, default = luma_of(eng_im, eng)
    print(json.dumps({"fuselage": regions, "engines": {"default": default, "luma": round(lum, 3)}}, indent=1))
    # A sticker box: a solid patch of fuselage paint, clear of both registration rectangles.
    solid = body >= 250
    for x, y, bw, bh in REG:
        solid[y:y + bh, x:x + bw] = False
    found = []
    for bw, bh in ((180, 120), (160, 100)):
        # stride so this stays a short scan of a 4096 image
        step = 40
        ys, xs = np.where(solid[::step, ::step])
        for yy, xx in zip(ys, xs):
            y0, x0 = int(yy * step), int(xx * step)
            if y0 + bh >= h or x0 + bw >= w:
                continue
            if solid[y0:y0 + bh, x0:x0 + bw].mean() > 0.98:
                found.append((x0, y0, bw, bh))
                if len(found) >= 6:
                    break
        if len(found) >= 6:
            break
    print("sticker boxes", found[:6])


if __name__ == "__main__":
    main()
