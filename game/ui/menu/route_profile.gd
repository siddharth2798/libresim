class_name RouteProfile
extends Control
## The Route step's vertical profile, under the map: terrain along the route (filled, from the start screen's own height
## reads, core/terrain_heights.gd) against the planned leg altitudes (the line), with the departure and destination
## elevations at the ends. Where a leg is less than 1000 ft above the terrain the line turns red, and the ground under it
## too (RouteTerrain.is_low; the take-off and landing ends are not judged). One caption line: the highest terrain and the
## lowest clearance. show_profile() takes RouteTerrain.profile().

const TERRAIN := Color("6b5d4a")
const TERRAIN_TOP := Color("a08a6a")
const MARGIN := Vector4(46, 20, 10, 16)  # left (the ft scale), top (the caption), right, bottom (nm)

var samples: Array = []
var verdict := {}
var ids: Array = []
var dep_ft := NAN
var dest_ft := NAN
var caption := ""


func _init() -> void:
	custom_minimum_size = Vector2(0, 88)
	mouse_filter = MOUSE_FILTER_PASS
	tooltip_text = "Vertical profile: the ground along the route and the planned altitude of each leg. Red: less than 1000 ft above the ground (take-off and landing not counted)."


func show_profile(p: Dictionary) -> void:
	samples = p.get("samples", [])
	verdict = p.get("verdict", {})
	ids = p.get("ids", [])
	dep_ft = float(p.get("dep_ft", NAN))
	dest_ft = float(p.get("dest_ft", NAN))
	caption = text_of(p)
	queue_redraw()


## "Highest ground 4,921 ft · lowest clearance 579 ft on leg 2 to BBBB" or "… · BELOW THE TERRAIN on leg 2 to BBBB".
static func text_of(p: Dictionary) -> String:
	var v: Dictionary = p.get("verdict", {})
	if (p.get("samples", []) as Array).is_empty() or v.is_empty():
		return "Vertical profile: plan two points or more."
	var top := "Highest ground %s ft" % AirportData.thousands(roundi(float(v.top_ft)))
	if int(v.below_leg) >= 0:
		return "%s · BELOW THE TERRAIN on %s" % [top, RouteTerrain.leg_name(p, int(v.below_leg))]
	if is_inf(float(v.clear_ft)):
		return top
	return "%s · lowest clearance %s ft on %s" % [top, AirportData.thousands(roundi(float(v.clear_ft))), RouteTerrain.leg_name(p, int(v.leg))]


## Plot area and scales: {plot (Rect2), span_m, top_ft}.
static func layout(size: Vector2, smp: Array) -> Dictionary:
	var plot := Rect2(MARGIN.x, MARGIN.y, maxf(size.x - MARGIN.x - MARGIN.z, 1.0), maxf(size.y - MARGIN.y - MARGIN.w, 1.0))
	var top := 1000.0
	for s in smp:
		top = maxf(top, maxf(float(s.terrain_ft), float(s.alt_ft)))
	top = ceilf(top * 1.15 / 1000.0) * 1000.0
	return {"plot": plot, "span_m": maxf(float(smp.back().d_m) if not smp.is_empty() else 1.0, 1.0), "top_ft": top}


func _draw() -> void:
	draw_style_box(MenuTheme.box(Color(0.02, 0.04, 0.06, 0.55), 8, MenuTheme.LINE), Rect2(Vector2.ZERO, size))
	var reg := MenuTheme.font("regular")
	var low := int(verdict.get("low_leg", -1)) >= 0
	var bad := int(verdict.get("below_leg", -1)) >= 0
	draw_string(reg, Vector2(8.0, 14.0), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16.0, 12,
		MenuTheme.BAD if bad else (MenuTheme.WARN if low else MenuTheme.DIM))
	if samples.size() < 2:
		return
	var l := layout(size, samples)
	var plot: Rect2 = l.plot
	var at := func(d_m: float, ft: float) -> Vector2:
		return Vector2(plot.position.x + d_m / l.span_m * plot.size.x, plot.end.y - clampf(ft, 0.0, l.top_ft) / l.top_ft * plot.size.y)
	for k in 2:  # scale: 0 and the top, light grid lines
		var y := plot.end.y - plot.size.y * k
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.08), 1.0)
		var t := "%s" % AirportData.thousands(roundi(l.top_ft * k))
		draw_string(reg, Vector2(4.0, y + (0.0 if k == 0 else 10.0)), t, HORIZONTAL_ALIGNMENT_RIGHT, MARGIN.x - 8.0, 11, MenuTheme.FAINT)
	var ground := PackedVector2Array([at.call(0.0, 0.0)])
	for s in samples:
		ground.append(at.call(float(s.d_m), float(s.terrain_ft)))
	ground.append(at.call(l.span_m, 0.0))
	draw_colored_polygon(ground, TERRAIN)
	draw_polyline(ground.slice(1, ground.size() - 1), TERRAIN_TOP, 1.0, true)
	for i in range(1, samples.size()):  # the planned altitude, red where too low, and the ground under it
		var a: Dictionary = samples[i - 1]
		var b: Dictionary = samples[i]
		var red := RouteTerrain.is_low(a) or RouteTerrain.is_low(b)
		var pa: Vector2 = at.call(float(a.d_m), float(b.alt_ft) if a.leg != b.leg else float(a.alt_ft))
		var pb: Vector2 = at.call(float(b.d_m), float(b.alt_ft))
		if a.leg != b.leg:  # the step at a waypoint
			draw_line(at.call(float(a.d_m), float(a.alt_ft)), pa, Color(MapStyle.ROUTE, 0.8), 2.0)
		if red:
			draw_line(at.call(float(a.d_m), float(a.terrain_ft)), at.call(float(b.d_m), float(b.terrain_ft)), MenuTheme.BAD, 2.0)
		draw_line(pa, pb, MenuTheme.BAD if red else MapStyle.ROUTE, 2.5)
	_ticks(reg, plot, l, at)


## Waypoint ticks with their idents along the bottom, the end elevations (dots; the departure's in ft at the left) and
## the length at the right. An ident that would touch its neighbour or the end labels is left out.
func _ticks(reg: Font, plot: Rect2, l: Dictionary, at: Callable) -> void:
	var y := size.y - 3.0
	var nm := "%.0f nm" % (l.span_m / RouteTerrain.NM)
	var nm_x := plot.end.x - reg.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(reg, Vector2(nm_x, y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MenuTheme.FAINT)
	var free_x := plot.position.x
	if not is_nan(dep_ft):
		var dt := "%s ft" % AirportData.thousands(roundi(dep_ft))
		draw_string(reg, Vector2(plot.position.x, y), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MenuTheme.FAINT)
		free_x += reg.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8.0
	var prev := -1
	for s in samples:
		if int(s.leg) == prev:
			continue
		prev = int(s.leg)
		var x: float = at.call(float(s.d_m), 0.0).x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(1, 1, 1, 0.12), 1.0)
		if prev <= 0 or prev >= ids.size():
			continue
		var t := str(ids[prev])
		var w := reg.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var tx := x - w * 0.5
		if tx >= free_x and tx + w < nm_x - 6.0:
			draw_string(reg, Vector2(tx, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, MenuTheme.FAINT)
			free_x = tx + w + 6.0
	for e in [[dep_ft, 0.0], [dest_ft, l.span_m]]:
		if not is_nan(float(e[0])):
			draw_circle(at.call(float(e[1]), float(e[0])), 3.5, MapStyle.ROUTE.lightened(0.4))
