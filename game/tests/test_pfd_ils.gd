extends Node
## The A320 PFD's ILS (ui/displays/pfd_ils.gd): ident, frequency and DME at the bottom left; a deviation beyond the scale
## shows as a half diamond pinned at the scale end (the full diamond stays inside it); nothing with the EFIS LS button off.
## The radios publish the unclamped deviations it needs (avionics/nav<n>/cdi_raw, gs_raw).

const KEEP := ["controls/efis/ls", "avionics/nav1/kind", "avionics/nav1/valid", "avionics/nav2/kind", "avionics/nav2/valid",
	"avionics/nav2/ident", "avionics/nav2/dme_nm", "controls/nav2/freq_mhz", "avionics/nav2/cdi", "avionics/nav2/cdi_raw",
	"avionics/nav2/gs", "avionics/nav2/gs_raw", "avionics/nav2/gs_valid"]

var _saved := {}
var _nodes: Array = []


func _keep() -> void:
	for k in KEEP:
		if not _saved.has(k):
			_saved[k] = Props.get_v(k) if Props.has(k) else null


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	for k in _saved:
		if _saved[k] == null:
			Props._p.erase(k)
		else:
			Props.set_v(k, _saved[k])
	_saved.clear()


func _ils(cdi: float, gs: float, dme := 7.36) -> void:
	_keep()
	Props.set_v("controls/efis/ls", true)
	Props.set_v("avionics/nav1/kind", "VOR")
	Props.set_v("avionics/nav1/valid", true)
	Props.set_v("avionics/nav2/kind", "ILS")
	Props.set_v("avionics/nav2/valid", true)
	Props.set_v("avionics/nav2/ident", "IBBB")
	Props.set_v("controls/nav2/freq_mhz", 110.3)
	Props.set_v("avionics/nav2/dme_nm", dme)
	Props.set_v("avionics/nav2/cdi_raw", cdi)
	Props.set_v("avionics/nav2/cdi", clampf(cdi, -1.0, 1.0))
	Props.set_v("avionics/nav2/gs_raw", gs)
	Props.set_v("avionics/nav2/gs", clampf(gs, -1.0, 1.0))
	Props.set_v("avionics/nav2/gs_valid", true)


func test_full_or_half_diamond_from_the_deviation() -> String:
	if PfdIls.diamond(0.5).half or PfdIls.diamond(-1.0).half or not PfdIls.diamond(1.4).half or not PfdIls.diamond(-3.0).half:
		return "half beyond |dev| > 1 (2 dots) only"
	if PfdIls.diamond(2.5).at != 1.0 or PfdIls.diamond(-2.5).at != -1.0 or PfdIls.diamond(0.25).at != 0.25:
		return "pinned at the scale end"
	var mid := Vector2(100, 50)
	var full := PfdIls.diamond_points(mid, Vector2.RIGHT, 0.5)
	if full.size() != 4 or full[0].distance_to(Vector2(127, 50)) > 0.01:
		return "a full diamond, centred one dot right: %s" % full
	var right := PfdIls.diamond_points(mid, Vector2.RIGHT, 1.8)
	var end := mid + Vector2(PfdIls.DOT_PX * 2.0, 0)
	if right.size() != 3 or right[1].x >= end.x or right[0].x != end.x or right[2].x != end.x:
		return "beyond the right end: a triangle with its base on the end mark pointing back in: %s" % right
	var low := PfdIls.diamond_points(mid, Vector2.UP, -2.0)  # glide slope: + is up, so -2 is pinned at the bottom
	if low.size() != 3 or low[0].y != mid.y + 72.0 or low[1].y >= low[0].y:
		return "a glide slope far below pins at the bottom, pointing up: %s" % low
	return ""


func test_ident_frequency_and_dme_lines() -> String:
	_ils(0.2, 0.1)
	var l := PfdIls.labels(2)
	if l != ["IBBB", "110.30", "7.4NM"]:
		return "ident, frequency, DME: %s" % [l]
	Props.set_v("avionics/nav2/dme_nm", 23.6)
	if PfdIls.labels(2)[2] != "24NM":
		return "whole miles from 20 NM: %s" % PfdIls.labels(2)[2]
	Props.set_v("avionics/nav2/dme_nm", -1.0)
	if PfdIls.labels(2).size() != 2:
		return "no DME line without DME"
	return ""


func test_ls_button_gates_the_ils_and_nav2_comes_first() -> String:
	_ils(0.0, 0.0)
	if PfdIls.source() != 2:
		return "the PFD shows NAV2's ILS: %d" % PfdIls.source()
	Props.set_v("controls/efis/ls", false)
	if PfdIls.source() != 0:
		return "LS off hides the ILS"
	var pfd := PFD.new()
	_nodes.append(pfd)
	var off := pfd.dry_paint()
	Props.set_v("controls/efis/ls", true)
	var on := pfd.dry_paint()
	if on <= off:
		return "LS on draws the scales and labels (%d vs %d draw calls)" % [on, off]
	return ""


func test_radios_publish_the_deviation_beyond_full_scale() -> String:
	_keep()
	for k in ["fdm/position_enu", "fdm/heading_rad", "systems/electrical/avionics_powered", "failures/nav2", "failures/dme",
			"avionics/nav2/to_from", "avionics/nav2/radial_deg"]:
		if not _saved.has(k):
			_saved[k] = Props.get_v(k) if Props.has(k) else null
	var n := NavRadios.new()
	n._ready()
	_nodes.append(n)
	var s: Dictionary = {}
	for i in n.db.ils:
		if i.ident == "IBB27":
			s = i
	if s.is_empty():
		return ""  # no ILS data in this checkout (tools/14_ils.py)
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("failures/nav2", false)
	Props.set_v("controls/nav2/freq_mhz", s.mhz)
	var th := Vector2(s.threshold.x, s.threshold.y)
	var fwd := Vector2(sin(deg_to_rad(s.course_true)), cos(deg_to_rad(s.course_true)))
	var p := th - fwd * 5.0 * 1852.0 + Vector2(fwd.y, -fwd.x) * 900.0  # 5 nm final, 900 m right of the centreline
	var alt: float = s.gs.h + tan(deg_to_rad(3.0)) * p.distance_to(Vector2(s.gs.x, s.gs.y)) + 250.0  # well above the path
	Props.set_v("fdm/position_enu", Vector3(p.x, p.y, alt))
	n._physics_process(0.1)
	var cdi := Props.get_f("avionics/nav2/cdi")
	var raw := Props.get_f("avionics/nav2/cdi_raw")
	var gs_raw := Props.get_f("avionics/nav2/gs_raw")
	if not Props.get_b("avionics/nav2/valid") or absf(cdi) != 1.0 or absf(raw) <= 1.5 or signf(raw) != signf(cdi):
		return "far off the localizer: needle %+.2f (clamped), raw %+.2f (beyond full scale)" % [cdi, raw]
	if not Props.get_b("avionics/nav2/gs_valid") or gs_raw >= -1.0 or Props.get_f("avionics/nav2/gs") != -1.0:
		return "well above the glide slope: raw %+.2f, needle %+.2f" % [gs_raw, Props.get_f("avionics/nav2/gs")]
	return ""
