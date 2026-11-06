class_name ControlTower
extends RefCounted
## A control-tower cab at each published tower point (airport_ops.json "towers").
## The cab roof is at the same height as the aerodrome beacon (airport_beacon.gd MAST),
## so the flash sits on the roof. The shape is a generic shaft and glass cab, not a
## measured copy of any one tower. Points within 40 m are one tower.


const CAB_ROOF := 32.0
static var _concrete: StandardMaterial3D
static var _glass: StandardMaterial3D


static func place_all(root: Node3D, solids: OpsSolids, towers: Array, hf: Callable) -> void:
	var kept: Array[Vector2] = []
	for tw in towers:
		var p := Vector2(float(tw.x), float(tw.y))
		var near := false
		for q in kept:
			if p.distance_to(q) < 40.0:
				near = true
				break
		if near:
			continue
		kept.append(p)
		_one(root, solids, p.x, p.y, hf.call(p.x, p.y))


static func _one(root: Node3D, solids: OpsSolids, x: float, y: float, ground: float) -> void:
	var base := Vector3(x, ground, -y)
	_cyl(root, 2.8, 3.2, 26.0, _shaft(), base + Vector3(0, 13.0, 0))
	_cyl(root, 5.4, 5.4, 5.4, _cab(), base + Vector3(0, 28.7, 0))
	_cyl(root, 6.0, 6.0, 0.7, _shaft(), base + Vector3(0, CAB_ROOF - 0.35, 0))
	_cyl(root, 0.18, 0.28, 8.0, _shaft(), base + Vector3(0, 36.0, 0))
	OpsSolids.add_pole(solids.group, Vector2(x, y), 3.2, CAB_ROOF, ground, "the control tower")


static func _cyl(root: Node3D, r0: float, r1: float, h: float, mat: Material, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r0
	m.bottom_radius = r1
	m.height = h
	mi.mesh = m
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)


static func _shaft() -> StandardMaterial3D:
	if _concrete == null:
		_concrete = StandardMaterial3D.new()
		_concrete.albedo_color = Color(0.78, 0.78, 0.76)
		_concrete.roughness = 0.85
	return _concrete


static func _cab() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color(0.45, 0.58, 0.66)
		_glass.roughness = 0.18
		_glass.metallic = 0.35
	return _glass
