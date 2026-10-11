"""Tile I/O for 17_airport_fixups.py: read/write level 0-2 height and land-class tiles in
place, keep the originals of every file it changes (terrain/fixups_orig/) so a re-run first
reverts and then re-applies (tool changes take effect; a second run gives the same bytes).
State: terrain/fixups.json = {"files": {relpath: sha1 written}, "meta": {"L/key": [min, max]}}.
"""
import gzip
import hashlib
import json
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


class Tiles:
    def __init__(self):
        self.files = {}  # relpath -> sha1 of what we wrote
        self.meta = json.loads((T / "meta.json").read_text())
        self.meta_orig = {}  # "L/key" -> original [min, max]

    # ------------------------------------------------------------ state / revert
    def prepare(self):
        """Revert a previous application (if the data is still ours), else start clean."""
        if not STATE.exists():
            shutil.rmtree(ORIG, ignore_errors=True)
            return "fresh"
        st = json.loads(STATE.read_text())
        ours = [(T / k).exists() and sha((T / k).read_bytes()) == v for k, v in st["files"].items()]
        if ours and not all(ours):
            raise SystemExit("some patched tiles were regenerated and some not: re-run 02 and 11, then this tool")
        if ours and all(ours):
            for k in st["files"]:
                shutil.copyfile(ORIG / k, T / k)
            for lk, mm in st["meta"].items():
                lv, key = lk.split("/")
                self._level(int(lv))[key][0:2] = mm
            res = "reverted previous fixups, re-applying"
        else:
            res = "tiles regenerated since last run, applying"
        shutil.rmtree(ORIG, ignore_errors=True)
        STATE.unlink()
        return res

    def save(self):
        (T / "meta.json").write_text(json.dumps(self.meta))
        STATE.write_text(json.dumps({"files": self.files, "meta": self.meta_orig}, indent=0))

    def _level(self, level):
        return next(lv for lv in self.meta["levels"] if lv.get("level", -1) == level)["tiles"]

    def _write(self, rel, b):
        if rel not in self.files:
            (ORIG / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(T / rel, ORIG / rel)
        (T / rel).write_bytes(b)
        self.files[rel] = sha(b)

    # ------------------------------------------------------------ heights
    @staticmethod
    def h_rel(level, tx, ty):
        return f"h/{level}/{tx}_{ty}.r16"

    def read_h(self, level, tx, ty):
        p = T / self.h_rel(level, tx, ty)
        if not p.exists():
            return None
        return np.fromfile(p, "<u2").reshape(N + 1, N + 1).astype(np.float64) * c.H_SCALE + c.H_OFFSET

    def write_h(self, level, tx, ty, a):
        b = np.clip(np.round((a - c.H_OFFSET) / c.H_SCALE), 0, 65535).astype("<u2").tobytes()
        self._write(self.h_rel(level, tx, ty), b)
        tiles, key = self._level(level), f"{tx}_{ty}"
        self.meta_orig.setdefault(f"{level}/{key}", list(tiles[key][0:2]))
        tiles[key][0:2] = [round(float(a.min()), 1), round(float(a.max()), 1)]

    # ------------------------------------------------------------ land class
    @staticmethod
    def lc_rel(level, tx, ty):
        return f"lc/{level}/{tx}_{ty}.r8.gz"

    def read_lc(self, level, tx, ty):
        p = T / self.lc_rel(level, tx, ty)
        if not p.exists():
            return None
        return np.frombuffer(gzip.decompress(p.read_bytes()), np.uint8).reshape(LCN, LCN).copy()

    def write_lc(self, level, tx, ty, a):
        self._write(self.lc_rel(level, tx, ty), gzip.compress(a.astype(np.uint8).tobytes(), 6, mtime=0))

    def lc_downsample(self, level, tx, ty):
        """11_landclass.downsample: majority water, mean tree density of the 2x2 children."""
        acc = np.zeros((LCN, LCN), np.float32)
        wat = np.zeros((LCN, LCN), np.float32)
        for dy in (0, 1):
            for dx in (0, 1):
                a = self.read_lc(level - 1, 2 * tx + dx, 2 * ty + dy)
                if a is None:
                    continue
                a2 = a.astype(np.float32).reshape(LCN // 2, 2, LCN // 2, 2)
                r0, c0 = (1 - dy) * (LCN // 2), dx * (LCN // 2)
                wat[r0:r0 + LCN // 2, c0:c0 + LCN // 2] = (a2 == 255).mean(axis=(1, 3))
                acc[r0:r0 + LCN // 2, c0:c0 + LCN // 2] = np.where(a2 == 255, 0, a2).mean(axis=(1, 3))
        out = np.round(acc).astype(np.uint8)
        out[wat > 0.5] = 255
        return out


def downsample(a):
    """02_dem_tiles.downsample: 2x decimation with a [1 2 1]/4 filter."""
    p = np.pad(a, 1, mode="edge")
    f = (p[:-2] + 2 * p[1:-1] + p[2:]) / 4
    f = (f[:, :-2] + 2 * f[:, 1:-1] + f[:, 2:]) / 4
    return f[::2, ::2]
