#!/usr/bin/env python3
"""Top-down silhouette (planform) of an aircraft's exterior glb, for its ground shadow (game/aircraft/common/ground_shadow.gd).

Every triangle of models/exterior.glb is projected straight down (structural metres: x aft, y right, z up; glb_probe.load)
and filled into a mask, 1 px = RES_M. Two images go to the aircraft's models/ folder, both LA PNGs (luminance 0 = black,
alpha = shadow), rows along x (nose at the top), columns along y (left wing on the left):
  planform_cast.png  lightly blurred: the sun's shadow on presets without real sun shadows
  planform_ao.png    each part weighted by its closeness to the ground (exp(-height / AO_HEIGHT_M)), widely blurred: the
                     soft darkening under the aircraft on every preset
and planform.json {x0, x1, y0, y1 (structural rect of the images), z_mid (median skin height: the plane the cast shadow
is thrown from), z_low (lowest point: the tyres), res_m}.

  tools/.venv/bin/python tools/30_planform.py c172 a320
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_probe  # noqa: E402

RES_M = {"c172": 0.03, "a320": 0.08}
MARGIN_M = {"c172": 1.0, "a320": 3.0}
CAST_BLUR_M = {"c172": 0.06, "a320": 0.15}
AO_BLUR_M = {"c172": 0.5, "a320": 1.2}
AO_HEIGHT_M = {"c172": 1.0, "a320": 2.2}  # a part this far above the tyres darkens the ground under it by 1/e


def planform(ac):
    parts = glb_probe.load(ac)
    allv = np.vstack([p[2] for p in parts])
    res = RES_M.get(ac, 0.05)
    m = MARGIN_M.get(ac, 1.5)
    x0, y0 = allv[:, 0].min() - m, allv[:, 1].min() - m
    x1, y1 = allv[:, 0].max() + m, allv[:, 1].max() + m
    w, h = int(np.ceil((y1 - y0) / res)), int(np.ceil((x1 - x0) / res))
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    for _, _, v, idx in parts:
        px = np.c_[(v[:, 1] - y0) / res, (v[:, 0] - x0) / res]
        for t in idx:
            d.polygon([tuple(px[k]) for k in t], fill=255)
    mask = np.asarray(img, float) / 255.0
    cast = gaussian_filter(mask, CAST_BLUR_M.get(ac, 0.1) / res)
    low = allv[:, 2].min()
    tris = []
    for _, _, v, idx in parts:
        px = np.c_[(v[:, 1] - y0) / res, (v[:, 0] - x0) / res]
        for t in idx:
            tris.append((np.exp(-(v[t, 2].mean() - low) / AO_HEIGHT_M.get(ac, 1.5)), [tuple(px[k]) for k in t]))
    tris.sort(key=lambda e: e[0])  # the part nearest the ground is drawn last and wins
    occ = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(occ)
    for wgt, poly in tris:
        d.polygon(poly, fill=int(round(255 * wgt)))
    ao = gaussian_filter(np.asarray(occ, float) / 255.0, AO_BLUR_M.get(ac, 1.0) / res)
    meta = {"x0": round(float(x0), 3), "x1": round(float(x0 + h * res), 3), "y0": round(float(y0), 3),
            "y1": round(float(y0 + w * res), 3), "z_mid": round(float(np.median(allv[:, 2])), 3),
            "z_low": round(float(allv[:, 2].min()), 3), "res_m": res,
            "note": "tools/30_planform.py: top-down silhouette of models/exterior.glb for aircraft/common/ground_shadow.gd"}
    return cast, ao, meta


def _save(a, path):
    la = np.zeros(a.shape + (2,), np.uint8)
    la[..., 1] = np.clip(np.round(a / max(a.max(), 1e-6) * 255), 0, 255)  # strongest = opaque; the decal sets the strength
    Image.fromarray(la, "LA").save(path, optimize=True)


def main():
    for ac in sys.argv[1:] or ["c172", "a320"]:
        cast, ao, meta = planform(ac)
        out = os.path.join(glb_probe.ROOT, ac, "models")
        _save(cast, os.path.join(out, "planform_cast.png"))
        _save(ao, os.path.join(out, "planform_ao.png"))
        with open(os.path.join(out, "planform.json"), "w") as f:
            json.dump(meta, f, indent=1)
        print(ac, cast.shape, meta)


if __name__ == "__main__":
    main()
