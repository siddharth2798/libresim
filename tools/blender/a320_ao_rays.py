"""Occlusion map for a UV2 layout. Cycles' AO bake writes an empty image in Blender 5.2,
so each kept face casts a few rays and the result is painted into its UV triangle.
"""
import array
import math

import bpy
from mathutils import Vector

SIZE = 2048
FLOOR = 0.72  # full occlusion is a light cavity; lower paints patches on the white fuselage
DIST = 2.0
RAYS = 12
LIFT = 0.02


def _hemi(n):
    gold = math.pi * (1.0 + 5.0 ** 0.5)
    out = []
    for i in range(n):
        z = (i + 0.5) / n
        r = math.sqrt(max(0.0, 1.0 - z * z))
        t = gold * i
        out.append(Vector((math.cos(t) * r, math.sin(t) * r, z)))
    return out


def _basis(normal):
    up = Vector((0.0, 0.0, 1.0)) if abs(normal.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    x = up.cross(normal).normalized()
    return x, normal.cross(x).normalized()


def _paint(acc, wgt, uvs, value):
    pts = [((u * (SIZE - 1)), (v * (SIZE - 1))) for u, v in uvs]
    for i in range(1, len(pts) - 1):
        _tri(acc, wgt, pts[0], pts[i], pts[i + 1], value)


def _tri(acc, wgt, a, b, c, value):
    minx, maxx = max(0, int(min(a[0], b[0], c[0]))), min(SIZE - 1, int(max(a[0], b[0], c[0])) + 1)
    miny, maxy = max(0, int(min(a[1], b[1], c[1]))), min(SIZE - 1, int(max(a[1], b[1], c[1])) + 1)
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-8:
        return
    if den < 0.0:
        b, c, den = c, b, -den
    for y in range(miny, maxy + 1):
        for x in range(minx, maxx + 1):
            w0 = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / den
            w1 = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / den
            if w0 >= -0.01 and w1 >= -0.01 and w0 + w1 <= 1.01:
                i = y * SIZE + x
                acc[i], wgt[i] = value, 1


def _dilate(acc, wgt):
    src = [i for i, f in enumerate(wgt) if f]
    for _ in range(8):
        nxt = []
        for i in src:
            x, y = i % SIZE, i // SIZE
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE:
                    continue
                j = ny * SIZE + nx
                if wgt[j]:
                    continue
                acc[j], wgt[j] = acc[i], 1
                nxt.append(j)
        if not nxt:
            break
        src = nxt


def _soften(acc):
    """Wide blur. Neighbouring islands then read as one shade along the skin, not patches."""
    import numpy as np
    img = np.array(acc, dtype=np.float32).reshape(SIZE, SIZE)
    sigma, rad = 32.0, 96
    x = np.arange(-rad, rad + 1, dtype=np.float32)
    k = np.exp(-0.5 * (x / sigma) ** 2)
    k /= k.sum()
    acc[:] = array.array("f", np.ascontiguousarray(_gauss(img, k, rad)).ravel())


def _gauss(img, k, rad):
    import numpy as np
    size = img.shape[0]
    tmp = np.zeros_like(img)
    p = np.pad(img, ((0, 0), (rad, rad)), mode="edge")
    for i, w in enumerate(k):
        tmp += w * p[:, i:i + size]
    out = np.zeros_like(img)
    p = np.pad(tmp, ((rad, rad), (0, 0)), mode="edge")
    for i, w in enumerate(k):
        out += w * p[i:i + size, :]
    return out


def _faces(obs, keep):
    for ob in obs:
        me, mw = ob.data, ob.matrix_world
        uv = me.uv_layers[1] if len(me.uv_layers) > 1 else None
        if uv is None:
            continue
        r3 = mw.to_3x3()
        for p in me.polygons:
            mat = me.materials[p.material_index] if p.material_index < len(me.materials) else None
            if not keep(mat.name if mat else ""):
                continue
            n = (r3 @ p.normal).normalized()
            if n.length < 0.5:
                continue
            centre = mw @ p.center
            # .uv is a live reference; copying the pair keeps each corner.
            loops = [(uv.data[li].uv.x, uv.data[li].uv.y) for li in p.loop_indices]
            yield centre, n, loops


def bake(obs, png, keep, dist=DIST):
    """Write an occlusion PNG. Returns the mean of the texels that a face covered."""
    dirs, scene = _hemi(RAYS), bpy.context.scene
    deps = bpy.context.evaluated_depsgraph_get()
    # Unpainted texels stay open. A black gutter is what the fuselage was sampling between islands.
    acc, wgt = array.array("f", [1.0]) * (SIZE * SIZE), array.array("I", [0]) * (SIZE * SIZE)
    faces, hist = 0, [0] * (RAYS + 1)
    for centre, normal, uvs in _faces(obs, keep):
        x, y = _basis(normal)
        origin = centre + normal * LIFT
        hit = 0
        for d in dirs:
            direction = (x * d.x + y * d.y + normal * d.z).normalized()
            if scene.ray_cast(deps, origin, direction, distance=dist)[0]:
                hit += 1
        hist[hit] += 1
        _paint(acc, wgt, uvs, FLOOR + (1.0 - FLOOR) * (1.0 - hit / RAYS))
        faces += 1
    print("AO HIST", hist, "texels", sum(wgt))
    _dilate(acc, wgt)
    _soften(acc)
    filled = [acc[i] for i, f in enumerate(wgt) if f]
    mean = sum(filled) / len(filled) if filled else 0.0
    # array.array foreach_set does not stick on a 2k image, and Non-Color saves black.
    import numpy as np
    acc_np = np.frombuffer(acc, dtype=np.float32)
    buf = np.ones(SIZE * SIZE * 4, dtype=np.float32)
    buf[0::4] = acc_np
    buf[1::4] = acc_np
    buf[2::4] = acc_np
    img = bpy.data.images.new("ao_bake", SIZE, SIZE, alpha=False, float_buffer=True)
    img.pixels.foreach_set(buf)
    img.filepath_raw, img.file_format = str(png), "PNG"
    img.save()
    bpy.data.images.remove(img)
    print("AO RAYS", faces, "mean", round(mean, 3), png.name)
    return mean
