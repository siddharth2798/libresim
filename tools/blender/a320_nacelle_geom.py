"""Measured inlet lip, hinge barrels, spinner cone and fan-blur annulus for a320_nacelle.py."""
import math

import bpy
from mathutils import Vector

LIP_N = 20
RAY_RADII = (0.70, 0.78, 0.86, 0.94, 1.02, 1.10, 1.18)


def wverts(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def basis(axis):
    axis = axis.normalized()
    tmp = Vector((0.0, 0.0, 1.0)) if abs(axis.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    u = tmp.cross(axis).normalized()
    v = axis.cross(u).normalized()
    return u, v


def shoot(body, origin, direction):
    inv = body.matrix_world.inverted()
    ok, loc, _nor, _i = body.ray_cast(inv @ origin, (inv.to_3x3() @ direction).normalized())
    if not ok:
        return None
    return body.matrix_world @ loc


def cylinder(p0, p1, r, segs=6):
    z = (p1 - p0).normalized()
    tmp = Vector((0, 0, 1)) if abs(z.z) < 0.9 else Vector((1, 0, 0))
    x = tmp.cross(z).normalized()
    y = z.cross(x)
    rings = []
    for p in (p0, p1):
        rings += [p + (x * math.cos(a) + y * math.sin(a)) * r for i in range(segs) for a in (2 * math.pi * i / segs,)]
    verts = rings + [p0, p1]
    faces = []
    for i in range(segs):
        j = (i + 1) % segs
        faces += [(i, j, segs + j, segs + i), (2 * segs, j, i), (2 * segs + 1, segs + i, segs + j)]
    return verts, faces


def tube(points, tube_r, minor, up):
    """Closed tube swept along measured rim points. `up` is the engine-forward axis."""
    n = len(points)
    frames = []
    for i in range(n):
        t = points[(i + 1) % n] - points[(i - 1) % n]
        if t.length < 1e-8:
            t = Vector((1.0, 0.0, 0.0))
        t.normalize()
        nrm = up - t * up.dot(t)
        if nrm.length < 0.15:
            nrm = Vector((0.0, 0.0, 1.0)) - t * t.z
        if nrm.length < 0.15:
            nrm = Vector((0.0, 1.0, 0.0))
        nrm.normalize()
        side = t.cross(nrm).normalized()
        frames.append((side.cross(t).normalized(), side))
    verts = []
    for p, (nrm, side) in zip(points, frames):
        for j in range(minor):
            a = 2.0 * math.pi * j / minor
            verts.append(p + (nrm * math.cos(a) + side * math.sin(a)) * tube_r)
    faces = []
    for i in range(n):
        i2 = (i + 1) % n
        for j in range(minor):
            j2 = (j + 1) % minor
            faces.append((i * minor + j, i * minor + j2, i2 * minor + j2, i2 * minor + j))
    return verts, faces


def axial_of(loc, centre, forward):
    rel = loc - centre
    axial = rel.dot(forward)
    return axial, (rel - forward * axial).length


def ray_front(body, centre, forward, arm):
    """Most forward body hit on rays parallel to the fan axis. The cowling is in `body`."""
    best = None
    for r in RAY_RADII:
        loc = shoot(body, centre + forward * 2.4 + arm * r, -forward)
        if loc is None:
            continue
        axial, rad = axial_of(loc, centre, forward)
        if axial < 0.25 or axial > 1.45 or rad < 0.62 or rad > 1.25:
            continue
        if best is None or axial > best[0]:
            best = (axial, rad, loc)
    return best


def vertex_fronts(body, centre, forward, n):
    u, v = basis(forward)
    best = [None] * n
    for w in wverts(body):
        axial, rad = axial_of(w, centre, forward)
        if axial < 0.25 or axial > 1.45 or rad < 0.62 or rad > 1.25:
            continue
        rel = w - centre - forward * axial
        ang = math.atan2(rel.dot(v), rel.dot(u))
        if ang < 0.0:
            ang += 2.0 * math.pi
        idx = int(round(ang / (2.0 * math.pi) * n)) % n
        if best[idx] is None or axial > best[idx][0]:
            best[idx] = (axial, rad, w)
    return best


def measure_lip(body, centre, forward):
    """Rim points in angle order. Raycast first; a body vertex fills a missed angle."""
    u, v = basis(forward)
    verts = vertex_fronts(body, centre, forward, LIP_N)
    hits, rays = [], 0
    for i in range(LIP_N):
        a = 2.0 * math.pi * i / LIP_N
        arm = u * math.cos(a) + v * math.sin(a)
        hit = ray_front(body, centre, forward, arm)
        if hit is None:
            hit = verts[i]
        else:
            rays += 1
        if hit is not None:
            hits.append(hit)
    if len(hits) < 16:
        return None

    def ang_of(h):
        rel = h[2] - centre - forward * h[0]
        a = math.atan2(rel.dot(v), rel.dot(u))
        return a if a >= 0.0 else a + 2.0 * math.pi

    hits.sort(key=ang_of)
    angs = [ang_of(h) for h in hits]
    gaps = [angs[i + 1] - angs[i] for i in range(len(angs) - 1)]
    gaps.append(angs[0] + 2.0 * math.pi - angs[-1])
    if max(gaps) > 2.5 * (2.0 * math.pi / LIP_N):
        return None
    return hits, rays


def fan_profile(fan, centre, forward):
    tip, nose = 0.0, None
    for w in wverts(fan):
        axial, rad = axial_of(w, centre, forward)
        tip = max(tip, rad)
        if rad < 0.22 and (nose is None or axial > nose):
            nose = axial
    return tip, 0.0 if nose is None else nose


def add_mesh(name, verts, faces, mat, parent, uvs=None, smooth=False, shadows=True):
    if bpy.data.objects.get(name):
        print("SKIP", name)
        return None
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    if uvs is not None:
        uv = me.uv_layers.new(name="UVMap")
        for p in me.polygons:
            for li, vi in zip(p.loop_indices, p.vertices):
                uv.data[li].uv = uvs[vi]
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if parent is not None:
        mw = ob.matrix_world.copy()
        ob.parent = parent
        ob.matrix_world = mw
    ob.visible_shadow = shadows
    return ob


def spinner_mesh(base_c, forward, radius, segs=16):
    u, v = basis(forward)
    apex = base_c + forward * 0.028
    verts = [apex, base_c]
    uvs = [(0.5, 0.5), (0.5, 0.5)]
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        arm = u * math.cos(a) + v * math.sin(a)
        verts.append(base_c + arm * radius)
        uvs.append((0.5 + 0.47 * math.cos(a), 0.5 + 0.47 * math.sin(a)))
    faces = []
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((0, 2 + i, 2 + j))
        faces.append((1, 2 + j, 2 + i))
    return verts, faces, uvs


def annulus(center, forward, r_in, r_out, segs=24):
    u, v = basis(forward)
    verts, uvs = [], []
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        arm = u * math.cos(a) + v * math.sin(a)
        verts.append(center + arm * r_in)
        verts.append(center + arm * r_out)
        for f in (0.0, 1.0):
            tr = (0.34 + 0.54 * f) * 0.5  # texture ring, transparent centre and outside
            uvs.append((0.5 + math.cos(a) * tr, 0.5 + math.sin(a) * tr))
    faces = []
    for i in range(segs):
        j = (i + 1) % segs
        faces.append((i * 2, j * 2, j * 2 + 1, i * 2 + 1))
    return verts, faces, uvs
