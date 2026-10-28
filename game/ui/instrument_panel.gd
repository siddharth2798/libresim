class_name InstrumentPanel
extends Control
## Steam-gauge panel of the current aircraft, laid out from its panel.json (the C172's: six-pack +
## VOR1 / VOR2(ILS) in two rows, tach - engine cluster - ADF in the third, the radio stack on the
## right, the switch row along the bottom). Lives in a SubViewport (see aircraft/common/cockpit.gd) so
## it can be mapped onto the 3D panel and shown as 2D overlay pieces in outside views.
## panel.json: cell, pad, switch_h (px), radio_w (cells), cols, rows, gauges {name: {script, cell, meta}},
## and the optional items strip {script, cell, span}, switches {script}, radios {script}.
## Additive keys for non-square / free layouts (the C172's file uses none of them):
##   size [w, h]            natural size in px (default: from the grid, enlarged to hold every rect)
##   gauges[name].span      [cols, rows] of grid cells (default [1, 1]); strip.span as before
##   gauges[name].rect      [x, y, w, h] in px, instead of cell / span (also on strip, radios, switches)
##   gauges[name].kind      "display": the script is a full-rect Display (ui/displays/display.gd)
##                          that scales its own drawing to the rect; any other value = a round Gauge
## Item names (asi, ai, ..., strip, radios, switches, pfd, nd, ...) are what the 3D cockpit spots and
## the 2D overlay layouts refer to.

const SIZES := {"cell": 190.0, "pad": 12.0, "switch_h": 70.0, "radio_w": 0.0, "cols": 1.0, "rows": 1.0}  # defaults

static var _layout := {}
static var _layout_id := ""

var layout_override := {}  # set before add_child: a layout (normalize()d panel.json) instead of the aircraft's
var _items := {}  # strip / switches / radios -> Control
var _l := {}


## The panel layout of the current aircraft (cached per aircraft).
static func layout() -> Dictionary:
	var def := AircraftDef.current()
	var id := def.id if def else ""
	if _layout.is_empty() or id != _layout_id:
		_layout = normalize(def.json("panel") if def else {})
		_layout_id = id
	return _layout


## panel.json content with the defaults filled in (pure, tested).
static func normalize(raw: Dictionary) -> Dictionary:
	var l := raw.duplicate()
	for k in SIZES:
		l[k] = float(l.get(k, SIZES[k]))
	if not l.has("radios"):
		l.radio_w = 0.0
	if not l.has("switches"):
		l.switch_h = 0.0
	if not l.has("gauges"):
		l.gauges = {}
	return l


## Forget the cached layout (tests that change the aircraft or panel.json).
static func clear_cache() -> void:
	_layout = {}
	_layout_id = ""


## Gauge name -> {script, cell, meta}.
static func gauges() -> Dictionary:
	return layout().gauges


func _ready() -> void:
	_l = layout_override if not layout_override.is_empty() else layout()
	var l := _l
	for k in l.gauges:
		var g: Control
		if l.gauges[k].get("kind", "") == "display":
			g = load(l.gauges[k].script).new()
		else:
			g = Control.new()
			g.set_script(load(l.gauges[k].script))
		for m in l.gauges[k].get("meta", {}):
			var v = l.gauges[k].meta[m]
			g.set_meta(m, int(v) if v is float and v == floorf(v) else v)
		g.name = k
		add_child(g)
	for k in ["strip", "switches", "radios"]:
		if l.has(k):
			_items[k] = _child(l[k].script)
	resized.connect(_layout_items)
	_layout_items()


func _child(path: String) -> Control:
	var c := Control.new()
	c.set_script(load(path))
	add_child(c)
	return c


## Panel's natural size (for the SubViewport).
static func natural_size() -> Vector2:
	return natural_size_of(layout())


static func natural_size_of(l: Dictionary) -> Vector2:
	if l.has("size"):
		return Vector2(l.size[0], l.size[1])
	var grid := Vector2(l.pad * 3 + l.cell * (l.cols + l.radio_w), l.pad * (l.rows + 1) + l.cell * l.rows + l.switch_h)
	if _has_free_rect(l):  # free rects may stick out of the grid: make room for them
		for r in rects_of(l).values():
			grid = grid.max(r.end + Vector2(l.pad, l.pad))
	return grid


static func _has_free_rect(l: Dictionary) -> bool:
	for k in l.gauges:
		if l.gauges[k].has("rect"):
			return true
	for k in ["strip", "radios", "switches"]:
		if l.has(k) and l[k].has("rect"):
			return true
	return false


## Pixel rects (at natural size) of every panel item, by name.
static func rects() -> Dictionary:
	return rects_of(layout())


static func rects_of(l: Dictionary) -> Dictionary:
	var cell: float = l.cell
	var pad: float = l.pad
	var r := {}
	for k in l.gauges:
		r[k] = _item_rect(l, l.gauges[k])
	if l.has("strip"):
		r["strip"] = _item_rect(l, l.strip)
	if l.has("radios"):
		r["radios"] = _rect_key(l.radios, Rect2(Vector2(pad * 2 + cell * l.cols, pad), Vector2(cell * l.radio_w, cell * l.rows + pad * (l.rows - 1))))
	if l.has("switches"):
		var sz := Vector2(l.size[0], l.size[1]) if l.has("size") else Vector2(l.pad * 3 + l.cell * (l.cols + l.radio_w), 0.0)
		r["switches"] = _rect_key(l.switches, Rect2(Vector2(pad, pad * (l.rows + 1) + cell * l.rows), Vector2(sz.x - pad * 2, l.switch_h - pad * 0.5)))
	return r


## The item's "rect" [x, y, w, h] if it has one, else its grid cell (+ span).
static func _item_rect(l: Dictionary, item: Dictionary) -> Rect2:
	var c: Array = item.get("cell", [0, 0])
	return _rect_key(item, _cell_rect(l, c, item.get("span", [1, 1])))


static func _rect_key(item: Dictionary, default: Rect2) -> Rect2:
	var a: Array = item.get("rect", [])
	return Rect2(a[0], a[1], a[2], a[3]) if a.size() == 4 else default


static func _cell_rect(l: Dictionary, c: Array, span: Array) -> Rect2:
	var cell: float = l.cell
	return Rect2(Vector2(l.pad + c[0] * cell, l.pad + c[1] * (cell + l.pad)), Vector2(cell * span[0], cell * span[1]))


func _layout_items() -> void:
	var ns := natural_size_of(_l)
	var s := minf(size.x / ns.x, size.y / ns.y)
	if s <= 0.0:
		return
	var r := rects_of(_l)
	for k in _l.gauges:
		var g: Control = get_node(k)
		g.position = r[k].position * s
		g.size = r[k].size * s
	for k in _items:
		_items[k].position = r[k].position * s
		_items[k].size = r[k].size * s


## Redraw every gauge (called by whoever is about to show the panel texture, ~30 Hz),
## instead of each gauge redrawing every frame.
func refresh() -> void:
	for c in get_children():
		(c as CanvasItem).queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.16, 0.17))
