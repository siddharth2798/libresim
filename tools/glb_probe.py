"""Probe an aircraft exterior .glb in JSBSim structural metres (x aft, y right, z up).

Used to place exterior lights (game/aircraft/<id>/aircraft.json "lights") on the model. The glb is
FlightGear's model frame exported Y-up (glTF X = FG x, Y = FG z, Z = -FG y) with its origin at
model.origin_m (else config.json metrics.vrp_m): structural = (X, -Z, Y) + origin.

  tools/.venv/bin/python tools/glb_probe.py c172 nodes             # per-node bounds
  tools/.venv/bin/python tools/glb_probe.py a320 materials         # per-material bounds
  tools/.venv/bin/python tools/glb_probe.py a320 box x0 x1 y0 y1 z0 z1 [node|material substring]
                                                                   # vertices in a box: bounds + extremes
  tools/.venv/bin/python tools/glb_probe.py a320 extremes          # wingtips, fin top, nose, tail cone, belly
  tools/.venv/bin/python tools/glb_probe.py a320 ray ox oy oz dx dy dz   # first skin hit along a ray
  tools/.venv/bin/python tools/glb_probe.py a320 section x=<v>|y=<v> [tol]   # skin profile at a station
"""
import json
import os
import struct
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "aircraft")
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _origin(ac):
    a = json.load(open(os.path.join(ROOT, ac, "aircraft.json")))
    o = a.get("model", {}).get("origin_m")
    if o is None:
        o = json.load(open(os.path.join(ROOT, ac, "config.json")))["metrics"]["vrp_m"]
    return np.array(o, float)


