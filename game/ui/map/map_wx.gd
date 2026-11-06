class_name MapWx
extends RefCounted
## Weather radar on the moving map: the same forward sweep as the ND (world/wx_radar.gd).


static var _key := ""
static var _cells: Array = []


static func draw(ci: CanvasItem, view: MapView, here: Vector2) -> void:
	var radius := view.m_per_px * view.size.length() * 0.55
	var hdg := Props.get_f("instruments/adirs/heading_deg")
	var key := "%d|%d|%d|%.2f|%.2f|%.2f|%d|%d" % [int(here.x / 2500.0), int(here.y / 2500.0), int(radius / 2500.0), Props.get_f("weather/storms"), Props.get_f("weather/precip"), Props.get_f("weather/cloud_cover"), int(Props.get_f("environment/storm_clock_s") / 20.0), int(roundf(hdg / WxRadar.BEAM_DEG))]
	if key != _key:
		_key = key
		_cells = WxRadar.sweep(here, hdg, radius)
	for c in _cells:
		var pts := PackedVector2Array()
		for rel in WxRadar.corners(float(c.az), float(c.r0), float(c.r1)):
			pts.append(view.to_px(here + rel))
		ci.draw_colored_polygon(pts, WxRadar.colour(int(c.level)))
