extends HBoxContainer
## Start screen page 1: aircraft chips (every res://aircraft/<id>/aircraft.json is listed), the chosen
## one as a big picture with its key figures, the registration (call sign, CallsignField) and a "Full
## specification" overlay (AircraftDetails: description, every spec row, credit); on the right fuel / payload,
## the weight against MTOW with a badge and, when SetupChecks finds a problem with the loading, its message,
## and the W&B chart.

signal changed

const LOADING_NOTE := "Over-weight or out-of-CG loading is allowed but you will feel it: longer takeoff roll, slower climb, higher stall speed; an aft CG makes pitch light and unstable."
const KEY_SPECS := 3  # specification rows always shown, as tiles (all of them are in the overlay)
const NO_RUNWAY := {"ident": "-", "length_m": 100000.0, "heading_deg": 0.0}  # SetupChecks needs a runway to look at; only the aircraft step's items are used here

var _chips := {}  # aircraft id -> AircraftChip
var _group := ButtonGroup.new()
var _hero: AircraftHero
var _specs: HBoxContainer  # the key figures, one tile each
var _details: AircraftDetails  # the "Full specification" overlay
var _details_btn: Button
var callsign: CallsignField  # the registration / call sign (core/callsign.gd)
var _credit: Label
var _weight: Label
var _badge: Label  # Within limits | Over MTOW | CG out of limits
var _bar: ProgressBar
var _issue: Label  # SetupChecks texts for this step, empty when the loading is fine
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
	var picker := GridContainer.new()  # two chips per row, each as wide as the column allows
	picker.columns = 2
	picker.add_theme_constant_override("h_separation", 10)
	picker.add_theme_constant_override("v_separation", 10)
	left.add_child(picker)
	_hero = AircraftHero.new()
	left.add_child(_hero)
	_specs = HBoxContainer.new()
	_specs.add_theme_constant_override("separation", 10)
	left.add_child(_specs)
	var reg := HBoxContainer.new()  # the full specification, and the registration (call sign) beside it
	reg.add_theme_constant_override("separation", 18)
	left.add_child(reg)
	_details_btn = Button.new()
	_details_btn.text = "▶  Full specification"
	_details_btn.size_flags_vertical = SIZE_SHRINK_BEGIN
	_details_btn.tooltip_text = "The description and every specification row of this aircraft"
	_details_btn.pressed.connect(_show_details.bind(true))
	reg.add_child(_details_btn)
	callsign = CallsignField.new().setup("Registration")
	callsign.size_flags_horizontal = SIZE_EXPAND_FILL  # the hint line gets the rest of the row
	reg.add_child(callsign)
	callsign.callsign_changed.connect(func(_v): changed.emit())
	_details = AircraftDetails.new()
	_details.closed.connect(func(): _details_btn.grab_focus())
	add_child(_details)  # top level: covers the window, takes no room in this row
	var gap := Control.new()  # pushes the credit to the bottom of the column
	gap.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(gap)
	_credit = MenuTheme.note("")
	_credit.add_theme_font_size_override("font_size", 12)
	_credit.max_lines_visible = 2  # the whole credit is in the tooltip, in the specification overlay and on the Credits screen
	_credit.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_credit.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(_credit)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	var head := HBoxContainer.new()
	right.add_child(head)
	var h := MenuTheme.heading("Fuel & payload")
	h.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(h)
	_badge = Label.new()
	_badge.add_theme_font_size_override("font_size", 12)
	head.add_child(_badge)
	_fuel_box = VBoxContainer.new()
	_fuel_box.add_theme_constant_override("separation", 6)
	right.add_child(_fuel_box)
	_weight = Label.new()
	_weight.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weight.add_theme_font_size_override("font_size", 14)
	right.add_child(_weight)
	_bar = ProgressBar.new()  # takeoff weight against MTOW: the fill goes amber near it and red over it
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.add_theme_stylebox_override("background", MenuTheme.box(Color(1, 1, 1, 0.10), 4, Color(0, 0, 0, 0), 0.0))
	right.add_child(_bar)
	_issue = Label.new()  # what SetupChecks says is wrong with the loading (the same texts as the rail dot and the Fly dialog)
	_issue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_issue.add_theme_font_size_override("font_size", 14)
	_issue.add_theme_color_override("font_color", MenuTheme.BAD)
	right.add_child(_issue)
	_chart = Control.new()
	_chart.set_script(load("res://ui/menu/wb_chart.gd"))
	_chart.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(_chart)
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
	callsign.refresh()  # an untouched call sign follows the aircraft (placeholder, hint)


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
	b.max_lines_visible = 2  # a long figure is cut here; the whole text is in the tooltip and in the specification overlay
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(110, 0)
	b.add_theme_font_size_override("font_size", 15)
	t.tooltip_text = "%s: %s" % [label, value]
	v.add_child(b)
	return t


