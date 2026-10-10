class_name InstrumentPanel
extends Control
## C172 steam-gauge panel, laid out like the real aircraft: six-pack + VOR1 / VOR2(ILS)
## in two rows, tach - engine cluster - ADF in the third, the radio stack on the right,
## the switch row along the bottom. Lives in a SubViewport (see cockpit.gd) so it can be
## mapped onto the 3D panel and shown as 2D overlay pieces in outside views.

const GAUGES := {  # name: [script, cell (col, row), metadata]
	"asi": ["res://ui/gauges/asi_gauge.gd", Vector2(0, 0), {}],
	"ai": ["res://ui/gauges/attitude_gauge.gd", Vector2(1, 0), {}],
	"alt": ["res://ui/gauges/altimeter_gauge.gd", Vector2(2, 0), {}],
	"vor1": ["res://ui/gauges/cdi_gauge.gd", Vector2(3, 0), {"nav": 1, "gs": false}],
	"tc": ["res://ui/gauges/turn_coordinator_gauge.gd", Vector2(0, 1), {}],
	"hi": ["res://ui/gauges/heading_gauge.gd", Vector2(1, 1), {}],
	"vsi": ["res://ui/gauges/vsi_gauge.gd", Vector2(2, 1), {}],
	"vor2": ["res://ui/gauges/cdi_gauge.gd", Vector2(3, 1), {"nav": 2, "gs": true}],
	"tach": ["res://ui/gauges/tach_gauge.gd", Vector2(0, 2), {}],
	"adf": ["res://ui/gauges/adf_gauge.gd", Vector2(3, 2), {}],
}
const CELL := 190.0
const PAD := 12.0
const SWITCH_H := 70.0
const RADIO_W := 2.0  # cells

var _strip: Control
var _switches: Control
var _radios: Control


func _ready() -> void:
	for k in GAUGES:
		var g: Control = Control.new()
		for m in GAUGES[k][2]:
			g.set_meta(m, GAUGES[k][2][m])
		g.set_script(load(GAUGES[k][0]))
		g.name = k
		add_child(g)
	_strip = _child("res://ui/gauges/engine_strip.gd")
	_switches = _child("res://ui/gauges/switch_row.gd")
	_radios = _child("res://ui/gauges/radio_stack.gd")
	resized.connect(_layout)
	_layout()


func _child(path: String) -> Control:
	var c := Control.new()
	c.set_script(load(path))
	add_child(c)
	return c


## Panel's natural size (for the SubViewport).
static func natural_size() -> Vector2:
	return Vector2(PAD * 3 + CELL * (4.0 + RADIO_W), PAD * 4 + CELL * 3 + SWITCH_H)


## Pixel rects (at natural size) of every panel item, by name.
static func rects() -> Dictionary:
	var r := {}
	for k in GAUGES:
		var cell: Vector2 = GAUGES[k][1]
		r[k] = Rect2(Vector2(PAD + cell.x * CELL, PAD + cell.y * (CELL + PAD)), Vector2(CELL, CELL))
	r["strip"] = Rect2(Vector2(PAD + CELL, PAD + 2.0 * (CELL + PAD)), Vector2(CELL * 2.0, CELL))
	r["radios"] = Rect2(Vector2(PAD * 2 + CELL * 4.0, PAD), Vector2(CELL * RADIO_W, CELL * 3.0 + PAD * 2))
	r["switches"] = Rect2(Vector2(PAD, PAD * 4 + CELL * 3), Vector2(natural_size().x - PAD * 2, SWITCH_H - PAD * 0.5))
	return r


func _layout() -> void:
	var s := minf(size.x / natural_size().x, size.y / natural_size().y)
	if s <= 0.0:
		return
	var r := rects()
	for k in GAUGES:
		var g: Control = get_node(k)
		g.position = r[k].position * s
		g.size = r[k].size * s
	for pair in [[_strip, "strip"], [_switches, "switches"], [_radios, "radios"]]:
		pair[0].position = r[pair[1]].position * s
		pair[0].size = r[pair[1]].size * s


## Redraw every gauge (called by whoever is about to show the panel texture, ~30 Hz),
## instead of each gauge redrawing every frame.
func refresh() -> void:
	for c in get_children():
		(c as CanvasItem).queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.16, 0.17))
