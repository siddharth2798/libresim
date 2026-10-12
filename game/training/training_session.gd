class_name TrainingSession
extends Node
## Runs a training lesson inside the flight scene (Session.training = lesson id, set by the
## start screen's Training page or --lesson=ID). Each physics tick it builds a snapshot of
## the flight (speed, height, runway-relative position, glide-path deviation ...), advances
## the lesson (training_logic.gd), drives the card / gauges (training_hud.gd), the 3D
## markers (training_markers.gd) and coach messages, and shows the graded result at the end.
## Assist level (Session.assist): full = markers + gauges + hints; light = card + hints +
## callouts; off = card and warnings only for the steps.
## A lesson ends either graded (all steps done) or "not completed" (the pilot touched down or
## left the approach too early, crashed ...: abort rules in lessons.json): the pilot always gets
## a result card, never a card stuck on a step. Try again / F5 restart it from the start.

var fdm_node: FdmNode
var airports: AirportBuilder
var terrain: TerrainQuadtree
var run: Dictionary = {}
var _lesson: Dictionary
var _hud: TrainingHud
var _markers: TrainingMarkers
var _rw := {}
var _u := Vector2.ZERO  # runway direction (east, north)
var _r := Vector2.ZERO  # to the right of the runway direction
var _last_along := -1.0e9
var _snap := {}
var result_kind := ""  # "" while flying the lesson, then "complete" or "incomplete"


func setup(f: FdmNode, ab: AirportBuilder, t: TerrainQuadtree) -> void:
	fdm_node = f
	airports = ab
	terrain = t
	if Session.training == "":
		set_physics_process(false)
		return
	_lesson = TrainingLogic.find(Session.training)
	if _lesson.is_empty():
		push_warning("unknown lesson %s" % Session.training)
		set_physics_process(false)
		return
	_hud = TrainingHud.new()
	get_parent().get_node("UI").add_child(_hud)
	_hud.setup(_lesson, Session.assist)
	_hud.retry.connect(retry)
	_hud.next_lesson.connect(_next_lesson)
	_hud.to_menu.connect(func(): get_tree().change_scene_to_file("res://ui/menu/start_screen.tscn"))
	_find_runway()
	if Session.assist == "full" and not _rw.is_empty():
		_markers = TrainingMarkers.new()
		get_parent().add_child(_markers)
		_markers.setup(_rw.thr, _rw.hdg, _rw.elev, _rw.length, t.height_at if t else Callable())
		for m in _lesson.get("markers", []):
			match m:
				"centreline": _markers.add_centreline()
				"hoops": _markers.add_rings()
				"aimpoint": _markers.add_aimpoint()
	restart()


## "Try again": put the aircraft back at the lesson start (what F5 does; it calls restart()).
func retry() -> void:
	var flight := get_parent()
	if flight.has_method("_reset"):
		flight._reset()
	else:
		get_tree().reload_current_scene()


## (Re)start the lesson from step 1 (also on F5).
func restart() -> void:
	if _lesson.is_empty():
		return
	run = TrainingLogic.new_run(_lesson)
	result_kind = ""
	_last_along = -1.0e9
	_hud.reset()
	_hud.show_step(0)
	_enter_step(0)
	if _markers:
		for r in _markers.rings:
			r[3] = "up"
			(r[0] as MeshInstance3D).material_override = _markers._mats.cyan
		_markers._highlight_next(-1.0e9)


func _find_runway() -> void:
	var s: Dictionary = Session.setup
	if airports == null or airports.data == null:
		return
	for r in airports.data.runways:
		if r.airport != s.airport:
			continue
		for i in 2:
			var e: Dictionary = r.ends[i]
			if e.ident == s.runway or (s.runway == "" and i == 0):
				_rw = {"thr": Vector2(e.x, e.y), "hdg": float(e.heading_true), "elev": float(e.h), "length": float(r.length)}
				var h := deg_to_rad(float(_rw.hdg))
				_u = Vector2(sin(h), cos(h))
				_r = Vector2(cos(h), -sin(h))
				return


