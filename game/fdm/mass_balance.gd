class_name MassBalance
extends RefCounted
## Mass, CG and inertia from empty aircraft + point masses (crew, baggage) + fuel.
## Positions are JSBSim structural metres (x aft, y right, z up).
## body_of() converts a structural point to body axes (x fwd, y right, z down) about the CG.

var empty_kg: float
var empty_cg: Vector3
var empty_inertia: Basis  # kg*m^2 about the empty CG, body axes
var point_masses: Array = []  # [{name, kg, pos}]
var tanks: Array = []  # [{pos, capacity_kg, contents_kg}]

var mass := 0.0
var cg := Vector3.ZERO  # structural
var inertia := Basis()  # body axes about current CG
var inertia_inv := Basis()


func _init(cfg: Dictionary) -> void:
	var m: Dictionary = cfg.mass
	empty_kg = m.empty_kg
	empty_cg = _v(m.empty_cg_m)
	var i: Dictionary = m.inertia_kgm2
	empty_inertia = Basis(Vector3(i.ixx, 0, -i.ixz), Vector3(0, i.iyy, 0), Vector3(-i.ixz, 0, i.izz))
	for p in m.point_masses:
		point_masses.append({"name": p.name, "kg": p.kg, "pos": _v(p.pos_m)})
	for t in cfg.tanks:
		tanks.append({"pos": _v(t.pos_m), "capacity_kg": t.capacity_kg, "contents_kg": t.contents_kg})
	update()


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Structural point -> body-axis vector from the CG.
func body_of(p_struct: Vector3) -> Vector3:
	var d := p_struct - cg
	return Vector3(-d.x, d.y, -d.z)


func set_payload(name: String, kg: float) -> void:
	for p in point_masses:
		if p.name == name:
			p.kg = kg
	update()


## "left" / "right" / "centre" by the tank's lateral position (structural y, right positive).
func tank_side(i: int) -> String:
	var y: float = tanks[i].pos.y
	return "left" if y < -0.1 else ("right" if y > 0.1 else "centre")


## Fuel (kg) in the tanks on one side.
func side_kg(side: String) -> float:
	var f := 0.0
	for i in tanks.size():
		if tank_side(i) == side:
			f += tanks[i].contents_kg
	return f


## Set the fuel on one side (replay take-over): tanks on it share `kg` in proportion to what they hold.
func set_side_kg(side: String, kg: float) -> void:
	var have := side_kg(side)
	var n := 0
	for i in tanks.size():
		n += 1 if tank_side(i) == side else 0
	for i in tanks.size():
		if tank_side(i) == side:
			tanks[i].contents_kg = kg * (tanks[i].contents_kg / have if have > 0.0 else 1.0 / n)


func fuel_kg() -> float:
	var f := 0.0
	for t in tanks:
		f += t.contents_kg
	return f


func update() -> void:
	var items: Array = [[empty_kg, empty_cg]]
	for p in point_masses:
		items.append([p.kg, p.pos])
	for t in tanks:
		items.append([t.contents_kg, t.pos])
	mass = 0.0
	var moment := Vector3.ZERO
	for it in items:
		mass += it[0]
		moment += it[1] * it[0]
	cg = moment / mass
	# Parallel-axis theorem: empty inertia shifted, plus point masses.
	inertia = _shift(empty_inertia, empty_kg, body_of(empty_cg))
	for k in range(1, items.size()):
		inertia = _add(inertia, _point(items[k][0], body_of(items[k][1])))
	inertia_inv = inertia.inverse()


static func _point(m: float, r: Vector3) -> Basis:
	return Basis(
		Vector3(m * (r.y * r.y + r.z * r.z), -m * r.x * r.y, -m * r.x * r.z),
		Vector3(-m * r.x * r.y, m * (r.x * r.x + r.z * r.z), -m * r.y * r.z),
		Vector3(-m * r.x * r.z, -m * r.y * r.z, m * (r.x * r.x + r.y * r.y)))


static func _shift(i: Basis, m: float, r: Vector3) -> Basis:
	return _add(i, _point(m, r))


static func _add(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)
