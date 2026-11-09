class_name JetwayRig
extends Node3D
## One movable jetway of an airport, hinged at its rotunda (tools/jetway_net.py: the OSM network node where the apron-drive bridge
## starts; a fixed link, JetwayLinks, joins it to the terminal), in two layouts: rest (straight toward the drawn cab end, hood
## REST_BACK_M short of it) and docked (hood face on the door of the aircraft parked at a gate it serves, JetwayDocks), and the
## move between them. Tunnel sections stretch; drum / girder / cab move rigidly (the cab turns about the drum to face the
## fuselage); the bridge tilts about the rotunda to put the cab floor at the door sill. The rotunda stays put, and the wheel
## support stands upright on the apron under the girder (JetwayLegs). Retracted it is solid (OpsSolids); extended it is not.
## Poses: JetwayPose.

const TUNNELS := ["Tunnel1", "Tunnel2", "Tunnel3", "Tunnel4", "Scissors"]
const WITH_DRUM := ["Rotunda2", "SupportGirder"]
const CAB := ["Hood", "Entrance", "GateSign"]
const SIGN_SHARE := 0.59  # the airline sign sits this far along the tunnel
const CAB_Z := -0.04
const DOCK_S := 6.0  # seconds to extend or retract
const CHECK_S := 0.25

var terminal := Vector2.ZERO  # the rotunda (ENU), where the rig stands
var rest := {}
var cands: Array = []
var pose := {}  # the pose now applied
var progress := 0.0  # 0 rest .. 1 docked
var docked_stand := ""  # ref of the gate the cab is (or is going) at, "" at rest
var ground_at := Callable()  # (east, north) -> ground height (m); unset: flat at the rotunda's ground
var _solids: OpsSolids
var _key := ""
var _ground := 0.0
var _pitch := Node3D.new()
var _cab := Node3D.new()
var _rotunda := Node3D.new()
var _legs: JetwayLegs
var _back_yaw := 0.0  # ENU angle the fixed rotunda (model +x) points along
var _model: Node3D
var _parts := {}
var _last := -1
var _check := 0.0
var _solid_on := false
var _first := true


## model: the instanced jetway scene; rot / way_cab: rotunda and drawn cab end (ENU); cands: JetwayDocks.candidates;
## back: unit vector from the rotunda toward the building (ZERO: opposite the tunnel); own_rot: false when another
## bridge of the same rotunda draws it.
func setup(model: Node3D, rot: Vector2, way_cab: Vector2, p_cands: Array, back := Vector2.ZERO, own_rot := true) -> void:
	terminal = rot
	rest = JetwayPose.rest(rot, way_cab)
	cands = p_cands
	_model = model
	_back_yaw = atan2(-back.y, -back.x) if back.length() > 0.5 else float(rest.yaw)
	_pitch.position = Vector3(0.0, JetwayPose.FLOOR_Y, 0.0)
	model.position = Vector3(-JetwayPose.PIVOT_X, -JetwayPose.FLOOR_Y, 0.0)
	add_child(_pitch)
	_pitch.add_child(model)
	model.add_child(_cab)
	add_child(_rotunda)
	for n in TUNNELS + WITH_DRUM + ["AirlineSign"]:
		_parts[n] = model.find_child(n, true, false)
	for n in CAB:
		var m := _take(model, n, _cab)
		if m:
			m.position = Vector3(-JetwayPose.DRUM_X, 0.0, -CAB_Z)
	var r := _take(model, "Rotunda1", _rotunda)
	if r:
		r.position = Vector3(-JetwayPose.PIVOT_X, 0.0, 0.0)
		if not own_rot:
			r.queue_free()
	var s := model.find_child("Support", true, false) as MeshInstance3D
	if s:
		_legs = JetwayLegs.new()
		_legs.take(s, self)
	apply(rest)


func _take(model: Node3D, n: String, to: Node3D) -> Node3D:
	var m := model.find_child(n, true, false) as Node3D
	if m:
		m.get_parent().remove_child(m)
		m.owner = null  # the glb's own scene owns it: adding it elsewhere would warn
		to.add_child(m)
	return m


## Call once the rig is in the tree (and its position is set): solids, and docked at once when the aircraft is there.
func start(solids: OpsSolids, key: String, ground: float) -> void:
	_solids = solids
	_key = key
	_ground = ground
	set_process(not cands.is_empty())
	_evaluate()
	if _last >= 0 and docked_stand != "":
		progress = 1.0
		apply(cands[_last].pose)
	else:
		apply(pose)  # the support's wheels onto the ground now that it is known
	_first = false
	_sync_solid()


func apply(p: Dictionary) -> void:
	pose = p
	rotation.y = p.yaw
	_pitch.rotation.z = p.pitch
	_rotunda.rotation.y = JetwayPose.angle_diff(_back_yaw, p.yaw)
	var dx: float = p.len - JetwayPose.LEN0
	var s := maxf((JetwayPose.TUN_X1 + dx - JetwayPose.TUN_X0) / (JetwayPose.TUN_X1 - JetwayPose.TUN_X0), 0.1)
	for n in TUNNELS:
		_set_x(n, JetwayPose.TUN_X0 * (1.0 - s), s)
	_set_x("AirlineSign", dx * SIGN_SHARE)
	for n in WITH_DRUM:
		_set_x(n, dx)
	_cab.position = Vector3(JetwayPose.DRUM_X + dx, 0.0, CAB_Z)
	_cab.rotation.y = JetwayPose.angle_diff(p.cab_yaw, p.yaw)
	if _legs:
		var xp := JetwayPose.SUPPORT_X + dx - JetwayPose.PIVOT_X  # along the tilted tunnel from the rotunda
		var c := cos(float(p.pitch))
		var sn := sin(float(p.pitch))
		var x := xp * c
		var top := JetwayPose.FLOOR_Y + xp * sn + (JetwayPose.TOP_Y - JetwayPose.FLOOR_Y) * c
		var foot := 0.0
		if ground_at.is_valid() and is_inside_tree():
			var at := terminal + Vector2.from_angle(p.yaw) * x
			foot = float(ground_at.call(at.x, at.y)) - _ground
		_legs.place(x, foot, top)


func _set_x(name: String, x: float, sx := 1.0) -> void:
	var n: Node3D = _parts.get(name)
	if n:
		n.position.x = x
		n.scale.x = sx


## Is the aircraft parked at a gate this jetway serves? Sets docked_stand / _last.
func _evaluate() -> void:
	var at := -1
	if not cands.is_empty():
		var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
		at = JetwayDocks.occupied(cands, Vector2(p.x, p.y), Props.get_f("fdm/groundspeed_mps"), docked_stand != "")
	if at >= 0:
		if at != _last and progress > 0.0 and not _first:
			progress = 0.0  # a different gate: retract first
		_last = at
		docked_stand = str(cands[at].stand)
	else:
		docked_stand = ""


func _process(dt: float) -> void:
	_check -= dt
	if _check <= 0.0:
		_check = CHECK_S
		_evaluate()
	var target := 1.0 if docked_stand != "" and not Props.get_b("controls/ground/jetway_stowed") else 0.0
	if is_equal_approx(progress, target):
		return
	progress = move_toward(progress, target, dt / DOCK_S)
	apply(JetwayPose.mix(rest, cands[_last].pose, smoothstep(0.0, 1.0, progress)))
	_sync_solid()


func _sync_solid() -> void:
	if _solids == null:
		return
	var want := progress <= 0.0
	if want and not _solid_on:
		_solids.add_jetway(self, _ground, _key)
	elif not want and _solid_on:
		_solids.remove_jetway(_key)
	_solid_on = want
