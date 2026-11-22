extends Node
## The green bars on the A320 FCU and EFIS buttons (CockpitLamps, CockpitBarLamps): each lights with its mode, not with
## the press; EXPED (no system) stays dark; brightness is steady by day, low and dimmable at night, off without power;
## the bars baked into the static cockpit mesh are split out so they can go dark.

const KEEP := ["controls/fcu/ap1", "ap/ap1", "ap/ap2", "controls/fcu/loc", "ap/loc", "controls/fcu/appr", "ap/appr", "ap/athr",
	"ap/fd", "controls/efis/ls", "controls/efis/nd_filter", "systems/electrical/powered", "environment/sun_elev_deg"]

var _saved := {}
var _root: Node


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


func _keep() -> void:
	for p in KEEP:
		_saved[p] = Props.get_v(p, null)


func test_fcu_lamps_follow_the_mode_not_the_press() -> String:
	_keep()
	Props.set_v("controls/fcu/loc", true)  # pressed, but no localiser to arm
	Props.set_v("ap/loc", false)
	if CockpitLamps.lit("lamp_loc"):
		return "LOC lit on the press with LOC neither armed nor engaged"
	Props.set_v("ap/loc", true)
	if not CockpitLamps.lit("lamp_loc"):
		return "LOC dark with LOC armed"
	Props.set_v("controls/fcu/ap1", true)  # requested on the ground: refused
	Props.set_v("ap/ap1", false)
	if CockpitLamps.lit("lamp_ap1"):
		return "AP1 lit while the autopilot is not engaged"
	Props.set_v("ap/ap1", true)
	Props.set_v("ap/ap2", false)
	if not CockpitLamps.lit("lamp_ap1") or CockpitLamps.lit("lamp_ap2"):
		return "AP1 / AP2 lamps"
	Props.set_v("ap/athr", true)
	Props.set_v("controls/fcu/appr", true)
	Props.set_v("ap/appr", false)
	if not CockpitLamps.lit("lamp_athr") or CockpitLamps.lit("lamp_appr"):
		return "A/THR / APPR lamps"
	Props.set_v("ap/fd", true)
	Props.set_v("controls/efis/ls", false)
	Props.set_v("controls/efis/nd_filter", 5)
	if not CockpitLamps.lit("lamp_fd_cpt") or not CockpitLamps.lit("lamp_fd_fo") or CockpitLamps.lit("lamp_ls_fo"):
		return "FD / LS lamps"
	if not CockpitLamps.lit("lamp_arpt_cpt") or CockpitLamps.lit("lamp_ndb_cpt") or CockpitLamps.lit("lamp_exped"):
		return "ND option lamps (ARPT only) and EXPED dark"
	return ""


func test_bar_brightness_by_day_night_dimmer_and_bus() -> String:
	var day := CockpitLamps.bar_energy(0.0, 0.5, true)
	var night_low := CockpitLamps.bar_energy(1.0, 0.0, true)
	var night_high := CockpitLamps.bar_energy(1.0, 1.0, true)
	var dead := CockpitLamps.bar_energy(0.0, 1.0, false)
	if day < 1.0 or night_high >= day or night_low >= night_high or night_low <= 0.0 or dead != 0.0:
		return "day %s night %s..%s dead %s" % [day, night_low, night_high, dead]
	return ""


func test_bar_lamps_are_built_and_light_with_their_mode() -> String:
	_keep()
	_root = Node3D.new()
	add_child(_root)
	var glb: Node3D = (load("res://aircraft/a320/models/interior.glb") as PackedScene).instantiate()
	_root.add_child(glb)
	var cfg: Dictionary = AircraftDef.load_def("a320").section("cockpit").bar_lamps
	var bars := CockpitBarLamps.new()
	_root.add_child(bars)
	var n := bars.build(glb, cfg)
	var want: int = cfg.pivots.size() + cfg.split.size()
	if n != want:
		return "built %d bar lamps, want %d (%s)" % [n, want, bars.names()]
	for k in cfg.split:  # each split lamp is a small patch at its button
		var mi := glb.find_child("lamp_" + k, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			return "no lamp_%s" % k
		var c: Vector3 = mi.transform * mi.get_aabb().get_center()
		var fg := Vector3(c.x, -c.z, c.y)
		var at := Vector3(cfg.split[k][0], cfg.split[k][1], cfg.split[k][2])
		if fg.distance_to(at) > 0.012 or mi.get_aabb().size.length() > 0.03:
			return "lamp_%s at %s size %s, want near %s" % [k, fg, mi.get_aabb().size, at]
	Props.set_v("systems/electrical/powered", true)
	Props.set_v("environment/sun_elev_deg", 40.0)
	Props.set_v("ap/ap1", true)
	Props.set_v("ap/ap2", false)
	bars._process(0.0)
	var on := _lit(glb, "lamp_ap1")
	var off := _lit(glb, "lamp_ap2")
	Props.set_v("systems/electrical/powered", false)
	bars._process(0.0)
	var dead := _lit(glb, "lamp_ap1")
	if on != 1.0 or off != 0.0 or dead != 0.0:
		return "lit uniforms: AP1 %s AP2 %s AP1 unpowered %s" % [on, off, dead]
	return ""


func _lit(glb: Node, lamp: String) -> float:
	var mi := glb.find_child(lamp, true, false) as MeshInstance3D
	return float((mi.material_override as ShaderMaterial).get_shader_parameter("lit"))
