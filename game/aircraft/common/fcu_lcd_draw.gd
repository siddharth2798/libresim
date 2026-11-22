class_name FcuLcdDraw
extends Control
## Paints the A320 FCU's LCD strip (FcuLcd) on a transparent canvas: the window labels from the model's own label art
## (interior_fcu.png, interior_fcu2.png for TRK), seven-segment digits and dashes, and the managed dots, all from
## FcuWindows. Layout is in strip fractions (0..1 across, 0..1 down) measured from the glb's label quads.

const AMBER := Color(1.0, 0.71, 0.10)
const ART := "res://aircraft/a320/models/interior_fcu.png"
const ART_TRK := "res://aircraft/a320/models/interior_fcu2.png"
## label art: name -> [atlas rect in the 512 x 64 art, strip rect as fractions]
const LABELS := {
	"SPD": [Rect2(0, 3.6, 40, 19), Rect2(0.005, 0.03, 0.043, 0.33)],
	"MACH": [Rect2(55, 3.6, 55, 19), Rect2(0.053, 0.03, 0.058, 0.33)],
	"HDG": [Rect2(130, 3.6, 45, 19), Rect2(0.201, 0.03, 0.045, 0.33)],
	"TRK": [Rect2(130, 3.6, 45, 19), Rect2(0.245, 0.03, 0.045, 0.33)],
	"LAT": [Rect2(194, 3.6, 36, 19), Rect2(0.298, 0.03, 0.042, 0.33)],
	"C_HDG": [Rect2(130, 3.6, 45, 19), Rect2(0.43, 0.34, 0.045, 0.33)],
	"C_VS": [Rect2(245, 3.6, 37, 19), Rect2(0.5, 0.34, 0.042, 0.33)],
	"C_TRK": [Rect2(130, 3.6, 45, 19), Rect2(0.43, 0.63, 0.045, 0.33)],
	"C_FPA": [Rect2(302, 3.6, 38, 19), Rect2(0.5, 0.63, 0.042, 0.33)],
	"ALT": [Rect2(360, 3.6, 37, 19), Rect2(0.688, 0.03, 0.042, 0.33)],
	"BRACKET": [Rect2(29, 26.4, 309, 30.6), Rect2(0.728, 0.03, 0.182, 0.33)],
	"V/S": [Rect2(245, 3.6, 37, 19), Rect2(0.905, 0.03, 0.042, 0.33)],
	"FPA": [Rect2(302, 3.6, 38, 19), Rect2(0.954, 0.03, 0.045, 0.33)],
}
## digit windows: [left, right] fractions, the row is DIGITS_Y
const WIN := {"spd": [0.005, 0.093], "hdg": [0.201, 0.289], "alt": [0.631, 0.777], "vs": [0.871, 0.991]}
const DIGITS_Y := Vector2(0.50, 0.95)
const DOTS := {"spd": 0.125, "hdg": 0.321, "alt": 0.815}
## segments a..g of 0-9 (a top, then clockwise, g middle)
const SEG := ["abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abcdfg"]

var _art: Texture2D
var _art_trk: Texture2D


func _ready() -> void:
	_art = load(ART) as Texture2D
	_art_trk = load(ART_TRK) as Texture2D


func _draw() -> void:
	if not FcuWindows.powered():
		return
	var s := FcuWindows.spd()
	var h := FcuWindows.hdg()
	var a := FcuWindows.alt()
	var v := FcuWindows.vs()
	_label(str(s.label))
	_label("TRK" if h.label == "TRK" else "HDG")
	_label("LAT")
	var centre := FcuWindows.mode_label()
	_label("C_TRK" if centre == "TRK FPA" else "C_HDG")
	_label("C_FPA" if centre == "TRK FPA" else "C_VS")
	_label("ALT")
	_label("BRACKET")
	_label(str(v.label))
	_digits("spd", str(s.text))
	_digits("hdg", str(h.text))
	_digits("alt", str(a.text))
	_digits("vs", str(v.text))
	for k in [["spd", s], ["hdg", h], ["alt", a]]:
		if bool(k[1].dot):
			draw_circle(Vector2(DOTS[k[0]] * size.x, lerpf(DIGITS_Y.x, DIGITS_Y.y, 0.5) * size.y), size.y * 0.12, AMBER)


func _label(key: String) -> void:
	var row: Array = LABELS[key]
	var tex := _art_trk if key == "TRK" or key == "C_TRK" else _art
	if tex == null:
		return
	var r: Rect2 = row[1]
	draw_texture_rect_region(tex, Rect2(r.position * size, r.size * size), row[0])


func _digits(win: String, text: String) -> void:
	var span: Array = WIN[win]
	var n := maxi(text.length(), 1)
	var w := (float(span[1]) - float(span[0])) * size.x / n
	for i in text.length():
		var cell := Rect2(float(span[0]) * size.x + i * w, DIGITS_Y.x * size.y, w, (DIGITS_Y.y - DIGITS_Y.x) * size.y)
		_char(text[i], cell.grow_individual(-w * 0.14, 0, -w * 0.14, 0))


## One seven-segment character in `r`: digits, "-", "+", "." and " ".
func _char(c: String, r: Rect2) -> void:
	var t := maxf(r.size.x * 0.17, 2.0)
	var l := r.position.x
	var rr := r.end.x
	var top := r.position.y
	var mid := r.get_center().y
	var bot := r.end.y
	match c:
		"-":
			draw_line(Vector2(l, mid), Vector2(rr, mid), AMBER, t)
			return
		"+":
			draw_line(Vector2(l, mid), Vector2(rr, mid), AMBER, t)
			draw_line(Vector2(r.get_center().x, mid - r.size.x * 0.5), Vector2(r.get_center().x, mid + r.size.x * 0.5), AMBER, t)
			return
		".":
			draw_rect(Rect2(Vector2(r.get_center().x - t * 0.6, bot - t * 1.2), Vector2(t * 1.2, t * 1.2)), AMBER)
			return
	if not c.is_valid_int():
		return
	var segs: String = SEG[int(c)]
	var pts := {"a": [Vector2(l, top), Vector2(rr, top)], "b": [Vector2(rr, top), Vector2(rr, mid)],
		"c": [Vector2(rr, mid), Vector2(rr, bot)], "d": [Vector2(l, bot), Vector2(rr, bot)],
		"e": [Vector2(l, mid), Vector2(l, bot)], "f": [Vector2(l, top), Vector2(l, mid)], "g": [Vector2(l, mid), Vector2(rr, mid)]}
	for sname in segs:
		var p: Array = pts[sname]
		draw_line(p[0], p[1], AMBER, t)
