extends VBoxContainer
## Home page of the pause screen (ui/pause_menu.gd): where the flight stands, as a row of stat
## cards, (the hotkeys are on the Controls & keys page). refresh(flight) re-reads the values each time it opens.
## The static helpers give the header's context line.

const AIRCRAFT := "res://aircraft/c172/aircraft.json"
const CARDS := ["ALTITUDE", "HEIGHT", "AIRSPEED", "HEADING", "WIND", "VISIBILITY", "LOCAL TIME", "FLIGHT TIME"]

static var _aircraft_name := ""
var _vals := {}


static func aircraft_name() -> String:
	if _aircraft_name == "":
		var d = Paths.load_res_json(AIRCRAFT)
		_aircraft_name = str(d.name) if d is Dictionary and d.has("name") else "Cessna 172"
	return _aircraft_name


static func clock() -> String:
	var t := Props.get_f("weather/time_h")
	return "%02d:%02d IST" % [int(t) % 24, int(fmod(t, 1.0) * 60.0)]


## "Cessna 172S Skyhawk SP · Flight from VAJJ · 14:32 IST · Lesson: Landing · Replay"
static func context(flight: Node) -> String:
	var parts: Array[String] = [aircraft_name()]
	var apt = flight.get("_apt") if flight else null
	if apt != null and str(apt) != "":
		parts.append("Flight from %s" % apt)
	parts.append(clock())
	if Session.training != "":
		parts.append("Lesson: %s" % TrainingLogic.find(Session.training).get("title", Session.training))
	if flight and flight.fdm_node.replaying:
		parts.append("Replay")
	return "  ·  ".join(parts)


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)
	for c in CARDS:
		grid.add_child(_card(c))


func _card(caption: String) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", MenuTheme.box(Color(1, 1, 1, 0.05), 10, Color(1, 1, 1, 0.08), 14.0))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pc.add_child(vb)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", MenuTheme.ACCENT)
	vb.add_child(cap)
	var v := Label.new()
	v.add_theme_font_size_override("font_size", 24)
	vb.add_child(v)
	_vals[caption] = v
	return pc


func refresh(flight: Node) -> void:
	var agl := Units.m_to_ft(Props.get_f("fdm/agl_m"))
	_vals["ALTITUDE"].text = "%d ft" % (roundi(Units.m_to_ft(Props.get_f("fdm/alt_m")) / 10.0) * 10)
	_vals["HEIGHT"].text = "On the ground" if Props.get_b("fdm/wow") else "%d ft AGL" % (roundi(agl / 10.0) * 10)
	_vals["AIRSPEED"].text = "%d kt" % roundi(Units.mps_to_kt(Props.get_f("fdm/cas_mps")))
	_vals["HEADING"].text = "%03d°" % (roundi(rad_to_deg(Props.get_f("fdm/heading_rad")) + 360.0) % 360)
	var kt := Props.get_f("weather/wind_kt")
	_vals["WIND"].text = "Calm" if kt < 1.0 else "%03d° / %d kt" % [roundi(Props.get_f("weather/wind_dir_deg")) % 360, roundi(kt)]
	_vals["VISIBILITY"].text = "%.0f km" % (Props.get_f("weather/visibility_m") / 1000.0)
	_vals["LOCAL TIME"].text = clock()
	var fm = flight.get_node_or_null("Systems/Failures") if flight else null
	var mins := int(fm.elapsed / 60.0) if fm else 0
	_vals["FLIGHT TIME"].text = "%d:%02d" % [mins / 60, mins % 60]
