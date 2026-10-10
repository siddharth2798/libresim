extends Control
## Basic flight HUD (M4): reads Props only. Replaced by real gauges in M5,
## kept as a toggleable overlay (H).

var _left: Label
var _right: Label
var _warn: Label
var _help: Label


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_left = _label(Vector2(12, 90))
	_right = _label(Vector2(-260, 90))
	_right.set_anchors_preset(PRESET_TOP_RIGHT)
	_right.position = Vector2(-270, 90)
	_warn = _label(Vector2(0, 0))
	_warn.set_anchors_preset(PRESET_CENTER_TOP)
	_warn.position = Vector2(-80, 40)
	_warn.add_theme_color_override("font_color", Color(1, 0.25, 0.2))
	_warn.add_theme_font_size_override("font_size", 26)
	_help = _label(Vector2(12, -230))
	_help.set_anchors_preset(PRESET_BOTTOM_LEFT)
	_help.position = Vector2(12, -235)
	_help.text = ("arrows pitch/roll  Z/X rudder  PgUp/PgDn throttle  ;/' mixture\n"
		+ "Home/End trim  [ ] or F6/F7 flaps  B brakes  Shift+B parking  ,/. diff brake\n"
		+ "S starter  M magnetos  Y mouse yoke  V centre view\n"
		+ "C / 1-8 views: cockpit chase orbit free tower wing tail fly-by (free cam: WASD QE)\n"
		+ "Tab / Shift+Tab panel layout (Full, Split, Compact, Minimal, Off)  F10 settings (graphics, weather, time, failures)\n"
		+ "T taxi route  P pushback  ` radio (ATC)  F2 checklists\n"
		+ "Esc pause  H hud  F1 help  F3 perf  F5 reset  F12 credits")
	_help.visible = false


func _label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_font_size_override("font_size", 17)
	add_child(l)
	return l


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo:
		if e.keycode == KEY_H:
			visible = not visible
		elif e.keycode == KEY_F1:
			_help.visible = not _help.visible


func _process(_dt: float) -> void:
	if not visible:
		return
	var p := Props
	var mags: String = ["OFF", "L", "R", "BOTH"][int(p.get_v("controls/magnetos", 3))]
	_left.text = "IAS  %3.0f kt\nALT %5.0f ft\nVS  %+5.0f fpm\nHDG  %03.0f°\nAGL %5.0f ft\nGS   %3.0f kt\nAOA  %4.1f°\nG    %4.2f" % [
		Units.mps_to_kt(p.get_f("fdm/cas_mps")), Units.m_to_ft(p.get_f("fdm/alt_m")),
		Units.mps_to_fpm(p.get_f("fdm/vs_mps")), rad_to_deg(p.get_f("fdm/heading_rad")),
		Units.m_to_ft(p.get_f("fdm/agl_m")), Units.mps_to_kt(p.get_f("fdm/groundspeed_mps")),
		rad_to_deg(p.get_f("fdm/alpha_rad")), p.get_f("fdm/load_factor")]
	_right.text = "RPM  %4.0f\nTHR  %3.0f %%\nMIX  %3.0f %%\nMAP  %4.1f inHg\nFLAP %2.0f°\nTRIM %+4.2f\nFUEL %4.1f gal\nMAGS %s%s%s" % [
		p.get_f("engine/rpm"), p.get_f("controls/throttle") * 100.0, p.get_f("controls/mixture") * 100.0,
		Units.pa_to_inhg(p.get_f("engine/map_pa")), p.get_f("fdm/flap_deg"), p.get_f("controls/pitch_trim"),
		p.get_f("fuel/total_kg") / 2.72, mags,
		"\nPARK BRAKE" if p.get_b("controls/parking_brake") else "",
		"\nMOUSE YOKE" if p.get_b("controls/mouse_yoke") else ""]
	var w := ""
	if p.get_b("fdm/stall_warning"):
		w = "STALL"
	elif not p.get_b("engine/running") and p.get_f("engine/rpm") < 300.0:
		w = "ENGINE OFF (hold S)"
	_warn.text = w
