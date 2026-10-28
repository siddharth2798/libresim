extends HBoxContainer
## Start screen page 2: aircraft (every res://aircraft/<id>/aircraft.json is listed),
## its specifications, and fuel / payload with the resulting weight against MTOW.

signal changed

var _list: ItemList
var _name: Label
var _cat: Label
var _desc: Label
var _specs: GridContainer
var _credit: Label
var _weight: Label
const LOADING_NOTE := "Over-weight or out-of-CG loading is allowed but you will feel it: longer takeoff roll, slower climb, higher stall speed; an aft CG makes pitch light and unstable."
var _chart: Control
var _note: Label  # the loading note under the aircraft list (names the pilot weight)
var _cfg := {}
var _ac := {}
var _sliders := {}
var _fuel_box: VBoxContainer  # the fuel and payload sliders (rebuilt for each aircraft)


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	add_child(left)
	left.add_child(MenuTheme.heading("Aircraft"))
	_list = ItemList.new()
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(_list)
	left.add_child(MenuTheme.note("More aircraft are planned; aircraft are data (aircraft/<id>/*.json)."))
	_note = MenuTheme.note("")
	left.add_child(_note)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	add_child(mid)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 28)
	mid.add_child(_name)
	_cat = MenuTheme.note("")
	mid.add_child(_cat)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 15)
	mid.add_child(_desc)
	mid.add_child(MenuTheme.heading("Specifications"))
	_specs = GridContainer.new()
	_specs.columns = 2
	_specs.add_theme_constant_override("h_separation", 16)
	_specs.add_theme_constant_override("v_separation", 1)
	mid.add_child(_specs)
	_credit = MenuTheme.note("")
	mid.add_child(_credit)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	right.add_theme_constant_override("separation", 6)
	add_child(right)
	right.add_child(MenuTheme.heading("Fuel & payload"))
	_fuel_box = VBoxContainer.new()
	_fuel_box.add_theme_constant_override("separation", 6)
	right.add_child(_fuel_box)
	_weight = Label.new()
	_weight.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weight.add_theme_font_size_override("font_size", 14)
	right.add_child(_weight)
	_chart = Control.new()
	_chart.set_script(load("res://ui/menu/wb_chart.gd"))
	_chart.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(_chart)
	for id in AircraftDef.list_ids():
		var j: Dictionary = AircraftDef.load_def(id).data
		var i := _list.add_item(j.get("name", id))
		_list.set_item_metadata(i, j)
		if j.get("id", id) == Session.setup.aircraft:
			_list.select(i)
			_show(j)
	_list.item_selected.connect(func(i):
		Session.setup.aircraft = _list.get_item_metadata(i).id
		Session.apply_payload_defaults(AircraftDef.load_def(Session.setup.aircraft))  # fuel and loads suit the new aircraft
		_show(_list.get_item_metadata(i)))
	if _ac.is_empty() and _list.item_count > 0:
		_list.select(0)
		_show(_list.get_item_metadata(0))


func _slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, unit: String) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	hb.add_child(l)
	var v := Label.new()
	hb.add_child(v)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(Session.setup.get(key, 0.0))
	v.text = "%.0f %s" % [sl.value, unit]
	sl.value_changed.connect(func(x):
		Session.setup[key] = x
		v.text = "%.0f %s" % [x, unit]
		_update_weight())
	parent.add_child(sl)
	_sliders[key] = sl


## The fuel and payload sliders of this aircraft (aircraft.json "payload": fuel_slider and stations).
func _build_sliders(pl: Dictionary) -> void:
	for c in _fuel_box.get_children():
		_fuel_box.remove_child(c)
		c.queue_free()
	_sliders.clear()
	var f: Dictionary = pl.get("fuel_slider", {"min": 0.0, "max": 20.0, "step": 1.0, "unit": "gal"})
	var in_kg := WeightBalance.fuel_in_kg({"payload": pl})  # total fuel in kg (the A320) instead of gal per tank
	_slider(_fuel_box, "Fuel (total)" if in_kg else "Fuel per tank", "fuel_gal", f.min, f.max, f.step, f.get("unit", "gal"))
	for st in pl.get("stations", []):
		_slider(_fuel_box, st.label, st.key, 0.0, st.max, st.step, "kg")


func _show(j: Dictionary) -> void:
	_ac = j
	_build_sliders(j.get("payload", {}))
	_cfg = WeightBalance.load_config(j)
	_name.text = j.name
	_cat.text = j.get("category", "")
	_desc.text = j.get("description", "")
	_credit.text = j.get("model_credit", "")
	var pilot := float(j.get("pilot_kg", 82.0))
	_note.text = ("Pilot %d kg is included. " % int(pilot) if pilot > 0.0 else "The crew is included in the empty weight. ") + LOADING_NOTE
	for c in _specs.get_children():
		c.queue_free()
	for s in j.get("specs", []):
		var a := Label.new()
		a.text = s[0]
		a.add_theme_color_override("font_color", MenuTheme.DIM)
		_specs.add_child(a)
		var b := Label.new()
		b.text = s[1]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(120, 0)
		_specs.add_child(b)
	_update_weight()


func _update_weight() -> void:
	if _ac.is_empty():
		return
	var s: Dictionary = Session.setup
	var pl: Dictionary = _ac.get("payload", {})
	var tanks := maxi((_cfg.get("tanks", []) as Array).size(), 1)
	var in_kg := WeightBalance.fuel_in_kg(_ac)
	var gal := float(s.fuel_gal) if in_kg else float(tanks) * float(s.fuel_gal)  # total fuel, all tanks (kg for the A320)
	var w: float = float(_ac.empty_kg) + float(_ac.pilot_kg) + (gal if in_kg else gal * WeightBalance.kg_per_gal(_ac))
	for st in pl.get("stations", []):
		w += float(s.get(st.key, 0.0))
	var over := w > float(_ac.mtow_kg)
	var txt := "Weight %d kg (%d lb), max %d\n" % [int(w), int(w / 0.4536), int(_ac.mtow_kg)]
	if in_kg:
		txt += "Fuel %d kg ≈ %.1f h at cruise" % [int(gal), maxf(gal - float(pl.get("reserve_kg", 1800.0)), 0.0) / float(pl.get("cruise_kgh", 2500.0))]
	else:
		txt += "Fuel %d gal ≈ %.1f h at 75 %% power" % [int(gal), maxf(gal - float(pl.get("reserve_gal", 3.0)), 0.0) / float(pl.get("cruise_gph", 9.0))]
	var wb := WeightBalance.compute(_ac, s, _cfg)
	var bad := over
	if not wb.is_empty():
		bad = bad or not wb.ok
		var cgu := str(_ac.cg_envelope.get("cg_unit", "in"))
		txt += "\nCG %.1f %s T/O, %.1f %s LDG" % [wb.takeoff.cg_in, cgu, wb.landing.cg_in, cgu]
	var issues := []
	if over:
		issues.append("OVER MTOW")
	if not wb.is_empty() and not wb.ok:
		issues.append("CG OUT OF LIMITS")
	if not issues.is_empty():
		txt += "\n" + ", ".join(issues)
	if not wb.is_empty():
		_chart.set_data(_ac.cg_envelope, wb)
	_chart.visible = not wb.is_empty()
	_weight.text = txt
	_weight.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if bad else MenuTheme.TEXT)
	changed.emit()
