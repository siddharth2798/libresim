extends Node
## The A320 glareshield in the 3D cockpit (aircraft.json cockpit.levers, models/interior.glb): every FCU and EFIS
## control is a lever or a hotspot, a click aimed at it from the pilot's seat lands on it (not on a neighbouring knob's
## box), and a click, drag, push or pull writes its property. FCU pushbuttons spring back after a press.

const BUTTONS := {"ap1": "controls/fcu/ap1", "ap2": "controls/fcu/ap2", "athr": "controls/fcu/athr", "loc": "controls/fcu/loc",
	"appr": "controls/fcu/appr", "athr_disc_l": "controls/fcu/athr_disc", "athr_disc_r": "controls/fcu/athr_disc"}
const TOGGLES := {"spd_mach": "controls/fcu/spd_mach", "trk_fpa": "controls/fcu/trk_fpa", "metric_alt": "controls/fcu/metric_alt",
	"alt_inc": "controls/fcu/alt_inc_1000", "fd_cpt": "controls/fcu/fd", "fd_fo": "controls/fcu/fd", "ls_cpt": "controls/efis/ls",
	"ls_fo": "controls/efis/ls"}
const KNOBS := ["spd_sel", "hdg_sel", "alt_sel", "vs_sel", "baro_cpt", "baro_fo", "nd_mode_cpt", "nd_mode_fo", "nd_range_cpt",
	"nd_range_fo"]
const OPTIONS := ["cstr", "wpt", "vord", "ndb", "arpt"]
const KEEP := ["controls/fcu/ap1", "controls/fcu/ap2", "controls/fcu/athr", "controls/fcu/loc", "controls/fcu/appr",
	"controls/fcu/athr_disc", "controls/fcu/spd_mach", "controls/fcu/trk_fpa", "controls/fcu/metric_alt", "controls/fcu/alt_inc_1000",
	"controls/fcu/fd", "controls/efis/ls", "controls/efis/nd_filter", "controls/fcu/hdg_deg", "controls/fcu/spd_kt",
	"controls/fcu/alt_ft", "controls/fcu/vs_fpm", "controls/fcu/hdg_managed", "controls/fcu/spd_managed", "controls/fcu/vs_managed",
	"controls/fcu/vert_select", "controls/baro/hpa", "controls/baro/std", "weather/qnh_hpa", "controls/nd/mode", "controls/nd/range_nm"]

var _saved := {}
var _root: Node3D
var _lv: CockpitLevers


func teardown() -> void:
	for p in _saved:
		if _saved[p] == null:
			Props._p.erase(p)
		else:
			Props.set_v(p, _saved[p])
	_saved.clear()
	if _root != null:
		_root.free()
		_root = null


func _rig() -> void:
	for p in KEEP:
		_saved[p] = Props.get_v(p, null)
	_root = Node3D.new()
	add_child(_root)
	var glb: Node3D = (load("res://aircraft/a320/models/interior.glb") as PackedScene).instantiate()
	_root.add_child(glb)
	_lv = CockpitLevers.new()
	_root.add_child(_lv)
	_lv.build(glb, AircraftDef.load_def("a320").section("cockpit").levers)


func _item(name: String) -> Dictionary:
	for it in _lv._items:
		if str((it.node as Node).name) == "pivot_" + name:
			return it
	return {}


## Where a click on the control aims: the middle of its own meshes, or the hotspot.
func _aim(it: Dictionary) -> Vector3:
	var meshes := CockpitPickHit.owned_meshes(it.node)
	if meshes.is_empty():
		return (it.node as Node3D).global_position
	var box := AABB()
	for i in meshes.size():
		var mi := meshes[i] as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if i == 0 else box.merge(b)
	return box.get_center()


## The captain's eye (cockpit.eye) or, for a control right of the centre line, the first officer's (glb frame).
func _eye(at: Vector3) -> Vector3:
	return Vector3(-16.25, 0.52, 0.5 if at.z > -0.1 else -0.5)


