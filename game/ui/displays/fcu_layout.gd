class_name FcuLayout
extends RefCounted
## Where everything sits on the 2D FCU card (ui/displays/fcu.gd), in its own design px (1280 x 170). One table feeds the
## drawing, the click zones and the hover note, so what is drawn is what is clickable. Pure: no Props, no nodes.
## Controls: the four knobs (SPD, HDG, ALT, V/S: the label and the window are one zone), the five FCU pushbuttons
## (LOC, AP1, AP2, A/THR, APPR, then EXPED, which the sim does not model: shown dim and disabled), the four
## selector buttons under the windows (SPD/MACH, HDG-V/S / TRK-FPA, METRIC ALT, ALT 100/1000) and the captain's
## EFIS FD and LS buttons. A zone is its drawn rect grown by half the gap, so there is no dead strip between buttons.

const DESIGN := Vector2(1280, 170)
const KNOBS := ["spd", "hdg", "alt", "vs"]
const WIN_W := 148.0
const WIN_STEP := 158.0
const WIN_X := 14.0
const WIN_Y := 28.0
const WIN_H := 58.0
const BTN_X := 668.0
const BTN_W := 92.0
const BTN_STEP := 100.0
const ROW1 := Rect2(0, 28, 0, 58)
const ROW2 := Rect2(0, 100, 0, 60)
const GROW := 4.0
const ROW1_IDS := ["loc", "ap1", "ap2", "athr", "appr", "exped"]
const ROW2_LEFT := ["spd_mach", "trk_fpa", "metric_alt", "alt_inc"]
const ROW2_RIGHT := ["fd", "ls"]


## The window rect of knob `key` (the digits box).
static func window_rect(key: String) -> Rect2:
	return Rect2(WIN_X + WIN_STEP * KNOBS.find(key), WIN_Y, WIN_W, WIN_H)


## Drawn rect of a pushbutton id (EXPED included), empty Rect2 for an unknown id.
static func button_rect(id: String) -> Rect2:
	var i := ROW1_IDS.find(id)
	if i >= 0:
		return Rect2(BTN_X + BTN_STEP * i, ROW1.position.y, BTN_W, ROW1.size.y)
	i = ROW2_LEFT.find(id)
	if i >= 0:
		return Rect2(WIN_X + WIN_STEP * i, ROW2.position.y, WIN_W, ROW2.size.y)
	i = ROW2_RIGHT.find(id)
	if i >= 0:
		return Rect2(BTN_X + BTN_STEP * i, ROW2.position.y, BTN_W, ROW2.size.y)
	return Rect2()


## Every zone: [{id, rect (drawn), hit (clickable), kind "knob" / "button" / "off"}]. Ids: knob_spd .. knob_vs, btn_<name>.
static func zones() -> Array:
	var out := []
	for k in KNOBS:
		var w := window_rect(k)
		var top := Rect2(w.position.x, 2.0, w.size.x, w.end.y - 2.0)  # label and window
		out.append({"id": "knob_" + k, "rect": w, "hit": top.grow_individual(5.0, 0.0, 5.0, 4.0), "kind": "knob"})
	for ids in [ROW1_IDS, ROW2_LEFT, ROW2_RIGHT]:
		for b in ids:
			var r := button_rect(b)
			out.append({"id": "btn_" + b, "rect": r, "hit": r.grow(GROW), "kind": "off" if b == "exped" else "button"})
	return out


## The zone id under a point of the card ("" for none). A button wins over a knob where the two grown rects meet.
static func zone_at(p: Vector2) -> String:
	var found := ""
	for z in zones():
		if (z.hit as Rect2).has_point(p):
			if z.kind == "knob":
				if found == "":
					found = z.id
			else:
				return z.id
	return found


## The panel pixel under a screen point of a piece drawn in `rect` (screen px) from the panel region `reg` (panel px): what
## ui/panel_overlay.gd forwards into the panel viewport.
static func piece_point(rect: Rect2, reg: Rect2, screen: Vector2) -> Vector2:
	return reg.position + (screen - rect.position) / rect.size * reg.size


## The zone id under a panel pixel ("" for none): the FCU's rect on the aircraft's panel, then the card's own zones.
static func zone_in_panel(panel_px: Vector2) -> String:
	var r: Rect2 = InstrumentPanel.rects().get("fcu", Rect2())
	if r.size.x <= 0.0 or not r.has_point(panel_px):
		return ""
	return zone_at(design_point(panel_px - r.position, r.size))


## The design-space point of a point `local` px inside a card of size `size` (the card scales its design uniformly).
static func design_point(local: Vector2, size: Vector2) -> Vector2:
	var s := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	return local / s if s > 0.0 else Vector2(-1, -1)
