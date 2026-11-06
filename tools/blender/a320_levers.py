"""Blender (5.x) headless helper for convert_a320_cockpit.py: gives the flight-deck controls listed in
a320_lever_table.py a `pivot_<name>` empty (origin and axis from the upstream hinge helper objects) and
parents the control's mesh(es) to it, so the game can move them (aircraft/common/cockpit_levers.gd).
The meshes were separate objects upstream (fd_complete.ac); nothing is cut out of a merged mesh. Pivoted
meshes stay out of the joined static `cockpit` mesh (S.join_static only joins unparented objects)."""
import bpy
from mathutils import Vector

import a320_lever_table as T
import a320_scene as S


def _mark_lamp(obj, lamp_name):
    """Own material `a320_fd_lamp_<pivot>` so the game can light this face without lighting the panel."""
    src = obj.data.materials[0] if obj.data.materials else None
    mat = src.copy() if src is not None else S._principled(lamp_name)
    mat.name = "a320_fd_lamp_" + lamp_name[len("lamp_"):]
    obj.name = lamp_name
    obj.data = obj.data.copy()
    obj.data.name = lamp_name
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def build(objs):
    """objs: {AC3D object name: Blender object}. Creates the pivots in table order (children first).
    Returns ({pivot name: empty}, [problems]). A row's `lamps` are parented too and renamed lamp_<pivot>."""
    piv, problems = {}, []
    for r in T.rows():
        kids = []
        for n in list(r["objs"]) + list(r.get("lamps", [])):
            if n not in objs:
                problems.append("%s: object %s missing" % (r["name"], n))
            elif objs[n] not in kids:
                kids.append(objs[n])
        kids += [piv[c] for c in r.get("children", [])]
        if not kids:
            continue
        a = Vector(r["at"])
        piv[r["name"]] = S.add_pivot(r["name"], kids, a, a + Vector(r["axis"]))
        for n in r.get("lamps", []):
            if n in objs:
                _mark_lamp(objs[n], "lamp_" + r["name"])
        for o in kids:  # sanity: the pivot must be near what it moves (a bad table row shows here, not in the game)
            if o.type == "MESH":
                bb = S.bbox([o])
                far = max((max(bb[i][0] - a[i], a[i] - bb[i][1], 0.0) for i in range(3)))
                if far > 0.45 and r["kind"] == "rotate":
                    problems.append("%s: pivot %.2f m from %s" % (r["name"], far, o.name))
    return piv, problems
