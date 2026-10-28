"""Blender (5.x) headless: A320 flight deck (FlightGear A320-family fd_complete.ac, GPL-2.0-only)
-> game/aircraft/a320/models/interior.glb  (+ models/interior_info.json: eye point and display rectangles)

Usage (repo root, after tools/24_a320_models_fetch.sh and tools/24_a320_textures.py):
  /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --python tools/blender/convert_a320_cockpit.py

Frame: same as exterior.glb (structural = FlightGear model frame): the flight deck is placed with upstream's offset
(-16.47411, -0.00015, -0.09483). Changes (change log in third_party/a320-family/SOURCE.md): seats, headsets, EFB,
HUD and IAE variants, the rear of the cabin (x > -15.75) are dropped; the rest is cleaned (planar dissolve) and
decimated to the triangle budget; the Nasal-driven display sockets are replaced by plain black quads named
screen_<display> (UV 0..1, normal toward the pilot) that cockpit code can texture with a live display;
materials are Principled BSDF from the (<= 2048 px, "Airbus A320 Family" legend painted out) textures.
Static: levers, sidesticks and switches are not animated in this first version.
"""
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a320_scene as S  # noqa: E402

RAW = S.ROOT / "data/raw/fg/a320/Models"
OUT = S.ROOT / "game/aircraft/a320/models"
OFF = (-16.47411, -0.00015, -0.09483)
BUDGET = 95000
EYE = (-16.25, -0.50, 0.52)  # captain's eye (structural frame); checked with tests/debug_a320_model.tscn
DROP_PREFIX = ("Headset", "seat", "EFB_", "extinguisher", "hud", "visor", "fcu_hud", "fcu_labels_hud", "ovh_eng_iae", "glare_ovh_eng_iae",
               "mcdu1.screen", "mcdu2.screen", "fcu_panel_emit", "batt_voltage", "dcduScreen")
SCREENS = {  # (file, object) -> screen name; instrument .ac quads are in the flight-deck frame
    ("Instruments/PFD/res/PFD1.ac", "pfd1.screen"): "pfd_cpt", ("Instruments/PFD/res/PFD2.ac", "pfd2.screen"): "pfd_fo",
    ("Instruments/ND/res/ND.ac", "ND.screen"): "nd_cpt", ("Instruments/ND/res/ND_R.ac", "ND_R.screen"): "nd_fo",
    ("Instruments/Upper-ECAM/res/Upper-ECAM.ac", "uecam.screen"): "ewd", ("Instruments/Lower-ECAM/res/Lower-ECAM.ac", "lecam.screen"): "sd",
    ("Instruments/IESI/res/IESI.ac", "iesi.screen"): "iesi",
}


def keep(name):
    return not name.startswith(DROP_PREFIX)


def face_keep(name, c):
    return c[0] < -15.75 and abs(c[1]) < 1.7


def tri(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def decimate(objs, target):
    """Planar dissolve every mesh over 100 triangles, then collapse-decimate (all over 60 triangles by one
    ratio) so the total reaches `target`."""
    for o in objs:
        if tri(o) > 100:
            bpy.context.view_layer.objects.active = o
            m = o.modifiers.new("pd", "DECIMATE")
            m.decimate_type = "DISSOLVE"
            m.angle_limit = 0.035
            m.delimit = {"UV", "MATERIAL"}
            bpy.ops.object.modifier_apply(modifier=m.name)
    small = sum(tri(o) for o in objs if tri(o) <= 60)
    bigt = sum(tri(o) for o in objs if tri(o) > 60)
    ratio = max(0.05, min(1.0, (target - small) / max(bigt, 1)))
    print("decimate: small", small, "big", bigt, "ratio %.3f" % ratio)
    if ratio < 1.0:
        for o in objs:
            if tri(o) > 60:
                bpy.context.view_layer.objects.active = o
                m = o.modifiers.new("dc", "DECIMATE")
                m.decimate_type = "COLLAPSE"
                m.ratio = ratio
                m.use_collapse_triangulate = True
                bpy.ops.object.modifier_apply(modifier=m.name)


def screen_info(ob, name):
    me = ob.data
    vs = [ob.matrix_world @ v.co for v in me.vertices]
    uvs = {}
    for p in me.polygons:
        for li, vi in zip(p.loop_indices, p.vertices):
            uvs[vi] = tuple(me.uv_layers[0].data[li].uv)
    cen = sum(vs, Vector()) / len(vs)
    i0 = min(uvs, key=lambda i: uvs[i][0] + uvs[i][1])  # uv (0,0) corner
    iu = max(uvs, key=lambda i: uvs[i][0] - uvs[i][1])
    iv = max(uvs, key=lambda i: uvs[i][1] - uvs[i][0])
    u, v = vs[iu] - vs[i0], vs[iv] - vs[i0]
    n = u.cross(v).normalized()
    return {"centre": [round(c, 4) for c in cen], "width": round(u.length, 4), "height": round(v.length, 4),
            "u_dir": [round(c, 4) for c in u.normalized()], "v_dir": [round(c, 4) for c in v.normalized()],
            "normal": [round(c, 4) for c in n]}


def main():
    S.reset()
    objs = S.import_ac(RAW / "FlightDeck/res/fd_complete.ac", keep, OFF, face_keep=face_keep)
    print("flight deck objects", len(objs), "triangles", S.triangles())
    decimate(list(objs.values()), BUDGET)
    shell = S.join_static(list(bpy.data.objects), "cockpit")
    shell.data.validate(verbose=True)
    mat = S._principled("a320_screen", (0.01, 0.012, 0.015), rough=0.15)
    info = {"eye": list(EYE), "panel_mesh": "cockpit", "screens": {}}
    for (f, on), sname in SCREENS.items():
        o = S.import_ac(RAW / f, lambda n, on=on: n == on, OFF)[on]
        o.name = "screen_" + sname
        o.data.materials.clear()
        o.data.materials.append(mat)
        info["screens"][sname] = screen_info(o, sname)
        if info["screens"][sname]["normal"][0] < 0:  # face the pilot (+x is aft)
            for p in o.data.polygons:
                p.flip()
            info["screens"][sname] = screen_info(o, sname)
    # MCDU screens: quads from the flight deck file itself
    for on, sname in (("mcdu1.screen", "mcdu_cpt"), ("mcdu2.screen", "mcdu_fo")):
        o = S.import_ac(RAW / "FlightDeck/res/fd_complete.ac", lambda n, on=on: n == on, OFF)[on]
        o.name = "screen_" + sname
        o.data.materials.clear()
        o.data.materials.append(mat)
        info["screens"][sname] = screen_info(o, sname)
        if info["screens"][sname]["normal"][0] < 0:
            for p in o.data.polygons:
                p.flip()
            info["screens"][sname] = screen_info(o, sname)
    S.smooth_by_angle(40.0)
    mats = sorted({m.name for m in bpy.data.materials if m.users})
    print("TRIANGLES", S.triangles(), "MATERIALS", len(mats), mats)
    S.export_glb(OUT / "interior.glb")
    (OUT / "interior_info.json").write_text(json.dumps(info, indent=1))
    print("EXPORTED", OUT / "interior.glb", (OUT / "interior.glb").stat().st_size // 1024, "KB")


main()
