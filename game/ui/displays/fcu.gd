class_name FCU
extends Display
## Flight control unit (glareshield autopilot panel): SPD / HDG / ALT / V/S windows with knobs and the
## LOC, AP1, AP2, A/THR, APPR buttons. WRITES the pilot's selections, Props controls/fcu/{spd_kt,
## hdg_deg, alt_ft, vs_fpm} (pilot units, like the keyboard actions in input/control_actions.gd) and
## the button toggles controls/fcu/{ap1, ap2, athr, loc, appr}; middle click on a knob toggles
## controls/fcu/{spd,hdg,vs}_managed (window shows dashes). READS the autopilot state to light the
## buttons: ap/{ap1, ap2, athr, loc, appr} (falls back to the control prop while the autoflight does
## not publish them).
## Knobs: click the left / right half of a window (or the wheel) = -/+ one step, right click = ten steps.

const KNOBS := {  # key -> [prop, step, min, max, wrap, managed prop]
	"spd": ["controls/fcu/spd_kt", 1.0, 100.0, 399.0, false, "controls/fcu/spd_managed"],
	"hdg": ["controls/fcu/hdg_deg", 1.0, 0.0, 359.0, true, "controls/fcu/hdg_managed"],
	"alt": ["controls/fcu/alt_ft", 100.0, 100.0, 39000.0, false, ""],
	"vs": ["controls/fcu/vs_fpm", 100.0, -6000.0, 6000.0, false, "controls/fcu/vs_managed"],
}
const BUTTONS := ["loc", "ap1", "ap2", "athr", "appr"]
const LABELS := {"loc": "LOC", "ap1": "AP1", "ap2": "AP2", "athr": "A/THR", "appr": "APPR"}
const WIN := [Rect2(25, 34, 140, 54), Rect2(185, 34, 140, 54), Rect2(345, 34, 140, 54), Rect2(505, 34, 140, 54)]


func _init() -> void:
	design = Vector2(700, 170)


## The value after `steps` knob steps (pure): wraps for a heading, clamps otherwise.
static func stepped(key: String, v: float, steps: float) -> float:
	var k: Array = KNOBS[key]
	var nv: float = v + steps * k[1]
	return fposmod(nv, 360.0) if k[4] else clampf(nv, k[2], k[3])


## Digits of a window: SPD / HDG 3 digits, ALT 5, V/S signed.
static func window_text(key: String, v: float) -> String:
	match key:
		"alt": return "%05d" % roundi(v)
		"vs": return "%+d" % roundi(v)
	return "%03d" % roundi(v)


func _knob(key: String, steps: float) -> void:
	var k: Array = KNOBS[key]
	Props.set_v(k[0], stepped(key, Props.get_f(k[0], k[2]), steps))


func _press(id: String, button: int, p: Vector2) -> void:
	if id.begins_with("btn_"):
		var pk := "controls/fcu/" + id.substr(4)
		Props.set_v(pk, not Props.get_b(pk))
		return
	var key := id.substr(5)
	var r: Rect2 = WIN[KNOBS.keys().find(key)]
	if button == MOUSE_BUTTON_MIDDLE:
		var m: String = KNOBS[key][5]
		if m != "":
			Props.set_v(m, not Props.get_b(m))
		return
	_knob(key, (-1.0 if p.x < r.get_center().x else 1.0) * (10.0 if button == MOUSE_BUTTON_RIGHT else 1.0))


func _wheel(id: String, dir: float) -> void:
	if id.begins_with("knob_"):
		_knob(id.substr(5), dir)


func _lit(k: String) -> bool:
	return Props.get_b("ap/" + k, Props.get_b("controls/fcu/" + k))


func _paint() -> void:
	fill(Rect2(Vector2.ZERO, design), Color(0.1, 0.11, 0.13))
	frame(Rect2(2, 2, design.x - 4, design.y - 4), Color(0.3, 0.32, 0.36), 2.0)
	var names := ["SPD", "HDG", "ALT", "V/S"]
	for i in 4:
		var key: String = KNOBS.keys()[i]
		var k: Array = KNOBS[key]
		txt(Vector2(WIN[i].get_center().x, 20), names[i], 16, WHITE, 0)
		var dashed: bool = k[5] != "" and Props.get_b(k[5])
		var v := Props.get_f(k[0], k[2])
		var s := "---" if dashed else window_text(key, v)
		window(WIN[i], s, AMBER if not dashed else Color(0.5, 0.35, 0.05))
		if key in ["spd", "hdg", "vs"]:
			var managed: bool = Props.get_b(k[5])
			dot(Vector2(WIN[i].end.x - 10, WIN[i].position.y + 8), 4.0, AMBER if managed else Color(0.25, 0.2, 0.05))
		hot(WIN[i], "knob_" + key)
	for i in BUTTONS.size():
		var b: String = BUTTONS[i]
		var lit := _lit(b)
		button(Rect2(25 + i * 135, 110, 120, 44), "btn_" + b, LABELS[b], lit, GREEN if b != "athr" else CYAN)
