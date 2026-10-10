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

var _strip: Control


func _ready() -> void:
	for k in GAUGES:
		var g: Control = Control.new()
		g.set_script(load(GAUGES[k][0]))
		g.name = k
		add_child(g)
	_strip = Control.new()
	_strip.set_script(load("res://ui/gauges/engine_strip.gd"))
	add_child(_strip)
	resized.connect(_layout)
	_layout()


## Panel's natural size (for the SubViewport).
static func natural_size() -> Vector2:
	return Vector2(CELL * 5.6, CELL * 2 + PAD * 3)


func _layout() -> void:
	var s := minf(size.x / natural_size().x, size.y / natural_size().y)
	if s <= 0.0:
		return
	for k in GAUGES:
		var g: Control = get_node(k)
		var cell: Vector2 = GAUGES[k][1]
		g.position = Vector2(PAD + cell.x * CELL, PAD + cell.y * (CELL + PAD)) * s
		g.size = Vector2(CELL, CELL) * s
	var tach: Control = get_node("tach")
	tach.size = Vector2(CELL * 0.95, CELL * 0.95) * s
	_strip.position = Vector2(PAD + 4.15 * CELL, PAD) * s
	_strip.size = Vector2(CELL * 1.4, CELL * 2.0 + PAD) * s


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.16, 0.17))
