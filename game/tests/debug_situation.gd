extends Node
## Integration check for saved flight situations: godot --path game res://tests/debug_situation.tscn
## Starts world/flight.tscn in the air near VAJJ, flies 5 s, saves (Situation.save and
## the saves panel's F11 quick-save), moves the aircraft away, loads, and checks the
## restored state. Then frees the scene, starts a fresh one and resumes the save the
## way the start screen does (Situation.pending_load). Prints PASS / FAIL and quits.

const NAME := "debug situation"
var _fails := 0


func _ready() -> void:
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.airport = "VAJJ"
	Session.setup.start = "air"
	Session.setup.air_ft = 2500.0
	Session.setup.failures = {"vacuum_pump": [1, 0.0]}
	var f := _start()
	await _wait(5.0)
	var fdm: FDM = f.fdm_node.fdm
	Props.set_v("controls/com1/freq_mhz", 121.35)
	Props.set_v("controls/flaps", 1)
	await _wait(0.5)
	var err := Situation.save(f, NAME, SituationStore.grab_thumbnail(get_viewport()))
	_check(err == "", "save: " + err)
	var ref := _state(f)
	print("saved at ENU %s alt %.0f ft, %.0f KIAS, rpm %.0f, fuel %.2f kg" % [ref.enu, Units.m_to_ft(ref.enu.z), ref.kias, ref.rpm, ref.fuel])
	# perturb: park it somewhere else, change controls, repair the failure
	f.fdm_node.place_on_ground(ref.enu.x + 9000.0, ref.enu.y - 4000.0, 0.0)
	FloatingOrigin.set_origin(Vector2(ref.enu.x + 9000.0, ref.enu.y - 4000.0))
	fdm.mb.tanks[0].contents_kg = 5.0
	Props.set_v("controls/com1/freq_mhz", 118.0)
	Props.set_v("controls/flaps", 0)
	Props.set_v("failures/vacuum_pump", false)
	await _wait(1.0)
	err = Situation.load_file(f, SituationStore.file_name(NAME))
	_check(err == "", "load: " + err)
	_compare("panel-less load", _state(f), ref)
	_check(Props.get_f("controls/com1/freq_mhz") == 121.35, "COM1 frequency not restored")
	_check(Props.get_v("controls/flaps") == 1 and typeof(Props.get_v("controls/flaps")) == TYPE_INT, "flap lever not restored as int")
	_check(Props.get_b("failures/vacuum_pump"), "failure flag not restored")
	_check(FloatingOrigin.origin.distance_to(Vector2(ref.enu.x, ref.enu.y)) < 1.0, "floating origin not moved")
	var m := Situation.list_saves().filter(func(x): return x.name == NAME)
	_check(m.size() == 1, "save not listed")
	if m.size() == 1 and m[0].thumb != "":
		var img := Image.load_from_file(m[0].thumb)
		_check(img.get_size() == Vector2i(320, 180), "thumbnail size %s" % img.get_size())
		print("thumbnail %s %s" % [m[0].thumb, img.get_size()])
	await _wait(2.0)
	_check(not fdm.damage.crashed and fdm.agl > 100.0, "not flying after load (agl %.0f m, crashed %s)" % [fdm.agl, fdm.damage.crashed])
	# the in-flight panel: F11 quick-save / Shift+F11 quick-load
	var panel := PanelContainer.new()
	panel.set_script(load("res://ui/saves_panel.gd"))
	panel.flight = f
	f.get_node("UI").add_child(panel)
	await panel.quick_save()
	var ref2 := _state(f)
	f.fdm_node.place_on_ground(ref2.enu.x - 3000.0, ref2.enu.y, 90.0)
	await _wait(0.5)
	panel.quick_load()
	_compare("quick-load", _state(f), ref2)
	await _wait(1.0)
	# a fresh flight scene resuming the save, as from the start screen
	f.queue_free()
	await get_tree().process_frame
	Session.setup = Session.DEFAULT.duplicate(true)  # start screen copies the save's setup
	Session.setup.merge(SituationStore.read(SituationStore.file_name(NAME)).setup, true)
	Situation.pending_load = SituationStore.file_name(NAME)
	f = _start()
	err = Situation.load_pending(f)  # what flight.gd does at the end of _ready
	_check(err == "", "pending load: " + err)
	_compare("fresh-scene load", _state(f), ref)
	await _wait(3.0)
	fdm = f.fdm_node.fdm
	_check(not fdm.damage.crashed and fdm.agl > 100.0, "fresh scene not flying (agl %.0f m)" % fdm.agl)
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/debug_situation.png")
	Situation.delete(SituationStore.file_name(NAME))
	Situation.delete(Situation.QUICK)
	print("PASS" if _fails == 0 else "FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _start() -> Node:
	var f: Node = load("res://world/flight.tscn").instantiate()
	add_child(f)
	return f


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _state(f: Node) -> Dictionary:
	var fdm: FDM = f.fdm_node.fdm
	return {"enu": f.fdm_node.position_enu(), "v": fdm.velocity_ned(), "q": fdm.q, "rpm": fdm.prop.rpm,
		"fuel": fdm.mb.fuel_kg(), "kias": Units.mps_to_kt(fdm.cas)}


func _compare(what: String, s: Dictionary, ref: Dictionary) -> void:
	var dp: float = s.enu.distance_to(ref.enu)
	var dv: float = s.v.distance_to(ref.v)
	var dq: float = s.q.angle_to(ref.q)
	print("%s: position error %.4f m, velocity %.4f m/s, attitude %.6f rad, rpm %.4f, fuel %.6f kg" % [
		what, dp, dv, dq, absf(s.rpm - ref.rpm), absf(s.fuel - ref.fuel)])
	_check(dp < 0.01 and dv < 0.01 and dq < 1e-4 and absf(s.rpm - ref.rpm) < 0.01 and absf(s.fuel - ref.fuel) < 1e-6, what + " state mismatch")


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL: " + msg)
