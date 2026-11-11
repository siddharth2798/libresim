class_name CabinDoorPanel
extends Node3D
## The L1 cabin door of an airliner that has no separate door in its glb (the A320's is painted on the skin): a curved panel on the
## skin, hinged at its forward edge, that moves out and swings forward flat along the fuselage when the player opens the door (key O: controls/door_open, systems/door_pos,
## world/cabin_door.gd), with a dark cabin doorway behind it. Closed, it is hidden and the painted door shows.
## aircraft.json ground: cg_to_door_m, door_y_m (skin side), door_sill_z_m, door_h_m, door_w_m, fuselage_r_m, door_axis_z_m (above
## the sill); structural frame x aft, y right, z up. Placed by AircraftModel (`s` converts structural points to its local frame).

const OPEN_DEG := 175.0  # an Airbus door ends parallel to the skin, forward of the doorway
const ARM_M := 0.3  # it first moves this far out (clear of the skin's curve when turned), then swings forward
const LIFT := 0.3  # share of the travel spent moving out
const OFFSET_M := 0.02  # panel stands this far outside the skin
const COLS := 3
const ROWS := 10

var _hinge := Node3D.new()
var _doorway := MeshInstance3D.new()
var _base := Vector3.ZERO  # the hinge closed


## g: the ground section; cg: structural CG; s: Callable(structural Vector3) -> local Vector3. Null without the data.
static func make(g: Dictionary, cg: Vector3, s: Callable) -> CabinDoorPanel:
	if not g.has("door_sill_z_m") or float(g.get("fuselage_r_m", 0.0)) <= 0.0:
		return null
	var d := CabinDoorPanel.new()
	d.name = "CabinDoorPanel"
	d._build(g, cg, s)
	return d


func _build(g: Dictionary, cg: Vector3, s: Callable) -> void:
	var r := float(g.fuselage_r_m)
	var side := -1.0 if float(g.get("door_y_m", -1.0)) < 0.0 else 1.0
	var w := float(g.get("door_w_m", 0.9))
	var h := float(g.get("door_h_m", 1.85))
	var z0 := float(g.door_sill_z_m)
	var zc := z0 + float(g.get("door_axis_z_m", 0.9))
	var x_mid := cg.x - float(g.get("cg_to_door_m", 0.0))
	var xf := x_mid - w * 0.5  # forward edge (hinge): structural x grows aft
	var skin := func(z: float) -> float: return side * sqrt(maxf(r * r - (z - zc) * (z - zc), 0.01))
	var hinge_at: Vector3 = s.call(Vector3(xf, float(skin.call(z0 + h * 0.5)) + side * OFFSET_M, 0.0))
	_hinge.position = Vector3(hinge_at.x, 0.0, hinge_at.z)
	_base = _hinge.position
	add_child(_hinge)
	var panel := MeshInstance3D.new()
	panel.mesh = _grid(skin, s, xf, w, z0, h, OFFSET_M * side, hinge_at)
	panel.material_override = _mat(Color(0.93, 0.94, 0.95), 0.45)
	_hinge.add_child(panel)
	for off in [1.6, 0.4]:  # the door window on both faces (open, the inner face looks out)
		var win := MeshInstance3D.new()
		win.mesh = _grid(skin, s, xf + w * 0.3, w * 0.28, z0 + h * 0.62, h * 0.2, OFFSET_M * off * side, hinge_at)
		win.material_override = _mat(Color(0.06, 0.08, 0.1), 0.1)
		_hinge.add_child(win)
	var dm := _mat(Color(0.03, 0.03, 0.035), 0.9)
	dm.emission_enabled = true
	dm.emission = Color(0.09, 0.08, 0.065)  # a lit cabin: dim warm grey (brown by day at 0.22)
	_doorway.material_override = dm
	_doorway.mesh = _grid(skin, s, xf + 0.03, w - 0.06, z0 + 0.04, h - 0.1, OFFSET_M * 0.4 * side, hinge_at)
	_doorway.position = Vector3(hinge_at.x, 0.0, hinge_at.z)
	add_child(_doorway)
	_apply(0.0)
	set_process(true)


## A curved grid on the skin: x from xf over w (structural), z from z0 over h, standing `off` outside it; vertices relative to `origin`.
func _grid(skin: Callable, s: Callable, xf: float, w: float, z0: float, h: float, off: float, origin: Vector3) -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in ROWS + 1:
		var z := z0 + h * float(j) / ROWS
		for i in COLS + 1:
			var p: Vector3 = s.call(Vector3(xf + w * float(i) / COLS, float(skin.call(z)) + off, z))
			v.append(Vector3(p.x - origin.x, p.y, p.z - origin.z))
	for j in ROWS:
		for i in COLS:
			var a := j * (COLS + 1) + i
			idx.append_array([a, a + 1, a + COLS + 1, a + 1, a + COLS + 2, a + COLS + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _process(_dt: float) -> void:
	_apply(Props.get_f("systems/door_pos"))


## pos 0..1: out by ARM_M over the first LIFT of the travel, then round the hinge to OPEN_DEG (forward). The panel hides while
## closed (the painted door shows); the doorway shows once it moves.
func _apply(pos: float) -> void:
	_hinge.visible = pos > 0.01
	_doorway.visible = pos > 0.01
	var side := signf(_base.x) if _base.x != 0.0 else -1.0
	_hinge.position = _base + Vector3(side * ARM_M * smoothstep(0.0, LIFT, pos), 0.0, 0.0)
	_hinge.rotation.y = deg_to_rad(OPEN_DEG) * smoothstep(LIFT, 1.0, pos) * side
