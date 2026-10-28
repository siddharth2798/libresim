class_name AirlinerControls
extends FlightControls
## Controls of an aircraft whose config.controls.flaps is a Dictionary (A320): per-surface actuators
## (config.controls.surfaces: aileron-l/r, elevator-l/r, stabilizer, rudder), flap + slat detents,
## spoiler panels, speedbrake, and mirrors of the gear / thrust lever state. Pilot inputs are the same
## as the C172's (pitch +1 = stick aft, roll +1 = right, yaw +1 = right pedal, pitch_trim like pitch).
## Direct control (law == null) maps them straight to surface commands:
##   elevator-l/r = -pitch * max, aileron-l = +roll * max and aileron-r = -roll * max, rudder = +yaw * max,
##   stabilizer = trim wheel (nose up = toward clip[0]), flaps / slats by lever detent index flap_cmd,
##   spoilers by the speedbrake lever (config lever_input_table) and the ground spoilers (on the ground,
##   fast, every thrust lever at idle or reverse).
## A control law (FlightControls.law, P2b) writes `cmd` (surface name -> deg) and `spoiler_cmd` (deg per
## panel) itself and the direct mapping is skipped; the actuators, flaps and slats stay here.
## Fields saved / replayed under these names: slat_deg slat_cmd spoiler spoiler_cmd speedbrake
## speedbrake_cmd gear_pos gear_cmd thrust_lever (and the base flap_deg / flap_cmd = lever index).
## elevator / aileron / rudder (rad) keep the C172 meaning for animation: rudder + = nose LEFT.

const GROUND_SPOILER_MPS := 15.0  # the ground spoilers need this ground speed (about 30 kt)

var slat_deg := 0.0
var slat_cmd := 0.0
var spoiler: Array = []  # deg per panel: left wing panels 0..n-1, right wing n..2n-1
var spoiler_cmd: Array = []  # deg per panel
var speedbrake := 0.0  # 0..1 extension the speedbrake panels reach
var speedbrake_cmd := 0.0  # lever 0..1
var gear_pos := 1.0  # 0 up .. 1 down (mirror of the gear, set by FDM)
var gear_cmd := 1  # lever: 1 = down
var thrust_lever: Array = []  # per engine -1 (reverse max) .. 1 (TOGA), set by FDM
var stabilizer_deg := 0.0
var cmd := {}  # surface name -> commanded deg
var ground_speed := 0.0  # set by FDM
var thrust_idle := true  # set by FDM: every thrust lever at idle or reverse
var landing_light_l := 0.0  # 0..1 extension (drag input), set by FdmNode
var landing_light_r := 0.0

var _acts := {}  # name -> SurfaceActuator
var _panels: Array[SurfaceActuator] = []
var _dets: Array = []
var _fl: Dictionary
var _sp: Dictionary
var _ctx := {}
var _n_panels := 5
var _sb_panels: Array = [1, 2, 3]


func _init(cfg: Dictionary) -> void:
	super(cfg)
	for n in cfg.controls.surfaces:
		_acts[n] = SurfaceActuator.new(n, cfg.controls.surfaces[n])
		cmd[n] = 0.0
	_fl = cfg.controls.flaps
	_dets = _fl.detents
	_sp = cfg.controls.get("spoilers", {})
	_n_panels = int(_sp.get("panels_per_wing", 5))
	_sb_panels = _sp.get("speedbrake_panels", _sb_panels)
	for i in 2 * _n_panels:
		var a := SurfaceActuator.new("spoiler%d" % i, {"lag_rad_s": _sp.get("lag_rad_s", 26.5),
			"rate_deg_s": _sp.get("rate_deg_s", 35.0), "max_deg": _sp.get("max_deg", 50.0), "clip_deg": [0.0, _sp.get("max_deg", 50.0)]})
		_panels.append(a)
		spoiler.append(0.0)
		spoiler_cmd.append(0.0)
	thrust_lever.resize((cfg.engines as Array).size() if cfg.has("engines") else 1)
	thrust_lever.fill(0.0)


func flap_detents() -> int:
	return _dets.size()


func surface(name: String) -> float:
	return _acts[name].pos if _acts.has(name) else 0.0


