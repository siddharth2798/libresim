class_name RouteMapLayers
extends RefCounted
## What the Route step's map (RouteMap) draws beyond the moving map's layers: the published airways as faint lines, the
## airway fixes as small triangles (named when zoomed in), the departure and destination rings, and while dragging the
## spot a waypoint will land on (a ring on the named point it snaps to, else a plain cross). Pure drawing statics.

const SHOW_FIX_NM := 160.0  # fixes are drawn (and can be clicked) below this view width
const SHOW_FIX_LABEL_NM := 70.0
const SHOW_AIRWAY_NM := 320.0
const FIX := Color(0.78, 0.86, 0.95, 0.85)
const AIRWAY := Color(0.62, 0.74, 0.9, 0.15)
const DEP := Color("6fe3a0")

static var _airway_lines := {}  # NavDatabase instance id -> [PackedVector2Array] (world metres)


## Every airway as a world polyline of its fixes (positions looked up once per database).
static func airway_lines(db: NavDatabase) -> Array:
	var key := db.get_instance_id()
	if not _airway_lines.has(key):
		var out := []
		var pos := {}
		for name in db.airways:
			var line := PackedVector2Array()
			for id in db.airways[name].get("fixes", []):
				if not pos.has(id):
					pos[id] = db.position_of(str(id))
				if pos[id] != null:
					line.append(pos[id])
			if line.size() >= 2:
				out.append(line)
		_airway_lines = {key: out}
	return _airway_lines[key]


static func draw_airways(ci: CanvasItem, view: MapView, db: NavDatabase) -> void:
	if view.across_nm() > SHOW_AIRWAY_NM:
		return
	var rect := Rect2(Vector2.ZERO, view.size)
	for line in airway_lines(db):
		for i in range(1, line.size()):
			var seg := MapView.clip_segment(view.to_px(line[i - 1]), view.to_px(line[i]), rect.grow(4.0))
			if seg.size() == 2:
				ci.draw_line(seg[0], seg[1], AIRWAY, 1.5, true)


static func draw_fixes(ci: CanvasItem, view: MapView, db: NavDatabase, font: Font, taken: Array) -> void:
	var across := view.across_nm()
	if across > SHOW_FIX_NM:
		return
	var rect := Rect2(Vector2.ZERO, view.size).grow(10.0)
	var named := across <= SHOW_FIX_LABEL_NM
	for id in db.fixes:
		var p := view.to_px(db.fixes[id])
		if not rect.has_point(p):
			continue
		var tri := PackedVector2Array([p + Vector2(0, -5), p + Vector2(4.5, 3.5), p + Vector2(-4.5, 3.5)])
		ci.draw_colored_polygon(tri, Color(MapStyle.OUTLINE, 0.8))
		tri.append(tri[0])
		ci.draw_polyline(tri, FIX, 1.3, true)
		if named:
			MapStyle.text_free(ci, font, str(id), p + Vector2(7, 4), 11, Color(FIX, 0.9), taken)


## Green ring at the departure, accent ring at the destination (their idents are the airport labels).
static func draw_ends(ci: CanvasItem, view: MapView, dep: Dictionary, dest: Dictionary) -> void:
	if not dep.is_empty():
		var p := view.to_px(dep.pos)
		ci.draw_arc(p, 16.0, 0.0, TAU, 32, MapStyle.OUTLINE, 6.0, true)
		ci.draw_arc(p, 16.0, 0.0, TAU, 32, DEP, 3.0, true)
	if not dest.is_empty():
		var q := view.to_px(dest.pos)
		ci.draw_arc(q, 18.0, 0.0, TAU, 32, MapStyle.OUTLINE, 6.0, true)
		ci.draw_arc(q, 18.0, 0.0, TAU, 32, MenuTheme.ACCENT, 3.0, true)


## Where a dragged waypoint lands: a ring on the named point it snaps to, else a cross at the cursor.
static func draw_snap(ci: CanvasItem, world: Vector2, view: MapView, ident: String, db: NavDatabase) -> void:
	if ident != "":
		var at = db.position_of(ident)
		if at != null:
			ci.draw_arc(view.to_px(at), 14.0, 0.0, TAU, 28, Color.WHITE, 2.0, true)
			return
	var p := view.to_px(world)
	for d in [Vector2(7, 0), Vector2(0, 7)]:
		ci.draw_line(p - d, p + d, Color.WHITE, 2.0, true)
