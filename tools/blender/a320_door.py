"""A320 passenger doors L1 R1 L2 R2 as a glb: game/aircraft/a320/models/doors.glb.
Blender -b --factory-startup --python tools/blender/a320_door.py

Each door is built on the real exterior skin around its painted outline (models/exterior.glb, mesh `body`, ray
cast per vertex), from aircraft.json ground.doors (x_m, side, sill_z_m, w_m, h_m). Frame: structural metres =
the exterior glb frame (x aft, y right, z up, origin_m 0); exported Y-up like exterior.glb.
Nodes per door <id> (aircraft/common/cabin_door_model.gd moves them):
  <id>_leaf             the door: outer skin with window and handle flap, edge and seal, inner lining and
                        fittings (moves with CabinDoorPanel.offset, never turns)
  <id>_handle           door control handle, modelled down; origin on its hinge (turns up while the door unlocks)
  <id>_lock_locked / _unlocked   locking indicator faces (green / red)
  <id>_arm              hinge arm; origin on the pivot pin in the forward frame (turns about the vertical)
  <id>_arm/<id>_arm_end empty on the door end of the arm
  <id>_frame            the open doorway and the galley beyond (drawn through the portal)
  <id>_mask             the portal: painted outline just outside the skin
"""
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a320_door_geom as G  # noqa: E402
import a320_door_parts as P  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
EXTERIOR = ROOT / "game/aircraft/a320/models/exterior.glb"
OUT = ROOT / "game/aircraft/a320/models/doors.glb"
AIRCRAFT = ROOT / "game/aircraft/a320/aircraft.json"
COPYRIGHT = "GPL-2.0-only; libresim A320 door, fitted to the FlightGear-derived exterior (third_party/a320-family/SOURCE.md)"


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def build_door(body, spec, mats):
    w, hh, side = float(spec["w_m"]), float(spec["h_m"]), (1 if float(spec["side"]) > 0 else -1)
    xf = float(spec["x_m"]) - w / 2
    s = G.Skin(body, xf, float(spec["sill_z_m"]), side)
    did = spec["id"]
    made = [P.leaf(s, w, hh).build(did + "_leaf", mats)]
    for locked in (True, False):
        made.append(P.lock_flag(s, locked).build(did + ("_lock_locked" if locked else "_lock_unlocked"), mats))
    hp, hinge = P.handle(s)
    made.append(hp.build(did + "_handle", mats, hinge))
    ap, piv, end = P.arm(s, w)
    arm = ap.build(did + "_arm", mats, piv)
    made.append(arm)
    tip = bpy.data.objects.new(did + "_arm_end", None)
    bpy.context.scene.collection.objects.link(tip)
    tip.parent = arm
    tip.location = end - piv
    made.append(P.frame(s, w, hh, piv).build(did + "_frame", mats))
    made.append(P.mask(s, w, hh).build(did + "_mask", mats))
    o = s.frame(w / 2, hh / 2)[0]
    print("DOOR %s centre skin (%.3f %.3f %.3f) pivot (%.3f %.3f %.3f) end (%.3f %.3f %.3f) arm %.3f" % (
        did, o.x, o.y, o.z, piv.x, piv.y, piv.z, end.x, end.y, end.z, (end - piv).length))
    return made


def main():
    doors = [d for d in json.loads(AIRCRAFT.read_text())["ground"]["doors"] if d.get("kind") == "passenger"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(EXTERIOR))
    body = bpy.data.objects["body"]
    imported = [o for o in bpy.data.objects]
    mats = [G.material(k, *v) for k, v in P.MATS.items()]
    made = []
    for spec in doors:
        made += build_door(body, spec, mats)
    for o in imported:
        bpy.data.objects.remove(o, do_unlink=True)
    for o in made:
        if o.type == "MESH":
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_smooth_by_angle(angle=0.6)
    for o in made:
        if o.type == "MESH":
            print("TRIS", o.name, tris(o))
    print("TRIS TOTAL", sum(tris(o) for o in made if o.type == "MESH"))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", export_yup=True, export_apply=True,
                              export_cameras=False, export_lights=False, export_copyright=COPYRIGHT)
    print("WROTE", OUT)


main()
