class_name ObstacleProbePilot
extends RefCounted
## Scripted pilot for tests/obstacle_probe.gd: drives an FDM directly (no Props, no real time).
## fly(): level flight along a ground track at a height above the terrain.
## taxi(): ground roll along a heading at a target ground speed.

const DT := 1.0 / 240.0
const KT := 0.514444

var f: FDM
var ground: Callable  # (east, north) -> terrain height m
var agl_target := 10.0  # m above the ground under the nose (look-ahead)
var line_p := Vector2.ZERO  # east, north of a point on the track
var line_dir := Vector2(0, 1)  # unit (east, north)
var speed_kt := 80.0
var absolute := false  # agl_target is an altitude AMSL instead
var _h := FdmHarness.new()


func _init(fdm: FDM, ground_height: Callable) -> void:
	f = fdm
	ground = ground_height
	_h.f = fdm


func set_line(p: Vector2, heading_deg: float) -> void:
	line_p = p
	line_dir = Vector2(sin(deg_to_rad(heading_deg)), cos(deg_to_rad(heading_deg)))


func _xte() -> float:
	return (Vector2(f.pos_e, f.pos_n) - line_p).cross(line_dir)  # + = right of the line


func _hdg_error(want: float) -> float:
	return wrapf(want - f.euler().z, -PI, PI)


## One physics step of level flight: altitude hold over the terrain ahead, track hold.
func fly() -> void:
	var ahead := Vector2(f.pos_e, f.pos_n) + line_dir * maxf(f.vt, 10.0) * 1.0
	var gh := maxf(ground.call(f.pos_e, f.pos_n), ground.call(ahead.x, ahead.y))
	_h.mode = "alt"
	_h.target_alt = agl_target if absolute else gh + agl_target
	_h._autopilot()
	var want := atan2(line_dir.x, line_dir.y) - clampf(_xte() * 0.012, -0.25, 0.25)
	var phi_t := clampf(1.5 * _hdg_error(want), -0.35, 0.35)
	var e := f.euler()
	f.fcs.roll = clampf(2.5 * (phi_t - e.x) - 0.8 * f.w_b.x, -1.0, 1.0)
	f.fcs.yaw = 0.0
	f.step(DT)


## One physics step of ground taxi along line_dir at speed_kt (steers to the line).
func taxi() -> void:
	var gs := Vector2(f.velocity_ned().y, f.velocity_ned().x).length()
	var want := speed_kt * KT
	f.engine.running = true
	f.prop.rpm = maxf(f.prop.rpm, 800.0)
	f.engine.magnetos = 3
	f.engine.mixture = 1.0
	f.engine.throttle = clampf(0.12 + (want - gs) * 0.12, 0.0, 0.6) if gs < want + 0.3 else 0.0
	var brake := clampf((gs - want - 0.5) * 0.5, 0.0, 1.0)
	f.gear.brake_left = brake
	f.gear.brake_right = brake
	var wanth := atan2(line_dir.x, line_dir.y) - clampf(_xte() * 0.03, -0.3, 0.3)
	f.fcs.yaw = clampf(1.5 * _hdg_error(wanth) - 0.4 * f.w_b.z, -1.0, 1.0)
	f.step(DT)


## Takeoff roll and climb-out along the line: full throttle, rudder holds the line, rotate at 52 kt, then an 8 degree climb.
func takeoff() -> void:
	f.engine.running = true
	f.prop.rpm = maxf(f.prop.rpm, 800.0)
	f.engine.magnetos = 3
	f.engine.mixture = 1.0
	f.engine.throttle = 1.0
	f.gear.brake_left = 0.0
	f.gear.brake_right = 0.0
	if f.gear.wow and f.agl < 3.0:
		var off := _xte()
		f.fcs.yaw = clampf(4.0 * _hdg_error(atan2(line_dir.x, line_dir.y)) - 0.08 * off, -1.0, 1.0)
		f.fcs.pitch = 0.55 if f.cas > 52.0 * KT else 0.0
		f.step(DT)
		return
	_h.mode = "pitch"
	_h.target_pitch = deg_to_rad(8.0)  # climb attitude at full power
	_h._autopilot()
	var phi_t := clampf(1.5 * _hdg_error(atan2(line_dir.x, line_dir.y) - clampf(_xte() * 0.004, -0.2, 0.2)), -0.3, 0.3)
	f.fcs.roll = clampf(2.5 * (phi_t - f.euler().x) - 0.8 * f.w_b.x, -1.0, 1.0)
	f.fcs.yaw = 0.0
	f.step(DT)


## 3 degree approach to the runway whose threshold is thr (line = its centreline), flare, roll-out and brake.
## Returns true once stopped.
var _td := -1.0
var _i_vs := 0.0


func land(thr: Vector2, thr_elev: float) -> bool:
	f.engine.running = true
	f.engine.mixture = 1.0
	f.engine.magnetos = 3
	var along := (Vector2(f.pos_e, f.pos_n) - thr).dot(line_dir)
	var gs := Vector2(f.velocity_ned().x, f.velocity_ned().y).length()
	if f.gear.wow:
		if _td < 0.0:
			_td = f.time
		f.engine.throttle = 0.0
		f.fcs.flap_cmd = 0
		var brake := 1.0 if f.time - _td > 3.0 else 0.0
		f.gear.brake_left = brake
		f.gear.brake_right = brake
		f.fcs.pitch = 0.0
		f.fcs.yaw = clampf(4.0 * _hdg_error(atan2(line_dir.x, line_dir.y)) - 0.1 * _xte(), -1.0, 1.0)
		f.step(DT)
		return gs < 0.5
	var want_h := maxf(300.0 - along, 0.0) * tan(deg_to_rad(3.0))
	var h := f.altitude() - thr_elev
	f.fcs.flap_cmd = 2
	var wanth := atan2(line_dir.x, line_dir.y) - clampf(_xte() * 0.004, -0.15, 0.15)
	var phi_t := clampf(1.5 * _hdg_error(wanth), -0.3, 0.3)
	if f.agl > 6.0:
		var vs := -f.velocity_ned().z
		var vs_cmd := -gs * tan(deg_to_rad(3.0)) + 0.1 * (want_h - h)
		_i_vs = clampf(_i_vs + (vs_cmd - vs) * 0.0004, -0.2, 0.3)
		f.engine.throttle = clampf(0.3 + 0.08 * (vs_cmd - vs) + _i_vs, 0.0, 1.0)
		_h.mode = "speed"
		_h.target_cas = 65.0 * KT
	else:
		f.engine.throttle = 0.0
		_h.mode = "pitch"
		_h.target_pitch = deg_to_rad(6.0)
	_h._autopilot()
	f.fcs.roll = clampf(2.5 * (phi_t - f.euler().x) - 0.8 * f.w_b.x, -1.0, 1.0)
	f.fcs.yaw = 0.0
	f.step(DT)
	return false
