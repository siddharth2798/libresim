"""Tile I/O for 17_airport_fixups.py: read/write level 0-2 height and land-class tiles in
place, keep the originals of every file it changes (terrain/fixups_orig/) so a re-run starts
again from the originals (tool changes take effect; a second run gives the same bytes).
Covers the base grid (meta.json) and region packs (meta_<region>.json); a tile's min/max
is updated in whichever meta lists it.
Every write goes through a temp file and an atomic rename, and tiles patched last time are
read from their originals instead of being reverted on disk first, so a game running during
the re-run never sees a half-written or temporarily unpatched tile.
State: terrain/fixups.json = {"files": {relpath: sha1 written},
                              "meta": {"<meta file>|<level>/<key>": original [min, max]}}.
A file regenerated since (02/11 re-run) no longer matches its sha1: its stale original is
dropped and the fresh file is patched instead.
"""
import gzip
import hashlib
import json
import os
import shutil

import numpy as np

import common as c

T = c.OUT / "terrain"
STATE = T / "fixups.json"
ORIG = T / "fixups_orig"
N = c.TILE_N
LCN = c.IMG_N


def sha(b):
    return hashlib.sha1(b).hexdigest()


def atomic_write(path, data):
    """Write bytes next to path, then rename over it (readers see the old or the new file)."""
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


class Tiles:
    def __init__(self):
        self.files = {}  # relpath -> sha1 of what we wrote this run
        self.metas = {p.name: json.loads(p.read_text()) for p in sorted(T.glob("meta*.json"))}
        self.meta_orig = {}
        self._dirty = set()
        self._ours = set()  # patched by the previous run, untouched since: originals are in ORIG

    # ------------------------------------------------------------ state / revert
    def prepare(self):
        """Find the files we patched last time (if still ours); their originals are read from ORIG
        and put back at save() unless this run patches them again."""
        if not STATE.exists():
            shutil.rmtree(ORIG, ignore_errors=True)
            return "fresh"
        st = json.loads(STATE.read_text())
        n_rev = n_new = 0
        for k, v in st["files"].items():
            if (T / k).exists() and (ORIG / k).exists() and sha((T / k).read_bytes()) == v:
                self._ours.add(k)
                n_rev += 1
                if k.startswith("h/"):
                    lv, key = k[2:-4].split("/")
                    for mk, mm in st["meta"].items():
                        mfile, lk = mk.split("|") if "|" in mk else ("meta.json", mk)
                        if lk == f"{lv}/{key}" and mfile in self.metas:
                            self._tiles(mfile, int(lv))[key][0:2] = mm
                            self._dirty.add(mfile)
            else:
                n_new += 1
        return f"{n_rev} tiles patched last time are re-derived from their originals; {n_new} were regenerated since"

    def save(self):
        for k in sorted(self._ours - set(self.files)):  # patched last time, not now: originals back
            atomic_write(T / k, (ORIG / k).read_bytes())
        for p in sorted(ORIG.rglob("*")):  # ORIG keeps exactly the originals of what we wrote
            if p.is_file() and p.relative_to(ORIG).as_posix() not in self.files:
                p.unlink()
        for m in self._dirty:
            atomic_write(T / m, json.dumps(self.metas[m]).encode())
        STATE.write_text(json.dumps({"files": self.files, "meta": self.meta_orig}, indent=0))

    def _tiles(self, mfile, level):
        for lv in self.metas[mfile]["levels"]:
            if lv.get("level", -1) == level:
                return lv["tiles"]
        return {}

    def _meta_entry(self, level, key):
        for m in self.metas:  # base meta.json sorts first and wins, as in TerrainMeta
            t = self._tiles(m, level)
            if key in t:
                return m, t
        return None, None

    def _src(self, rel):
        """Where the unpatched-so-far bytes of a tile are: its original, until this run writes it."""
        return ORIG / rel if rel in self._ours and rel not in self.files else T / rel

    def _write(self, rel, b):
        if rel not in self.files and rel not in self._ours:
            (ORIG / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(T / rel, ORIG / rel)
        atomic_write(T / rel, b)
        self.files[rel] = sha(b)

    # ------------------------------------------------------------ heights
    def read_h(self, level, tx, ty):
        p = self._src(f"h/{level}/{tx}_{ty}.r16")
        if not p.exists():
            return None
        return np.fromfile(p, "<u2").reshape(N + 1, N + 1).astype(np.float64) * c.H_SCALE + c.H_OFFSET

    def write_h(self, level, tx, ty, a):
        b = np.clip(np.round((a - c.H_OFFSET) / c.H_SCALE), 0, 65535).astype("<u2").tobytes()
        self._write(f"h/{level}/{tx}_{ty}.r16", b)
        key = f"{tx}_{ty}"
        m, tiles = self._meta_entry(level, key)
        if m is not None:
            self.meta_orig.setdefault(f"{m}|{level}/{key}", list(tiles[key][0:2]))
            tiles[key][0:2] = [round(float(a.min()), 1), round(float(a.max()), 1)]
            self._dirty.add(m)

    # ------------------------------------------------------------ land class
    def read_lc(self, level, tx, ty):
        p = self._src(f"lc/{level}/{tx}_{ty}.r8.gz")
        if not p.exists():
            return None
        return np.frombuffer(gzip.decompress(p.read_bytes()), np.uint8).reshape(LCN, LCN).copy()

    def write_lc(self, level, tx, ty, a):
        self._write(f"lc/{level}/{tx}_{ty}.r8.gz", gzip.compress(a.astype(np.uint8).tobytes(), 6, mtime=0))


def downsample(a):
    """02_dem_tiles.downsample: 2x decimation with a [1 2 1]/4 filter."""
    p = np.pad(a, 1, mode="edge")
    f = (p[:-2] + 2 * p[1:-1] + p[2:]) / 4
    f = (f[:, :-2] + 2 * f[:, 1:-1] + f[:, 2:]) / 4
    return f[::2, ::2]
