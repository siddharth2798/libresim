"""Pull coincident (z-fighting) faces of a glb apart by a hair. Plain Python + numpy, edits the file in place.

  tools/.venv/bin/python tools/blender/separate_coplanar_glb.py <file.glb> [--eps 0.01] [--check]

The generic FlightGear jetway has a cab back wall and its door drawn on the same plane (back to
back, both materials double sided), so the depth test flips between them frame to frame. Every
pair of triangles that lie in one plane and overlap is moved apart along its own normal: facing
away from each other for opposite normals, one sheet laid over the other for equal normals.
A moved triangle gets its own copy of its vertices (appended to the file), so its neighbours stay
put. Idempotent: a second run finds nothing to move. --check only reports.
"""
import json
import struct
import sys

import numpy as np

PLANE_TOL = 0.003  # m: planes closer than this fight
OVERLAP_MIN = 1e-3  # m^2


def read_glb(path):
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    js = json.loads(b[20:20 + n])
    off = 20 + n
    m = struct.unpack_from("<I", b, off)[0]
    return js, bytearray(b[off + 8:off + 8 + m])


def write_glb(path, js, bin_):
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * (-len(j) % 4)
    bin_ += b"\0" * (-len(bin_) % 4)
    total = 12 + 8 + len(j) + 8 + len(bin_)
    open(path, "wb").write(struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(j), 0x4E4F534A) + j
                           + struct.pack("<II", len(bin_), 0x004E4942) + bin_)


def accessor(js, bin_, idx):
    a = js["accessors"][idx]
    bv = js["bufferViews"][a["bufferView"]]
    comp = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4)}[a["componentType"]]
    nc = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[a["type"]]
    stride = bv.get("byteStride") or comp[1] * nc
    return a, bv["byteOffset"] + a.get("byteOffset", 0), stride, comp, nc


def put_view(js, bin_, acc, data, count, target):
    """Append `data` as a new buffer view and point the accessor at it."""
    bin_ += b"\0" * (-len(bin_) % 4)
    js["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(data), "target": target})
    bin_ += data
    js["buffers"][0]["byteLength"] = len(bin_)
    acc["bufferView"] = len(js["bufferViews"]) - 1
    acc["byteOffset"] = 0
    acc["count"] = count


def clip(poly, a, b):
    def inside(p): return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= -1e-9
    out = []
    for i in range(len(poly)):
        p, q = poly[i], poly[(i + 1) % len(poly)]
        ip, iq = inside(p), inside(q)
        if ip != iq:
            den = (p[0] - q[0]) * (a[1] - b[1]) - (p[1] - q[1]) * (a[0] - b[0])
            t = ((p[0] - a[0]) * (a[1] - b[1]) - (p[1] - a[1]) * (a[0] - b[0])) / den if abs(den) > 1e-12 else 0.0
            out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
        if iq:
            out.append(q)
    return out


def ccw(p):
    s = sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))
    return p if s > 0 else p[::-1]


def overlap_area(ta, tb, n):
    k = int(np.argmax(np.abs(n)))
    ax = [i for i in range(3) if i != k]
    pa = ccw([(v[ax[0]], v[ax[1]]) for v in ta])
    pb = ccw([(v[ax[0]], v[ax[1]]) for v in tb])
    for i in range(3):
        if not pa:
            return 0.0
        pa = clip(pa, pb[i], pb[(i + 1) % 3])
    if len(pa) < 3:
        return 0.0
    return abs(sum(pa[i][0] * pa[(i + 1) % len(pa)][1] - pa[(i + 1) % len(pa)][0] * pa[i][1] for i in range(len(pa)))) / 2


