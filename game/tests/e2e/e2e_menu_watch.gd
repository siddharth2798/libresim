extends Node
## Survives the start screen's change_scene to the flight (added to the root by
## e2e_menu.gd): checks that FLY started the chosen flight, then quits.

var out := "/tmp/e2e"
var _t := 0.0
var _seen := -1.0
var _done := false


func _process(dt: float) -> void:
	_t += dt
	var cs := get_tree().current_scene
	if _seen < 0.0 and cs != null and cs.name == "Flight":
		_seen = _t
	if _done:
		return
	if _seen >= 0.0 and _t - _seen > 8.0:
		_done = true
		_finish(cs)
	elif _t > 90.0:
		_done = true
		_finish(null)


func _finish(f: Node) -> void:
	var checks := []
	var ok := f != null
	checks.append({"name": "fly_launches_flight", "ok": ok, "detail": "flight scene up after %.1f s" % _seen if ok else "no flight scene after 90 s"})
	if ok:
		var apt: String = f.get("_apt")
		var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
		var st: Dictionary = f.get("_start")
		var d := Vector2(p.x, p.y).distance_to(st.pos)
		checks.append({"name": "fly_uses_setup_airport", "ok": apt == "VAPO" and d < 100.0, "detail": "airport %s, %.0f m from the runway 28 start" % [apt, d]})
		checks.append({"name": "fly_uses_setup_weather", "ok": absf(Props.get_f("weather/cloud_cover") - 0.95) < 0.01 and absf(Props.get_f("weather/time_h") - 7.5) < 0.2,
			"detail": "cloud %.2f time %.2f" % [Props.get_f("weather/cloud_cover"), Props.get_f("weather/time_h")]})
		checks.append({"name": "fly_not_crashed", "ok": not Props.get_b("damage/crashed"), "detail": str(Props.get_v("damage/events", []))})
	for c in checks:
		print("E2E %s %s: %s" % ["PASS" if c.ok else "FAIL", c.name, c.detail])
	await RenderingServer.frame_post_draw
	var path := out.path_join("shots/menu_fly.png")
	get_viewport().get_texture().get_image().save_png(path)
	DirAccess.make_dir_recursive_absolute(out.path_join("results"))
	var fa := FileAccess.open(out.path_join("results/menu_fly.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify({"tag": "menu_fly", "scenario": "menu_fly", "checks": checks, "metrics": {},
		"shots": [{"name": "fly", "path": path}]}, "  "))
	fa.close()
	get_tree().quit()
