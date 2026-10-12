extends RefCounted
## Simple vector glyphs for the home-screen choice cards, drawn with CanvasItem draw calls
## (no image assets). Call from a Control's draw signal: Glyphs.draw(control, "flight", lit).

## Top-down C172 in unit coordinates, nose at (0, -1): fuselage, wing, tailplane.
const PLANE := [
	[Vector2(0, -1), Vector2(0.09, -0.7), Vector2(0.09, 0.45), Vector2(0.04, 0.95), Vector2(-0.04, 0.95), Vector2(-0.09, 0.45), Vector2(-0.09, -0.7)],
	[Vector2(0.09, -0.3), Vector2(1.0, -0.22), Vector2(1.0, 0.02), Vector2(0.09, 0.1), Vector2(-0.09, 0.1), Vector2(-1.0, 0.02), Vector2(-1.0, -0.22), Vector2(-0.09, -0.3)],
	[Vector2(0.09, 0.62), Vector2(0.42, 0.72), Vector2(0.42, 0.88), Vector2(0.09, 0.86), Vector2(-0.09, 0.86), Vector2(-0.42, 0.88), Vector2(-0.42, 0.72), Vector2(-0.09, 0.62)],
]
## Mortar board (learning): cap bowl, board.
const CAP := [
	[Vector2(-0.52, 0.0), Vector2(-0.52, 0.42), Vector2(0, 0.7), Vector2(0.52, 0.42), Vector2(0.52, 0.0)],
	[Vector2(0, -0.62), Vector2(1.05, -0.12), Vector2(0, 0.38), Vector2(-1.05, -0.12)],
]


static func draw(c: Control, kind: String, lit: bool) -> void:
	var centre := c.size * 0.5
	var r := minf(c.size.x, c.size.y) * 0.5
	var accent := MenuTheme.ACCENT
	c.draw_circle(centre, r - 1.0, Color(accent, 0.22 if lit else 0.12))
	c.draw_arc(centre, r - 1.5, 0.0, TAU, 72, Color(accent, 0.95 if lit else 0.5), 2.5, true)
	match kind:
		"flight":
			c.draw_set_transform(centre, PI / 4.0, Vector2.ONE * r * 0.56)
			for poly in PLANE:
				c.draw_colored_polygon(PackedVector2Array(poly), MenuTheme.TEXT)
			c.draw_rect(Rect2(-0.3, -1.04, 0.6, 0.06), accent)  # propeller disc edge
		"training":
			c.draw_set_transform(centre + Vector2(0, r * 0.05), 0.0, Vector2.ONE * r * 0.58)
			c.draw_colored_polygon(PackedVector2Array(CAP[0]), Color(MenuTheme.TEXT, 0.65))
			c.draw_colored_polygon(PackedVector2Array(CAP[1]), MenuTheme.TEXT)
			c.draw_line(Vector2(0, -0.12), Vector2(0.86, 0.04), accent, 0.07)
			c.draw_line(Vector2(0.86, 0.04), Vector2(0.86, 0.5), accent, 0.07)
			c.draw_circle(Vector2(0.86, 0.56), 0.1, accent)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
