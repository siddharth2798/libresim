"""A320-200 exterior small parts on the existing exterior.glb (no AC3D re-convert).
Blender -b --factory-startup --python tools/blender/a320_details.py
New meshes share the fuselage body's parent. Export is a320_scene.export_glb.
Stops and restores /tmp/exterior.glb.bak if a node drops or a pivot_* moves (1 mm / 0.1 deg).
The glb has no a320_plain; the APU cavity reuses a320_engine at its black texel.
"""
import json
import math
import shutil
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a320_scene as S  # noqa: E402

GLB = S.ROOT / "game/aircraft/a320/models/exterior.glb"
BAK = Path("/tmp/exterior.glb.bak")
DARK_UV = (0.375, 0.875)

def glb_json(path):
    data = Path(path).read_bytes()
    n = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20:20 + n])

def node_table(js):
    nodes, parent, out = js["nodes"], {}, {}
    for n in nodes:
        for c in n.get("children", []):
            parent[nodes[c]["name"]] = n.get("name")
    for n in nodes:
        out[n["name"]] = (n.get("translation"), n.get("rotation"), parent.get(n["name"]))
    return out

def q_deg(a, b):
    def nrm(q):
        q = q or [0, 0, 0, 1]
        L = math.sqrt(sum(x * x for x in q)) or 1.0
        return [x / L for x in q]
    a, b = nrm(a), nrm(b)
    return math.degrees(2 * math.acos(min(1.0, abs(sum(x * y for x, y in zip(a, b))))))

def vlen(a, b):
    a, b = a or [0, 0, 0], b or [0, 0, 0]
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))

def wverts(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]

def shoot(body, origin, direction):
    inv = body.matrix_world.inverted()
    ok, loc, nor, _i = body.ray_cast(inv @ origin, (inv.to_3x3() @ direction).normalized())
    if not ok:
        return None
    w = body.matrix_world
    return w @ loc, (w.to_3x3() @ nor).normalized()

def merge(*parts):
    verts, faces = [], []
    for vs, fs in parts:
        b = len(verts)
        verts.extend(vs)
        faces.extend(tuple(i + b for i in f) for f in fs)
    return verts, faces

def cylinder(p0, p1, r, segs=8):
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

def box(o, x, y, z):
    vs = [o + x * i + y * j + z * k for i in (0, 1) for j in (0, 1) for k in (0, 1)]
    fs = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    return vs, fs

def dome(c, rx, ry, h, seg=8):
    ax, ay, n = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    verts = [c + n * h]
    for f, s in ((0.5, 0.65), (1.0, 1.0)):
        for i in range(seg):
            a = 2 * math.pi * i / seg
            verts.append(c + n * (h * (1 - f)) + (ax * math.cos(a) * rx + ay * math.sin(a) * ry) * s)
    faces = []
    for i in range(seg):
        j = (i + 1) % seg
        faces += [(0, 1 + i, 1 + j), (1 + i, 1 + seg + i, 1 + seg + j, 1 + j)]
    return verts, faces

