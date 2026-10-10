extends Node3D
## Main flight scene (M4). Command-line options (after "--"):
##   --airport=VAJJ --runway=08   start on a runway (default VAJJ, first runway)
##   --air=<alt_ft>               start airborne on the runway's extended centreline, 5 nm out
##   --shot=<png>                 screenshot after 6 s and quit (testing)
##   --time=<s>                   with --shot: fly that many seconds hands-off first
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
	airports.build(terrain)
	_start = airports.runway_start(apt, rwy)
	if _start.is_empty():
		push_error("no runway %s at %s, using VAJJ" % [rwy, apt])
		_start = airports.runway_start("VAJJ", "")
	model.build(fdm_node)
	cam.setup(model)
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
	fdm_node.fdm.engine.running = true


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
