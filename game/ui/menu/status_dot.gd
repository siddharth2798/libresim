class_name StatusDot
extends Control
## The small status mark of the free-flight rail and chips. The shape carries the meaning as well as
## the colour: a filled green circle = ready ("ok"), an amber triangle = look at it ("warn"), a red
## triangle = a problem ("bad"), a hollow grey ring = optional and nothing chosen ("none").

var level := "none":
	set(v):
		level = v
		queue_redraw()


func _init(l := "none", px := 12) -> void:
	level = l
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func color_of(l: String) -> Color:
	return {"ok": MenuTheme.OK, "warn": MenuTheme.WARN, "bad": MenuTheme.BAD}.get(l, MenuTheme.FAINT)


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 0.5
	var col := color_of(level)
	match level:
		"warn", "bad":
			draw_colored_polygon(PackedVector2Array([Vector2(c.x, c.y - r), Vector2(c.x + r, c.y + r * 0.85), Vector2(c.x - r, c.y + r * 0.85)]), col)
		"ok":
			draw_circle(c, r, col)
		_:
			draw_arc(c, r - 1.0, 0.0, TAU, 20, col, 1.5, true)
