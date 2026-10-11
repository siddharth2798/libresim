extends RefCounted
## E2E scenarios: start positions (runway / air / stand), and the 8 camera views.

const VIEWS := ["cockpit", "chase", "orbit", "free", "tower", "wing", "tail", "flyby"]


func _runway_end(apt: String, ident: String) -> Dictionary:
	var d = Paths.load_json("runways.json")
	if d == null:
		return {}
	var best := {}
	var best_len := -1.0
	for r in d.runways:
		if r.airport != apt:
			continue
		for e in r.ends:
			if (ident == "" and float(r.length) > best_len) or e.ident == ident:
				best = e
				best_len = float(r.length)
				if ident != "":
					return e
	return best


## Start, let it settle, then check it is where and how it should be.
func spawn(r) -> void:
	var s: Dictionary = Session.setup
	var kind: String = s.start
	var t0_pos: Vector3 = r.f.get_node("Fdm").position_enu()
	await r.wait(float(r.arg("e2e_dur", 7.0)))
	var crashed: bool = r.p("damage/crashed", false)
	r.check("not_crashed", not crashed, "reason=%s events=%s" % [r.p("damage/reason", ""), str(r.p("damage/events", []))])
	var agl: float = r.p("fdm/agl_m")
	var wow: bool = r.p("fdm/wow", false)
	var pos: Vector3 = r.f.get_node("Fdm").position_enu()
	var ground := float(r.p("fdm/alt_m")) - agl
	var terr: float = r.f.get_node("Terrain").height_at(pos.x, pos.y)
	r.metric("agl_m", agl)
	r.metric("wow", wow)
	r.metric("kias", r.kias())
	r.metric("hdg", r.hdg_deg())
	r.metric("moved_m", Vector2(pos.x - t0_pos.x, pos.y - t0_pos.y).length())
	r.metric("fdm_ground_m", ground)
	r.metric("terrain_mesh_h_m", terr)
	var start: Dictionary = r.f._start
	var ident: String = start.get("ident", "")
	if kind == "air":
		var want := float(s.air_ft) * 0.3048
		r.check("airborne", not wow, "wow=%s" % wow)
		var sp: Vector2 = r.f._start.pos  # height is set above the runway, not above the ground 5 nm out
		var above_field: float = float(r.p("fdm/alt_m")) - r.f.get_node("Terrain").height_at(sp.x, sp.y)
		r.check("height_above_field_plausible", absf(above_field - want) < 120.0 and agl > 60.0,
			"%.0f m above the runway (wanted ~%.0f m), agl %.0f m" % [above_field, want, agl])
		r.check("airspeed_plausible", r.kias() > 60.0 and r.kias() < 130.0, "%.0f KIAS" % r.kias())
	else:
		r.check("on_ground_wow", wow, "wow=%s" % wow)
		r.check("agl_plausible", agl > 0.2 and agl < 2.5, "agl %.2f m (CG above ground)" % agl)
		r.check("ground_matches_terrain", absf(ground - terr) < 1.0, "fdm ground %.2f m vs terrain mesh %.2f m" % [ground, terr])
		if kind == "runway":
			var e := _runway_end(r.f._apt, ident)
			if not e.is_empty():
				r.check("on_runway_elevation", absf(ground - float(e.h)) < 4.0, "ground %.1f m vs runway end %.1f m" % [ground, float(e.h)])
			r.check("stayed_near_start", r.metrics.moved_m < 80.0, "moved %.0f m" % r.metrics.moved_m)
		else:
			r.check("cold_and_dark", not bool(r.p("engine/running", false)), "engine running=%s" % r.p("engine/running", false))
			r.check("parking_brake", bool(r.p("controls/parking_brake", false)), "")
			r.check("stand_assigned", str(r.p("ops/stand", "")) != "", "stand=%s" % r.p("ops/stand", ""))
	if kind != "stand" and ident != "" and ident.substr(0, 2).is_valid_int():
		var want_h := float(ident.substr(0, 2).to_int() * 10)
		r.check("heading_matches_ident", r.angle_diff(r.hdg_deg(), want_h) < 12.0,
			"rwy %s heading %.1f deg (runway true %.1f)" % [ident, r.hdg_deg(), float(start.heading_deg)])
	var wx: String = r.arg("e2e_wx", "")
	if wx != "":
		var want: Dictionary = Session.WEATHER.get(wx, {})
		r.check("weather_preset_applied", Session.setup.weather == wx and absf(Props.get_f("weather/visibility_m") - float(want.get("visibility_m", -1))) < 1.0,
			"--weather=%s -> setup.weather '%s', visibility %.0f m (preset %s)" % [wx.to_lower(), Session.setup.weather, Props.get_f("weather/visibility_m"), want.get("visibility_m", "?")])
	var tod: String = r.arg("tod", "")
	if tod != "":
		r.metric("sun_elev_deg", r.p("environment/sun_elev_deg"))
	r.metric("fps", Engine.get_frames_per_second())
	await r.shot(r.arg("e2e_shot", "main"))


## Every camera view, through the 1-8 keys.
func views(r) -> void:
	await r.wait(6.0)
	for i in VIEWS.size():
		await r.key(KEY_1 + i)
		await r.wait(1.5)
		var mode := str(r.p("view/mode", ""))
		var cm: int = r.f.get_node("Camera").mode
		r.check("view_" + VIEWS[i], cm == i, "camera mode %d, view/mode=%s" % [cm, mode])
		await r.shot("view_%d_%s" % [i + 1, VIEWS[i]])
	await r.key(KEY_C)  # C cycles from flyby back to cockpit
	await r.frames(2)
	r.check("view_cycle_C", r.f.get_node("Camera").mode == 0, "after C: %s" % r.p("view/mode", ""))
