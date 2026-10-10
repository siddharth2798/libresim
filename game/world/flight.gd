extends Node3D
## Main flight scene (M4). Command-line options (after "--"):
##   --airport=VAJJ --runway=08   start on a runway (default VAJJ, first runway)
##   --air=<alt_ft>               start airborne on the runway's extended centreline, 5 nm out
##   --shot=<png>                 screenshot after 6 s and quit (testing)
##   --time=<s>                   with --shot: fly that many seconds hands-off first
##   --view=cockpit|orbit         initial camera (default chase)
## Keys: Esc pause, F5 reset to start.

@onready var terrain: TerrainQuadtree = $Terrain
@onready var fdm_node: FdmNode = $Fdm
@onready var model: C172Model = $Aircraft
@onready var cam: CameraRig = $Camera
@onready var airports: AirportBuilder = $Airports

var _start := {}
var _air_ft := -1.0
var _shot := ""
var _shot_time := 6.0
var _t := 0.0
var _view := ""


func _ready() -> void:
	var apt := "VAJJ"
	var rwy := ""
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		match kv[0]:
			"airport": apt = kv[1].to_upper()
			"runway": rwy = kv[1]
			"air": _air_ft = float(kv[1]) if kv.size() > 1 else 1500.0
			"shot": _shot = kv[1]
			"time": _shot_time = float(kv[1]) + 6.0
			"view": _view = kv[1]
	airports.build(terrain)
	_start = airports.runway_start(apt, rwy)
	if _start.is_empty():
		push_error("no runway %s at %s, using VAJJ" % [rwy, apt])
		_start = airports.runway_start("VAJJ", "")
	model.build(fdm_node)
	cam.setup(model)
	$Instruments/Gyros.fdm = fdm_node.fdm
	$Instruments/Compass.fdm = fdm_node.fdm
	$UI/Panel.setup(model.cockpit, cam)
	if _view == "cockpit":
		cam.mode = CameraRig.Mode.COCKPIT
	elif _view == "orbit":
		cam.mode = CameraRig.Mode.ORBIT
	_reset()


func _reset() -> void:
	var p: Vector2 = _start.pos
	var hdg: float = _start.heading_deg
	FloatingOrigin.set_origin(p)
	if _air_ft > 0.0:
		var back := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg))) * -9260.0
		var q := p + back
		fdm_node.place_airborne(q.x, q.y, terrain.height_at(p.x, p.y) + _air_ft * 0.3048, hdg, 90.0)
		Props.set_v("controls/throttle", 0.55)
		Props.set_v("controls/pitch_trim", -0.05)
	else:
		fdm_node.place_on_ground(p.x, p.y, hdg)
		fdm_node.fdm.prop.rpm = 800.0
		Props.set_v("controls/throttle", 0.0)
		Props.set_v("controls/pitch_trim", -0.05)
	Props.set_v("controls/flaps", 0)
	Props.set_v("environment/qnh_pa", 101325.0)
	Props.set_v("environment/delta_t", 0.0)
	Props.set_v("instruments/altimeter/kollsman_inhg", 29.92)
	var eng := fdm_node.fdm.engine
	eng.running = true
	eng.oil_temp_k = 355.0  # warmed up: 180 F oil, 380 F CHT
	eng.cht_k = 466.0
	eng.egt_k = 900.0
	eng.oil_press_pa = 4.5e5
	$Instruments/Gyros.start_running()
	$Instruments/Compass.settle()


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_ESCAPE:
		fdm_node.paused = not fdm_node.paused
	elif e.keycode == KEY_F5:
		_reset()


func _process(dt: float) -> void:
	FloatingOrigin.update_focus(fdm_node.position_enu())
	if _shot.is_empty():
		return
	_t += dt
	if _t > _shot_time and _t - dt <= _shot_time:
		get_viewport().get_texture().get_image().save_png(_shot)
		var p := Props
		print("saved %s fps %d  kias %.0f alt %.0f ft agl %.0f rpm %.0f" % [_shot, Engine.get_frames_per_second(),
			Units.mps_to_kt(p.get_f("fdm/cas_mps")), Units.m_to_ft(p.get_f("fdm/alt_m")),
			Units.m_to_ft(p.get_f("fdm/agl_m")), p.get_f("engine/rpm")])
		get_tree().quit()
