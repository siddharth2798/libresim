class_name PlanFile
extends RefCounted
## Microsoft Flight Simulator flight plan files (.PLN, the AceXML format MSFS, FSX, P3D and Little Navmap write): read
## to a plain Dictionary and written from one. Pure text in, text out (no file access, no nav data: core/plan_import.gd
## turns it into a route). The plan:
##   {title, fp_type ("VFR" | "IFR"), route_type, cruise_ft, dep_id, dep (LLA or {}), dest_id, dest (LLA or {}),
##    wps: [{id, type ("Airport" | "VOR" | "NDB" | "Intersection" | "User"), lla, airway}]}
## LLA = {lat, lon, alt_ft}. wps holds every ATCWaypoint in order, the departure and destination airports included.
## WorldPosition / *LLA text: N18° 45' 30.12",E73° 24' 0.00",+000500.00 (degrees, minutes, seconds; feet). The degree
## sign may be any character (older files are not UTF-8) and the seconds may be missing (decimal minutes).

const TYPES := ["Airport", "VOR", "NDB", "Intersection", "User"]

static var _lla_re: RegEx


## Parse a .PLN text: {ok, error, plan}.
static func parse(text: String) -> Dictionary:
	var xml := XMLParser.new()
	var body := text.strip_edges()
	if not body.contains("FlightPlan.FlightPlan"):
		return {"ok": false, "error": "Not a flight plan file (no FlightPlan.FlightPlan)", "plan": {}}
	if xml.open_buffer(body.to_utf8_buffer()) != OK:
		return {"ok": false, "error": "The file could not be read as XML", "plan": {}}
	var plan := {"title": "", "fp_type": "VFR", "route_type": "", "cruise_ft": 0.0, "dep_id": "", "dep": {},
		"dest_id": "", "dest": {}, "wps": []}
	var stack: Array[String] = []
	var wp := {}
	while xml.read() == OK:
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := xml.get_node_name()
				if tag == "ATCWaypoint":
					wp = {"id": xml.get_named_attribute_value_safe("id").strip_edges().to_upper(), "type": "User", "lla": {},
						"airway": ""}
				if not xml.is_empty():
					stack.append(tag)
			XMLParser.NODE_ELEMENT_END:
				if xml.get_node_name() == "ATCWaypoint" and not wp.is_empty():
					plan.wps.append(wp)
					wp = {}
				if not stack.is_empty():
					stack.pop_back()
			XMLParser.NODE_TEXT:
				var t := xml.get_node_data().strip_edges()
				if t != "" and not stack.is_empty():
					_text(plan, wp, stack, t)
	if plan.wps.is_empty() and plan.dep_id == "":
		return {"ok": false, "error": "The flight plan has no waypoints", "plan": plan}
	return {"ok": true, "error": "", "plan": plan}


static func _text(plan: Dictionary, wp: Dictionary, stack: Array[String], t: String) -> void:
	var tag: String = stack.back()
	if not wp.is_empty() and stack.has("ATCWaypoint"):
		match tag:
			"ATCWaypointType":
				wp.type = t if t in TYPES else "User"
			"WorldPosition":
				wp.lla = parse_lla(t)
			"ICAOIdent":
				wp.id = t.to_upper()
			"ATCAirway":
				wp.airway = t
		return
	match tag:
		"Title":
			plan.title = t
		"FPType":
			plan.fp_type = t.to_upper()
		"RouteType":
			plan.route_type = t
		"CruisingAlt":
			plan.cruise_ft = t.to_float()
		"DepartureID":
			plan.dep_id = t.to_upper()
		"DepartureLLA":
			plan.dep = parse_lla(t)
		"DestinationID":
			plan.dest_id = t.to_upper()
		"DestinationLLA":
			plan.dest = parse_lla(t)


