class_name CabinDoorPanel
extends Node3D
## One door of an airliner whose glb paints its doors on the skin (the A320): a curved panel on the skin, hidden while shut (the
## painted door shows), that opens with its request (world/cabin_door.gd: L1 = controls/door_open / systems/door_pos, the others
## controls/doors/<id> / systems/doors/<id>). A dark doorway or hold shows behind it once it moves.
##   passenger  the Airbus way: the plug door first rises and moves out a few cm off its stops, then the hinge arm (pivoted on the
##              forward door frame, a guide arm keeping the door parallel to the fuselage) swings it out and forward, so it ends
##              outer face out, flat along the skin just ahead of the doorway. It never turns. Docked at a jetway, L1's doorway and
##              open door lie inside the cab's canopy (GroundParams.hood_fwd_m, JetwayCanopy).
##   cargo      hinged along its top edge, it swings out and up to CARGO_DEG (lower lobe, Airbus cargo doors).
## aircraft.json ground.doors [{id, kind, x_m, side, sill_z_m, w_m, h_m}] (without it, L1 from cg_to_door_m, door_y_m,
## door_sill_z_m, door_w_m, door_h_m). The skin comes from a SkinProbe on the exterior meshes (the panel lies on the real surface);
## without one, a round fuselage of fuselage_r_m about the axis door_sill_z_m + door_axis_z_m. Structural frame x aft, y right,
## z up; AircraftModel places the panels (`s` converts structural points to its local frame).

const PLUG_OUT_M := 0.05  # off the stops: out ...
const PLUG_UP_M := 0.04  # ... and up
const PLUG := 0.15  # share of the travel spent coming off the stops
const SWING_DEG := 165.0  # hinge arm travel: short of 180 so the open door stands off the skin (PLUG_OUT_M + arm * sin 15 deg)
const SWING_GAP_M := 0.05  # the arm pivot is this far ahead of the door's forward edge: the open door clears the frame by ~2x
const CARGO_DEG := 110.0
const OFFSET_M := 0.02  # panel stands this far outside the skin
const COLS := 3
const ROWS := 10

var id := "L1"
var kind := "passenger"
var _hinge := Node3D.new()
var _doorway := MeshInstance3D.new()
var _base := Vector3.ZERO  # the hinge closed
var _arm := 0.5  # hinge arm length: pivot to door centre (w / 2 + SWING_GAP_M)
var _side := -1.0  # +1: door on the right (local +x)


## The L1 panel. g: the ground section; cg: structural CG; s: Callable(structural Vector3) -> local Vector3. Null without the data.
static func make(g: Dictionary, cg: Vector3, s: Callable, probe: SkinProbe = null) -> CabinDoorPanel:
	var all := make_all(g, cg, s, probe)
	for d: CabinDoorPanel in all:
		if d.id == "L1":
			return d
	return null


## A panel for every door of the ground section (empty without a fuselage radius and a sill).
static func make_all(g: Dictionary, cg: Vector3, s: Callable, probe: SkinProbe = null) -> Array[CabinDoorPanel]:
	var out: Array[CabinDoorPanel] = []
	if not g.has("door_sill_z_m") or float(g.get("fuselage_r_m", 0.0)) <= 0.0:
		return out
	var list = g.get("doors")
	if not list is Array or list.is_empty():
		list = [{"id": "L1", "kind": "passenger", "x_m": cg.x - float(g.get("cg_to_door_m", 0.0)),
			"side": -1.0 if float(g.get("door_y_m", -1.0)) < 0.0 else 1.0, "sill_z_m": float(g.door_sill_z_m),
			"w_m": float(g.get("door_w_m", 0.9)), "h_m": float(g.get("door_h_m", 1.85))}]
	var zc := float(g.door_sill_z_m) + float(g.get("door_axis_z_m", 0.9))
	for spec: Dictionary in list:
		var d := CabinDoorPanel.new()
		d.id = str(spec.get("id", "L1"))
		d.kind = str(spec.get("kind", "passenger"))
		d.name = "CabinDoor_" + d.id
		d._build(spec, float(g.fuselage_r_m), zc, s, probe)
		out.append(d)
	return out


