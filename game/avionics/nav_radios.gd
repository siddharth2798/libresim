class_name NavRadios
extends Node
## NAV1/NAV2 (KX-155 style VOR/LOC/GS + DME) and ADF (KR-87). Reads the tuned
## frequencies & OBS from Props "controls/nav{1,2}/{freq_mhz,obs_deg}", "controls/adf/freq_khz";
## publishes "avionics/nav{1,2}/*" and "avionics/adf/*".
## Physics: VOR radial from the station (magnetic, station variation), CDI = course
## error (10 deg full scale VOR; LOC ~2.5 deg full scale from 700 ft course width);
## GS = angle error vs 3 deg (0.7 deg full scale). Reception needs range (VOR ~
## 1.23*sqrt(h_ft) nm line-of-sight radio horizon, LOC 18 nm, GS 10 nm, NDB 50 nm),
## power and a terrain line-of-sight check (ray-marched at 2 Hz). DME: slant range.

const NM := 1852.0
const FT := 0.3048

var db: NavDatabase
var terrain: TerrainQuadtree
var _los := {}  # station key -> bool (refreshed every 0.5 s)
var _los_t := 0.0


func _ready() -> void:
	db = NavDatabase.new()
	var defaults := {"controls/nav1/freq_mhz": 116.6, "controls/nav1/standby_mhz": 113.9, "controls/nav1/obs_deg": 270.0,
		"controls/nav2/freq_mhz": 108.1, "controls/nav2/standby_mhz": 109.3, "controls/nav2/obs_deg": 270.0,
		"controls/adf/freq_khz": 381.0, "controls/adf/standby_khz": 381.0,
		"controls/com1/freq_mhz": 118.1, "controls/com1/standby_mhz": 121.9,
		"controls/com2/freq_mhz": 126.4, "controls/com2/standby_mhz": 123.5,
		"controls/xpdr/code": 7000, "controls/xpdr/mode": 3}
	for k in defaults:
		if not Props.has(k):
			Props.set_v(k, defaults[k])


func _physics_process(dt: float) -> void:
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var powered := Props.get_b("systems/electrical/avionics_powered", true)
	_los_t -= dt
	var refresh := _los_t <= 0.0
	if refresh:
		_los_t = 0.5
	for i in [1, 2]:
		_nav(i, p, powered and not Props.get_b("failures/nav%d" % i), refresh)
	_adf(p, powered and not Props.get_b("failures/adf"), refresh)


func _line_of_sight(key: String, a: Vector3, b: Vector3, refresh: bool) -> bool:
	if not refresh and _los.has(key):
		return _los[key]
	var ok := true
	if terrain:
		var n := 24
		for k in range(1, n):
			var t := float(k) / n
			var q := a.lerp(b, t)
			if terrain.height_at(q.x, q.y) > q.z + 10.0:
				ok = false
				break
	_los[key] = ok
	return ok


func _nav(i: int, p: Vector3, powered: bool, refresh: bool) -> void:
	var pre := "avionics/nav%d/" % i
	var st := db.nav_station(Props.get_f("controls/nav%d/freq_mhz" % i), Vector2(p.x, p.y)) if powered else {}
	var out := {"valid": false, "cdi": 0.0, "to_from": 0, "gs_valid": false, "gs": 0.0, "dme_nm": -1.0,
		"ident": "", "kind": "", "radial_deg": 0.0}
	if not st.is_empty():
		var s: Dictionary = st.s
		var obs := Props.get_f("controls/nav%d/obs_deg" % i)
		if st.kind == "VOR":
			var sp := Vector3(s.x, s.y, s.h)
			var dist := Vector2(p.x, p.y).distance_to(Vector2(s.x, s.y))
			var horizon := 1.23 * (sqrt(maxf(p.z / FT, 1.0)) + sqrt(maxf(s.h / FT, 1.0))) * NM
			if dist < minf(horizon, 130.0 * NM) and _line_of_sight(s.ident, sp, p, refresh):
				var brg_from := fposmod(rad_to_deg(atan2(p.x - s.x, p.y - s.y)) - s.var_deg, 360.0)  # magnetic radial
				var diff := wrapf(brg_from - obs, -180.0, 180.0)
				var from := absf(diff) < 90.0
				var err := diff if from else wrapf(diff - 180.0, -180.0, 180.0)
				# + = needle right (fly right). FROM: radial clockwise of course = right of track
				# -> fly left; TO (inbound): radial clockwise of the inbound radial = left of track -> fly right
				out.cdi = clampf((-err if from else err) / 10.0, -1.0, 1.0)
				out.to_from = -1 if from else 1
				out.valid = dist > 300.0  # cone of confusion overhead
				out.radial_deg = brg_from
				out.ident = s.ident
				out.kind = "VOR"
				if s.dme:
					out.dme_nm = p.distance_to(sp) / NM
		else:  # ILS localizer + glideslope
			var loc: Dictionary = s.loc
			var lp := Vector3(loc.x, loc.y, loc.h + 3.0)
			var dist2 := Vector2(p.x, p.y).distance_to(Vector2(loc.x, loc.y))
			var to_loc := fposmod(rad_to_deg(atan2(loc.x - p.x, loc.y - p.y)), 360.0)
			var err2 := wrapf(to_loc - s.course_true, -180.0, 180.0)  # + = aircraft left of course
			if dist2 < 18.0 * NM and absf(err2) < 35.0 and _line_of_sight(s.ident, lp, p, refresh):
				var width := clampf(rad_to_deg(atan2(105.0, dist2)), 1.5, 3.0)  # 700 ft course sector
				out.cdi = clampf(err2 / width, -1.0, 1.0)
				out.valid = true
				out.to_from = 1
				out.ident = s.ident
				out.kind = "ILS"
				var g: Dictionary = s.gs
				var gd := Vector2(p.x, p.y).distance_to(Vector2(g.x, g.y))
				if gd < 10.0 * NM and absf(err2) < 8.0:
					var ang := rad_to_deg(atan2(p.z - g.h, gd))
					out.gs = clampf((s.gs_deg - ang) / 0.7, -1.0, 1.0)  # + = needle up (fly up)
					out.gs_valid = true
				out.dme_nm = p.distance_to(Vector3(s.threshold.x, s.threshold.y, s.threshold.h)) / NM
	if i == 1 and Props.get_b("failures/dme"):  # the KI-266 is slaved to NAV1
		out.dme_nm = -1.0
	for k in out:
		Props.set_v(pre + k, out[k])


func _adf(p: Vector3, powered: bool, refresh: bool) -> void:
	var st := db.ndb_station(Props.get_f("controls/adf/freq_khz"), Vector2(p.x, p.y)) if powered else {}
	var valid := false
	var rel := 90.0  # needle parks at 90 deg with no signal
	if not st.is_empty():
		var dist := Vector2(p.x, p.y).distance_to(Vector2(st.x, st.y))
		if dist < 50.0 * NM and _line_of_sight("ndb" + st.ident, Vector3(st.x, st.y, st.h), p, refresh):
			var brg := rad_to_deg(atan2(st.x - p.x, st.y - p.y))
			rel = fposmod(brg - rad_to_deg(Props.get_f("fdm/heading_rad")), 360.0)
			valid = true
	Props.set_v("avionics/adf/valid", valid)
	Props.set_v("avionics/adf/bearing_deg", rel)
	Props.set_v("avionics/adf/ident", st.get("ident", "") if valid else "")