def main():
    path = sys.argv[1]
    eps = float(sys.argv[sys.argv.index("--eps") + 1]) if "--eps" in sys.argv else 0.01
    js, bin_ = read_glb(path)
    for nd in js["nodes"]:
        assert not any(k in nd for k in ("matrix", "rotation", "scale")), "node transforms not supported"
    tris = []  # (mesh name, position offset, stride, vertex idx x3, primitive)
    for nd in js["nodes"]:
        if "mesh" not in nd:
            continue
        for pr in js["meshes"][nd["mesh"]]["primitives"]:
            pa, po, ps, _, _ = accessor(js, bin_, pr["attributes"]["POSITION"])
            ia, io, istr, ic, _ = accessor(js, bin_, pr["indices"])
            idx = [struct.unpack_from("<" + ic[0], bin_, io + i * istr)[0] for i in range(ia["count"])]
            for t in range(0, len(idx), 3):
                tris.append((js["meshes"][nd["mesh"]].get("name", nd.get("name")), po, ps, idx[t:t + 3], pr))
    pos = [np.array([struct.unpack_from("<3f", bin_, t[1] + i * t[2]) for i in t[3]], dtype=np.float64) for t in tris]
    nrm = []
    for p in pos:
        n = np.cross(p[1] - p[0], p[2] - p[0])
        ln = np.linalg.norm(n)
        nrm.append(n / ln if ln > 1e-12 else np.zeros(3))
    N = np.array(nrm)
    D = np.array([N[i] @ pos[i][0] for i in range(len(tris))])
    dot = N @ N.T
    cand = np.argwhere((np.abs(dot) > 0.9995) & (np.triu(np.ones_like(dot), 1) > 0))
    level = np.zeros(len(tris), dtype=int)
    pairs = []
    for i, j in cand:
        sgn = 1.0 if dot[i, j] > 0 else -1.0
        if abs(D[i] - sgn * D[j]) > PLANE_TOL:
            continue
        if tris[i][3] == tris[j][3] and tris[i][1] == tris[j][1]:
            continue
        if overlap_area(pos[i], pos[j], N[i]) > OVERLAP_MIN:
            pairs.append((i, j, sgn))
    print("overlapping coplanar triangle pairs:", len(pairs), "(%d opposite)" % sum(1 for p in pairs if p[2] < 0))
    for _ in range(8):
        for i, j, sgn in pairs:
            if sgn < 0:
                level[i] = max(level[i], 1)
                level[j] = max(level[j], 1)
            else:
                level[j] = max(level[j], level[i] + 1)
    moved = {i for i in range(len(tris)) if level[i] > 0}
    if "--check" in sys.argv or not moved:
        return
    by_prim = {}
    for i in moved:
        by_prim.setdefault(id(tris[i][4]), []).append(i)
    for ids in by_prim.values():
        pr = tris[ids[0]][4]
        new_idx = {}  # (old vertex, level) -> new vertex
        for i in ids:
            for v, p in zip(tris[i][3], pos[i]):
                new_idx.setdefault((v, int(level[i])), (len(new_idx), p + N[i] * eps * level[i]))
        attrs = {}
        for name in ("POSITION", "NORMAL", "TEXCOORD_0"):
            a, o, st, _, nc = accessor(js, bin_, pr["attributes"][name])
            old = [struct.unpack_from("<%df" % nc, bin_, o + k * st) for k in range(a["count"])]
            add = []
            for (v, _lv), (n, p) in sorted(new_idx.items(), key=lambda kv: kv[1][0]):
                add.append(tuple(p) if name == "POSITION" else old[v])
            attrs[name] = (a, old + add, nc)
        base = attrs["POSITION"][0]["count"]
        for name, (a, rows, nc) in attrs.items():
            put_view(js, bin_, a, b"".join(struct.pack("<%df" % nc, *r) for r in rows), len(rows), 34962)
        ia, io, istr, ic, _ = accessor(js, bin_, pr["indices"])
        idx = [struct.unpack_from("<" + ic[0], bin_, io + k * istr)[0] for k in range(ia["count"])]
        for i in ids:
            t0 = None
            for k in range(0, len(idx), 3):
                if idx[k:k + 3] == tris[i][3]:
                    t0 = k
                    break
            for q, v in enumerate(tris[i][3]):
                idx[t0 + q] = base + new_idx[(v, int(level[i]))][0]
        ia["componentType"] = 5125
        put_view(js, bin_, ia, b"".join(struct.pack("<I", x) for x in idx), len(idx), 34963)
    for a in js["accessors"]:  # refresh the POSITION bounds (they grew by a few cm)
        if a["type"] == "VEC3" and "min" in a:
            bv = js["bufferViews"][a["bufferView"]]
            o = bv["byteOffset"] + a.get("byteOffset", 0)
            arr = np.array([struct.unpack_from("<3f", bin_, o + i * 12) for i in range(a["count"])])
            a["min"], a["max"] = arr.min(0).tolist(), arr.max(0).tolist()
    write_glb(path, js, bin_)
    print("moved %d triangles by %.3f m x level" % (len(moved), eps))


main()
