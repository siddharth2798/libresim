"""Terrain detail textures: CC0 PBR sets from ambientCG, packed for the terrain shader.

Downloads each set's 1K-JPG zip once into data/raw/textures/<asset>/ (colour, OpenGL normal,
roughness, AO; ambientCG assets are all CC0 1.0, https://docs.ambientcg.com/license/) and writes
two vertical strips of SIZE x SIZE layers, imported by Godot as Texture2DArray (one layer per row;
the .import files are written here):
  game/world/textures/terrain/detail_mod.webp  RGB: albedo modulation x 0.5 (0.5 = unchanged), linear.
      The imagery sets the ground tone; this adds structure. Each layer is high-passed (divided by
      a wrap-around blur, so no tile-sized blotch repeats from altitude), contrast-normalised
      (CONTRAST), hue partly kept (HUE).
  game/world/textures/terrain/detail_nrm.webp  RGBA: normal x, y (OpenGL, +y = north), roughness - mean + 0.5, AO.
  game/world/textures/terrain/SOURCES.md       layer -> asset, URL, licence (CREDITS.md lists the same).
Layer order = the L_* constants in game/world/terrain_detail.gdshaderinc; keep them in step.
Usage: tools/.venv/bin/python tools/26_terrain_textures.py [--force-download]
"""
import argparse
import io
import sys
import urllib.request
import zipfile

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, zoom

import common as c

RAW = c.RAW / "textures"
DST = c.ROOT / "game" / "world" / "textures" / "terrain"
SIZE = 1024
CONTRAST = 0.22  # target std of log luminance after the high-pass
HUE = 0.35       # 0: luminance-only modulation, 1: full colour ratio
# (layer name, ambientCG asset, what it is used for); index = layer
LAYERS = [
    ("soil", "Ground048", "crop land: ploughed soil"),
    ("grass", "Grass004", "grassland, moss / lichen"),
    ("scrub", "Ground103", "shrub land, dry ground"),
    ("laterite", "Gravel025", "bare / sparse ground (laterite plateaus)"),
    ("rock", "Rocks011", "cliffs and steep slopes (triplanar)"),
    ("forest", "Ground076", "forest floor under tree cover"),
    ("urban", "Ground110", "built-up ground"),
    ("sand", "Ground080", "beaches and sand near the sea"),
    ("mud", "Ground036", "herbaceous wetland, mangrove"),
    ("concrete", "Concrete047A", "airport aprons (concrete)"),
    ("asphalt", "Asphalt031", "asphalt aprons, runway / taxiway shoulders"),
]
MAPS = {"color": "_Color.jpg", "normal": "_NormalGL.jpg", "rough": "_Roughness.jpg", "ao": "_AmbientOcclusion.jpg"}
URL = "https://ambientcg.com/get?file={}_1K-JPG.zip"
PAGE = "https://ambientcg.com/view?id={}"


def fetch(asset, force=False):
    """-> {map: Path} for the asset (downloads and unpacks the needed files once)."""
    d = RAW / asset
    want = {k: d / f"{asset}{suf}" for k, suf in MAPS.items()}
    if not force and all(p.exists() for k, p in want.items() if k != "ao") and (d / "zip.ok").exists():
        return {k: p for k, p in want.items() if p.exists()}
    d.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(URL.format(asset), headers={"User-Agent": "libresim-tools/1.0"})
    data = urllib.request.urlopen(req, timeout=120).read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        names = z.namelist()
        for k, p in want.items():
            src = next((n for n in names if n.endswith(MAPS[k]) and "/" not in n), None)
            if src is None:
                if k == "ao":
                    continue
                sys.exit(f"{asset}: *{MAPS[k]} missing from the zip")
            p.write_bytes(z.read(src))  # written under our own name, never a path from the archive
    (d / "zip.ok").write_text(URL.format(asset) + "\n")
    print(f"  fetched {asset} ({len(data) / 1e6:.1f} MB)")
    return {k: p for k, p in want.items() if p.exists()}


def load(p, mode):
    im = Image.open(p).convert(mode)
    if im.size != (SIZE, SIZE):
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(im, np.float32) / 255.0


