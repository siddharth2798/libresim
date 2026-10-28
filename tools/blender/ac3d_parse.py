"""Minimal AC3D (.ac, AC3Db) reader, pure Python (no bpy), so it works in any Blender version.

Why: the FlightGear AC3D importer add-on (Blender-AC3D) is not installed here and is written for
Blender <= 4.x; Blender 5.x has no AC3D importer, so libresim parses the (simple, text) format itself
and builds the Blender scene from the result (tools/blender/a320_scene.py). Decision recorded 2026-10-28.

Frame: AC3D is Y-up. `to_fg()` converts to the FlightGear model frame (x aft, y right, z up):
x_fg = x_ac, y_fg = -z_ac, z_fg = y_ac (a proper rotation; matches the Blender-AC3D importer).

Data model: parse(path) -> (materials, root). Obj has name, kind (world|group|poly), loc, rot (3x3 row
tuples), texture, texrep, texoff, verts [(x,y,z) local], surfs [(flags, mat, [(vertex, u, v)])], kids.
The file is untrusted data: it is only parsed, never executed.
"""
import shlex
from dataclasses import dataclass, field


@dataclass
class Obj:
    kind: str = "poly"
    name: str = ""
    data: str = ""
    loc: tuple = (0.0, 0.0, 0.0)
    rot: tuple = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
    texture: str = ""
    texrep: tuple = (1.0, 1.0)
    texoff: tuple = (0.0, 0.0)
    crease: float = 45.0
    verts: list = field(default_factory=list)
    surfs: list = field(default_factory=list)
    kids: list = field(default_factory=list)


def parse(path):
    with open(path, "r", errors="ignore") as f:
        lines = [ln.rstrip("\n") for ln in f]
    if not lines or not lines[0].startswith("AC3D"):
        raise ValueError("not an AC3D file: %s" % path)
    mats = []
    pos = [1]

    def nxt():
        ln = lines[pos[0]]
        pos[0] += 1
        return ln

    def peek():
        return lines[pos[0]] if pos[0] < len(lines) else None

    def read_obj():
        o = Obj(kind=nxt().split()[1])
        while True:
            ln = nxt()
            t = ln.split(None, 1)
            k = t[0]
            if k == "name":
                o.name = shlex.split(t[1])[0] if len(t) > 1 else ""
            elif k == "data":
                o.data = nxt() if int(t[1]) > 0 else ""
            elif k == "texture":
                o.texture = shlex.split(t[1])[0]
            elif k == "texrep":
                o.texrep = tuple(float(x) for x in t[1].split())
            elif k == "texoff":
                o.texoff = tuple(float(x) for x in t[1].split())
            elif k == "rot":
                v = [float(x) for x in t[1].split()]
                o.rot = (tuple(v[0:3]), tuple(v[3:6]), tuple(v[6:9]))
            elif k == "loc":
                o.loc = tuple(float(x) for x in t[1].split())
            elif k == "crease":
                o.crease = float(t[1])
            elif k == "numvert":
                o.verts = [tuple(float(x) for x in nxt().split()[:3]) for _ in range(int(t[1]))]
            elif k == "numsurf":
                for _ in range(int(t[1])):
                    assert nxt().startswith("SURF")
                    flags = int(ln_flags(lines[pos[0] - 1]), 16)
                    mat, refs = 0, []
                    while True:
                        s = nxt().split()
                        if s[0] == "mat":
                            mat = int(s[1])
                        elif s[0] == "refs":
                            for _ in range(int(s[1])):
                                r = nxt().split()
                                refs.append((int(r[0]), float(r[1]), float(r[2])))
                            break
                    o.surfs.append((flags, mat, refs))
            elif k == "kids":
                for _ in range(int(t[1])):
                    o.kids.append(read_obj())
                return o

    def ln_flags(s):
        return s.split()[1]

    while peek() is not None and peek().startswith("MATERIAL"):
        t = shlex.split(nxt())
        d = {"name": t[1]}
        i = 2
        while i < len(t):
            key = t[i]
            n = 3 if key in ("rgb", "amb", "emis", "spec") else 1
            d[key] = [float(x) for x in t[i + 1:i + 1 + n]]
            i += 1 + n
        mats.append(d)
    return mats, read_obj()


def mat_mul(r, v):
    """AC3D rot is stored row-wise and applied as v' = R^T-free form used by FlightGear: v' = v . R."""
    return tuple(sum(v[i] * r[i][j] for i in range(3)) for j in range(3))


def walk(root):
    """Yield (obj, world_vertices) for every poly with geometry, vertices in AC3D world space."""
    def rec(o, pr, pt):
        # world = parent_rot applied after local: p_world = (p . rot + loc) . pr + pt (row-vector convention)
        out = []
        if o.verts:
            out.append((o, [tuple(a + b for a, b in zip(_apply(pr, _add(mat_mul(o.rot, v), o.loc)), pt)) for v in o.verts]))
        nr = _compose(o.rot, pr)
        nt = tuple(a + b for a, b in zip(_apply(pr, o.loc), pt))
        for k in o.kids:
            out += rec(k, nr, nt)
        return out
    ident = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
    return rec(root, ident, (0, 0, 0))


def _add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def _apply(r, v):
    return mat_mul(r, v)


def _compose(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)) for i in range(3))


def to_fg(p):
    return (p[0], -p[2], p[1])