func settle() -> void:
	super()
	if law == null:
		_direct()
	for a: SurfaceActuator in _acts.values():
		a.cmd = cmd.get(a.name, 0.0)
		a.settle()
	var d: Dictionary = _dets[clampi(flap_cmd, 0, _dets.size() - 1)]
	flap_deg = d.flap_deg
	slat_deg = d.slat_deg
	slat_cmd = slat_deg
	for i in _panels.size():
		_panels[i].cmd = spoiler_cmd[i]
		_panels[i].settle()
		spoiler[i] = _panels[i].pos
	_publish_state()


func update(dt: float) -> void:
	if law == null:
		_direct()
	for a: SurfaceActuator in _acts.values():
		a.cmd = cmd.get(a.name, 0.0)
		a.update(dt)
	_flaps(dt)
	for i in _panels.size():
		_panels[i].cmd = spoiler_cmd[i]
		_panels[i].update(dt)
		spoiler[i] = _panels[i].pos
	_publish_state()


## Stick -> surface commands (direct law), spoiler commands.
func _direct() -> void:
	cmd["elevator-l"] = -pitch * _max("elevator-l")
	cmd["elevator-r"] = -pitch * _max("elevator-r")
	cmd["aileron-l"] = roll * _max("aileron-l")
	cmd["aileron-r"] = -roll * _max("aileron-r")
	cmd["rudder"] = yaw * _max("rudder")
	if _acts.has("stabilizer"):  # trim wheel: nose up = negative deflection, travel differs per side
		var st: SurfaceActuator = _acts.stabilizer
		cmd["stabilizer"] = pitch_trim * st.lo if pitch_trim >= 0.0 else -pitch_trim * st.hi
	speedbrake_cmd = clampf(speedbrake_cmd, 0.0, 1.0)
	var sb := 0.0
	var lever: Dictionary = _sp.get("lever_input_table", {})
	if not lever.is_empty():
		sb = clampf(Table.eval2(lever, speedbrake_cmd), 0.0, 1.0)
	var ground := not airborne and ground_speed > GROUND_SPOILER_MPS and thrust_idle
	var max_deg: float = _sp.get("max_deg", 50.0)
	for i in _panels.size():
		var local := i % _n_panels
		var v := 1.0 if ground else (sb if local in _sb_panels else 0.0)
		spoiler_cmd[i] = v * max_deg


func _max(n: String) -> float:
	return _acts[n].max_deg if _acts.has(n) else 0.0


## Flaps and slats move to the detent of the lever (flap_cmd), each at its own rate.
func _flaps(dt: float) -> void:
	var d: Dictionary = _dets[clampi(flap_cmd, 0, _dets.size() - 1)]
	slat_cmd = d.slat_deg
	flap_motor_running = flaps_powered and not (is_equal_approx(flap_deg, d.flap_deg) and is_equal_approx(slat_deg, d.slat_deg))
	if flap_motor_running:
		flap_deg = move_toward(flap_deg, d.flap_deg, _fl.flap_rate_deg_s * dt)
		slat_deg = move_toward(slat_deg, d.slat_deg, _fl.slat_rate_deg_s * dt)


func _publish_state() -> void:
	var e: float = deg_to_rad(surface("elevator-l") + surface("elevator-r")) * 0.5
	elevator = e
	aileron = deg_to_rad(surface("aileron-l"))
	rudder = -deg_to_rad(surface("rudder"))
	stabilizer_deg = surface("stabilizer")
	var l := 0.0
	var r := 0.0
	var mx := 0.0
	for i in _n_panels:
		l = maxf(l, spoiler[i])
		r = maxf(r, spoiler[_n_panels + i])
	for i in _sb_panels:
		mx = maxf(mx, maxf(spoiler[i], spoiler[_n_panels + i]))
	speedbrake = mx / float(_sp.get("max_deg", 50.0))
	var o: Dictionary = _sp.get("outputs", {})
	for a: SurfaceActuator in _acts.values():
		_ctx[a.output] = a.pos
	_ctx[o.get("left", "fcs/spoiler-left-deg")] = l
	_ctx[o.get("right", "fcs/spoiler-right-deg")] = r
	_ctx[o.get("symmetrical", "fcs/spoiler-symmetrical-deg")] = (l + r) * 0.5
	_ctx["fcs/slat-pos-deg"] = slat_deg
	_ctx["fcs/slat-pos-norm"] = slat_deg / float(_fl.slat_max_deg)
	_ctx["/systems/gear/all-norm"] = gear_pos
	_ctx["/controls/lighting/landing-light-pos-l"] = landing_light_l
	_ctx["/controls/lighting/landing-light-pos-r"] = landing_light_r


func aero_ctx() -> Dictionary:
	return _ctx
