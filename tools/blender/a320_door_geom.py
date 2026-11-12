"""Geometry helpers for the A320 passenger door (tools/blender/a320_door.py). Run inside Blender.

Frame: structural metres = the exterior glb's frame (x aft, y right, z up). A door is addressed in its own
surface coordinates: `a` metres aft of the door's forward edge, `h` metres above its sill, `d` metres inboard of
the door's outer face measured along the skin normal. Skin.pt(a, h, d) turns that into a structural point on the
real exterior skin (ray cast on the `body` mesh), so every part follows the fuselage curvature and taper there.
"""
import math

import bmesh
import bpy
from mathutils import Vector

EPS_OUT = 0.004  # the closed door's outer face stands this far outside the painted skin


def srgb(hexstr):
    """'#rrggbb' -> linear RGB for Blender's Base Color (the glTF factor is linear, Godot shows it as sRGB)."""
    c = [int(hexstr[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name, hexstr, rough=0.6, metal=0.0):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*srgb(hexstr), 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    m.use_backface_culling = False  # glTF doubleSided: thin plates and placards read from both faces
    return m


class Skin:
    """The exterior skin around one door: structural point and outward normal at door coordinates (a, h)."""

    def __init__(self, body, xf, z0, side):
        self.body, self.xf, self.z0, self.side = body, xf, z0, side
        self.inv = body.matrix_world.inverted()
        self._cache = {}

    def _y(self, x, z):
        o = Vector((x, self.side * 8.0, z))
        d = Vector((0.0, -self.side, 0.0))
        ok, loc, _n, _i = self.body.ray_cast(self.inv @ o, (self.inv.to_3x3() @ d).normalized())
        if not ok:
            raise RuntimeError("no skin at x %.3f z %.3f side %d" % (x, z, self.side))
        return (self.body.matrix_world @ loc).y

    def frame(self, a, h):
        key = (round(a, 4), round(h, 4))
        if key not in self._cache:
            x, z, e = self.xf + a, self.z0 + h, 0.05
            p = Vector((x, self._y(x, z), z))
            tx = Vector((2 * e, self._y(x + e, z) - self._y(x - e, z), 0.0))
            tz = Vector((0.0, self._y(x, z + e) - self._y(x, z - e), 2 * e))
            n = tx.cross(tz).normalized()
            if n.y * self.side < 0:
                n = -n
            self._cache[key] = (p, n)
        return self._cache[key]

    def pt(self, a, h, d):
        """Point d inboard of the door's outer face (negative d stands proud of it)."""
        p, n = self.frame(a, h)
        return p + n * (EPS_OUT - d)

    def inward(self):
        return Vector((0.0, -self.side, 0.0))


def rr_rows(a0, a1, h0, h1, rb, rt, ncol, nmid, narc=3):
    """Rows of (a, h) filling a rounded rectangle (bottom corner radius rb, top rt). Two calls with the same
    ncol / nmid / narc and both radii either zero or not give rows of the same shape (loops match)."""
    def arc(r, i):
        return r * (1.0 - math.cos(i / narc * math.pi / 2)) if narc else 0.0
    nb = narc if rb > 0 else 0
    nt = narc if rt > 0 else 0
    hs = [h0 + arc(rb, i) for i in range(nb)]
    lo, hi = h0 + (rb if nb else 0.0), h1 - (rt if nt else 0.0)
    hs += [lo + (hi - lo) * k / nmid for k in range(nmid + 1)]
    hs += [h1 - arc(rt, i) for i in range(nt - 1, -1, -1)]

    def inset(h):
        if nb and h < h0 + rb - 1e-9:
            dz = h0 + rb - h
            return rb - math.sqrt(max(rb * rb - dz * dz, 0.0))
        if nt and h > h1 - rt + 1e-9:
            dz = h - (h1 - rt)
            return rt - math.sqrt(max(rt * rt - dz * dz, 0.0))
        return 0.0
    rows = []
    for h in hs:
        s = inset(h)
        rows.append([(a0 + s + (a1 - a0 - 2 * s) * j / ncol, h) for j in range(ncol + 1)])
    return rows


def boundary(rows):
    """(row, col) pairs round the edge of a row grid, counter-clockwise in (a, h)."""
    nr, nc = len(rows), len(rows[0]) - 1
    loop = [(0, j) for j in range(nc + 1)] + [(i, nc) for i in range(1, nr)]
    loop += [(nr - 1, j) for j in range(nc - 1, -1, -1)] + [(i, 0) for i in range(nr - 2, 0, -1)]
    return loop


class Part:
    """Vertices and faces of one exported object. Faces are either in a closed shell (normals made outward by
    bmesh) or carry a `want` direction their normal must face."""

    def __init__(self, skin):
        self.s = skin
        self.v, self.f, self.mat, self.want = [], [], [], []

    def add_v(self, p):
        self.v.append(Vector(p))
        return len(self.v) - 1

    def face(self, idx, mat, want=None):
        self.f.append(tuple(idx))
        self.mat.append(mat)
        self.want.append(want)

    def grid(self, rows, d, mat, want=None, fn=None):
        """A surface over the row grid at depth d (or fn(a, h) -> point). Returns the index grid."""
        fn = fn or (lambda a, h: self.s.pt(a, h, d))
        ids = [[self.add_v(fn(a, h)) for (a, h) in row] for row in rows]
        for i in range(len(rows) - 1):
            for j in range(len(rows[0]) - 1):
                self.face((ids[i][j], ids[i][j + 1], ids[i + 1][j + 1], ids[i + 1][j]), mat, want)
        return ids

    def loop(self, rows, d=None, fn=None):
        fn = fn or (lambda a, h: self.s.pt(a, h, d))
        return [self.add_v(fn(*rows[i][j])) for (i, j) in boundary(rows)]

    def band(self, la, lb, mat, want=None, mat_fn=None):
        n = len(la)
        assert n == len(lb), (n, len(lb))
        for k in range(n):
            q = (la[k], la[(k + 1) % n], lb[(k + 1) % n], lb[k])
            self.face(q, mat_fn(k) if mat_fn else mat, want(q) if callable(want) else want)

    def box(self, a0, a1, h0, h1, d0, d1, mat, r=0.0, bev=0.004, nc=2, nm=2, front_mat=None):
        """A panel or housing standing from depth d0 to d1 (d1 > d0 = toward the cabin, d1 < d0 = outboard),
        chamfered by bev, closed at the back so its normals come out right."""
        rr = r if r > 0 else 0.0
        sgn = 1.0 if d1 > d0 else -1.0
        outer = rr_rows(a0, a1, h0, h1, rr, rr, nc, nm)
        inner = rr_rows(a0 + bev, a1 - bev, h0 + bev, h1 - bev, max(rr - bev, 0.002) if rr else 0.0,
                        max(rr - bev, 0.002) if rr else 0.0, nc, nm)
        back = self.grid(outer, d0, mat)
        l0 = [back[i][j] for (i, j) in boundary(outer)]
        l1 = self.loop(outer, d1 - sgn * bev)
        front = self.grid(inner, d1, front_mat or mat)
        l2 = [front[i][j] for (i, j) in boundary(inner)]
        self.band(l0, l1, mat)
        self.band(l1, l2, mat)

    def sheet(self, a0, a1, h0, h1, d, mat, toward_cabin=True, r=0.0, nc=1, nm=1):
        """A placard or lens: one curved plate facing the cabin (or outboard)."""
        a, h = (a0 + a1) / 2, (h0 + h1) / 2
        n = self.s.frame(a, h)[1]
        self.grid(rr_rows(a0, a1, h0, h1, r, r, nc, nm), d, mat, -n if toward_cabin else n)

    def disc(self, a, h, rad, d, mat, toward_cabin=True, seg=10):
        n = self.s.frame(a, h)[1]
        c = self.add_v(self.s.pt(a, h, d))
        ring = [self.add_v(self.s.pt(a + rad * math.cos(t), h + rad * math.sin(t), d))
                for t in (2 * math.pi * i / seg for i in range(seg))]
        for i in range(seg):
            self.face((c, ring[i], ring[(i + 1) % seg]), mat, -n if toward_cabin else n)

    def poly(self, pts, mat, want):
        self.face([self.add_v(p) for p in pts], mat, want)

    def cylinder(self, p0, p1, r, mat, segs=10):
        z = (p1 - p0).normalized()
        x = (Vector((0, 0, 1)) if abs(z.z) < 0.9 else Vector((1, 0, 0))).cross(z).normalized()
        y = z.cross(x)
        r0 = [self.add_v(p0 + (x * math.cos(t) + y * math.sin(t)) * r) for t in (2 * math.pi * i / segs for i in range(segs))]
        r1 = [self.add_v(p1 + (x * math.cos(t) + y * math.sin(t)) * r) for t in (2 * math.pi * i / segs for i in range(segs))]
        for i in range(segs):
            j = (i + 1) % segs
            self.face((r0[i], r0[j], r1[j], r1[i]), mat)
        self.face(list(reversed(r0)), mat)
        self.face(r1, mat)

    def tube(self, path, half_w, half_h, mat, up=Vector((0, 0, 1))):
        """A box-section beam along a polyline (plan-width 2 half_w, height 2 half_h), capped."""
        rings = []
        for k, p in enumerate(path):
            t = (path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)])
            t = Vector((t.x, t.y, 0.0)).normalized()
            m = up.cross(t).normalized()
            rings.append([self.add_v(p + m * sm * half_w + up * su * half_h) for sm, su in ((-1, -1), (1, -1), (1, 1), (-1, 1))])
        for a, b in zip(rings, rings[1:]):
            for i in range(4):
                j = (i + 1) % 4
                self.face((a[i], a[j], b[j], b[i]), mat)
        self.face(list(reversed(rings[0])), mat)
        self.face(rings[-1], mat)

    def build(self, name, mats, origin=Vector((0, 0, 0))):
        me = bpy.data.meshes.new(name)
        me.from_pydata([p - origin for p in self.v], [], self.f)
        for m in mats:
            me.materials.append(m)
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        shell = [bm.faces[i] for i, w in enumerate(self.want) if w is None]
        if shell:
            bmesh.ops.recalc_face_normals(bm, faces=shell)
        for i, f in enumerate(bm.faces):
            f.material_index = self.mat[i]
            w = self.want[i]
            if w is not None:
                f.normal_update()
                if f.normal.dot(w) < 0:
                    f.normal_flip()
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        ob.location = origin
        bpy.context.scene.collection.objects.link(ob)
        return ob
