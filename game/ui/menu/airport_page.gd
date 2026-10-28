extends HBoxContainer
## Start screen page 1: airport list (searchable), diagram, and where to start:
## on a runway, parked at a stand / gate, or in the air on final to a runway.

signal changed

var _airports: Array = []  # [{icao, name, elev_m, runways, stands, taxiways}]
var _list: ItemList
var _search: LineEdit
var _diagram: Control
var _info: Label
var _mode_btns := {}
var _rwy: OptionButton
var _stand: OptionButton
var _air_box: Control
var _alt: SpinBox
var _dist: SpinBox
var _cold: CheckBox
var _stand_note: Label
var _cur := {}


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_load()
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	add_child(left)
	left.add_child(MenuTheme.heading("Airport"))
	_search = LineEdit.new()
	_search.placeholder_text = "Search ICAO or name…"
	_search.text_changed.connect(func(_t): _fill_list())
	left.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i): _select(_list.get_item_metadata(i)))
	left.add_child(_list)
	_diagram = Control.new()
	_diagram.set_script(load("res://ui/menu/airport_diagram.gd"))
	_diagram.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(_diagram)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(290, 0)
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)
	right.add_child(MenuTheme.heading("Start at"))
	var modes := HBoxContainer.new()
	right.add_child(modes)
	var g := ButtonGroup.new()
	for m in [["runway", "Runway"], ["stand", "Stand / gate"], ["air", "In the air"]]:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.button_group = g
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(func(): _put("start", m[0]))
		modes.add_child(b)
		_mode_btns[m[0]] = b
	right.add_child(_lbl("Runway (or the one to land on)"))
	_rwy = OptionButton.new()
	_rwy.item_selected.connect(func(i): _put("runway", _rwy.get_item_metadata(i)))
	right.add_child(_rwy)
	_stand = OptionButton.new()
	_stand.item_selected.connect(func(i): _put("stand", _stand.get_item_metadata(i)))
	right.add_child(_stand)
	_air_box = GridContainer.new()
	_air_box.columns = 2
	right.add_child(_air_box)
	_alt = _spin("Height above field (ft)", 300, 12000, 100, "air_ft")
	_dist = _spin("Distance out on final (nm)", 1, 25, 0.5, "air_nm")
	_cold = CheckBox.new()
	_cold.text = "Cold & dark (engine off, everything off — run the checklists)"
	_cold.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cold.toggled.connect(func(on): _put("cold", on))
	right.add_child(_cold)
	_stand_note = MenuTheme.note("Stand starts are always cold & dark with the parking brake set: run the checklists.")
	right.add_child(_stand_note)
	right.add_child(MenuTheme.note("Stands come from OpenStreetMap: gates with jetbridges at the big airports, remote bays and GA parking. On the ground: T taxi route + follow-me car, P pushback, ` radio."))
	_fill_list()
	var s: Dictionary = Session.setup
	_mode_btns[s.start].button_pressed = true
	_alt.set_value_no_signal(float(s.air_ft))
	_dist.set_value_no_signal(float(s.air_nm))
	_cold.set_pressed_no_signal(bool(s.cold))
	for a in _airports:
		if a.icao == s.airport:
			_select(a, false)


func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", MenuTheme.DIM)
	return l


func _spin(label: String, lo: float, hi: float, step: float, key: String) -> SpinBox:
	_air_box.add_child(_lbl(label))
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value_changed.connect(func(v): _put(key, v))
	_air_box.add_child(sb)
	return sb


func _load() -> void:
	var apts = Paths.load_json("airports.json")
	var rw = Paths.load_json("runways.json")
	var ops = Paths.load_json("airport_ops.json")
	if apts == null or rw == null:
		return
	ops = ops if ops else {}
	for a in apts:
		var code: String = a.icao if str(a.icao) != "" else a.ident
		var rws: Array = rw.runways.filter(func(r): return r.airport == code)
		if rws.is_empty() or a.type == "heliport":
			continue
		rws.sort_custom(func(x, y): return x.length > y.length)
		var box := Rect2(Vector2(rws[0].ends[0].x, rws[0].ends[0].y), Vector2.ZERO)
		for r in rws:
			for e in r.ends:
				box = box.expand(Vector2(e.x, e.y))
		box = box.grow(2500.0)
		var tws := []
		for t in rw.taxiways:
			if box.has_point(Vector2(t.pts[0][0], t.pts[0][1])):
				tws.append(t.pts.map(func(p): return Vector2(p[0], p[1])))
		_airports.append({"icao": code, "name": a.name, "elev_m": float(a.elev_m), "runways": rws,
			"stands": ops.get(code, {}).get("stands", []), "taxiways": tws, "type": a.type})
	_airports.sort_custom(func(x, y): return x.type < y.type if x.type != y.type else x.icao < y.icao)