func _snapshot() -> Dictionary:
	var p := Props
	var pos := fdm_node.position_enu()
	var along := 0.0
	var cross := 0.0
	var gp := 0.0
	var gp_dev := 0.0
	if not _rw.is_empty():
		var rel: Vector2 = Vector2(pos.x, pos.y) - (_rw.thr as Vector2)
		along = rel.dot(_u)
		cross = rel.dot(_r)
		if along < -50.0:
			gp = rad_to_deg(atan2(pos.z - float(_rw.elev) - TrainingMarkers.TCH, -along))
			gp_dev = gp - TrainingMarkers.PATH_DEG
	return {
		"ias": Units.mps_to_kt(p.get_f("fdm/cas_mps")), "gs": Units.mps_to_kt(p.get_f("fdm/groundspeed_mps")),
		"agl": Units.m_to_ft(p.get_f("fdm/agl_m")), "alt": Units.m_to_ft(pos.z),
		"vs": Units.mps_to_fpm(p.get_f("fdm/vs_mps")), "hdg": fposmod(rad_to_deg(p.get_f("fdm/heading_rad")), 360.0),
		"bank": rad_to_deg(p.get_f("fdm/roll_rad")), "pitch": rad_to_deg(p.get_f("fdm/pitch_rad")),
		"throttle": p.get_f("controls/throttle"), "rpm": p.get_f("engine/rpm"), "flaps": float(p.get_v("controls/flaps", 0)),
		"wow": 1.0 if p.get_b("fdm/wow") else 0.0, "brake": maxf(p.get_f("controls/brake_left"), p.get_f("controls/brake_right")),
		"pitch_in": p.get_f("controls/pitch"), "along": along, "cross": cross, "gp": gp, "gp_dev": gp_dev,
		"dist": maxf(-along, 0.0), "rem": float(_rw.get("length", 0.0)) - along if not _rw.is_empty() else 0.0, "pos": pos}


func _physics_process(dt: float) -> void:
	if run.is_empty() or run.done or fdm_node.paused or fdm_node.replaying:
		return
	if fdm_node.fdm.damage.crashed:
		_abort(TrainingLogic.abort(run, "You crashed during step {n}, {step}.", str(_lesson.get("crash_tip", ""))), true)
		return
	_snap = _snapshot()
	_update_rings()
	var ev := TrainingLogic.step(run, _snap, dt)
	if Session.assist != "off":
		for c in ev.say:
			_coach(str(c[0]), int(c[1]))
	if not run.done:
		_hud.update_gauges(_snap, run.s0)
	if ev.completed >= 0:
		for k in ev.skipped:
			_notify("✓  " + str(_lesson.steps[k].title), "", Notifications.INFO)
		_notify("✓  " + str(_lesson.steps[ev.completed].title), "", Notifications.INFO)
		if ev.finished:
			_finish()
		else:
			_hud.show_step(run.step)
			_enter_step(run.step)
	elif not ev.aborted.is_empty():
		_abort(ev.aborted, false)
	_last_along = _snap.along


func _enter_step(i: int) -> void:
	var st: Dictionary = _lesson.steps[i]
	_speak(str(st.text))
	if _markers == null:
		return
	if st.has("beacon_dhdg"):  # beacon in the direction of the target heading
		var hd := fposmod(rad_to_deg(Props.get_f("fdm/heading_rad")), 360.0)
		_markers.set_beacon(fdm_node.position_enu(), hd + float(st.beacon_dhdg))
	else:
		_markers.clear_beacon()


func _update_rings() -> void:
	if _markers == null:
		return
	for i in _markers.rings.size():
		var rg: Array = _markers.rings[i]
		if rg[3] != "up":
			continue
		if _last_along < rg[1] and _snap.along >= rg[1]:
			var d := Vector2(_snap.cross, _snap.pos.z - rg[2]).length()
			_markers.ring_done(i, d <= TrainingMarkers.RING_R * 1.15)
		elif _snap.along > rg[1] + 150.0:
			_markers.ring_done(i, false)


## The lesson cannot be finished: tell the pilot why (coach line + result card, or the ended
## lesson card after a crash, where the crash card has the buttons).
func _abort(info: Dictionary, crashed: bool) -> void:
	result_kind = "incomplete"
	if _markers:
		_markers.clear_beacon()
	_coach(str(info.reason), 1)
	if crashed:
		_hud.show_ended(info)
	else:
		_hud.show_incomplete(info)


func _finish() -> void:
	result_kind = "complete"
	var grade := TrainingLogic.grade(run)
	TrainingLogic.save_stars(_lesson.id, grade.stars)
	var lessons := TrainingLogic.load_lessons()
	var idx := lessons.find_custom(func(l): return l.id == _lesson.id)
	_hud.show_result(grade, idx >= 0 and idx + 1 < lessons.size())
	if _markers:
		_markers.clear_beacon()


func _next_lesson() -> void:
	var lessons := TrainingLogic.load_lessons()
	var idx := lessons.find_custom(func(l): return l.id == _lesson.id)
	if idx >= 0 and idx + 1 < lessons.size():
		var n: Dictionary = lessons[idx + 1]
		Session.begin_lesson(n.id, n.setup, Session.assist)
		get_tree().reload_current_scene()


func _coach(text: String, level: int) -> void:
	_notify(text, "", Notifications.CAUTION if level >= 1 else Notifications.INFO)
	_speak(text)


func _notify(title: String, detail: String, level: int) -> void:
	var n := get_tree().get_first_node_in_group("notifications")
	if n:
		n.post(title, detail, level, "train:" + title)


func _speak(text: String) -> void:
	var c := get_tree().get_first_node_in_group("callouts")
	if c and Session.assist != "off":
		c.speak(text)