def modulation(rgb):
    """Albedo -> high-passed, contrast-normalised multiplier (1 = unchanged)."""
    lin = np.power(rgb, 2.2) + 1e-3
    sigma = SIZE / 10.0
    low = np.stack([gaussian_filter(lin[..., i], sigma, mode="wrap") for i in range(3)], -1)
    ratio = lin / low
    lum = ratio @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    lg = np.log(np.maximum(lum, 1e-3))
    gain = CONTRAST / max(float(lg.std()), 1e-3)
    lum_m = np.exp((lg - lg.mean()) * gain)
    hue = ratio / np.maximum(lum, 1e-3)[..., None]  # colour ratio at unit luminance
    m = lum_m[..., None] * (1.0 + (hue - 1.0) * HUE)
    return np.clip(m, 0.0, 1.99)


def pack(files):
    rgb = load(files["color"], "RGB")
    mod = modulation(rgb)
    n = load(files["normal"], "RGB")
    rough = load(files["rough"], "L")
    ao = load(files["ao"], "L") if "ao" in files else np.ones((SIZE, SIZE), np.float32)
    mod8 = np.clip(np.round(mod * 0.5 * 255.0), 0, 255).astype(np.uint8)
    # roughness relative to the set's mean (0.5 = the shader's own roughness): the sets disagree on absolute values
    rel = 0.5 + (rough - rough.mean())
    nrm8 = np.clip(np.round(np.dstack([n[..., 0], n[..., 1], rel, ao]) * 255.0), 0, 255).astype(np.uint8)
    return mod8, nrm8, float(rough.mean())


IMPORT = """[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="res://world/textures/terrain/{name}"

[params]

compress/mode=2
compress/high_quality={hq}
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/channel_pack=1
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal=1
slices/vertical={n}
"""


def write_import(name, n, hq):
    """Godot import settings: VRAM compressed (BC on desktop, ASTC / ETC2 on mobile), mipmapped,
    n rows. Godot fills in uid / dest_files on first import; an existing .import (uid) is kept."""
    p = DST / (name + ".import")
    if p.exists() and f"slices/vertical={n}" in p.read_text():
        return
    p.write_text(IMPORT.format(name=name, n=n, hq="true" if hq else "false"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force-download", action="store_true")
    args = ap.parse_args()
    DST.mkdir(parents=True, exist_ok=True)
    mods, nrms, rows = [], [], []
    for i, (name, asset, use) in enumerate(LAYERS):
        files = fetch(asset, args.force_download)
        m, n, r = pack(files)
        mods.append(m)
        nrms.append(n)
        rows.append(f"| {i} | {name} | {asset} | {use} | {PAGE.format(asset)} | CC0 1.0 |")
        print(f"layer {i:2d} {name:9s} {asset:12s} mean roughness {r:.2f}")
    # lossy WebP keeps the repository small (the game re-compresses to BC / ASTC on import anyway)
    Image.fromarray(np.concatenate(mods, 0), "RGB").save(DST / "detail_mod.webp", quality=90, method=6)
    Image.fromarray(np.concatenate(nrms, 0), "RGBA").save(DST / "detail_nrm.webp", quality=92, alpha_quality=90, method=6)
    write_import("detail_mod.webp", len(LAYERS), False)
    write_import("detail_nrm.webp", len(LAYERS), True)
    (DST / "SOURCES.md").write_text(
        "# Terrain detail textures\n\nMade by `tools/26_terrain_textures.py` from ambientCG material sets "
        "(1K-JPG: colour, NormalGL, roughness, ambient occlusion), all **CC0 1.0** "
        "(https://docs.ambientcg.com/license/). Changes: albedo high-passed and turned into a modulation map, "
        "normal / roughness / AO packed into one RGBA map, stacked into texture arrays.\n\n"
        "| layer | name | asset | used for | source | licence |\n|---|---|---|---|---|---|\n" + "\n".join(rows) + "\n")
    for f in ("detail_mod.webp", "detail_nrm.webp"):
        print(f"{f}: {(DST / f).stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