func _fill_list() -> void:
	_list.clear()
	var q := _search.text.strip_edges().to_lower()
	for a in _airports:
		if q != "" and not (q in a.icao.to_lower() or q in str(a.name).to_lower()):
			continue
		var i := _list.add_item("%s   %s" % [a.icao, a.name])
		_list.set_item_metadata(i, a)
		if not _cur.is_empty() and a.icao == _cur.icao:
			_list.select(i)


func _select(a: Dictionary, user := true) -> void:
	_cur = a
	var s: Dictionary = Session.setup
	if user:
		s.airport = a.icao
		s.runway = ""
		s.stand = ""
	_fill_list()
	var rl := []
	for r in a.runways:
		rl.append("%s/%s  %d m" % [r.ends[0].ident, r.ends[1].ident, int(r.length)])
	_info.text = "%s\n%s\nElevation %d ft · %d stands\n%s" % [a.icao, a.name, int(Units.m_to_ft(a.elev_m)), a.stands.size(), "\n".join(rl)]
	_rwy.clear()
	var def := AircraftDef.load_def(str(s.get("aircraft", AircraftDef.DEFAULT_ID)))
	var gp := GroundParams.ground(def)
	var min_len := float(gp.min_runway_m)
	var first_ok := -1  # default pick: the first runway long enough for the aircraft
	for r in a.runways:
		for e in r.ends:
			var short := " — too short for this aircraft" if float(r.length) < min_len else ""
			_rwy.add_item("Runway %s  (%d m)%s" % [e.ident, int(r.length), short])
			_rwy.set_item_metadata(_rwy.item_count - 1, e.ident)
			if first_ok < 0 and short == "":
				first_ok = _rwy.item_count - 1
			if e.ident == s.runway:
				_rwy.select(_rwy.item_count - 1)
	if s.runway == "" and _rwy.item_count > 0:
		var pick := maxi(first_ok, 0)
		_rwy.select(pick)
		s.runway = _rwy.get_item_metadata(pick)
	_stand.clear()
	# an airliner is offered gates and remote bays (not GA tie-downs), a light aircraft the other way round;
	# "any" (the C172) keeps every stand in the data order
	var cls := str(gp.stand_class)
	for st in GroundChoice.offered(a.stands, cls):
		_stand.add_item("%s  (%s)" % [st.ref, "jetbridge gate" if st.jetbridge else str(st.kind)])
		_stand.set_item_metadata(_stand.item_count - 1, st.ref)
		if st.ref == s.stand:
			_stand.select(_stand.item_count - 1)
	if _stand.item_count > 0 and (s.stand == "" or _stand.get_selected_metadata() != s.stand):
		_stand.select(0)  # none yet, or the remembered one is not on offer for this aircraft
		s.stand = _stand.get_item_metadata(0)
	_diagram.show_airport(a.runways, a.taxiways, a.stands)
	_refresh()


func _put(key: String, v: Variant) -> void:
	Session.setup[key] = v
	_refresh()


func _refresh() -> void:
	var s: Dictionary = Session.setup
	if s.start == "stand" and _cur.get("stands", []).is_empty():
		s.start = "runway"
		_mode_btns.runway.button_pressed = true
	_mode_btns.stand.disabled = _cur.get("stands", []).is_empty()
	_stand.visible = s.start == "stand"
	_air_box.visible = s.start == "air"
	# Cold & dark is only a choice on a runway: stands are always cold & dark (a note says so)
	# and air starts never are. The control is removed, not greyed, and an air start never
	# keeps a stale value.
	_cold.visible = s.start == "runway"
	_stand_note.visible = s.start == "stand"
	if s.start == "air":
		s.cold = false
	_cold.set_pressed_no_signal(bool(s.cold))
	_diagram.start = {}
	for r in _cur.get("runways", []):
		for e in r.ends:
			if e.ident == s.runway:
				var h := deg_to_rad(float(e.heading_true))
				var f := Vector2(sin(h), cos(h))
				var p := Vector2(e.x, e.y) + f * (25.0 if s.start != "air" else -float(s.air_nm) * 1852.0)
				_diagram.set_start(p, float(e.heading_true))
	if s.start == "stand":
		for st in _cur.stands:
			if st.ref == s.stand:
				_diagram.set_start(Vector2(st.x, st.y), float(st.heading_deg))
	changed.emit()
