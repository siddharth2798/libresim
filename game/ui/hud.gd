extends Control
## Flight-data bar (H toggles): one slim translucent strip at the top-centre with only
## what a pilot glances at — IAS, GS, ALT, AGL near the ground, VS, HDG. Everything else
## (engine, fuel, switches) is on the instrument panel. F1 shows a key-help card.
## Warnings, failures and damage messages are cards from ui/notifications.gd.

const ITEMS := ["IAS", "GS", "ALT", "AGL", "VS", "HDG"]

var _bar: PanelContainer
var _vals := {}
var _cells := {}
var _help: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_bar = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.06, 0.09, 0.62)
	s.set_corner_radius_all(10)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	_bar.add_theme_stylebox_override("panel", s)
	_bar.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(Notifications.centered(_bar, PRESET_TOP_WIDE, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	_bar.add_child(hb)
	for k in ITEMS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", -4)
		var cap := Label.new()
		cap.text = k
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_theme_font_size_override("font_size", 11)
		cap.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
		cell.add_child(cap)
		var v := Label.new()
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.custom_minimum_size = Vector2(64, 0)
		v.add_theme_font_size_override("font_size", 19)
		cell.add_child(v)
		hb.add_child(cell)
		_vals[k] = v
		_cells[k] = cell
	_help = _help_card()
	visible = bool(UserOptions.get_v("hud_at_start"))


func _help_card() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Notifications.card_style(Notifications.COLORS[0]))
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 4)
	p.add_child(g)
	for row in [["↑ ↓ ← →", "pitch / roll", "Z / X", "rudder"], ["PgUp / PgDn", "throttle", "; / '", "mixture"],
			["Home / End", "trim", "[ / ]", "flaps"], ["B · , .", "brakes", "Shift+B", "parking brake"],
			["M · S", "magnetos · starter", "Y", "mouse yoke"], ["C · 1–8", "views", "Tab", "panel layout"],
			["N", "map", "`", "radio / ATC"], ["T · P", "taxi route · pushback", "F2", "checklists"],
			["F9 · F10", "failures · settings", "R · F8", "replay · record"], ["F11", "quick-save", "J", "controls"],
			["H", "flight-data bar", "Esc", "pause menu"], ["L · Shift+L", "panel lights + / −", "F1", "this help"], ["Shift+M · Shift+V", "master · avionics", "Shift+F · Ctrl+F", "fuel selector · shutoff"], ["Ctrl+B N S L T", "beacon nav strobe land taxi", "Ctrl+H", "pitot heat"], ["Ctrl+click", "zoom on cockpit item", "wheel", "zoom to cursor"], ["K", "training callouts on / off", "Backspace", "dismiss taxi message"]]:
		for i in 4:
			var l := Label.new()
			l.text = row[i]
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", Color(1, 0.85, 0.5) if i % 2 == 0 else Color(0.88, 0.9, 0.92))
			g.add_child(l)
	p.visible = false
	add_child(Notifications.centered(p, PRESET_FULL_RECT, 0))
	return p


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo:
		if e.keycode == KEY_H:
			_bar.visible = not _bar.visible
		elif e.keycode == KEY_F1:
			_help.visible = not _help.visible


func _process(_dt: float) -> void:
	if not _bar.visible:
		return
	var p := Props
	var agl := Units.m_to_ft(p.get_f("fdm/agl_m"))
	_vals.IAS.text = "%d kt" % roundi(Units.mps_to_kt(p.get_f("fdm/cas_mps")))
	_vals.GS.text = "%d kt" % roundi(Units.mps_to_kt(p.get_f("fdm/groundspeed_mps")))
	_vals.ALT.text = "%d ft" % (roundi(Units.m_to_ft(p.get_f("fdm/alt_m")) / 10.0) * 10)
	_vals.AGL.text = "%d ft" % roundi(agl)
	_cells.AGL.visible = agl < 2500.0
	var vs := Units.mps_to_fpm(p.get_f("fdm/vs_mps"))
	_vals.VS.text = "%+d" % (roundi(vs / 10.0) * 10) if absf(vs) >= 20.0 else "0"
	_vals.HDG.text = "%03d°" % (roundi(rad_to_deg(p.get_f("fdm/heading_rad")) + 360.0) % 360)
