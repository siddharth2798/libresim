class_name Gauge
extends Control
## Base class for a round steam gauge drawn with Control._draw().
## Subclasses implement _draw_face(c, r) and _draw_needles(c, r); faces are
## drawn every redraw (cheap). Helpers for ticks, arcs, labels and needles.
## Knobs: subclasses override _knob(delta) for click (left/right half) and wheel.

const BEZEL := Color(0.08, 0.08, 0.09)
const FACE := Color(0.04, 0.04, 0.05)
const INK := Color(0.93, 0.93, 0.9)
const NEEDLE := Color(0.96, 0.96, 0.94)

var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(150, 150)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, BEZEL)
	draw_circle(c, r * 0.92, FACE)
	_draw_face(c, r * 0.9)
	_draw_needles(c, r * 0.9)
	draw_arc(c, r * 0.92, 0, TAU, 64, Color(0.25, 0.25, 0.27), 2.0, true)


func _draw_face(_c: Vector2, _r: float) -> void:
	pass


func _draw_needles(_c: Vector2, _r: float) -> void:
	pass


## Angle (rad, 0 = up, clockwise positive) -> unit vector in screen space.
static func dir(a: float) -> Vector2:
	return Vector2(sin(a), -cos(a))


func ticks(c: Vector2, r: float, a0: float, a1: float, n: int, length: float, width := 2.0, col := INK) -> void:
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		draw_line(c + dir(a) * r, c + dir(a) * (r - length), col, width, true)


func arc(c: Vector2, r: float, a0: float, a1: float, col: Color, width: float) -> void:
	# draw_arc uses 0 = +x, counter-clockwise in math terms but y is down -> clockwise on screen
	draw_arc(c, r, a0 - PI / 2, a1 - PI / 2, 24, col, width, true)


func label(pos: Vector2, text: String, fs := 14, col := INK) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, pos + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func needle(c: Vector2, a: float, length: float, width := 4.0, col := NEEDLE, tail := 0.15) -> void:
	var d := dir(a)
	var n := Vector2(-d.y, d.x) * width * 0.5
	var tip := c + d * length
	var back := c - d * length * tail
	draw_colored_polygon(PackedVector2Array([back + n, tip, back - n]), col)
	draw_circle(c, width * 1.1, Color(0.2, 0.2, 0.2))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_LEFT: _knob(-1.0 if e.position.x < size.x * 0.5 else 1.0)
			MOUSE_BUTTON_WHEEL_UP: _knob(1.0)
			MOUSE_BUTTON_WHEEL_DOWN: _knob(-1.0)


func _knob(_delta: float) -> void:
	pass
