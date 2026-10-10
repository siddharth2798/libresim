extends RefCounted
## M7 navigation tests: VOR radial/CDI sense (TO and FROM), DME, ILS localizer & glideslope,
## terrain line-of-sight blocking.

const NM := 1852.0
const FT := 0.3048


func _radios() -> NavRadios:
	var n := NavRadios.new()
	n._ready()
	var tq := TerrainQuadtree.new()
	tq.cache = TerrainTileCache.new()
	n.terrain = tq
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("failures/nav1", false)
	Props.set_v("failures/nav2", false)
	return n


func _vor(n: NavRadios, ident: String) -> Dictionary:
	for v in n.db.vors:
		if v.ident == ident:
			return v
	return {}


func _fly(n: NavRadios, pos: Vector3, heading_deg: float) -> void:
	Props.set_v("fdm/position_enu", pos)
	Props.set_v("fdm/heading_rad", deg_to_rad(heading_deg))
	n._los_t = 0.0
	n._physics_process(0.1)


func test_nav_vor_radial_and_cdi_sense() -> String:
	var n := _radios()
	var v := _vor(n, "BBB")
	if v.is_empty():
		return "BBB VOR missing from navaids.json"
	Props.set_v("controls/nav1/freq_mhz", v.mhz)
	# 20 nm due east of the station at 6000 ft: magnetic radial ~ 090 + 0.5 (variation -0.5)
	var p := Vector3(v.x + 20.0 * NM, v.y, 6000.0 * FT)
	Props.set_v("controls/nav1/obs_deg", 90.0)
	_fly(n, p, 90.0)
	var radial := Props.get_f("avionics/nav1/radial_deg")
	var tf: int = Props.get_v("avionics/nav1/to_from")
	print("    on radial %.1f, FROM flag %s, DME %.1f nm" % [radial, tf < 0, Props.get_f("avionics/nav1/dme_nm")])
	if absf(wrapf(radial - 90.5, -180, 180)) > 1.0 or tf >= 0:
		return "expected radial ~090 FROM, got %.1f to_from %d" % [radial, tf]
	if absf(Props.get_f("avionics/nav1/dme_nm") - 20.0) > 0.5:
		return "DME wrong"
	# FROM, OBS 090: move north of the course (left of track when flying east) -> needle right
	_fly(n, p + Vector3(0, 1.0 * NM, 0), 90.0)
	var c1 := Props.get_f("avionics/nav1/cdi")
	# TO, OBS 270 (flying west to the station): same spot north of track = right of track -> needle left
	Props.set_v("controls/nav1/obs_deg", 270.0)
	_fly(n, p + Vector3(0, 1.0 * NM, 0), 270.0)
	var c2 := Props.get_f("avionics/nav1/cdi")
	print("    1 nm north of the 090 radial: FROM 090 cdi %+.2f, TO 270 cdi %+.2f" % [c1, c2])
	if not (c1 > 0.2 and c2 < -0.2):
		return "CDI sense wrong (FROM %+.2f should be right, TO %+.2f should be left)" % [c1, c2]
	return ""


func test_nav_ils_on_path() -> String:
	var n := _radios()
	var s: Dictionary = {}
	for i in n.db.ils:
		if i.ident == "IBB27":
			s = i
	if s.is_empty():
		return "IBB27 missing (run tools/14_ils.py)"
	Props.set_v("controls/nav2/freq_mhz", s.mhz)
	var th := Vector2(s.threshold.x, s.threshold.y)
	var back := -Vector2(sin(deg_to_rad(s.course_true)), cos(deg_to_rad(s.course_true)))
	# 5 nm final on the extended centreline, on a 3 deg path through the GS antenna point
	var gs := Vector2(s.gs.x, s.gs.y)
	var p2 := th + back * 5.0 * NM
	var alt: float = s.gs.h + tan(deg_to_rad(3.0)) * p2.distance_to(gs)
	_fly(n, Vector3(p2.x, p2.y, alt), s.course_true)
	var cdi := Props.get_f("avionics/nav2/cdi")
	var g := Props.get_f("avionics/nav2/gs")
	print("    5 nm final: LOC %+.2f, GS %+.2f (valid %s)" % [cdi, g, Props.get_b("avionics/nav2/gs_valid")])
	if absf(cdi) > 0.1 or absf(g) > 0.15 or not Props.get_b("avionics/nav2/gs_valid"):
		return "on-path readings off: loc %+.2f gs %+.2f" % [cdi, g]
	_fly(n, Vector3(p2.x, p2.y, alt + 150.0), s.course_true)  # 500 ft high -> fly down
	if Props.get_f("avionics/nav2/gs") > -0.5:
		return "high on the glideslope did not show fly-down"
	return ""


func test_nav_terrain_blocks_vor() -> String:
	var n := _radios()
	var v := _vor(n, "PUN")
	Props.set_v("controls/nav1/freq_mhz", v.mhz)
	# low in the Konkan, west of the Western Ghats escarpment, ~65 km from Pune
	_fly(n, Vector3(-15000.0, -15000.0, 120.0), 90.0)
	var low: bool = Props.get_b("avionics/nav1/valid")
	_fly(n, Vector3(-15000.0, -15000.0, 3000.0), 90.0)
	var high: bool = Props.get_b("avionics/nav1/valid")
	print("    PUN VOR from the Konkan: at 400 ft %s, at 9800 ft %s" % ["received" if low else "blocked", "received" if high else "blocked"])
	if low or not high:
		return "line-of-sight: expected blocked low and received high"
	return ""
