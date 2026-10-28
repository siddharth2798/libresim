class_name InstrumentPanel
extends Control
## Steam-gauge panel of the current aircraft, laid out from its panel.json (the C172's: six-pack +
## VOR1 / VOR2(ILS) in two rows, tach - engine cluster - ADF in the third, the radio stack on the
## right, the switch row along the bottom). Lives in a SubViewport (see aircraft/common/cockpit.gd) so
## it can be mapped onto the 3D panel and shown as 2D overlay pieces in outside views.
## panel.json: cell, pad, switch_h (px), radio_w (cells), cols, rows, gauges {name: {script, cell, meta}},
## and the optional items strip {script, cell, span}, switches {script}, radios {script}.
## Item names (asi, ai, ..., strip, radios, switches) are what the 3D cockpit spots and the 2D
## overlay layouts refer to.

const SIZES := {"cell": 190.0, "pad": 12.0, "switch_h": 70.0, "radio_w": 0.0, "cols": 1.0, "rows": 1.0}  # defaults

static var _layout := {}
static var _layout_id := ""

var _items := {}  # strip / switches / radios -> Control


## The panel layout of the current aircraft (cached per aircraft).
static func layout() -> Dictionary:
	var def := AircraftDef.current()
	var id := def.id if def else ""
	if _layout.is_empty() or id != _layout_id:
		_layout = def.json("panel") if def else {}
		_layout_id = id
		for k in SIZES:
			_layout[k] = float(_layout.get(k, SIZES[k]))
		if not _layout.has("radios"):
			_layout.radio_w = 0.0
		if not _layout.has("switches"):
			_layout.switch_h = 0.0
		if not _layout.has("gauges"):
			_layout.gauges = {}
	return _layout


## Forget the cached layout (tests that change the aircraft or panel.json).
static func clear_cache() -> void:
	_layout = {}
	_layout_id = ""


## Gauge name -> {script, cell, meta}.
static func gauges() -> Dictionary:
	return layout().gauges


func _ready() -> void:
	var l := layout()
	for k in l.gauges:
		var g := Control.new()
		for m in l.gauges[k].get("meta", {}):
			var v = l.gauges[k].meta[m]
			g.set_meta(m, int(v) if v is float and v == floorf(v) else v)  # JSON numbers are floats
		g.set_script(load(l.gauges[k].script))
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
	var l := layout()
	return Vector2(l.pad * 3 + l.cell * (l.cols + l.radio_w), l.pad * (l.rows + 1) + l.cell * l.rows + l.switch_h)


## Pixel rects (at natural size) of every panel item, by name.
static func rects() -> Dictionary:
	var l := layout()
	var cell: float = l.cell
	var pad: float = l.pad
	var r := {}
	for k in l.gauges:
		r[k] = _cell_rect(l, l.gauges[k].cell, [1, 1])
	if l.has("strip"):
		r["strip"] = _cell_rect(l, l.strip.cell, l.strip.get("span", [1, 1]))
	if l.has("radios"):
		r["radios"] = Rect2(Vector2(pad * 2 + cell * l.cols, pad), Vector2(cell * l.radio_w, cell * l.rows + pad * (l.rows - 1)))
	if l.has("switches"):
		r["switches"] = Rect2(Vector2(pad, pad * (l.rows + 1) + cell * l.rows), Vector2(natural_size().x - pad * 2, l.switch_h - pad * 0.5))
	return r


static func _cell_rect(l: Dictionary, c: Array, span: Array) -> Rect2:
	var cell: float = l.cell
	return Rect2(Vector2(l.pad + c[0] * cell, l.pad + c[1] * (cell + l.pad)), Vector2(cell * span[0], cell * span[1]))


func _layout_items() -> void:
	var s := minf(size.x / natural_size().x, size.y / natural_size().y)
	if s <= 0.0:
		return
	var r := rects()
	for k in gauges():
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
