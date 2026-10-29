extends Node
## Debug: the A320 cockpit controls in the real flight scene. Each view is  name | k=v,k=v | eye | target  (eye and target
## in structural metres, x aft / y right / z up from the model origin; empty eye = the pilot's cockpit view): the property
## values are set, the controls settle, a screenshot <shots>/<name>.png is saved.
##   godot --path game res://tests/debug_levers.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB --stand --clean \
##     --shots=<abs dir> --views="idle|controls/throttle_1=0|-15.6,0.2,-0.1|-16.5,-0.05,-0.2;toga|controls/throttle_1=1,controls/throttle_2=1||"
var f: Node
var _shots := ""
var _views: Array = []
var _probe: PackedStringArray = []
var _force := {}  # property values re-applied every frame (the input code rewrites the controls)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--probe="):
			_probe = a.substr(8).split(",")
		elif a.begins_with("--views="):
			for v in a.substr(8).split(";", false):
				_views.append(v.split("|"))
	DirAccess.make_dir_recursive_absolute(_shots)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _apply(spec: String) -> void:
	for kv in spec.split(",", false):
		var p := kv.split("=")
		var v: Variant = p[1]
		if v == "true" or v == "false":
			v = v == "true"
		elif p[0] in ["controls/flaps", "controls/gear", "controls/engine_mode", "controls/autobrake"]:
			v = int(v)
		else:
			v = float(v)
		_force[p[0]] = v
		Props.set_v(p[0], v)


func _process(_dt: float) -> void:
	for k in _force:
		Props.set_v(k, _force[k])


func _run() -> void:
	await get_tree().create_timer(8.0).timeout
	var cam: CameraRig = f.get_node("Camera")
	var m: AircraftModel = f.get_node("Aircraft")
	for v in _views:
		_apply(v[1] if v.size() > 1 else "")
		if v.size() > 2 and v[2] != "":
			cam.set_mode(3)
			var e := FloatingOrigin.to_world(m.global_transform * m._s(_vec(v[2])))
			var d := FloatingOrigin.to_world(m.global_transform * m._s(_vec(v[3]))) - e
			cam._free_enu = e
			cam._look = Vector2(-atan2(d.x, d.y), atan2(d.z, Vector2(d.x, d.y).length()))
		else:
			cam.set_mode(0)
			if v.size() > 3 and v[3] != "":  # yaw,pitch deg of the pilot's head
				var a: PackedStringArray = v[3].split(",")
				cam._look = Vector2(deg_to_rad(float(a[0])), deg_to_rad(float(a[1])))
				cam._look_goal = cam._look
		Props.set_v("view/mode", "Cockpit")  # the levers only move in the cockpit view
		await get_tree().create_timer(2.5).timeout
		for pn in _probe:  # pivots' positions in the aircraft's render frame (x right, y up, z aft; forward = -z), cm
			var nd: Node3D = m.cockpit.interior.find_child("pivot_" + pn, true, false)
			var pp := m.to_local(nd.global_position) * 100.0
			print("PROBE %s %s (%.1f %.1f %.1f)" % [v[0], pn, pp.x, pp.y, pp.z])
		var lv: CockpitLevers = m.cockpit.levers
		print("LEVERS ", lv._items.size() if lv else -1, " active ", lv._active if lv else false, " throttle_1 ", Props.get_f("controls/throttle_1"),
			" thr_l angle ", (lv._items.filter(func(i): return i.node.name == "pivot_thr_l")[0].value) if lv else 0.0)
		get_viewport().get_texture().get_image().save_png(_shots.path_join(v[0] + ".png"))
		print("SHOT ", v[0])
	get_tree().quit()
