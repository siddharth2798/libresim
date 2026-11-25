extends "res://tests/fcu_panel_base.gd"
## The clickable 2D FCU card of the outside views (ui/displays/fcu.gd, fcu_layout.gd, fcu_tips.gd, ui/panel_overlay.gd):
## a point maps to the right control at every window size, UI scale and layout (Full and Custom), the hover notes name the
## control and its key and come after a short hold and only on the card, a press the autopilot refuses does not engage and the lamps
## follow what it did, and the Cessna panel is untouched. That each click writes what its cockpit twin writes: test_fcu_panel_twin.gd.


func test_every_control_has_one_zone_that_maps_back_to_it() -> String:
	var zones := FcuLayout.zones()
	if zones.size() != 16:
		return "4 knobs, 5 lamps, EXPED, 4 selectors, FD and LS = 16 zones, got %d" % zones.size()
	for z in zones:
		if FcuLayout.zone_at((z.rect as Rect2).get_center()) != z.id:
			return "the middle of %s maps to %s" % [z.id, FcuLayout.zone_at((z.rect as Rect2).get_center())]
		if not Rect2(Vector2.ZERO, FcuLayout.DESIGN).encloses(z.hit):
			return "%s sticks out of the card" % z.id
		for o in zones:
			if o.id != z.id and (z.hit as Rect2).intersects(o.hit):
				return "%s and %s overlap" % [z.id, o.id]
	for b in FcuActions.BUTTONS:
		if FcuLayout.zone_at(_centre("btn_" + b)) != "btn_" + b:
			return "button %s has no zone" % b
	var gap := (FcuLayout.button_rect("ap1").end.x + FcuLayout.button_rect("ap2").position.x) * 0.5
	if FcuLayout.zone_at(Vector2(gap, 56.0)) == "":
		return "the strip between two buttons is a dead zone"
	return ""


func test_a_screen_point_reaches_the_right_control_at_every_scale_and_layout() -> String:
	_begin()
	var def := AircraftDef.load_def("a320")
	var p := ScreenLayout.load_pieces(def)
	p.fcu.merge({"on": true, "x": 0.2, "y": 0.06, "h": 0.16}, true)
	ScreenLayout.save_pieces(def, p)
	var fcu_rect: Rect2 = InstrumentPanel.rects().fcu
	var ov: Control = load("res://ui/panel_overlay.gd").new()
	var seen := 0
	for win in [Vector2(1280, 720), Vector2(1920, 1080)]:
		for ui_scale in [1.0, 1.5, 2.0]:
			var vs: Vector2 = win / ui_scale  # the visible rect at that UI scale
			for layout in ["Full", "Custom"]:
				ov.layout = ov.LAYOUTS.find(layout)
				for pl in ov.placements(vs):
					if not "fcu" in pl[0]:
						continue
					var rect: Rect2 = pl[1]
					var reg := ScreenLayout.region(def, pl[0])
					var k := rect.size / reg.size  # screen px per panel px
					for z in FcuLayout.zones():
						var panel_px: Vector2 = fcu_rect.position + (z.hit as Rect2).get_center()
						var screen := rect.position + (panel_px - reg.position) * k
						var got := FcuLayout.zone_in_panel(FcuLayout.piece_point(rect, reg, screen))
						if got != z.id:
							ov.free()
							return "%s %s at UI %s: %s maps to %s" % [layout, win, ui_scale, z.id, got]
						var phys: Vector2 = (z.hit as Rect2).size * k.x * ui_scale  # on the monitor, whatever the UI scale
						if phys.y < 14.0 or phys.x < 28.0:
							ov.free()
							return "%s %s UI %s: %s is only %.0f x %.0f px to click" % [layout, win, ui_scale, z.id, phys.x, phys.y]
						seen += 1
	ov.free()
	return "" if seen == 2 * 3 * 2 * 16 else "checked %d points" % seen


func test_the_cessna_panel_has_no_fcu_zone_and_no_note() -> String:
	_begin()
	Session.setup.aircraft = "c172"
	InstrumentPanel.clear_cache()
	for r in InstrumentPanel.rects().values():
		if FcuLayout.zone_in_panel((r as Rect2).get_center()) != "":
			return "a Cessna panel point reached an FCU zone"
	var ov: Control = load("res://ui/panel_overlay.gd").new()
	var ck := Cockpit.new()
	ov.cockpit = ck
	ov._hover_px = Vector2(300, 100)
	var note: String = ov.hover_note(1.0)
	ov.free()
	ck.free()
	return "" if note == "" else "the Cessna overlay showed a note [%s]" % note


func test_a_point_outside_the_card_or_the_piece_reaches_nothing() -> String:
	_begin()
	var fcu_rect: Rect2 = InstrumentPanel.rects().fcu
	if FcuLayout.zone_in_panel(fcu_rect.position - Vector2(5, 5)) != "":
		return "above-left of the card"
	if FcuLayout.zone_in_panel(InstrumentPanel.rects().pfd.get_center()) != "":
		return "the PFD is not an FCU zone"
	if FcuLayout.zone_at(Vector2(1275, 5)) != "":
		return "the card's empty corner"
	return ""


