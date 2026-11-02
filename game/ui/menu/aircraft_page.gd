extends HBoxContainer
## Start screen page 1: aircraft chips (every res://aircraft/<id>/aircraft.json is listed), the chosen
## one as a big picture with its key figures (the full specification, description and credit are under
## "Details"), and fuel / payload with the resulting weight against MTOW and the W&B chart.

signal changed

const LOADING_NOTE := "Over-weight or out-of-CG loading is allowed but you will feel it: longer takeoff roll, slower climb, higher stall speed; an aft CG makes pitch light and unstable."
const KEY_SPECS := 3  # specification rows always shown, as tiles (the rest sit under Details)

static var _details_open := false  # "Details" stays open or closed for the session

var _chips := {}  # aircraft id -> AircraftChip
var _group := ButtonGroup.new()
var _hero: AircraftHero
var _specs: HBoxContainer  # the key figures, one tile each
var _more_specs: GridContainer  # the remaining ones, under Details
var _desc: Label
var _details: Control
var _details_btn: Button
var _credit: Label
var _weight: Label
var _chart: Control
var _cfg := {}
var _ac := {}
var _sliders := {}
var _fuel_box: VBoxContainer  # the fuel and payload sliders (rebuilt for each aircraft)


func _ready() -> void:
	add_theme_constant_override("separation", 22)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	var picker := HFlowContainer.new()
	picker.add_theme_constant_override("h_separation", 10)
	picker.add_theme_constant_override("v_separation", 10)
	left.add_child(picker)
	_hero = AircraftHero.new()
	left.add_child(_hero)
	_specs = HBoxContainer.new()
	_specs.add_theme_constant_override("separation", 10)
	left.add_child(_specs)
	_details_btn = Button.new()
	_details_btn.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_details_btn.pressed.connect(func(): _show_details(not _details_open))
	left.add_child(_details_btn)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 8)
	left.add_child(_details)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 15)
	_details.add_child(_desc)
	_more_specs = GridContainer.new()
	_more_specs.columns = 2
	_more_specs.add_theme_constant_override("h_separation", 16)
	_more_specs.add_theme_constant_override("v_separation", 2)
	_details.add_child(_more_specs)
	var gap := Control.new()  # pushes the credit to the bottom of the column
	gap.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(gap)
	_credit = MenuTheme.note("")
	_credit.add_theme_font_size_override("font_size", 12)
	left.add_child(_credit)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 8)
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
	_show_details(_details_open)
	for id in AircraftDef.list_ids():
		var j: Dictionary = AircraftDef.load_def(id).data
		var chip := AircraftChip.new().setup(j, _group)
		chip.pressed.connect(_choose.bind(j))
		picker.add_child(chip)
		_chips[id] = chip
		if j.get("id", id) == Session.setup.aircraft:
			chip.set_pressed_no_signal(true)
			_show(j)
	if _ac.is_empty() and not _chips.is_empty():  # the remembered aircraft is gone: the first one is the choice
		choose_id(_chips.keys()[0])


## The id of the lit chip ("" if there is none).
func selected_id() -> String:
	return str(_ac.get("id", ""))


## Choose this aircraft as a click on its chip would.
func choose_id(id: String) -> bool:
	if not _chips.has(id):
		return false
	_chips[id].set_pressed_no_signal(true)
	_choose(AircraftDef.load_def(id).data)
	return true


## An aircraft is chosen (this is step 1: the airport page that follows reads it).
func _choose(j: Dictionary) -> void:
	Session.setup.aircraft = j.id
	Session.apply_payload_defaults(AircraftDef.load_def(Session.setup.aircraft))  # fuel and loads suit the new aircraft
	Session.apply_air_defaults()  # and the airborne start (height, distance, speed) unless the pilot set it
	_show(j)


## One key figure: a small dim label over the value.
func _tile(label: String, value: String) -> Control:
	var t := PanelContainer.new()
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	t.add_theme_stylebox_override("panel", MenuTheme.box(Color(1, 1, 1, 0.05), 10, Color(1, 1, 1, 0.08), 10.0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	t.add_child(v)
	var a := Label.new()
	a.text = label.to_upper()
	a.add_theme_font_size_override("font_size", 12)
	a.add_theme_color_override("font_color", MenuTheme.ACCENT)
	v.add_child(a)
	var b := Label.new()
	b.text = value
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(120, 0)
	b.add_theme_font_size_override("font_size", 15)
	v.add_child(b)
	return t


func _show_details(open: bool) -> void:
	_details_open = open
	_details.visible = open
	_details_btn.text = "▼  Hide details" if open else "▶  Details: description and full specification"


func _slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, unit: String) -> void:
	var row := SliderRow.new().setup(label, lo, hi, step, label if label.length() > 26 else "", 215.0, 72.0)
	var sl := row.slider
	sl.value = float(Session.setup.get(key, 0.0))
	row.value_label.text = "%.0f %s" % [sl.value, unit]
	sl.value_changed.connect(func(x):
		Session.setup[key] = x
		row.value_label.text = "%.0f %s" % [x, unit]
		_update_weight())
	parent.add_child(row)
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
	_hero.show_aircraft(j)
	_desc.text = j.get("description", "")
	_credit.text = j.get("model_credit", "")
	var pilot := float(j.get("pilot_kg", 82.0))
	_weight.tooltip_text = ("Pilot %d kg is included. " % int(pilot) if pilot > 0.0 else "The crew is included in the empty weight. ") + LOADING_NOTE
	_weight.mouse_filter = Control.MOUSE_FILTER_PASS
	for g in [_specs, _more_specs]:
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
	var n := 0
	for sp in j.get("specs", []):
		n += 1
		if n <= KEY_SPECS:
			_specs.add_child(_tile(sp[0], sp[1]))
			continue
		var a := Label.new()
		a.text = sp[0]
		a.add_theme_color_override("font_color", MenuTheme.DIM)
		_more_specs.add_child(a)
		var b := Label.new()
		b.text = sp[1]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(120, 0)
		_more_specs.add_child(b)
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
