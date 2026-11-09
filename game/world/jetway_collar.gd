class_name JetwayCollar
extends RefCounted
## The rubber canopy of a docked jetway: a skirt from the hood face's edge forward to the fuselage skin. The hood face is flat and
## 2.6 x 2.5 m; the fuselage curves away from it (about 1 m at the top edge), so without the skirt daylight shows round the hood.
## Depth at a height comes from a round fuselage (aircraft.json ground: fuselage_r_m, door_axis_z_m = fuselage axis above the door
## sill; the door centre line is where the face touches). The skirt unfolds (scale along x) as the bridge docks.

const FACE_X := 17.01  # hood face (jetway.glb)
const Y0 := 3.752  # hood bottom = the cab floor = the door sill
const Y1 := 6.252
const Z0 := -1.34
const Z1 := 1.26
const OVERLAP_M := 0.05
const STEPS := 10


## The skirt node (child of `hood`) or null when the aircraft gives no fuselage radius.
static func build(hood: Node3D, ground: Dictionary) -> Node3D:
	var r := float(ground.get("fuselage_r_m", 0.0))
	if r <= 0.0 or hood == null:
		return null
	var n := Node3D.new()
	n.name = "Collar"
	n.position = Vector3(FACE_X, 0.0, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(r, float(ground.get("door_axis_z_m", 0.9)))
	mi.material_override = _rubber()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	n.add_child(mi)
	n.scale.x = 0.01
	n.visible = false
	hood.add_child(n)
	return n


## How far in front of the face the skin is at hood height y (hood-local): round fuselage of radius r whose axis is
## axis_above_sill above the cab floor; zero at the door centre line (the face touches the skin there).
static func depth_at(y: float, r: float, axis_above_sill: float) -> float:
	var dz := y - Y0 - axis_above_sill
	var half := sqrt(maxf(r * r - dz * dz, 0.0))
	var half0 := sqrt(r * r - 0.0)  # at the axis height the skin is r out
	return maxf(half0 - half, 0.0) + OVERLAP_M


static func mesh(r: float, axis_above_sill: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	# ring of points around the face outline, each with its forward point: a quad strip all the way round
	var pts: Array[Vector2] = []  # (y, z) on the face outline, counter-clockwise
	for i in STEPS:
		pts.append(Vector2(Y0, lerpf(Z0, Z1, float(i) / STEPS)))
	for i in STEPS:
		pts.append(Vector2(lerpf(Y0, Y1, float(i) / STEPS), Z1))
	for i in STEPS:
		pts.append(Vector2(Y1, lerpf(Z1, Z0, float(i) / STEPS)))
	for i in STEPS:
		pts.append(Vector2(lerpf(Y1, Y0, float(i) / STEPS), Z0))
	for p in pts:
		v.append(Vector3(0.0, p.x, p.y))
		v.append(Vector3(depth_at(p.x, r, axis_above_sill), p.x, p.y))
	var n := pts.size()
	for i in n:
		var a := i * 2
		var b := ((i + 1) % n) * 2
		idx.append_array([a, a + 1, b, b, a + 1, b + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func _rubber() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.06)
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## 0 = folded away (hidden), 1 = reaching the skin.
static func set_open(collar: Node3D, k: float) -> void:
	if collar == null:
		return
	collar.visible = k > 0.02
	collar.scale.x = maxf(k, 0.01)