## Open or close the "Full specification" overlay.
func _show_details(open: bool) -> void:
	if open:
		_details.open()
	else:
		_details.close()


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
	_details.show_aircraft(j)
	_credit.text = j.get("model_credit", "")
	_credit.tooltip_text = _credit.text
	var pilot := float(j.get("pilot_kg", 82.0))
	_weight.tooltip_text = ("Pilot %d kg is included. " % int(pilot) if pilot > 0.0 else "The crew is included in the empty weight. ") + LOADING_NOTE
	_weight.mouse_filter = Control.MOUSE_FILTER_PASS
	for c in _specs.get_children():
		_specs.remove_child(c)
		c.queue_free()
	for sp in (j.get("specs", []) as Array).slice(0, KEY_SPECS):
		_specs.add_child(_tile(sp[0], sp[1]))
	_update_weight()


func _update_weight() -> void:
	if _ac.is_empty():
		return
	var s: Dictionary = Session.setup
	var pl: Dictionary = _ac.get("payload", {})
	var in_kg := WeightBalance.fuel_in_kg(_ac)
	var gal := WeightBalance.fuel_total(_ac, s, _cfg)  # total fuel, all tanks (kg for the A320)
	var w := WeightBalance.takeoff_kg(_ac, s, _cfg)
	var txt := "Weight %d kg (%d lb), max %d\n" % [int(w), int(w / 0.4536), int(_ac.mtow_kg)]
	if in_kg:
		txt += "Fuel %d kg ≈ %.1f h at cruise" % [int(gal), maxf(gal - float(pl.get("reserve_kg", 1800.0)), 0.0) / float(pl.get("cruise_kgh", 2500.0))]
	else:
		txt += "Fuel %d gal ≈ %.1f h at 75 %% power" % [int(gal), maxf(gal - float(pl.get("reserve_gal", 3.0)), 0.0) / float(pl.get("cruise_gph", 9.0))]
	var wb := WeightBalance.compute(_ac, s, _cfg)
	if not wb.is_empty():
		var cgu := str(_ac.cg_envelope.get("cg_unit", "in"))
		txt += "\nCG %.1f %s T/O, %.1f %s LDG" % [wb.takeoff.cg_in, cgu, wb.landing.cg_in, cgu]
		_chart.set_data(_ac.cg_envelope, wb)
	_chart.visible = not wb.is_empty()
	_weight.text = txt
	_show_status(w)
	changed.emit()


## Badge, bar and the message: what SetupChecks reports for this step (the rail dot and the Fly dialog say the same).
func _show_status(w: float) -> void:
	var items := SetupChecks.checks(Session.setup, NO_RUNWAY).filter(func(c): return c.step == "aircraft")
	var mtow := float(_ac.mtow_kg)
	var tone := MenuTheme.OK
	var label := "Within limits"
	if not items.is_empty():
		tone = MenuTheme.BAD
		label = "Over MTOW" if items.any(func(c): return c.id == "over_weight") else "CG out of limits"
	elif w > mtow * 0.92:
		tone = MenuTheme.WARN
	_badge.text = ("▲ " if not items.is_empty() else "● ") + label.to_upper()
	_badge.add_theme_color_override("font_color", tone)
	_bar.max_value = mtow
	_bar.value = minf(w, mtow)
	_bar.add_theme_stylebox_override("fill", MenuTheme.box(tone, 4, Color(0, 0, 0, 0), 0.0))
	_issue.visible = not items.is_empty()
	_issue.text = ""
	if not items.is_empty():
		_issue.text = "▲ " + ". ".join(items.map(func(c): return c.text)) + ". Allowed, but you will feel it: longer takeoff roll, slower climb, higher stall speed."
