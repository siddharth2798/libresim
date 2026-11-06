extends HBoxContainer
## Start screen page 2: Airport & start. Left, the map panel: an airport search box, the airport's name and facts, a
## clickable diagram (runway ends and stands) and its legend. Right (AirportStartPanel): where the flight starts, on a
## runway, parked at a stand / gate, or in the air on final to a runway, with only the controls that start needs.
## The map, the search box and the lists all end in the same four calls (pick_airport, pick_runway, pick_stand, _put),
## so any of them gives the same Session.setup. Stand names: world/stand_names.gd. Data: airport_data.gd.

signal changed

var _airports: Array = []  # [{icao, name, city, elev_m, runways, stands, taxiways, type}]
var _search: AirportSearch
var _diagram: AirportDiagram
var _panel: AirportStartPanel
var _name: Label
var _facts: Label
var _cur := {}
var _stand_rows := []  # the stands on offer at _cur for this aircraft, in list order: [{name, stand, sub}]
# the start panel's controls, where tests and other pages look for them
var _mode_btns := {}
var _alt: SpinBox
var _dist: SpinBox
var _air_note: Label
var _cold: SwitchRow
var _stand_note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_airports = AirportData.load_all()
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(340, 0)
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	_search = AirportSearch.new()
	_search.tooltip_text = "Type an ICAO code, an airport name or a city."
	_search.picked.connect(pick_airport)
	left.add_child(_search)
	_name = Label.new()
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	MenuTheme.use_font(_name, "semibold", 17)
	left.add_child(_name)
	_facts = MenuTheme.note("")
	left.add_child(_facts)
	_diagram = AirportDiagram.new()
	_diagram.size_flags_horizontal = SIZE_EXPAND_FILL
	_diagram.size_flags_vertical = SIZE_EXPAND_FILL
	_diagram.runway_picked.connect(pick_runway)
	_diagram.stand_picked.connect(func(st): pick_stand(str(st.get("name", st.get("ref", "")))))
	left.add_child(_diagram)
	left.add_child(_legend())
	_panel = AirportStartPanel.new()
	_panel.size_flags_horizontal = SIZE_SHRINK_END
	_panel.mode_picked.connect(func(m): _put("start", m))
	_panel.runway_picked.connect(pick_runway)
	_panel.stand_picked.connect(pick_stand)
	_panel.cold_toggled.connect(func(on): _put("cold", on))
	_panel.air_edited.connect(func(k, v):
		Session.setup.air_custom = true  # the pilot's own numbers: they stop following the aircraft
		_put(k, v))
	_panel.air_reset.connect(func():
		Session.setup.air_custom = false
		_sync_air()
		_refresh())
	add_child(_panel)
	_mode_btns = _panel.mode_btns
	_alt = _panel.alt
	_dist = _panel.dist
	_air_note = _panel.air_note
	_cold = _panel.cold
	_stand_note = _panel.stand_note
	var s: Dictionary = Session.setup
	_sync_air()
	visibility_changed.connect(_when_shown)
	_cold.set_on(bool(s.cold))
	for a in _airports:
		if a.icao == s.airport:
			_select(a, false)
	_refresh()


## The aircraft step may have changed the aircraft since this page was last shown.
func _when_shown() -> void:
	if visible:
		_sync_air()
		if not _cur.is_empty():
			_select(_cur, false)  # keeps the runway and stand, re-filters the lists for the aircraft
		_refresh()  # the diagram marks the distance


func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	for it in [["●", AirportDiagram.GATE, "gate (jetbridge)"], ["●", AirportDiagram.BAY, "remote / GA stand"], ["▲", AirportDiagram.MARK, "your start"]]:
		var l := Label.new()
		l.text = "%s %s" % [it[0], it[2]]
		l.add_theme_color_override("font_color", it[1])
		l.add_theme_font_size_override("font_size", MenuTheme.SIZE_NOTE)
		row.add_child(l)
	return row


## The air-start controls for the chosen aircraft: its limits and, unless the pilot set them, its default
## height, distance and speed (Session.apply_air_defaults).
func _sync_air() -> void:
	Session.apply_air_defaults()
	var def := AircraftDef.load_def(str(Session.setup.get("aircraft", AircraftDef.DEFAULT_ID)))
	_panel.sync_air(def.air_start(), Session.setup)


# ---- the choices: one path whether they come from the map, the search box or a list ----

func pick_airport(icao: String) -> void:
	for a in _airports:
		if a.icao == icao:
			_select(a)


## Choose a runway end (ident "27"). From the map while parked at a stand this means "start on that runway"; an air
## start stays an air start (it lands on that runway).
func pick_runway(ident: String) -> void:
	Session.setup.runway = ident
	if Session.setup.start == "stand":
		Session.setup.start = "runway"
	_refresh()


## Choose a stand by name (real ref or made-up, see StandNames); that is a stand start.
func pick_stand(stand_name: String) -> void:
	Session.setup.stand = stand_name
	Session.setup.start = "stand"
	_refresh()


func _put(key: String, v: Variant) -> void:
	Session.setup[key] = v
	_refresh()


func current_airport() -> Dictionary:
	return _cur


## The stands on offer, in list order: [{name, stand, sub}].
func stand_rows() -> Array:
	return _stand_rows


## How many runway ends the list marks "short" for the aircraft.
func short_runway_count() -> int:
	return _diagram.short_ends.size()


