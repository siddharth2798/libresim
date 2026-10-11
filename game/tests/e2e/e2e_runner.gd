extends Node
## End-to-end test runner (QA sweep, driven by tools/e2e.sh). Builds the flight scene
## from the normal command-line flight options, then runs one scenario script:
##   godot --path game res://tests/e2e/e2e_runner.tscn -- --airport=VABB --runway=27 \
##       --e2e=spawn --e2e_out=/tmp/e2e/run1 --e2e_tag=vabb_27 [--e2e_nm=3] [--e2e_dur=7]
## Scenarios (game/tests/e2e/sc_*.gd) expose `func run(r) -> void` (a coroutine) and
## call r.check(name, ok, detail), r.metric(name, value) and r.shot(name).
## Results go to <out>/results/<tag>.json; screenshots to <out>/shots/<tag>_<name>.png.

const SCEN := {
	"spawn": ["res://tests/e2e/sc_spawn.gd", "spawn"],
	"views": ["res://tests/e2e/sc_spawn.gd", "views"],
	"takeoff": ["res://tests/e2e/sc_flight.gd", "takeoff"],
	"handsoff": ["res://tests/e2e/sc_flight.gd", "handsoff"],
	"landing": ["res://tests/e2e/sc_flight.gd", "landing"],
	"coldstart": ["res://tests/e2e/sc_flight.gd", "coldstart"],
	"taxi": ["res://tests/e2e/sc_ops.gd", "taxi"],
	"panels": ["res://tests/e2e/sc_ops.gd", "panels"],
	"saveload": ["res://tests/e2e/sc_ops.gd", "saveload"],
	"replay": ["res://tests/e2e/sc_ops.gd", "replay"],
	"record": ["res://tests/e2e/sc_ops.gd", "record"],
	"failures": ["res://tests/e2e/sc_systems.gd", "failures"],
	"nav": ["res://tests/e2e/sc_systems.gd", "nav"],
	"perf": ["res://tests/e2e/sc_systems.gd", "perf"],
}

var f: Node  # the flight scene
var args := {}
var out := "/tmp/e2e"
var tag := "run"
var checks: Array = []
var metrics := {}
var shots: Array = []
var sim_t := 0.0  # simulated seconds since the flight was built
var pilot: Node  # optional E2E autopilot (e2e_pilot.gd)
var _wall := 0.0
var _done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	out = args.get("e2e_out", out)
	tag = args.get("e2e_tag", args.get("e2e", "run"))
	DirAccess.make_dir_recursive_absolute(out.path_join("results"))
	DirAccess.make_dir_recursive_absolute(out.path_join("shots"))
	Session.setup.record_dir = out.path_join("rec")
	Session.setup.record_mp4 = false
	if args.has("e2e_nm"):
		Session.setup.air_nm = float(args.e2e_nm)
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep driving the test while the pause menu is open
	f = load("res://world/flight.tscn").instantiate()
	f.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(f)
	pilot = Node.new()
	pilot.set_script(load("res://tests/e2e/e2e_pilot.gd"))
	pilot.name = "E2EPilot"
	pilot.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(pilot)
	var spec: Array = SCEN.get(args.get("e2e", "spawn"), [])
	if spec.is_empty():
		check("scenario_known", false, "unknown scenario " + str(args.get("e2e")))
		finish()
		return
	var scr: GDScript = load(spec[0])
	if scr == null or not scr.can_instantiate():
		check("scenario_loads", false, "script %s failed to load (parse error?)" % spec[0])
		finish()
		return
	await scr.new().call(spec[1], self)
	finish()


func _physics_process(dt: float) -> void:
	sim_t += dt


func _process(dt: float) -> void:
	_wall += dt
	if _wall > float(args.get("e2e_timeout", 300.0)) and not _done:
		check("timeout", false, "scenario did not finish in %s s wall time" % args.get("e2e_timeout", 300))
		finish()


## --- helpers for scenarios ---

func arg(k: String, d: Variant = "") -> Variant:
	return args.get(k, d)


func wait(sim_seconds: float) -> void:  # simulated time (physics ticks)
	var end := sim_t + sim_seconds
	while sim_t < end and not _done:
		await get_tree().physics_frame


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func check(name: String, ok: bool, detail := "") -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})
	print("E2E %s %s: %s" % ["PASS" if ok else "FAIL", name, detail])


func metric(name: String, v: Variant) -> void:
	metrics[name] = v


func shot(name: String) -> String:
	await RenderingServer.frame_post_draw
	var path := out.path_join("shots").path_join("%s_%s.png" % [tag, name])
	get_viewport().get_texture().get_image().save_png(path)
	shots.append({"name": name, "path": path})
	return path


func key(code: Key, shift := false, ctrl := false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		Input.parse_input_event(e)
		await get_tree().process_frame
	Input.flush_buffered_events()


func p(k: String, d: Variant = 0.0) -> Variant:
	return Props.get_v(k, d)


func kias() -> float:
	return Units.mps_to_kt(Props.get_f("fdm/cas_mps"))


func hdg_deg() -> float:
	return fposmod(rad_to_deg(Props.get_f("fdm/heading_rad")), 360.0)


func alt_ft() -> float:
	return Units.m_to_ft(Props.get_f("fdm/alt_m"))


func angle_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


## Hand the controls to the script: the keyboard/joystick nodes stop writing controls/*.
func take_controls() -> void:
	for n in ["Controls", "JoystickControls"]:
		var c := f.get_node_or_null(n)
		if c:
			c.set_process(false)
			c.set_physics_process(false)


func finish() -> void:
	if _done:
		return
	_done = true
	var d := {"tag": tag, "scenario": args.get("e2e", ""), "args": args, "checks": checks,
		"metrics": metrics, "shots": shots, "sim_t": sim_t, "wall_t": _wall,
		"final": {"kias": kias(), "alt_ft": alt_ft(), "agl_m": Props.get_f("fdm/agl_m"),
			"crashed": Props.get_b("damage/crashed"), "reason": str(Props.get_v("damage/reason", "")),
			"events": str(Props.get_v("damage/events", []))}}
	var fa := FileAccess.open(out.path_join("results").path_join(tag + ".json"), FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(d, "  "))
		fa.close()
	print("E2E DONE %s checks=%d failed=%d" % [tag, checks.size(), checks.filter(func(c): return not c.ok).size()])
	get_tree().quit()
