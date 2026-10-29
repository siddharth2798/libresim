"""Blender (5.x) headless helper for convert_a320_cockpit.py: gives the flight-deck controls listed in
a320_lever_table.py a `pivot_<name>` empty (origin and axis from the upstream hinge helper objects) and
parents the control's mesh(es) to it, so the game can move them (aircraft/common/cockpit_levers.gd).
The meshes were separate objects upstream (fd_complete.ac); nothing is cut out of a merged mesh. Pivoted
meshes stay out of the joined static `cockpit` mesh (S.join_static only joins unparented objects)."""
import bpy
from mathutils import Vector

import a320_lever_table as T
import a320_scene as S


def build(objs):
    """objs: {AC3D object name: Blender object}. Creates the pivots in table order (children first).
    Returns ({pivot name: empty}, [problems])."""
    piv, problems = {}, []
    for r in T.rows():
        kids = []
        for n in r["objs"]:
            if n in objs:
                kids.append(objs[n])
            else:
                problems.append("%s: object %s missing" % (r["name"], n))
        kids += [piv[c] for c in r.get("children", [])]
        if not kids:
            continue
        a = Vector(r["at"])
        piv[r["name"]] = S.add_pivot(r["name"], kids, a, a + Vector(r["axis"]))
        for o in kids:  # sanity: the pivot must be near what it moves (a bad table row shows here, not in the game)
            if o.type == "MESH":
                bb = S.bbox([o])
                far = max((max(bb[i][0] - a[i], a[i] - bb[i][1], 0.0) for i in range(3)))
                if far > 0.45 and r["kind"] == "rotate":
                    problems.append("%s: pivot %.2f m from %s" % (r["name"], far, o.name))
    return piv, problems
