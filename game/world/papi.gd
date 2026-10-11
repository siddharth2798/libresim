class_name Papi
extends RefCounted
## Precision approach path indicator: 4 units on the left of the runway, abeam the ILS
## glide-slope point (or 300 m past the threshold), for a 3 degree path. Each unit shows
## white above its setting and red below: 3.5, 3.17, 2.83, 2.5 deg from the unit nearest
## the runway outward, so on the path the pilot sees 2 red (inner) + 2 white (outer).
## The colour is computed in the light shader from the camera position (mode 10 + angle);
## unit_color() is the same rule for scripts and tests.

const ANGLES := [3.5, 3.1667, 2.8333, 2.5]  # inner -> outer
const SPACING := 9.0
const INNER_GAP := 15.0  # from the runway edge to the inner unit
const LENS_H := 0.8
const DEFAULT_DIST := 300.0


## True when a unit set to angle_deg shows white to a viewer elev_deg above it.
static func is_white(elev_deg: float, angle_deg: float) -> bool:
	return elev_deg > angle_deg


static func unit_color(elev_deg: float, angle_deg: float) -> Color:
	return RunwayLightLayout.WHITE if is_white(elev_deg, angle_deg) else RunwayLightLayout.RED


## What a viewer at ENU eye sees: "R"/"W" per unit, outer unit first (left to right as
## seen on approach), e.g. "WWRR" on the 3 degree path.
static func reading(units: Array, eye: Vector3) -> String:
	var out := ""
	for k in range(units.size() - 1, -1, -1):
		var u: Vector3 = units[k].pos
		var d := eye - u
		var el := rad_to_deg(atan2(d.z, Vector2(d.x, d.y).length()))
		out += "W" if is_white(el, units[k].angle) else "R"
	return out


## Unit positions of the PAPI for end i ([{pos: Vector3 ENU, angle}], inner first), or []
## for runways too short to have one.
static func units(r: Dictionary, i: int, hf: Callable, gs_dist := -1.0) -> Array:
	if r.len < 800.0:
		return []
	var f := RunwayLightLayout.end_frame(r, i)
	var t: Vector2 = f[0]
	var d: Vector2 = f[1]
	var left := Vector2(-d.y, d.x)
	var along := gs_dist if gs_dist > 100.0 else minf(DEFAULT_DIST, r.len * 0.25)
	var out := []
	for k in 4:
		var p: Vector2 = t + d * along + left * (r.width * 0.5 + INNER_GAP + k * SPACING)
		out.append({"pos": Vector3(p.x, p.y, hf.call(p.x, p.y) + LENS_H), "angle": ANGLES[k], "dir": -d})
	return out


## Light points into s (mix-blended material) and housing transforms into boxes (ENU
## position + yaw), for the given units.
static func add_units(units_: Array, s: LightSet, boxes: Array) -> void:
	for u in units_:
		var p: Vector3 = u.pos
		var dir: Vector2 = u.dir
		for k in [-1.0, 1.0]:  # two lamps per unit, side by side
			var q: Vector2 = Vector2(p.x, p.y) + Vector2(dir.y, -dir.x) * k * 0.35 + dir * 0.5
			s.add(q.x, q.y, p.z, Color.WHITE, dir, 2.0, 0.0, false, 10.0 + u.angle, 1.5)
		boxes.append([p - Vector3(0, 0, 0.45), atan2(dir.x, dir.y)])


## A MultiMesh of grey boxes for the unit housings (ENU anchor as in LightSet).
static func housings(boxes: Array, anchor: Vector2) -> MultiMeshInstance3D:
	if boxes.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.33, 0.33)
	mat.roughness = 0.7
	bm.material = mat
	mm.mesh = bm
	mm.instance_count = boxes.size()
	for k in boxes.size():
		var p: Vector3 = boxes[k][0]
		var b := Basis(Vector3.UP, -float(boxes[k][1]))
		mm.set_instance_transform(k, Transform3D(b, Vector3(p.x - anchor.x, p.z, -(p.y - anchor.y))))
	var mi := MultiMeshInstance3D.new()
	mi.name = "papi_housings"
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
