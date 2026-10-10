extends Control
## Weight & balance chart: POH CG envelope (normal filled, utility outlined), the
## takeoff point (circle) and landing point (square) joined by the fuel-burn line.
## Turns red when either point is outside the normal envelope.
## set_data(envelope from aircraft.json, WeightBalance.compute() result).

const OK_COL := Color(0.35, 0.75, 1.0)
const BAD_COL := Color(1.0, 0.4, 0.3)
const PAD_L := 44.0
const PAD_B := 22.0
const PAD_T := 6.0
const PAD_R := 8.0

var _env := {}
var _res := {}
var _x0 := 33.0
var _x1 := 50.0
var _y0 := 1500.0
var _y1 := 2600.0


func _ready() -> void:
	custom_minimum_size = Vector2(250, 120)


func set_data(env: Dictionary, res: Dictionary) -> void:
	_env = env
	_res = res
	_x0 = 33.0
	_x1 = 50.0
	_y0 = 1500.0
	_y1 = 2600.0
	for k in ["takeoff", "landing"]:  # keep off-chart points visible
		if res.has(k):
			_x0 = minf(_x0, floorf(res[k].cg_in - 1.0))
			_x1 = maxf(_x1, ceilf(res[k].cg_in + 3.0))
			_y0 = minf(_y0, floorf(res[k].lb / 100.0) * 100.0 - 50.0)
			_y1 = maxf(_y1, ceilf(res[k].lb / 100.0) * 100.0 + 50.0)
	queue_redraw()


func _map(cg_in: float, lb: float) -> Vector2:
	var w := size.x - PAD_L - PAD_R
	var h := size.y - PAD_T - PAD_B
	return Vector2(PAD_L + (cg_in - _x0) / (_x1 - _x0) * w, PAD_T + (1.0 - (lb - _y0) / (_y1 - _y0)) * h)


func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_map(p[0], p[1]))
	return out


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 12
	var dim := Color(0.62, 0.66, 0.72)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.3))
	# grid + axis labels
	var x := ceilf(_x0 / 2.0) * 2.0
	while x <= _x1:
		var a := _map(x, _y0)
		draw_line(a, _map(x, _y1), Color(1, 1, 1, 0.07))
		draw_string(font, a + Vector2(-8, 15), "%d" % x, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
		x += 2.0
	var y := ceilf(_y0 / 200.0) * 200.0
	while y <= _y1:
		var b := _map(_x0, y)
		draw_line(b, _map(_x1, y), Color(1, 1, 1, 0.07))
		draw_string(font, b + Vector2(-40, 4), "%d" % y, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
		y += 200.0
	draw_string(font, Vector2(size.x - 150, size.y - PAD_B - 4), "CG in aft of datum", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	draw_string(font, Vector2(PAD_L + 4, PAD_T + 12), "lb", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	if _env.is_empty():
		return
	var ok: bool = _res.get("ok", true)
	var col := OK_COL if ok else BAD_COL
	var normal := _poly(_env.normal)
	draw_colored_polygon(normal, Color(col, 0.16))
	normal.append(normal[0])
	draw_polyline(normal, col, 2.0, true)
	if _env.has("utility"):
		var u := _poly(_env.utility)
		u.append(u[0])
		for i in u.size() - 1:
			draw_dashed_line(u[i], u[i + 1], Color(1, 1, 1, 0.45), 1.0, 5.0)
		draw_string(font, _map(_env.utility[2][0], _env.utility[2][1]) + Vector2(-4, 14), "utility", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim)
	if not _res.has("takeoff"):
		return
	var to := _map(_res.takeoff.cg_in, _res.takeoff.lb)
	var ld := _map(_res.landing.cg_in, _res.landing.lb)
	draw_line(to, ld, Color.WHITE, 2.0, true)
	var to_col := Color.WHITE if _res.takeoff.normal else BAD_COL
	var ld_col := Color.WHITE if _res.landing.normal else BAD_COL
	draw_circle(to, 5.0, to_col)
	draw_rect(Rect2(ld - Vector2(4, 4), Vector2(8, 8)), ld_col)
	if to.distance_to(ld) < 12.0:
		_label(font, to, "T/O = LDG", to_col)
	else:
		_label(font, to, "T/O", to_col)
		_label(font, ld, "LDG", ld_col)


func _label(font: Font, at: Vector2, text: String, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var off := Vector2(8, 4) if at.x + 8.0 + w < size.x - 2.0 else Vector2(-10.0 - w, 4)
	draw_string(font, at + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
