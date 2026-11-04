class_name LessonMap
extends RefCounted
## The airport diagram of the Training page's "Where you start": what a lesson's setup (training/lessons.json, read
## only) puts on the diagram of the Airport step (AirportDiagram): the airport's runways and taxiways, the lesson's
## runway lit, and the start arrow (on the runway, or in the air on the extended centreline with the dashed approach
## track, the same geometry as airport_page.gd). Pure statics over airport records ({icao, runways, taxiways}, the shape
## AirportData.load_all() gives; tests pass their own), no nodes.

static var _all: Array = []  # AirportData.load_all(), read on first use


## {ok, icao, runways, taxiways, runway (ident), start: {pos, heading, from, label}} of a lesson; ok = false when its
## airport or runway is not in `airports` (the page then shows the text only). `airports` empty = the game's data.
static func spec(lesson: Dictionary, airports := []) -> Dictionary:
	var s: Dictionary = lesson.get("setup", {})
	var icao := str(s.get("airport", ""))
	var want := str(s.get("runway", ""))
	var out := {"ok": false, "icao": icao, "runways": [], "taxiways": [], "runway": want, "start": {}}
	var apt := airport(icao, airports)
	if apt.is_empty():
		return out
	for r in apt.runways:
		for e in r.ends:
			if str(e.ident) != want:
				continue
			var h := deg_to_rad(float(e.heading_true))
			var thr := Vector2(float(e.x), float(e.y))
			var f := Vector2(sin(h), cos(h))
			if str(s.get("start", "runway")) == "air":
				var nm := float(s.get("air_nm", 5.0))
				out.start = {"pos": thr - f * nm * 1852.0, "heading": float(e.heading_true), "from": thr, "label": "%s nm out" % FailuresLogic.fmt(nm)}
			else:
				out.start = {"pos": thr + f * 25.0, "heading": float(e.heading_true), "from": Vector2.INF, "label": ""}
			out.ok = true
			out.runways = apt.runways
			out.taxiways = apt.get("taxiways", [])
			return out
	return out


## The airport record of `icao` in `airports` (empty = AirportData.load_all(), cached); {} when absent.
static func airport(icao: String, airports := []) -> Dictionary:
	if airports.is_empty():
		if _all.is_empty():
			_all = AirportData.load_all()
		airports = _all
	for a in airports:
		if str(a.icao) == icao:
			return a
	return {}


## Put `spec` on `diagram` (an AirportDiagram, normally read_only): runways, taxiways, no stands, the lesson's runway
## lit and the start arrow. Nothing drawn when the spec is not ok.
static func apply(diagram: AirportDiagram, sp: Dictionary) -> void:
	diagram.visible = bool(sp.ok)
	if not sp.ok:
		return
	diagram.show_airport(sp.runways, sp.taxiways, [])
	diagram.set_selection(str(sp.runway), "")
	var st: Dictionary = sp.start
	diagram.set_start(st.pos, float(st.heading), st.from, str(st.label))