# ---- hover notes -------------------------------------------------------------------------------------

func test_every_zone_has_a_three_line_note_with_its_key() -> String:
	_begin()
	var keys := KeyBindings.defaults()
	for z in FcuLayout.zones():
		var t := FcuTips.text(z.id, keys)
		if t.split("\n").size() != 3 or t.split("\n")[0] == "":
			return "%s note is not name / how / state: [%s]" % [z.id, t]
	var ap1 := FcuTips.text("btn_ap1", keys)
	if not ap1.begins_with("Autopilot 1\nClick") or not ap1.contains("Ctrl+1"):
		return "AP1 note: [%s]" % ap1
	var spd := FcuTips.text("knob_spd", keys)
	if not spd.contains("Wheel") or not spd.contains("Click: push") or not spd.contains("Shift+click: pull") or not spd.contains("["):
		return "SPD note: [%s]" % spd
	Props.set_v("controls/fcu/spd_managed", true)
	if not FcuTips.text("knob_spd", keys).contains("managed"):
		return "SPD note should say managed"
	Props.set_v("ap/ap1", false)
	var off := FcuTips.text("btn_ap1", keys)
	Props.set_v("ap/ap1", true)
	return "" if off.ends_with("Off") and FcuTips.text("btn_ap1", keys).ends_with("Engaged") else "AP1 state follows the autopilot, not the press"


func test_the_overlay_shows_the_note_after_a_short_hold_and_only_on_the_card() -> String:
	_begin()
	var ov: Control = load("res://ui/panel_overlay.gd").new()
	var ck := Cockpit.new()
	ov.cockpit = ck
	var fr: Rect2 = InstrumentPanel.rects().fcu
	ov._hover_px = fr.position + _centre("btn_ap1")
	var first: String = ov.hover_note(0.05)
	var held: String = ov.hover_note(0.2)
	ov._hover_px = InstrumentPanel.rects().pfd.get_center()  # the pointer is on another display of the panel
	var off: String = ov.hover_note(0.5)
	ov._hover_px = fr.position + _centre("knob_hdg")
	ov.hover_note(0.05)
	var knob: String = ov.hover_note(0.2)
	ov.free()
	ck.free()
	if first != "" or not held.begins_with("Autopilot 1\n") or off != "":
		return "note after 0.05 s [%s], after 0.25 s [%s], off the card [%s]" % [first, held, off]
	return "" if knob.begins_with("Heading\n") else "HDG knob note [%s]" % knob


# ---- feedback is the real state ----------------------------------------------------------------------

func test_refused_presses_do_not_engage_and_the_lamps_follow_the_autopilot() -> String:
	_begin()
	for k in ["environment/wind_ned", "environment/gust_pqr"]:
		Props.set_v(k, Vector3.ZERO)
	var r := AfRig.new(250.0, 10000.0, 0.0)
	_new_card()
	for k in ["ap1", "ap2", "athr", "loc", "appr"]:  # what an earlier suite in this process left
		Props.set_v("ap/" + k, false)
	Props.set_v("controls/fcu/hdg_deg", 0.0)
	if _card._lit("ap1"):
		return "AP1 is dark before any press"
	Props.set_v("controls/fcu/fd", false)  # no AP and no FD: LOC and APPR have nothing to arm, the presses spring back
	_click("btn_loc")
	_click("btn_appr")
	if not Props.get_b("controls/fcu/loc"):
		return "the press itself shows as a request"
	r.run(0.5)
	if Props.get_b("controls/fcu/loc") or Props.get_b("controls/fcu/appr") or _card._lit("loc") or _card._lit("appr"):
		return "LOC / APPR that arm nothing must spring back dark: loc %s appr %s lit %s %s" % [Props.get_b("controls/fcu/loc"),
			Props.get_b("controls/fcu/appr"), _card._lit("loc"), _card._lit("appr")]
	Props.set_v("controls/fcu/fd", true)
	_click("btn_ap1")
	r.run(1.0)
	if not _card._lit("ap1") or not Props.get_b("ap/ap1"):
		return "AP1 should light once the autopilot engaged"
	_click("knob_hdg")  # push: NAV, with no route there is nothing to follow
	if not Props.get_b("controls/fcu/hdg_managed"):
		return "the press itself shows as a request"
	r.run(0.5)
	if Props.get_b("controls/fcu/hdg_managed") or FcuWindows.hdg().text.begins_with("-") or FcuWindows.hdg().dot:
		return "NAV with no route must not engage: managed %s, window %s" % [Props.get_b("controls/fcu/hdg_managed"), FcuWindows.hdg()]
	_click("btn_loc")  # with the AP on, LOC is armed (blue on the FMA) and its lamp lights from that, not from the press
	r.run(0.5)
	if not _card._lit("loc") or not Props.get_b("ap/loc"):
		return "LOC lamp should show the armed localizer, FMA %s" % Props.get_v("ap/fma/lateral")
	_click("btn_ap1")
	r.run(0.5)
	if _card._lit("ap1"):
		return "a second press disengages and darkens the lamp"
	_click("btn_athr")
	r.run(0.5)
	return "" if _card._lit("athr") else "A/THR lamp follows the armed autothrust"