func test_every_glareshield_control_is_picked_from_the_seat() -> String:
	_rig()
	var names: Array = BUTTONS.keys() + TOGGLES.keys() + KNOBS
	for o in OPTIONS:
		names += [o + "_cpt", o + "_fo"]
	for n in names:
		var it := _item(n)
		if it.is_empty():
			return "%s is not a cockpit lever" % n
		if n.begins_with("athr_disc"):
			continue  # on the thrust levers, below the glareshield
		var at := _aim(it)
		var eye := _eye(at)
		var hit := CockpitPick.pick(_lv._items, eye, (at - eye).normalized())
		if hit.is_empty() or hit.node != it.node:
			return "a click on %s picked %s" % [n, "nothing" if hit.is_empty() else str((hit.node as Node).name)]
	return ""


func test_fcu_buttons_toggle_their_request_and_spring_back() -> String:
	_rig()
	for n in BUTTONS:
		var it := _item(n)
		Props.set_v(BUTTONS[n], false)
		CockpitPick.commit(it)
		if not Props.get_b(BUTTONS[n]):
			return "%s did not set %s" % [n, BUTTONS[n]]
		var pressed := CockpitLevers.target(it)
		it.press_t = 0.0
		var rest := CockpitLevers.target(it)
		if absf(pressed - rest) < 1.0e-4:
			return "%s did not move in on the click (%s / %s)" % [n, pressed, rest]
		if absf(rest - ModelDrives.table(it.map, 0.0)) > 1.0e-6:
			return "%s stays pushed in while its function is on" % n
	return ""


func test_glareshield_hotspots_and_options_write_their_property() -> String:
	_rig()
	for n in TOGGLES:
		Props.set_v(TOGGLES[n], false)
		CockpitPick.commit(_item(n))
		if not Props.get_b(TOGGLES[n]):
			return "%s did not set %s" % [n, TOGGLES[n]]
		CockpitPick.commit(_item(n))
		if Props.get_b(TOGGLES[n]):
			return "%s did not clear %s" % [n, TOGGLES[n]]
	Props.set_v("controls/efis/nd_filter", 0)
	for side in ["_cpt", "_fo"]:
		for i in OPTIONS.size():
			CockpitPick.commit(_item(OPTIONS[i] + side))
			if roundi(Props.get_f("controls/efis/nd_filter")) != i + 1:
				return "%s%s selected %s" % [OPTIONS[i], side, Props.get_v("controls/efis/nd_filter")]
	CockpitPick.commit(_item("cstr_fo"))
	CockpitPick.commit(_item("cstr_cpt"))
	return "" if roundi(Props.get_f("controls/efis/nd_filter")) == 0 else "pressing the lit option again should clear it"