func _build(spec: Dictionary, r: float, zc: float, s: Callable, probe: SkinProbe) -> void:
	var side := 1.0 if float(spec.get("side", -1.0)) > 0.0 else -1.0
	var w := float(spec.get("w_m", 0.9))
	var h := float(spec.get("h_m", 1.85))
	var z0 := float(spec.get("sill_z_m", 0.0))
	var xf := float(spec.get("x_m", 0.0)) - w * 0.5  # forward edge: structural x grows aft
	_side = side
	_arm = w * 0.5 + SWING_GAP_M
	var skin := func(x: float, z: float) -> float:  # structural y of the skin
		var y := probe.y_at(x, z, side) if probe != null else NAN
		return y if not is_nan(y) else side * sqrt(maxf(r * r - (z - zc) * (z - zc), 0.01))
	var hinge_at: Vector3
	if kind == "cargo":  # along the top edge, mid-door
		hinge_at = s.call(Vector3(xf + w * 0.5, float(skin.call(xf + w * 0.5, z0 + h)) + side * OFFSET_M, z0 + h))
	else:  # the forward edge, half way up, at struct z 0 (the panel only translates)
		hinge_at = s.call(Vector3(xf, float(skin.call(xf, z0 + h * 0.5)) + side * OFFSET_M, 0.0))
	_hinge.position = hinge_at
	_base = hinge_at
	add_child(_hinge)
	var panel := MeshInstance3D.new()
	panel.mesh = _grid(skin, s, xf, w, z0, h, OFFSET_M * side, hinge_at)
	panel.material_override = _mat(Color(0.93, 0.94, 0.95), 0.45)
	_hinge.add_child(panel)
	if kind != "cargo":
		for off in [1.6, 0.4]:  # the door window on both faces
			var win := MeshInstance3D.new()
			win.mesh = _grid(skin, s, xf + w * 0.3, w * 0.28, z0 + h * 0.62, h * 0.2, OFFSET_M * off * side, hinge_at)
			win.material_override = _mat(Color(0.06, 0.08, 0.1), 0.1)
			_hinge.add_child(win)
	var dm := _mat(Color(0.03, 0.03, 0.035), 0.9)
	if kind != "cargo":
		dm.emission_enabled = true
		dm.emission = Color(0.09, 0.08, 0.065)  # a lit cabin: dim warm grey (brown by day at 0.22)
	_doorway.material_override = dm
	_doorway.mesh = _grid(skin, s, xf + 0.03, w - 0.06, z0 + 0.04, h - 0.08, OFFSET_M * 0.4 * side, hinge_at)
	_doorway.position = hinge_at
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
			var x := xf + w * float(i) / COLS
			var p: Vector3 = s.call(Vector3(x, float(skin.call(x, z)) + off, z))
			v.append(p - origin)
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
	_apply(Props.get_f(CabinDoor.pos_prop(id)))


## pos 0..1. Passenger: off the stops over the first PLUG of the travel, then the arm swings to SWING_DEG. Cargo: up round the
## top hinge to CARGO_DEG. The panel hides while closed (the painted door shows); the doorway shows once it moves.
func _apply(pos: float) -> void:
	_hinge.visible = pos > 0.01
	_doorway.visible = pos > 0.01
	if kind == "cargo":
		_hinge.rotation.z = _side * deg_to_rad(CARGO_DEG) * smoothstep(0.0, 1.0, pos)  # the bottom edge swings out and up
	else:
		_hinge.position = _base + offset(pos, _arm, _side)


## Where the door is (local frame: x = structural right, y up, z = structural aft) against its closed place at pos 0..1. The door
## centre runs on a circle of radius `arm` round a pivot ahead of it: out at a quarter of the swing, ahead of the frame at the end.
static func offset(pos: float, arm: float, side: float) -> Vector3:
	var k := smoothstep(0.0, PLUG, pos)
	var a := deg_to_rad(SWING_DEG) * smoothstep(PLUG, 1.0, pos)
	var out := PLUG_OUT_M * k + arm * sin(a)
	var aft := arm * (cos(a) - 1.0)
	return Vector3(side * out, PLUG_UP_M * k, aft)
