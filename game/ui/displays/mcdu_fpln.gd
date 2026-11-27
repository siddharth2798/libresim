class_name McduFpln
extends RefCounted
## F-PLN page of the lite MCDU: six lines of the route (active waypoint first, then the later ones, then the
## "[ ]" insert slot), scrolled by the mouse wheel over the page or the slew keys (up / down under the letters).
## Props: mcdu/fpln_top (first route index shown; clamped to the route on every read, so a route that sequences
## or shrinks never leaves the page blank). Writes controls/gps/{target, route_next} through MCDU._commit.

const ROWS := 6
const IDENT_W := 220.0  # the ident column; the course / distance column sits right of it


## Replace waypoint `i` (0-based; past the end = append) with `ident`; the new route (pure).
static func with_waypoint(wps: Array, i: int, ident: String) -> Array:
	var out := wps.duplicate()
	if i >= out.size():
		out.append(ident)
	else:
		out[i] = ident
	return out


## INIT FROM/TO as the real MCDU shows it: origin / destination only (the full route is on this page). Pure.
static func from_to_shown(text: String) -> String:
	var parts := FlightPlan.split_from_to(text)
	return "%s/%s" % [parts[0], parts[-1]] if parts.size() > 2 else text


## Entries on the page: the waypoints plus the insert slot.
static func entries(n_wps: int) -> int:
	return n_wps + 1


## The first route index shown, clamped so the last page is full and never starts past the slot. Pure.
static func top_clamped(top: int, n_wps: int) -> int:
	return clampi(top, 0, maxi(entries(n_wps) - ROWS, 0))


static func top(n_wps: int) -> int:
	return top_clamped(int(Props.get_f("mcdu/fpln_top")), n_wps)


## Scroll by `lines` (+ = later waypoints).
static func scroll(lines: int) -> void:
	var n := MCDU.route().size()
	Props.set_v("mcdu/fpln_top", top_clamped(top(n) + lines, n))


static func line_key(d: MCDU, side: String, row: int, s: String, known: Callable) -> void:
	if side != "l" or row < 1:
		return
	var wps := MCDU.route()
	var ed := FlightPlan.edit(wps, top(wps.size()) + row - 1, s, known)
	if ed.error != "":
		Props.set_v("mcdu/scratch", ed.error)
	elif s == "":
		Props.set_v("mcdu/scratch", ed.scratch)
	elif not ed.wps.is_empty():
		d._commit(str(ed.wps[0]), ed.wps.slice(1), true)


static func paint(d: MCDU) -> void:
	var wps := MCDU.route()
	var legs: Array = Props.get_v("avionics/fms/legs", [])
	var t := top(wps.size())
	d.hot(Rect2(64, 44, 292, 264), "fpln_body")  # wheel scrolls; the line keys are registered after, so they win
	for row in ROWS:
		var i := t + row
		var y := 50.0 + row * 44.0
		if i < wps.size():
			d.txt_fit(Vector2(16, y + 20), str(wps[i]), 20, IDENT_W, MCDU.MAGENTA if i == 0 else MCDU.GREEN)
			if i < legs.size():
				var lg: Dictionary = legs[i]
				d.txt_fit(Vector2(400, y + 20), "%03d %dNM" % [roundi(lg.get("course", 0)), roundi(lg.get("dist_nm", 0))],
					16, 384.0 - IDENT_W, MCDU.GREEN, 1)
		elif i == wps.size():
			d.txt(Vector2(16, y + 20), "[    ]", 20, Color(0.4, 0.6, 0.7))
	_slew(d, t > 0, t < top_clamped(1 << 20, wps.size()))


## The slew keys, lit while there is more of the route that way.
static func _slew(d: MCDU, up: bool, down: bool) -> void:
	var ar := d.font != null and d.font.has_char(0x2191) and d.font.has_char(0x2193)
	d.button(Rect2(336, 546, 36, 34), "slew_up", "↑" if ar else "UP", up, MCDU.GREEN, 16 if ar else 11)
	d.button(Rect2(376, 546, 36, 34), "slew_dn", "↓" if ar else "DN", down, MCDU.GREEN, 16 if ar else 11)
