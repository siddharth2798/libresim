extends RefCounted
## Special views for tests/debug_showcase.gd scene definitions: the follow-me car, the moving map, panel layouts,
## the pause screen, the floating checklist and the taxi banner after landing. `s` is the showcase node
## (s.f = the flight scene; s.wait / s.frames / s.save).


## Follow-me car scenes: ask for taxi, optionally stand the aircraft m metres along the route (nose along
## it, brakes on), put the car ~55 m ahead of it and let it settle (it waits for the aircraft there).
static func follow_me(s: Node, d: Dictionary) -> void:
	var f: Node = s.f
	var g: GroundOps = f.get_node("GroundOps")
	g.request_taxi()
	await s.wait(1.0)
	if d.has("on_route_m") and not g._route.is_empty():
		var r := g._route_at(float(d.on_route_m))
		var fd: FDM = f.get_node("Fdm").fdm
		fd.pos_e = r[0].x
		fd.pos_n = r[0].y
		var e := fd.euler()
		fd.q = FDM.euler_to_quat(e.x, e.y, r[1])
		fd.v_b = Vector3.ZERO
		fd.w_b = Vector3.ZERO
		Props.set_v("controls/parking_brake", true)
		g._follow_s = float(d.on_route_m) + 55.0
	await s.wait(float(d.get("secs", 12.0)))
	if g._follow != null:  # where the car stands relative to the aircraft's nose
		var ap: Vector3 = f.get_node("Fdm").position_enu()
		var rel := Vector2(g._follow.world_enu.x - ap.x, g._follow.world_enu.y - ap.y)
		var hd := Props.get_f("fdm/heading_rad", 0.0)
		print("FOLLOW_ME car %.0f m ahead, %.0f m right of the aircraft" % [rel.dot(Vector2(sin(hd), cos(hd))), rel.dot(Vector2(cos(hd), -sin(hd)))])
	else:
		print("FOLLOW_ME no car")


## The overlays a view asks for, once the scenery has settled: map, panel layout, pause page, checklist.
static func overlays(s: Node, d: Dictionary) -> void:
	var f: Node = s.f
	if d.get("map", false):
		await show_map(s, d)
	if d.has("panel"):
		var pn = f.get_node("UI/Panel")
		pn.layout = int(d.panel)
		pn._build()
	if d.has("pause"):  # the full-screen pause over the frozen scene (UI/Pause was hidden by hide_ui)
		var pm: Control = f.get_node("UI/Pause")
		pm.visible = false
		pm.open()
		pm.show_page(str(d.pause))
	if d.has("checklist"):
		await show_checklist(s, d.checklist)


static func show_map(s: Node, d: Dictionary) -> void:
	var m: Control = s.f.get_node("UI/Map")
	m.clip_contents = true  # the map draws imagery tiles past its own edge otherwise
	var route: Array = d.get("map_route", [d.gps] if d.has("gps") else [])  # GPS direct-to, then later legs
	Props.set_v("controls/gps/target", route[0] if not route.is_empty() else "")
	Props.set_v("controls/gps/route_next", route.slice(1))
	m.set_process(true)  # hide_ui stopped it; it redraws from _process
	m.visible = true  # opens centred on the aircraft (wider if the route needs it)
	await s.wait(1.0)
	var v := {"heading_up": d.get("map_heading_up", false)}
	if d.has("map_across"):
		v["across_nm"] = d.map_across
	if d.has("map_centre_on"):
		v["centre_on"] = d.map_centre_on
	m.apply_view(v)
	await s.wait(1.0)
	m.wait_imagery()  # tiles load on worker threads
	await s.wait(0.5)


## Just after landing (the aircraft stands on the runway): ATC gives "taxi to the apron". Saves the
## screen 1.5 s after the instruction (<scene>_a) and again once it has faded (<scene>_b).
static func taxi_banner(s: Node, d: Dictionary) -> void:
	var f: Node = s.f
	var atc: Control = f.get_node("UI/Atc")
	atc.session.c.set_state("landed")
	if d.get("stack", false):  # the cards that usually come with a landing
		var notes := s.get_tree().get_first_node_in_group("notifications") as Notifications
		notes.post("Touchdown · Smooth", "420 fpm · 1.2 g · 63 KIAS", Notifications.INFO, "td")
	var txt: String = f.get_node("GroundOps").request_taxi_to_stand()
	print("TAXI instruction: ", txt)
	await s.wait(1.5)
	await s.save("_a")
	await s.wait(float(d.get("fade_s", 15.0)))
	await s.save("_b")


## The floating checklist (F2) in a given state: {frac: [x, y] (omit = default dock), size: [w, h],
## opacity, collapsed, list, ticks (items ticked by hand)}.
static func show_checklist(s: Node, d: Dictionary) -> void:
	var cl: ChecklistPanel = s.f.get_node("UI/Checklist")
	cl.persist = false
	cl.current = int(d.get("list", 0))
	cl._rebuild()
	for i in int(d.get("ticks", 0)):
		cl._manual["%d/%d" % [cl.current, i]] = true
	cl.visible = true
	if d.has("frac"):
		cl.set_placement(Vector2(d.frac[0], d.frac[1]), Vector2(d.size[0], d.size[1]), float(d.get("opacity", 0.9)), bool(d.get("collapsed", false)))
	else:
		cl.set_opacity(float(d.get("opacity", 0.9)), false)
		if d.get("collapsed", false):
			cl.set_collapsed(true)
	await s.frames(3)
