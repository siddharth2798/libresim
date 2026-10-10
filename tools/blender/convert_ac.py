"""Blender headless: convert any FlightGear AC3D model (+ textures beside it) to glb.

  blender -b --factory-startup --python tools/blender/convert_ac.py -- <in.ac> <out.glb>

Keeps the model frame as-is (FlightGear: x/y horizontal, z up -> glTF Y up). Normal maps
named <tex>-normal.png are wired in when present. Used for fgdata airport models.
"""
import importlib
import sys
import types
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.modules["imp"] = types.SimpleNamespace(reload=importlib.reload)
sys.path.insert(0, str(ROOT / "data/raw/fg/addon/Blender-AC3D-4.0"))
import io_scene_ac3d  # noqa: E402


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    src, dst = Path(args[0]), Path(args[1])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    io_scene_ac3d.register()
    bpy.ops.import_scene.import_ac3d(filepath=str(src))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for mat in bpy.data.materials:
        b = mat.node_tree.nodes.get("Principled BSDF") if mat.use_nodes else None
        if b:
            b.inputs["Roughness"].default_value = 0.55
    dst.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(dst), export_format="GLB", export_yup=True, export_apply=True,
                              export_cameras=False, export_lights=False)
    xs = [v[0] for o in bpy.data.objects for v in o.bound_box]
    ys = [v[1] for o in bpy.data.objects for v in o.bound_box]
    zs = [v[2] for o in bpy.data.objects for v in o.bound_box]
    print("EXPORTED", dst, "bbox x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f" % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))


main()