func test_fcu_knobs_turn_in_detents_and_push_or_pull() -> String:
	_rig()
	var hdg := _item("hdg_sel")
	Props.set_v("controls/fcu/hdg_deg", 359.0)
	CockpitPick.apply_motion(hdg, _lv._items, Vector2(0, -4))  # pointer up one detent: wraps to 0
	CockpitPick.release(hdg, false)  # a drag is not a push
	if Props.get_f("controls/fcu/hdg_deg") != 0.0 or Props.get_b("controls/fcu/hdg_managed"):
		return "HDG drag %s managed %s" % [Props.get_f("controls/fcu/hdg_deg"), Props.get_b("controls/fcu/hdg_managed")]
	CockpitPick.release(hdg, false)
	var pushed := Props.get_b("controls/fcu/hdg_managed")
	CockpitPick.release(hdg, true)
	if not pushed or Props.get_b("controls/fcu/hdg_managed"):
		return "HDG push / pull"
	var alt := _item("alt_sel")
	Props.set_v("controls/fcu/alt_inc_1000", false)
	Props.set_v("controls/fcu/alt_ft", 10000.0)
	CockpitPick.apply_motion(alt, _lv._items, Vector2(0, -6))
	var a100 := Props.get_f("controls/fcu/alt_ft")
	Props.set_v("controls/fcu/alt_inc_1000", true)
	CockpitPick.apply_motion(alt, _lv._items, Vector2(0, -6))
	var a1000 := Props.get_f("controls/fcu/alt_ft")
	CockpitPick.apply_motion(alt, _lv._items, Vector2(0, 6))
	if a100 != 10100.0 or a1000 != 11000.0 or Props.get_f("controls/fcu/alt_ft") != 10000.0:
		return "ALT steps %s %s %s" % [a100, a1000, Props.get_f("controls/fcu/alt_ft")]
	CockpitPick.release(alt, false)
	CockpitPick.release(alt, false)
	if not Props.get_b("controls/fcu/vs_managed") or str(Props.get_v("controls/fcu/vert_select", "")) != "MANAGED":
		return "ALT push is managed climb / descent"
	CockpitPick.release(alt, true)
	if Props.get_b("controls/fcu/vs_managed") or str(Props.get_v("controls/fcu/vert_select", "")) != "OPEN":
		return "ALT pull is open climb / descent"
	# V/S: a turn only presets the target (no mode request); the pull flies it; the push levels off (V/S 0)
	Props.set_v("controls/fcu/vert_select", "")
	Props.set_v("controls/fcu/vs_fpm", 0.0)
	CockpitPick.apply_motion(_item("vs_sel"), _lv._items, Vector2(0, 12))
	if Props.get_f("controls/fcu/vs_fpm") != -200.0 or str(Props.get_v("controls/fcu/vert_select", "")) != "":
		return "V/S turn presets %s and must not ask for a mode (%s)" % [Props.get_f("controls/fcu/vs_fpm"), Props.get_v("controls/fcu/vert_select")]
	CockpitPick.release(_item("vs_sel"), false)  # ends the drag (a release after a drag is no click)
	CockpitPick.release(_item("vs_sel"), true)
	if Props.get_f("controls/fcu/vs_fpm") != -200.0 or str(Props.get_v("controls/fcu/vert_select", "")) != "VS":
		return "V/S pull flies the preset"
	Props.set_v("controls/fcu/vs_fpm", -1200.0)
	CockpitPick.release(_item("vs_sel"), false)
	if Props.get_f("controls/fcu/vs_fpm") != 0.0 or str(Props.get_v("controls/fcu/vert_select", "")) != "LEVEL":
		return "V/S push levels off"
	CockpitPick.release(_item("spd_sel"), false)
	var spd := Props.get_b("controls/fcu/spd_managed")
	CockpitPick.release(_item("spd_sel"), true)
	return "" if spd and not Props.get_b("controls/fcu/spd_managed") else "SPD push / pull"


func test_efis_knobs_baro_and_nd() -> String:
	_rig()
	Props._p.erase("controls/baro/hpa")
	Props.set_v("weather/qnh_hpa", 1009.0)
	var baro := _item("baro_fo")
	CockpitPick.apply_motion(baro, _lv._items, Vector2(0, -5))
	if Props.get_f("controls/baro/hpa") != 1010.0:
		return "BARO starts from the weather QNH: %s" % Props.get_f("controls/baro/hpa")
	CockpitPick.release(baro, false)
	CockpitPick.release(baro, true)
	var std := Props.get_b("controls/baro/std")
	CockpitPick.release(baro, false)
	if not std or Props.get_b("controls/baro/std"):
		return "BARO pull = STD, push = QNH"
	var rng := _item("nd_range_cpt")
	Props.set_v("controls/nd/range_nm", 40.0)
	CockpitPick.release(rng, false)
	var up := Props.get_f("controls/nd/range_nm")
	CockpitPick.release(rng, true)
	var back := Props.get_f("controls/nd/range_nm")
	CockpitPick.apply_motion(rng, _lv._items, Vector2(0, -14))
	CockpitPick.release(rng, false)
	if up != 80.0 or back != 40.0 or Props.get_f("controls/nd/range_nm") != 80.0:
		return "ND range %s %s %s" % [up, back, Props.get_f("controls/nd/range_nm")]
	var mode := _item("nd_mode_fo")
	Props.set_v("controls/nd/mode", 0)
	CockpitPick.release(mode, false)
	var plan := Props.get_f("controls/nd/mode")  # the knob turns LS VOR NAV ARC PLAN: ARC -> PLAN, then round to LS
	CockpitPick.release(mode, false)
	var ls := Props.get_f("controls/nd/mode")
	return "" if plan == 4.0 and ls == 3.0 else "ND mode knob %s %s" % [plan, ls]