def add_obj(body, name, verts, faces, mat, mats=None, dark=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.validate()
    me.materials.append(mat)
    if dark is not None:
        me.materials.append(dark)
        uv = me.uv_layers.new(name="UVMap")
        for p, m in zip(me.polygons, mats):
            p.material_index = m
            if m:
                for li in p.loop_indices:
                    uv.data[li].uv = DARK_UV
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = body.parent
    return ob

def side_out(nor, side):
    flat = Vector((nor.x, nor.y, 0))
    return (flat if flat.length > 0.25 else Vector((0, side, 0))).normalized()

def window_line(body, right):
    me, mw, gi = body.data, body.matrix_world, body.data.materials.find("a320_glass")
    r3, xs, zs = mw.to_3x3(), [], []
    for p in me.polygons:
        if p.material_index != gi or abs((r3 @ p.normal).normalized().dot(right)) < 0.5:
            continue
        for vi in p.vertices:
            c = mw @ me.vertices[vi].co
            xs.append(c.x)
            zs.append(c.z)
    return min(xs), max(xs), min(zs)

def te_at(vs, y):
    y = min(vs, key=lambda v: abs(v.y - y)).y
    return max((v for v in vs if abs(v.y - y) < 0.9), key=lambda v: v.x)

def te_frac(ob, axis, t):
    mw, key = ob.matrix_world, (lambda v: v.y) if axis == "y" else (lambda v: v.z)
    vs = [mw @ v.co for v in ob.data.vertices]
    lo, hi = min(map(key, vs)), max(map(key, vs)); target, best = lo + (hi - lo) * t, None
    for e in ob.data.edges:
        a, b = vs[e.vertices[0]], vs[e.vertices[1]]; den = key(b) - key(a)
        if den and (key(a) - target) * (key(b) - target) <= 0:
            p = a.lerp(b, (target - key(a)) / den); best = p if best is None or p.x > best.x else best
    return best if best is not None else min(vs, key=lambda v: abs(key(v) - target))

def span_y(vs, t):
    ys = [v.y for v in vs]
    inn, out = min(ys, key=abs), max(ys, key=abs)
    return inn + (out - inn) * t

def main():
    src = node_table(js := glb_json(GLB))
    mats_before = [m["name"] for m in js["materials"]]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(GLB))
    body = bpy.data.objects["body"]
    names = {o.name for o in bpy.data.objects}
    if "detail_pitot_l" in names:
        print("DETAILS PRESENT, not adding again")
        return
    pivots = {o.name: o.matrix_world.copy() for o in bpy.data.objects if o.name.startswith("pivot_")}
    before = S.triangles()
    print("TRIANGLES", before)
    vs = wverts(body)
    nose = min(vs, key=lambda v: v.x if abs(v.y) < 0.4 else 1e9)
    tail = max(vs, key=lambda v: v.x if abs(v.y) < 0.8 else -1e9)
    fin = max(vs, key=lambda v: v.z if abs(v.y) < 1 and v.x > 8 else -1e9)
    aft = (tail - nose).normalized()
    up = (fin - tail)
    up = (up - aft * up.dot(aft)).normalized()
    right = up.cross(aft).normalized()
    rnd = lambda v: tuple(round(c, 3) for c in v)
    print("LANDMARKS nose", rnd(nose), "tail", rnd(tail), "tip+", rnd(max(vs, key=lambda v: v.y)),
          "tip-", rnd(min(vs, key=lambda v: v.y)), "fin", rnd(fin))
    print("AXES aft", rnd(aft), "up", rnd(up), "right", rnd(right))
    for n in ("pivot_fan_L", "pivot_fan_R"):
        print("NACELLE", n[-1], rnd(bpy.data.objects[n].matrix_world.translation))
    metal, dark = bpy.data.materials["a320_plain_333"], bpy.data.materials["a320_engine"]
    wx0, wx1, wz = window_line(body, right)
    print("SIDE WINDOW x", round(wx0, 3), round(wx1, 3), "zmin", round(wz, 3))
    px, pz = wx0 - 0.12, wz - 0.22  # just aft of the radome, below the side-window line; +X is aft

    def hit_side(x, z, side):
        return shoot(body, Vector((x, side * 8.0, z)), Vector((0, -side, 0)))

    def pitot(name, x, z, side):
        loc, nor = hit_side(x, z, side)
        out = side_out(nor, side)
        elbow = loc + out * 0.18
        tip = elbow + Vector((-0.25, side * 0.02, 0))
        add_obj(body, name, *merge(cylinder(loc, elbow, 0.013, 8), cylinder(elbow, tip, 0.0075, 8)), metal)

    pitot("detail_pitot_l", px, pz, -1)
    pitot("detail_pitot_r", px, pz, 1)
    pitot("detail_pitot_standby", px + 0.28, pz - 0.32, -1)
    ax, az = wx0 + 0.78 * (wx1 - wx0), wz - 0.10

    def aoa(name, side):
        loc, nor = hit_side(ax, az, side)
        out = side_out(nor, side)
        root = loc + out * 0.04
        plate = root + Vector((0.02, 0, -0.028)) - out * 0.0025
        add_obj(body, name, *merge(cylinder(loc, root, 0.007, 6),
                                    box(plate, Vector((-0.105, 0, 0)), Vector((0, 0, 0.058)), out * 0.005)), metal)

    aoa("detail_aoa_l", -1)
    aoa("detail_aoa_r", 1)
    loc, nor = hit_side(px + 0.85, pz - 0.16, -1)
    out = side_out(nor, -1)
    elbow = loc + out * 0.11
    add_obj(body, "detail_tat", *merge(cylinder(loc, elbow, 0.01, 6),
                                        cylinder(elbow, elbow + Vector((-0.09, -0.02, -0.025)), 0.011, 6)), metal)

    def blade(name, loc, grow, height, chord, thick):
        origin = loc - Vector((chord * 0.35, thick * 0.5, 0))
        add_obj(body, name, *box(origin, Vector((chord, 0, 0)), Vector((0, thick, 0)), grow * height + Vector((0.03, 0, 0))), metal)

    crown = shoot(body, Vector((0.0, 0, 12)), Vector((0, 0, -1)))
    blade("detail_vhf_upper", crown[0], Vector((0, 0, 1)), 0.32, 0.10, 0.014)
    belly = shoot(body, Vector((-8.5, 0, -8)), Vector((0, 0, 1)))
    blade("detail_vhf_lower", belly[0], Vector((0, 0, -1)), 0.18, 0.08, 0.012)
    fin_x = next(x for i in range(90, 170) if (h := shoot(body, Vector((x := i / 10, 0, 12)), Vector((0, 0, -1))))
                 and h[0].z > crown[0].z + 0.4)
    print("FIN ROOT x", fin_x)
    for i, x in enumerate((fin_x - 2.3, fin_x - 1.35)):
        h = shoot(body, Vector((x, 0, 12)), Vector((0, 0, -1)))
        add_obj(body, "detail_gps_%d" % (i + 1), *dome(h[0], 0.075, 0.045, 0.032), metal)

    wicks = []
    for sgn, ail_n, flap_n in ((-1, "AileronL", "FlapL2"), (1, "AileronR", "FlapR2")):
        av, fv = wverts(bpy.data.objects[ail_n]), wverts(bpy.data.objects[flap_n])
        wicks.append((te_at(fv, span_y(fv, 0.72)), Vector((1, 0, 0))))
        wicks += [(te_at(av, span_y(av, t)), Vector((1, 0, 0))) for t in (0.32, 0.70)]
        tip = max((v for v in vs if v.y * sgn > 17.2), key=lambda v: (abs(v.y), v.z))
        wicks.append((tip, Vector((0.55, 0.3 * sgn, 0.8))))
    for name, axis, ts, d in (("ElevatorL", "y", (0.40, 0.78), Vector((1, 0, 0))),
                              ("ElevatorR", "y", (0.40, 0.78), Vector((1, 0, 0))),
                              ("Rudder", "z", (0.28, 0.55, 0.82), Vector((1, 0, 0.08)))):
        wicks += [(te_frac(bpy.data.objects[name], axis, t), d) for t in ts]
    for i, (p, d) in enumerate(wicks, 1):
        d = d.normalized()
        add_obj(body, "detail_wick_%02d" % i, *cylinder(p + d * 0.006, p + d * 0.12, 0.0032, 5), metal)
    print("WICKS", len(wicks))

    h = shoot(body, Vector((tail.x - 1.15, 4.0, tail.z)), Vector((0, -1, 0)))
    axis = Vector((0.72, 0.68, 0.08)).normalized()
    up_a = (Vector((0, 0, 1)) - axis * axis.z).normalized()
    wide, seg = axis.cross(up_a).normalized(), 14

    def ring(c, rw, rh):
        return [c + wide * (rw * math.cos(a)) + up_a * (rh * math.sin(a)) for i in range(seg) for a in (2 * math.pi * i / seg,)]

    mouth, inner = h[0] + axis * 0.015, h[0] - axis * 0.16
    rings = ring(h[0] + axis * 0.04, 0.16, 0.20) + ring(mouth, 0.145, 0.185) + ring(mouth, 0.115, 0.155) + ring(inner, 0.09, 0.125)
    def strip(n0):
        return [(n0 + i, n0 + (i + 1) % seg, n0 + seg + (i + 1) % seg, n0 + seg + i) for i in range(seg)]
    faces, mats_f = strip(0) + strip(2 * seg), [0] * seg + [1] * seg
    rings.append(inner)
    for i in range(seg):
        faces.append((len(rings) - 1, 3 * seg + (i + 1) % seg, 3 * seg + i))
        mats_f.append(1)
    add_obj(body, "detail_apu_exhaust", rings, faces, metal, mats_f, dark)
    dhit = shoot(body, Vector((6.8, 0.2, -8)), Vector((0, 0, 1)))
    add_obj(body, "detail_drain_mast", *box(dhit[0] - Vector((0.015, 0.004, 0)), Vector((0.055, 0, 0)),
                                            Vector((0, 0.008, 0)), Vector((0.035, 0, -0.18))), metal)

    after = S.triangles()
    new = sorted(o.name for o in bpy.data.objects if o.name.startswith("detail_"))
    print("TRIANGLES", after, "DELTA", after - before)
    print("NEW OBJECTS", len(new), new)
    missing, bad = sorted(names - {o.name for o in bpy.data.objects}), []
    for n, m in pivots.items():
        o = bpy.data.objects.get(n)
        dt = (o.matrix_world.translation - m.translation).length if o else 9
        ang = math.degrees(m.to_quaternion().rotation_difference(o.matrix_world.to_quaternion()).angle) if o else 9
        if o is None or dt > 0.001 or ang > 0.1:
            bad.append((n, round(dt, 5), round(ang, 4)))
    ok = not missing and not bad
    print("PIVOT ASSERT", "OK" if ok else "FAIL", "missing", missing, "moved", bad)
    shutil.copy2(GLB, BAK)
    if not ok:
        shutil.copy2(BAK, GLB)
        raise SystemExit(1)
    S.export_glb(GLB)
    got = node_table(js2 := glb_json(GLB))
    gone = [k for k in src if k not in got]
    moved = [k for k, (t, r, par) in src.items() if k in got and (got[k][2] != par or vlen(t, got[k][0]) > 0.001 or q_deg(r, got[k][1]) > 0.1)]
    mats_after = [m["name"] for m in js2["materials"]]
    file_ok = not gone and not moved and mats_after == mats_before
    print("EXPORT CHECK", "OK" if file_ok else "FAIL", "gone", gone, "moved", len(moved), "mats", mats_after)
    if not file_ok:
        shutil.copy2(BAK, GLB)
        raise SystemExit(1)

main()
