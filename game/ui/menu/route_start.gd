class_name RouteStart
extends VBoxContainer
## "Start" under the Route step's nav log: for an "In the air" start, where the flight begins, on final as the Airport
## step sets it (route.air_at = -1) or on leg k of the route (air_at = k: core/route_air_start.gd puts the aircraft 2 nm
## along that leg at its planned altitude). Hidden (a note says why) for runway and stand starts or without a route.

signal leg_picked(k: int)  # -1 = on final

var opt: OptionButton
var note: Label
var _sig := ""


func _init() -> void:
	add_theme_constant_override("separation", 4)
	add_child(MenuTheme.heading("Start", 13))
	opt = OptionButton.new()
	opt.tooltip_text = "Where an \"In the air\" start puts you: on final (the Airport step), or on a leg of this route."
	opt.item_selected.connect(func(i): leg_picked.emit(int(opt.get_item_metadata(i))))
	add_child(opt)
	note = MenuTheme.note("")
	add_child(note)


## Show the choice for setup `s`, its normalized route `r` and its legs (RouteEdit.legs).
func fill(s: Dictionary, r: Dictionary, legs: Array) -> void:
	var air := str(s.get("start", "")) == "air"
	opt.visible = air and not legs.is_empty()
	var sig := JSON.stringify(legs.map(func(l): return [l.from, l.ident]))
	if sig != _sig:
		_sig = sig
		opt.clear()
		opt.add_item("On final (Airport step)")
		opt.set_item_metadata(0, -1)
		for k in legs.size():
			opt.add_item("On leg %d: %s → %s" % [k + 1, legs[k].from, legs[k].ident])
			opt.set_item_metadata(k + 1, k)
	opt.select(clampi(int(r.air_at) + 1, 0, opt.item_count - 1))
	if not air:
		note.text = "Starting on a leg of the route is for \"In the air\" starts (Airport & start step)."
	elif legs.is_empty():
		note.text = "Plan a route to start in the air on one of its legs."
	elif int(r.air_at) >= 0:
		note.text = "You start 2 nm along that leg, heading for its end, at its planned altitude (at least 1,000 ft above the ground)."
	else:
		note.text = "You start on final, as set in the Airport & start step."