## "N18° 45' 30.12",E73° 24' 0.00",+000500.00" -> {lat, lon, alt_ft}; {} when it does not read.
static func parse_lla(s: String) -> Dictionary:
	if _lla_re == null:
		_lla_re = RegEx.create_from_string(
			"([NS])\\s*(\\d+)[^\\d.]+([\\d.]+)'\\s*(?:([\\d.]+)\\s*\"?)?\\s*,\\s*([EW])\\s*(\\d+)[^\\d.]+([\\d.]+)'\\s*(?:([\\d.]+)\\s*\"?)?(?:\\s*,\\s*([+-]?[\\d.]+))?")
	var m := _lla_re.search(s.to_upper())
	if m == null:
		return {}
	var lat := m.get_string(2).to_float() + m.get_string(3).to_float() / 60.0 + m.get_string(4).to_float() / 3600.0
	var lon := m.get_string(6).to_float() + m.get_string(7).to_float() / 60.0 + m.get_string(8).to_float() / 3600.0
	if m.get_string(1) == "S":
		lat = -lat
	if m.get_string(5) == "W":
		lon = -lon
	return {"lat": lat, "lon": lon, "alt_ft": m.get_string(9).to_float()}


## {lat, lon, alt_ft} -> "N18° 45' 30.12",E73° 24' 0.00",+000500.00".
static func format_lla(lat: float, lon: float, alt_ft: float) -> String:
	return "%s,%s,%s%09.2f" % [_dms(lat, "N", "S"), _dms(lon, "E", "W"), "+" if alt_ft >= 0.0 else "-", absf(alt_ft)]


static func _dms(v: float, pos: String, neg: String) -> String:
	var a := absf(v)
	var deg := floori(a)
	var mins := floori((a - deg) * 60.0)
	var secs := (a - deg - mins / 60.0) * 3600.0
	if secs >= 59.995:  # would print as 60.00
		secs = 0.0
		mins += 1
		if mins == 60:
			mins = 0
			deg += 1
	return "%s%d° %d' %.2f\"" % [pos if v >= 0.0 else neg, deg, mins, secs]


## The .PLN text of `plan` (the parse() shape; wps include the departure and destination airports).
static func write(plan: Dictionary) -> String:
	var L := PackedStringArray(['<?xml version="1.0" encoding="UTF-8"?>', "", '<SimBase.Document Type="AceXML" version="1,0">',
		"    <Descr>AceXML Document</Descr>", "    <FlightPlan.FlightPlan>"])
	var head := [["Title", plan.get("title", "")], ["FPType", plan.get("fp_type", "VFR")],
		["RouteType", plan.get("route_type", "Direct")], ["CruisingAlt", str(roundi(float(plan.get("cruise_ft", 0.0))))],
		["DepartureID", plan.get("dep_id", "")], ["DepartureLLA", _lla_text(plan.get("dep", {}))],
		["DestinationID", plan.get("dest_id", "")], ["DestinationLLA", _lla_text(plan.get("dest", {}))],
		["Descr", plan.get("title", "")]]
	for h in head:
		if str(h[1]) != "":
			L.append("        <%s>%s</%s>" % [h[0], esc(str(h[1])), h[0]])
	L.append_array(["        <AppVersion>", "            <AppVersionMajor>11</AppVersionMajor>",
		"            <AppVersionBuild>282174</AppVersionBuild>", "        </AppVersion>"])
	for w in plan.get("wps", []):
		L.append('        <ATCWaypoint id="%s">' % esc(str(w.id), true))
		L.append("            <ATCWaypointType>%s</ATCWaypointType>" % str(w.get("type", "User")))
		L.append("            <WorldPosition>%s</WorldPosition>" % _lla_text(w.get("lla", {})))
		if str(w.get("airway", "")) != "":
			L.append("            <ATCAirway>%s</ATCAirway>" % esc(str(w.airway)))
		if str(w.get("type", "User")) != "User":
			L.append_array(["            <ICAO>", "                <ICAOIdent>%s</ICAOIdent>" % esc(str(w.id)), "            </ICAO>"])
		L.append("        </ATCWaypoint>")
	L.append_array(["    </FlightPlan.FlightPlan>", "</SimBase.Document>", ""])
	return "\n".join(L)


static func _lla_text(lla: Dictionary) -> String:
	return "" if lla.is_empty() else format_lla(float(lla.lat), float(lla.lon), float(lla.get("alt_ft", 0.0)))


## XML-escaped text; `attr` also escapes double quotes (attribute values; element text keeps them, as MSFS writes it).
static func esc(s: String, attr := false) -> String:
	var t := s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
	return t.replace("\"", "&quot;") if attr else t
