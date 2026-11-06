class_name MapWx
extends RefCounted
## Weather radar on the moving map: the same returns as the ND (world/wx_radar.gd).


static var _key := ""
static var _blobs: Array = []


static func draw(ci: CanvasItem, view: MapView, here: Vector2) -> void:
	var radius := view.m_per_px * view.size.length() * 0.55
	var key := "%d|%d|%d|%.2f|%.2f|%.2f|%d" % [int(here.x / 2500.0), int(here.y / 2500.0), int(radius / 2500.0), Props.get_f("weather/storms"), Props.get_f("weather/precip"), Props.get_f("weather/cloud_cover"), int(Props.get_f("environment/storm_clock_s") / 20.0)]
	if key != _key:
		_key = key
		_blobs = WxRadar.blobs(here, radius)
	for b in _blobs:
		ci.draw_circle(view.to_px(Vector2(b.e, b.n)), maxf(float(b.r) / view.m_per_px, 3.0), WxRadar.colour(int(b.level)))
