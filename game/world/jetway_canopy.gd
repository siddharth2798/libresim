class_name JetwayCanopy
extends Node3D
## The closure of a docked jetway cab, as on a real passenger boarding bridge: a bellows canopy fixed to the hood frame whose front
## edge reaches the fuselage everywhere, and a floor plate with a rubber bumper up to the skin at the sill (JetwayCanopyMesh).
## fit() measures where the skin is: one ray per edge sample along the hood's forward axis onto the aircraft's exterior meshes
## (TriangleMesh, built once per mesh), so the edge follows the real shape (the nose taper at L1, the crown) and any cab angle.
## Without an aircraft it falls back to a round fuselage (aircraft.json ground: fuselage_r_m, door_axis_z_m above the sill).
## set_open() unfolds it (scale along x): JetwayRig lowers it after the bridge stops and folds it before the bridge moves.

const FACE_X := 17.01  # hood face (jetway.glb)
const BACK_M := 0.5  # rays start this far behind the face (a skin closer than the face still counts)
const MAX_M := 3.0  # longest reach; beyond it a sample is a miss
const GROUP := "aircraft_model"

var depths := PackedFloat32Array()
var floor_depths := PackedFloat32Array()
var fitted := false  # depths come from the aircraft's meshes (not the round-fuselage guess)
var _mi := MeshInstance3D.new()
var _r := 0.0
var _axis := 0.9


## The canopy node (child of `hood`) or null when the aircraft gives no fuselage radius.
static func build(hood: Node3D, ground: Dictionary) -> JetwayCanopy:
	var r := float(ground.get("fuselage_r_m", 0.0))
	if r <= 0.0 or hood == null:
		return null
	var c := JetwayCanopy.new()
	c.name = "Canopy"
	c.position = Vector3(FACE_X, 0.0, 0.0)
	c._r = r
	c._axis = float(ground.get("door_axis_z_m", 0.9))
	c._mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	c.add_child(c._mi)
	c._guess()
	c.scale.x = 0.01
	c.visible = false
	hood.add_child(c)
	return c


## How far in front of the face a round fuselage's skin is at hood height y: zero at the fuselage axis height.
static func depth_at(y: float, r: float, axis_above_sill: float) -> float:
	var dz := y - JetwayCanopyMesh.Y0 - axis_above_sill
	return maxf(r - sqrt(maxf(r * r - dz * dz, 0.0)), 0.0)


## 0 = folded against the hood (hidden), 1 = pressed on the skin.
static func set_open(c: JetwayCanopy, k: float) -> void:
	if c == null:
		return
	c.visible = k > 0.02
	c.scale.x = maxf(k, 0.01)


## The exterior model of the player's aircraft (AircraftModel joins GROUP), or null.
static func aircraft_exterior(tree: SceneTree) -> Node3D:
	var m := tree.get_first_node_in_group(GROUP) if tree != null else null
	return m.exterior() if m != null and m.has_method("exterior") else null


## Measure the skin in front of the hood (the cab at its docked place) and rebuild. False (round guess kept) without hits.
func fit(exterior: Node3D) -> bool:
	if exterior == null or not is_inside_tree():
		_guess()
		return false
	var meshes := _meshes_near(exterior)
	var o := JetwayCanopyMesh.outline()
	var d := _fill(_cast(o[0], meshes))
	var fd := _fill(_cast(JetwayCanopyMesh.floor_points(), meshes))
	fitted = not d.is_empty() and not fd.is_empty()
	if fitted:
		depths = d
		floor_depths = fd
	else:
		_guess()
		return false
	_rebuild()
	return true


func _guess() -> void:
	var o := JetwayCanopyMesh.outline()
	depths = PackedFloat32Array()
	for p: Vector3 in o[0]:
		depths.append(depth_at(p.y, _r, _axis) + GroundParams.DOOR_GAP_M)
	floor_depths = PackedFloat32Array()
	for p in JetwayCanopyMesh.floor_points():
		floor_depths.append(depth_at(p.y, _r, _axis) + GroundParams.DOOR_GAP_M)
	fitted = false
	_rebuild()


func _rebuild() -> void:
	_mi.mesh = JetwayCanopyMesh.build(depths, floor_depths)
	_mi.mesh.surface_set_material(0, _mat(Color(0.2, 0.205, 0.21), 0.9, 0.0))
	_mi.mesh.surface_set_material(1, _mat(Color(0.42, 0.43, 0.44), 0.55, 0.4))


## [TriangleMesh, Transform3D (global -> mesh local)] of the exterior meshes whose box reaches the space in front of the hood.
func _meshes_near(exterior: Node3D) -> Array:
	var reach := AABB(Vector3(-BACK_M, JetwayCanopyMesh.Y0 - 0.5, JetwayCanopyMesh.Z0 - 0.5), Vector3(MAX_M + BACK_M, 3.5, 3.6))
	var box := global_transform.scaled_local(Vector3(1.0 / maxf(scale.x, 1e-3), 1.0, 1.0)) * reach  # unfolded frame: it fits while folded
	var out := []
	for n in exterior.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if not (mi.global_transform * mi.get_aabb()).intersects(box):
			continue
		if not mi.has_meta("canopy_tm"):
			mi.set_meta("canopy_tm", mi.mesh.generate_triangle_mesh())
		var tm: TriangleMesh = mi.get_meta("canopy_tm")
		if tm != null:
			out.append([tm, mi.global_transform.affine_inverse()])
	return out


## Forward distance from the face to the nearest skin at each point (NAN: no skin within MAX_M).
func _cast(pts: Array, meshes: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var dir := global_transform.basis.x.normalized()
	var unit := global_transform.basis.x.length()  # world metres per local unit (the canopy is scaled along x while folded)
	var parent_unit := unit / maxf(scale.x, 1e-3)  # ... and once unfolded (scale 1): depths are stored in those units
	for p: Vector3 in pts:
		var from := global_transform * Vector3(p.x - BACK_M / unit, p.y, p.z)
		var best := INF
		for m in meshes:
			var inv: Transform3D = m[1]
			var hit: Dictionary = (m[0] as TriangleMesh).intersect_ray(inv * from, (inv.basis * dir).normalized())
			if not hit.is_empty():
				var at: Vector3 = inv.affine_inverse() * (hit.position as Vector3)
				best = minf(best, (at - from).dot(dir))
		out.append(clampf(best - BACK_M, 0.0, MAX_M) / parent_unit if best <= MAX_M + BACK_M else NAN)
	return out


## Misses take the nearest hit along the edge. Empty when nothing hit.
static func _fill(d: PackedFloat32Array) -> PackedFloat32Array:
	var any := false
	for v in d:
		any = any or not is_nan(v)
	if not any:
		return PackedFloat32Array()
	for i in d.size():
		if not is_nan(d[i]):
			continue
		for s in range(1, d.size()):
			var j := i - s if i - s >= 0 and not is_nan(d[i - s]) else (i + s if i + s < d.size() and not is_nan(d[i + s]) else -1)
			if j >= 0:
				d[i] = d[j]
				break
	return d


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
