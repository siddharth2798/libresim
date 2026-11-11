"""The A320 exterior skin as a BVH, for flight-deck parts built in interior.glb (same frame) that must stay inside it."""
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

EXT = Path(__file__).resolve().parents[2] / "game/aircraft/a320/models/exterior.glb"


def skin():
    """BVH of the exterior glb (same frame as interior.glb); the imported objects are removed again."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(EXT))
    new = [o for o in bpy.data.objects if o not in before]
    verts, polys = [], []
    for o in new:
        if o.type != "MESH":
            continue
        base = len(verts)
        verts += [o.matrix_world @ v.co for v in o.data.vertices]
        polys += [[base + i for i in p.vertices] for p in o.data.polygons]
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    return BVHTree.FromPolygons(verts, polys)


def roof(skin, x, floor, clear=0.03):
    """y -> the skin height above (x, y) at both faces of the wall, less `clear` (a ray up from 0.8 m above the floor)."""
    def f(y):
        zs = []
        for xx in (x, x + 0.028):
            hit = skin.ray_cast(Vector((xx, y, floor + 0.8)), Vector((0, 0, 1)), 3.0)
            zs.append(hit[0].z if hit[0] is not None else floor + 0.8)
        return min(zs) - clear
    return f
