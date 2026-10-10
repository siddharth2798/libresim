class_name InstrumentPanel
extends Control
## C172 steam-gauge panel layout (six-pack + tachometer + engine/fuel cluster).
## Lives inside a SubViewport (see cockpit_panel.gd) so it can be shown on the
## 3D cockpit panel, and also directly as a 2D overlay in outside views.

const GAUGES := {
	"asi": ["res://ui/gauges/asi_gauge.gd", Vector2(0, 0)],
	"ai": ["res://ui/gauges/attitude_gauge.gd", Vector2(1, 0)],
	"alt": ["res://ui/gauges/altimeter_gauge.gd", Vector2(2, 0)],
	"tc": ["res://ui/gauges/turn_coordinator_gauge.gd", Vector2(0, 1)],
	"hi": ["res://ui/gauges/heading_gauge.gd", Vector2(1, 1)],
	"vsi": ["res://ui/gauges/vsi_gauge.gd", Vector2(2, 1)],
	"tach": ["res://ui/gauges/tach_gauge.gd", Vector2(3.15, 0)],
}
const CELL := 190.0
const PAD := 12.0
const SWITCH_H := 70.0

var _strip: Control
var _switches: Control


func _ready() -> void:
	for k in GAUGES:
		var g: Control = Control.new()
		g.set_script(load(GAUGES[k][0]))
		g.name = k
		add_child(g)
	_strip = Control.new()
	_strip.set_script(load("res://ui/gauges/engine_strip.gd"))
	add_child(_strip)
	_switches = Control.new()
	_switches.set_script(load("res://ui/gauges/switch_row.gd"))
	add_child(_switches)
	resized.connect(_layout)
	_layout()


## Panel's natural size (for the SubViewport).
static func natural_size() -> Vector2:
	return Vector2(CELL * 5.6, CELL * 2 + PAD * 3 + SWITCH_H)


## Pixel rects (at natural size) of each gauge, the engine strip and the switch row.
static func rects() -> Dictionary:
	var r := {}
	for k in GAUGES:
		var cell: Vector2 = GAUGES[k][1]
		var sz := CELL * (0.95 if k == "tach" else 1.0)
		r[k] = Rect2(Vector2(PAD + cell.x * CELL, PAD + cell.y * (CELL + PAD)), Vector2(sz, sz))
	r["strip"] = Rect2(Vector2(PAD + 4.15 * CELL, PAD), Vector2(CELL * 1.4, CELL * 2.0 + PAD))
	r["switches"] = Rect2(Vector2(PAD, PAD * 2 + CELL * 2 + PAD * 0.5), Vector2(CELL * 5.6 - PAD * 2, SWITCH_H - PAD * 0.5))
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
	_strip.position = r.strip.position * s
	_strip.size = r.strip.size * s
	_switches.position = r.switches.position * s
	_switches.size = r.switches.size * s


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.16, 0.17))