func _select(a: Dictionary, user := true) -> void:
	_cur = a
	var s: Dictionary = Session.setup
	if user:
		s.airport = a.icao
		s.runway = ""
		s.stand = ""
	var def := AircraftDef.load_def(str(s.get("aircraft", AircraftDef.DEFAULT_ID)))
	var gp := GroundParams.ground(def)
	var min_len := float(gp.min_runway_m)
	_search.set_items(AirportData.search_items(_airports, min_len))
	_search.set_current(a.icao)
	_name.text = str(a.name)
	var rows := []
	var first_ok := ""  # default pick: the first runway long enough for the aircraft
	var short := {}
	var xmax := float(def.section("limits").get("max_crosswind_kt", SetupChecks.DEFAULT_MAX_CROSSWIND_KT))
	for r in a.runways:
		for e in r.ends:
			var id := str(e.ident)
			var is_short := float(r.length) < min_len
			var w := AirportData.wind_parts(float(s.wind_dir_deg), float(s.wind_kt), float(e.heading_true))
			rows.append({"ident": id, "text": "%s   %s m%s" % [id, AirportData.thousands(int(r.length)), "  ·  short" if is_short else ""],
				"wind": AirportData.wind_text(w), "short": is_short, "bad": AirportData.wind_bad(w, xmax),
				"tip": ("Too short for this aircraft: it needs about %s m. " % AirportData.thousands(roundi(min_len)) if is_short else "")
					+ "Heading %03d°, wind %s." % [roundi(float(e.heading_true)), AirportData.wind_text(w)]})
			if is_short:
				short[id] = true
			if first_ok == "" and not is_short:
				first_ok = id
	if s.runway == "" or not rows.any(func(r): return r.ident == s.runway):
		s.runway = first_ok if first_ok != "" else (rows[0].ident if not rows.is_empty() else "")
	var note := ""
	if not short.is_empty():
		note = "Runways marked short are shorter than the %s m the %s needs." % [AirportData.thousands(roundi(min_len)), str(def.data.get("short_name", def.id))]
	_panel.set_runways(rows, s.runway, note)
	_diagram.short_ends = short
	_select_stands(a, def, gp)
	_diagram.show_airport(a.runways, a.taxiways, _stand_rows.map(func(r): return r.stand))
	_refresh()


## The stands to offer this aircraft (suitable class first, natural order of the names) and the remembered one.
func _select_stands(a: Dictionary, def: AircraftDef, gp: Dictionary) -> void:
	var s: Dictionary = Session.setup
	var stands: Array = a.stands
	var descs := StandNames.describe(stands, StandNames.terminals_of(str(a.icao)))
	var names := descs.map(func(d): return d.name)
	_stand_rows = []
	var panel_rows := []
	for i in StandNames.offered_indices(stands, names, str(gp.stand_class)):
		var d: Dictionary = descs[i]
		var sub := "jetbridge gate" if stands[i].get("jetbridge", false) else "remote stand"
		sub += "  ·  " + d.hint if d.hint != "" else ""
		_stand_rows.append({"name": d.name, "stand": stands[i].merged({"name": d.name}), "sub": sub})
		panel_rows.append({"name": d.name, "jetbridge": stands[i].get("jetbridge", false), "sub": sub})
	if not _stand_rows.is_empty():
		var at := StandNames.find_index(stands, str(s.stand))  # a real ref saved earlier, or a made-up name
		var known := _stand_rows.filter(func(r): return at >= 0 and r.name == names[at])
		s.stand = known[0].name if not known.is_empty() else _stand_rows[0].name  # none yet or not on offer: the first
	_panel.set_stands(panel_rows, str(s.stand), "Stand  ·  %d on offer for the %s" % [panel_rows.size(), str(def.data.get("short_name", def.id))])


func _refresh() -> void:
	var s: Dictionary = Session.setup
	var stands: Array = _cur.get("stands", [])
	if s.start == "stand" and stands.is_empty():
		s.start = "runway"
	if s.start == "air":
		s.cold = false  # an air start is never cold & dark and never keeps a stale value
	_panel.show_mode(str(s.start), not stands.is_empty())
	_cold.set_on(bool(s.cold))
	_panel.mark_runway(str(s.runway))
	_panel.mark_stand(str(s.stand))
	_panel.refresh_profile()
	_diagram.start = {}
	var stand_name := ""
	for r in _cur.get("runways", []):
		for e in r.ends:
			if e.ident == s.runway:
				var h := deg_to_rad(float(e.heading_true))
				var thr := Vector2(e.x, e.y)
				var f := Vector2(sin(h), cos(h))
				var nm := float(s.air_nm)
				if s.start == "air":
					_diagram.set_start(thr - f * nm * 1852.0, float(e.heading_true), thr, "%s nm out" % Session.nm_text(nm))
				else:
					_diagram.set_start(thr + f * 25.0, float(e.heading_true))
				_facts.text = _facts_text(r, e)
	if s.start == "stand":
		for r in _stand_rows:
			if r.name == s.stand:
				stand_name = r.name
				_diagram.set_start(Vector2(r.stand.x, r.stand.y), float(r.stand.get("heading_deg", 0.0)))
	_diagram.set_selection(str(s.runway) if s.start != "stand" else "", stand_name)
	changed.emit()


func _facts_text(r: Dictionary, e: Dictionary) -> String:
	var city := str(_cur.get("city", ""))
	return "%s%d ft elevation  ·  runway %s: %s m, heading %03d°" % [city + "  ·  " if city != "" else "",
		roundi(Units.m_to_ft(float(_cur.get("elev_m", 0.0)))), str(e.ident), AirportData.thousands(int(r.length)), roundi(float(e.heading_true))]