def _accessor(j, binb, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    n, c, dt = a["count"], NC[a["type"]], CT[a["componentType"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or c * np.dtype(dt).itemsize
    raw = np.frombuffer(binb, np.uint8, count=stride * (n - 1) + c * np.dtype(dt).itemsize, offset=off)
    rows = np.lib.stride_tricks.as_strided(raw, (n, c * np.dtype(dt).itemsize), (stride, 1))
    return np.ascontiguousarray(rows).view(dt).reshape(n, c).astype(float)


def _local(n):
    if "matrix" in n:
        return np.array(n["matrix"], float).reshape(4, 4).T
    t = np.eye(4)
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    t[:3, :3] = r * np.array(n.get("scale", [1, 1, 1]))
    t[:3, 3] = n.get("translation", [0, 0, 0])
    return t


def load(ac):
    """-> list of (node name, material name, (n, 3) structural vertices)."""
    b = open(os.path.join(ROOT, ac, "models", "exterior.glb"), "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    binb = b[20 + jl + 8:]
    org = _origin(ac)
    out = []
    parent = {}
    for i, n in enumerate(j["nodes"]):
        for c in n.get("children", []):
            parent[c] = i

    def world(i):
        m = _local(j["nodes"][i])
        while i in parent:
            i = parent[i]
            m = _local(j["nodes"][i]) @ m
        return m

    for i, n in enumerate(j["nodes"]):
        if "mesh" not in n:
            continue
        w = world(i)
        for p in j["meshes"][n["mesh"]]["primitives"]:
            v = _accessor(j, binb, p["attributes"]["POSITION"])
            v = (np.c_[v, np.ones(len(v))] @ w.T)[:, :3]
            s = np.c_[v[:, 0], -v[:, 2], v[:, 1]] + org
            mat = j["materials"][p["material"]].get("name", "?") if "material" in p else "?"
            idx = _accessor(j, binb, p["indices"]).astype(int).reshape(-1, 3) if "indices" in p else np.arange(len(s)).reshape(-1, 3)
            out.append((n.get("name", "?"), mat, s, idx))
    return out


def _fmt(v):
    return "[%7.3f %7.3f %7.3f]" % tuple(v)


def _bounds(groups):
    for k, vs in sorted(groups.items()):
        a = np.vstack(vs)
        print("%-34s n=%6d min %s max %s" % (k[:34], len(a), _fmt(a.min(0)), _fmt(a.max(0))))


def cmd_nodes(parts, key=0):
    g = {}
    for p in parts:
        g.setdefault(p[key], []).append(p[2])
    _bounds(g)


def _all(parts, sub=None):
    vs = [p[2] for p in parts if sub is None or sub in p[0] or sub in p[1]]
    return np.vstack(vs)


def cmd_box(parts, lo, hi, sub=None):
    a = _all(parts, sub)
    m = np.all((a >= lo) & (a <= hi), axis=1)
    a = a[m]
    if len(a) == 0:
        print("no vertices")
        return
    print("n=%d min %s max %s mean %s" % (len(a), _fmt(a.min(0)), _fmt(a.max(0)), _fmt(a.mean(0))))
    for ax, nm in enumerate("xyz"):
        print("  min %s at %s   max %s at %s" % (nm, _fmt(a[a[:, ax].argmin()]), nm, _fmt(a[a[:, ax].argmax()])))
    hits = {}
    for p in parts:
        if sub is not None and sub not in p[0] and sub not in p[1]:
            continue
        k = np.all((p[2] >= lo) & (p[2] <= hi), axis=1).sum()
        if k:
            hits[(p[0], p[1])] = hits.get((p[0], p[1]), 0) + int(k)
    for k, n in sorted(hits.items(), key=lambda t: -t[1])[:12]:
        print("  %6d  %s / %s" % (n, k[0], k[1]))


def cmd_extremes(parts):
    a = _all(parts)
    for nm, i, s in [("nose (min x)", 0, -1), ("tail (max x)", 0, 1), ("left tip (min y)", 1, -1),
                     ("right tip (max y)", 1, 1), ("belly (min z)", 2, -1), ("fin top (max z)", 2, 1)]:
        k = a[:, i].argmin() if s < 0 else a[:, i].argmax()
        print("%-18s %s" % (nm, _fmt(a[k])))


def cmd_section(parts, spec, tol=0.05):
    ax = "xyz".index(spec[0])
    v = float(spec[2:])
    a = _all(parts)
    a = a[np.abs(a[:, ax] - v) < tol]
    print("n=%d min %s max %s" % (len(a), _fmt(a.min(0)), _fmt(a.max(0))))
    o = [i for i in range(3) if i != ax]
    for k in o:
        for s in (a[:, k].argmin(), a[:, k].argmax()):
            print("  extreme %s: %s" % ("xyz"[k], _fmt(a[s])))


def cmd_ray(parts, o, d):
    """First skin hit along o + t d (t > 0): Moller-Trumbore over every triangle."""
    d = d / np.linalg.norm(d)
    best = (np.inf, None)
    for p in parts:
        v, f = p[2], p[3]
        a, b, c = v[f[:, 0]], v[f[:, 1]], v[f[:, 2]]
        e1, e2 = b - a, c - a
        h = np.cross(d, e2)
        det = (e1 * h).sum(1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        s = o - a
        u = (s * h).sum(1) * inv
        q = np.cross(s, e1)
        w = (q * d).sum(1) * inv
        t = (q * e2).sum(1) * inv
        m = ok & (u >= 0) & (w >= 0) & (u + w <= 1) & (t > 1e-6)
        if m.any():
            k = np.where(m)[0][t[m].argmin()]
            if t[k] < best[0]:
                best = (t[k], (p[0], p[1]))
    if best[1] is None:
        print("ray %s dir %s: no hit" % (_fmt(o), _fmt(d)))
    else:
        print("ray %s dir %s: hit %s at t=%.3f on %s / %s" % (_fmt(o), _fmt(d), _fmt(o + d * best[0]), best[0], *best[1]))


def main():
    ac, cmd = sys.argv[1], sys.argv[2]
    parts = load(ac)
    if cmd == "nodes":
        cmd_nodes(parts, 0)
    elif cmd == "materials":
        cmd_nodes(parts, 1)
    elif cmd == "box":
        f = [float(x) for x in sys.argv[3:9]]
        cmd_box(parts, np.array(f[0::2]), np.array(f[1::2]), sys.argv[9] if len(sys.argv) > 9 else None)
    elif cmd == "extremes":
        cmd_extremes(parts)
    elif cmd == "section":
        cmd_section(parts, sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 0.05)
    elif cmd == "ray":
        f = [float(x) for x in sys.argv[3:9]]
        cmd_ray(parts, np.array(f[:3]), np.array(f[3:]))
    elif cmd == "bounds":
        a = _all(parts)
        print(json.dumps({"min": a.min(0).round(3).tolist(), "max": a.max(0).round(3).tolist()}))


if __name__ == "__main__":
    main()
