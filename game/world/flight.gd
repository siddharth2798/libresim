extends Node3D
## Main flight scene (M4). Command-line options (after "--"):
##   --airport=VAJJ --runway=08   start on a runway (default VAJJ, first runway)
##   --air=<alt_ft>               start airborne on the runway's extended centreline, 5 nm out
##   --shot=<png>                 screenshot after 6 s and quit (testing)
##   --time=<s>                   with --shot: fly that many seconds hands-off first
##   --view=cockpit|chase|orbit|free|tower|wing|tail|flyby   initial camera (default chase)
##   --quality=low|medium|high|ultra   graphics preset (saved from the F10 menu otherwise)
##   --tod=19.5 --wind=270/15G25 --vis=3000 --clouds=0.6@3000   time (IST h) and weather
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
			"tod": Props.set_v("weather/time_h", float(kv[1]))
			"wind": _wind(kv[1])
			"vis": Props.set_v("weather/visibility_m", float(kv[1]))
			"clouds": _clouds(kv[1])
	airports.build(terrain)
	$Weather.terrain = terrain
	$Trees.terrain = terrain
	if airports.data:
		$RunwayLights.build(airports.data, terrain)
	_start = airports.runway_start(apt, rwy)
	if _start.is_empty():
		push_error("no runway %s at %s, using VAJJ" % [rwy, apt])
		_start = airports.runway_start("VAJJ", "")
	model.build(fdm_node)
	cam.setup(model)
	$Instruments/Gyros.fdm = fdm_node.fdm
	$Instruments/Compass.fdm = fdm_node.fdm
	$UI/Panel.setup(model.cockpit, cam)
	var views := ["cockpit", "chase", "orbit", "free", "tower", "wing", "tail", "flyby"]
	var vi := views.find(_view)
	cam.set_mode(vi if vi >= 0 else 1)
	Graphics.apply_to_scene(self)
	_reset()


func _wind(v: String) -> void:  # "270/15" or "270/15G25"
	var p := v.split("/")
	Props.set_v("weather/wind_dir_deg", float(p[0]))
	var sp := p[1].split("G")
	Props.set_v("weather/wind_kt", float(sp[0]))
	Props.set_v("weather/aloft_dir_deg", float(p[0]) + 10.0)
	Props.set_v("weather/aloft_kt", float(sp[0]) * 1.6)
	Props.set_v("weather/gust_kt", float(sp[1]) if sp.size() > 1 else 0.0)


func _clouds(v: String) -> void:  # "0.5@3500" = cover@base_ft
	var p := v.split("@")
	Props.set_v("weather/cloud_cover", float(p[0]))
	if p.size() > 1:
		Props.set_v("weather/cloud_base_ft", float(p[1]))


func _reset() -> void:
	var p: Vector2 = _start.pos
	var hdg: float = _start.heading_deg
	FloatingOrigin.set_origin(p)
	if _air_ft > 0.0:
		var back := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg))) * -9260.0
		var q := p + back
		fdm_node.place_airborne(q.x, q.y, terrain.height_at(p.x, p.y) + _air_ft * 0.3048, hdg, 90.0)
	else:
		fdm_node.place_on_ground(p.x, p.y, hdg)
		fdm_node.fdm.prop.rpm = 800.0
		Props.set_v("controls/throttle", 0.0)
		Props.set_v("controls/pitch_trim", -0.05)
	Props.set_v("controls/flaps", 0)
	for k in ["master_bat", "master_alt", "avionics"]:
		Props.set_v("controls/electrical/" + k, true)
	Props.set_v("controls/lights/beacon", true)
	Props.set_v("controls/lights/nav", Props.get_f("environment/sun_elev_deg", 30.0) < 5.0)
	Props.set_v("controls/fuel/selector", 3)
	Props.set_v("controls/fuel/shutoff", false)
	# altimeter set to the current QNH, as after a pre-flight check
	Props.set_v("instruments/altimeter/kollsman_inhg", snappedf(Props.get_f("weather/qnh_hpa", 1013.25) * 100.0 / Units.INHG, 0.01))
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
