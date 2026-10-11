extends RefCounted
## E2E scenarios: taxi guidance + pushback, in-flight panels/credits, save & load,
## replay, session recording.

## [key, shift, node path under the flight scene, property holder ("" = node itself)]
const PANELS := [
	["F9 failures", KEY_F9, "UI/Failures", ""],
	["F10 settings", KEY_F10, "UI/Settings", ""],
	["F2 checklists", KEY_F2, "UI/Checklist", ""],
	["N moving map", KEY_N, "UI/Map", ""],
	["` radio/ATC", KEY_QUOTELEFT, "UI/Atc", ""],
	["F12 credits", KEY_F12, "UI/Credits", "_panel"],
	["Esc pause", KEY_ESCAPE, "UI/Pause", ""],
	["F1 key help", KEY_F1, "UI/Hud", "_help"],
	["J controls", KEY_J, "ControlsOverlay", ""],
]


## VABB stand start (--stand): T taxi route + follow-me, then P pushback.
func taxi(r) -> void:
	await r.wait(6.0)
	var g: Node = r.f.get_node("GroundOps")
	await r.key(KEY_T)
	await r.wait(2.0)
	var route := str(r.p("ops/taxi_route", ""))
	r.check("taxi_route_T", route.begins_with("Taxi to runway"), "ops/taxi_route='%s'" % route)
	r.check("follow_me_spawned", g.get("_follow") != null, "")
	r.check("route_line_drawn", g.get("_line") != null, "")
	r.metric("taxi_route", route)
	await r.key(KEY_9)  # no-op key; let the follow-me move a bit
	await r.wait(3.0)
	await r.shot("taxi_route")
	await r.key(KEY_T)
	await r.wait(0.5)
	r.check("taxi_route_cleared", g.get("_line") == null, "")
	# pushback: parking brake off, then P
	r.take_controls()
	r.f.get_node("Controls").parking_brake = false
	Props.set_v("controls/parking_brake", false)
	for b in ["brake_left", "brake_right"]:
		Props.set_v("controls/" + b, 0.0)
	await r.wait(1.0)
	var p0: Vector3 = r.f.get_node("Fdm").position_enu()
	var h0: float = r.hdg_deg()
	await r.key(KEY_P)
	await r.wait(1.0)
	r.check("pushback_tug_spawned", g.get("_tug") != null, "label: %s" % g.get("_label").text)
	await r.wait(14.0)
	await r.shot("pushback")
	var p1: Vector3 = r.f.get_node("Fdm").position_enu()
	var fwd := Vector2(sin(deg_to_rad(h0)), cos(deg_to_rad(h0)))
	var moved := Vector2(p1.x - p0.x, p1.y - p0.y)
	r.metric("push_moved_m", moved.length())
	r.metric("push_along_m", moved.dot(fwd))
	r.metric("push_turned_deg", r.angle_diff(r.hdg_deg(), h0))
	r.check("pushback_moves_backward", moved.dot(fwd) < -5.0, "moved %.1f m along the nose (negative = backward), turned %.0f deg" % [moved.dot(fwd), r.metrics.push_turned_deg])
	r.check("pushback_not_crashed", not r.p("damage/crashed", false), str(r.p("damage/events", [])))


func _vis(r, path: String, holder: String) -> bool:
	var n: Node = r.f.get_node_or_null(path)
	if n == null:
		return false
	if holder == "*":
		for c in n.get_children():
			if c is CanvasItem and c.visible:
				return true
		return false
	if holder != "":
		n = n.get(holder)
	return n != null and n.visible


## Every in-flight panel opens with its key and closes again.
func panels(r) -> void:
	await r.wait(6.0)
	for pn in PANELS:
		var before := _vis(r, pn[2], pn[3])
		await r.key(pn[1])
		await r.wait(0.6)
		var after := _vis(r, pn[2], pn[3])
		var ok: bool = after and not before
		var shot := str(pn[0]).get_slice(" ", 0).replace("`", "backquote")
		await r.shot("panel_" + shot)
		await r.key(pn[1])
		await r.wait(0.4)
		var closed := not _vis(r, pn[2], pn[3])
		if pn[1] == KEY_QUOTELEFT and not closed:  # ` reopens the menu; Esc / ` again closes
			await r.key(KEY_QUOTELEFT)
			await r.wait(0.3)
			closed = not _vis(r, pn[2], pn[3])
		r.check("panel " + str(pn[0]), ok and closed, "before=%s open=%s closed_again=%s" % [before, after, closed])
	get_tree_paused_check(r)


