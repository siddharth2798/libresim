extends Node3D
## Main flight scene. Started from the start screen (ui/menu) with the setup in the
## Session autoload, or directly with command-line options (after "--"):
##   --airport=VAJJ --runway=08   start on a runway (default VAJJ, first runway)
##   --air=<alt_ft> [--air-nm=5]  start airborne on the runway's extended centreline, 5 nm out
##   --stand[=REF]                start parked at a stand/gate, cold & dark (e.g. --stand="Bay 40"); default: a jetbridge gate
##   --cold                       cold & dark (everything off, parking brake set)
##   --shot=<png>                 screenshot after 6 s and quit (testing)
##   --time=<s>                   with --shot: fly that many seconds hands-off first
##   --view=cockpit|chase|orbit|free|tower|wing|tail|flyby   initial camera (default chase)
##   --quality=low|medium|high|ultra   graphics preset (saved from the F10 menu otherwise)
##   --tod=19.5 --wind=270/15G25 --vis=3000 --clouds=0.6@3000   time (IST h) and weather
##   --weather=clear|fair|scattered|broken|overcast|monsoon   weather preset
##   --fail=engine,vacuum_pump | --fail=engine@5   failures at start / after N min
##   --random-failures            random failures (defaults: 1 in 2-30 min, any system)
##   --record                     record the session (video + sound, see the start screen)
##   --clean                      hide all UI (screenshots)
##   --menu                       show the start screen pre-filled with these options
## Keys: Esc pause menu, F5 reset to start, F9 failures, F11 quick-save (Shift: load), R replay, J controls.

@onready var terrain: TerrainQuadtree = $Terrain
@onready var fdm_node: FdmNode = $Fdm
@onready var model: C172Model = $Aircraft
@onready var cam: CameraRig = $Camera
@onready var airports: AirportBuilder = $Airports

var _start := {}
var _apt := ""
var _air_ft := -1.0
var _air_nm := 5.0
var _shot := ""
var _shot_time := 6.0
var _t := 0.0
var _view := ""
var _stand_ref := ""  # "" = runway start, "*" = default stand, else a stand ref
var _cold := false


func _ready() -> void:
	var s: Dictionary = Session.setup
	var apt: String = s.airport
	var rwy: String = s.runway
	match s.start:
		"air":
			_air_ft = float(s.air_ft)
			_air_nm = float(s.air_nm)
		"stand": _stand_ref = s.stand if s.stand != "" else "*"
	_cold = bool(s.cold)
	_shot = Session.shot
	_shot_time = Session.shot_time
	_view = Session.view
	Session.apply_to_props()
	$UI.visible = not Session.clean
	airports.build(terrain)
	$Weather.terrain = terrain
	$Trees.terrain = terrain
	$UI/Crash.airports = airports
	$AirportOps.setup(terrain)
	$GroundOps.setup($AirportOps, airports, fdm_node, terrain, $UI)
	$UI/Atc.ground_ops = $GroundOps
	$UI/Atc.fdm_node = fdm_node
	$Avionics/Nav.terrain = terrain
	$Avionics/Gps.db = $Avionics/Nav.db
	$Systems/Failures.fdm_node = fdm_node
	$UI/Failures.manager = $Systems/Failures
	$UI/Pause.flight = self
	$UI/Map.setup($Avionics/Nav.db, airports, terrain.cache)
	_apt = apt
	if airports.data:
		$RunwayLights.build(airports.data, terrain)
	_start = airports.runway_start(apt, rwy)
	if _start.is_empty():
		_start = airports.runway_start(apt, "")  # unknown runway ident: the longest one
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
	$UI/Saves.flight = self
	if Situation.load_pending(self) != "":
		$Replay.clear()


func _reset() -> void:
	$Replay.clear()
	var p: Vector2 = _start.pos
	var hdg: float = _start.heading_deg
	FloatingOrigin.set_origin(p)
	_load_aircraft()
	if _air_ft > 0.0:
		var back := Vector2(sin(deg_to_rad(hdg)), cos(deg_to_rad(hdg))) * -_air_nm * 1852.0
		var q := p + back
		fdm_node.place_airborne(q.x, q.y, terrain.height_at(p.x, p.y) + _air_ft * 0.3048, hdg, 90.0, $Weather.wind_at(_air_ft * 0.3048))
	elif _stand_ref != "":
		var st: Dictionary = $AirportOps.find_stand(_apt, "" if _stand_ref == "*" else _stand_ref)
		if not st.is_empty():
			p = Vector2(st.x, st.y)
			hdg = float(st.heading_deg)
			FloatingOrigin.set_origin(p)
			Props.set_v("ops/stand", "%s %s%s" % [_apt, st.ref, " (jetbridge)" if st.jetbridge else ""])
		fdm_node.place_on_ground(p.x, p.y, hdg)
		fdm_node.fdm.prop.rpm = 800.0
		Props.set_v("controls/throttle", 0.0)
		Props.set_v("controls/pitch_trim", -0.05)
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
	if (_cold or _stand_ref != "") and _air_ft <= 0.0:  # parked at a stand = always cold & dark
		_cold_and_dark()
	$Systems/Failures.restart()


## Fuel and payload from the flight setup (aircraft page).
func _load_aircraft() -> void:
	var s: Dictionary = Session.setup
	var mb := fdm_node.fdm.mb
	for t in mb.tanks:
		t.contents_kg = minf(float(s.fuel_gal) * 2.72, t.capacity_kg)
	mb.set_payload("Co-Pilot", float(s.copilot_kg))
	mb.set_payload("Left Passenger", float(s.rear_kg) * 0.5)
	mb.set_payload("Right Passenger", float(s.rear_kg) * 0.5)
	mb.set_payload("Baggage", float(s.baggage_kg))


## Everything off, parked: the real pre-flight starting state.
func _cold_and_dark() -> void:
	var f := fdm_node.fdm
	f.prop.rpm = 0.0
	f.engine.running = false
	f.engine.oil_temp_k = 300.0
	f.engine.cht_k = 300.0
	f.engine.egt_k = 300.0
	f.engine.oil_press_pa = 0.0
	for k in ["master_bat", "master_alt", "avionics", "pitot_heat"]:
		Props.set_v("controls/electrical/" + k, false)
	for k in ["beacon", "nav", "strobe", "taxi", "landing"]:
		Props.set_v("controls/lights/" + k, false)
	Props.set_v("controls/magnetos", 0)
	Props.set_v("controls/mixture", 0.0)
	Props.set_v("controls/throttle", 0.0)
	Props.set_v("controls/parking_brake", true)
	$Controls.parking_brake = true
	Props.set_v("instruments/altimeter/kollsman_inhg", 29.92)
	$Instruments/Gyros._ai_spin = 0.0
	$Instruments/Gyros._hi_spin = 0.0


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_F5:
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
		print("failures: ", FailureCatalog.all_ids().filter(func(id): return p.get_b("failures/" + id)), "  events: ", p.get_v("damage/events", []).slice(0, 3))
		get_tree().quit()