func get_tree_paused_check(r) -> void:
	r.check("not_left_paused", not r.get_tree().paused, "tree paused=%s" % r.get_tree().paused)


## Save, fly on, load: back at the saved position, speed and altitude. Then F11 / Shift+F11.
func saveload(r) -> void:
	await r.wait(5.0)
	var fn: Node = r.f.get_node("Fdm")
	var p0: Vector3 = fn.position_enu()
	var k0: float = r.kias()
	var err: String = Situation.save(r.f, "e2e_test")
	r.check("save", err == "", "error='%s'" % err)
	await r.wait(10.0)
	var file: String = SituationStore.file_name("e2e_test")
	err = Situation.load_file(r.f, file)
	await r.frames(2)
	var p1: Vector3 = fn.position_enu()
	r.check("load", err == "", "error='%s' file=%s" % [err, file])
	r.check("load_restores_position", p0.distance_to(p1) < 5.0, "%.1f m from the saved position" % p0.distance_to(p1))
	r.check("load_restores_speed", absf(r.kias() - k0) < 3.0, "%.1f -> %.1f KIAS" % [k0, r.kias()])
	await r.wait(5.0)
	r.check("flies_after_load", not r.p("damage/crashed", false) and r.kias() > 50.0, "%.0f KIAS" % r.kias())
	Situation.delete(file)
	p0 = fn.position_enu()
	await r.key(KEY_F11)  # quick-save
	await r.wait(5.0)
	await r.key(KEY_F11, true)  # quick-load
	await r.frames(3)
	var d: float = p0.distance_to(fn.position_enu())
	r.check("quicksave_F11_quickload_shiftF11", d < 60.0, "%.1f m from the quick-save point (5 s of flight = ~230 m)" % d)
	await r.shot("after_load")


## Replay: R starts it, seek/speed work, take control flies on; R again exits.
func replay(r) -> void:
	await r.wait(22.0)
	var rp: Node = r.f.get_node("Replay")
	var fn: Node = r.f.get_node("Fdm")
	var live: Vector3 = fn.position_enu()
	await r.key(KEY_R)
	await r.wait(0.5)
	r.check("replay_R_starts", rp.active and bool(r.p("replay/active", false)), "active=%s" % rp.active)
	rp.set_speed(2.0)
	var t0: float = rp.t
	await r.frames(60)
	await r.shot("replay")
	r.check("replay_advances", rp.t > t0, "t %.2f -> %.2f" % [t0, rp.t])
	r.check("replay_fdm_held", fn.replaying, "")
	await r.key(KEY_R)
	await r.frames(3)
	var back: float = live.distance_to(fn.position_enu())
	r.check("replay_R_exits_to_live", not rp.active and back < 400.0, "active=%s, %.0f m from the live position" % [rp.active, back])
	await r.wait(5.0)
	rp.start_replay(10.0)
	await r.frames(10)
	var k: float = r.kias()
	rp.take_control()
	await r.wait(10.0)
	r.check("replay_take_control_flies", not rp.active and not r.p("damage/crashed", false) and r.kias() > 50.0,
		"took control at %.0f KIAS, 10 s later %.0f KIAS alt %.0f ft" % [k, r.kias(), r.alt_ft()])


## F8 records 6 s to an MKV in <out>/rec (ffprobe'd by tools/e2e_report.py).
func record(r) -> void:
	await r.wait(5.0)
	var rec: Node = r.f.get_node("UI/Recorder")
	await r.key(KEY_F8)
	await r.wait(0.5)
	r.check("record_F8_starts", rec.recording, "path=%s" % rec.path)
	await r.wait(6.0)
	await r.key(KEY_F8)
	await r.wait(1.0)
	r.check("record_F8_stops", not rec.recording, rec.text)
	r.metric("mkv", rec.path)
	r.check("mkv_written", FileAccess.file_exists(rec.path) and FileAccess.get_file_as_bytes(rec.path).size() > 100000,
		"%s %d bytes" % [rec.path, FileAccess.get_file_as_bytes(rec.path).size() if FileAccess.file_exists(rec.path) else 0])
