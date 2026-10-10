extends HBoxContainer
## Start screen page 2: aircraft (every res://aircraft/<id>/aircraft.json is listed),
## its specifications, and fuel / payload with the resulting weight against MTOW.

signal changed

const KG_PER_GAL := 2.72  # avgas, 6.0 lb/US gal

var _list: ItemList
var _name: Label
var _cat: Label
var _desc: Label
var _specs: GridContainer
var _credit: Label
var _weight: Label
var _ac := {}
var _sliders := {}


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(200, 0)
	add_child(left)
	left.add_child(MenuTheme.heading("Aircraft"))
	_list = ItemList.new()
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(_list)
	left.add_child(MenuTheme.note("More aircraft are planned. Aircraft behaviour is data (aircraft/<id>/*.json), so new types can be added without code."))
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	add_child(mid)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 28)
	mid.add_child(_name)
	_cat = MenuTheme.note("")
	mid.add_child(_cat)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(_desc)
	mid.add_child(MenuTheme.heading("Specifications"))
	_specs = GridContainer.new()
	_specs.columns = 2
	_specs.add_theme_constant_override("h_separation", 16)
	mid.add_child(_specs)
	_credit = MenuTheme.note("")
	mid.add_child(_credit)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	right.add_theme_constant_override("separation", 6)
	add_child(right)
	right.add_child(MenuTheme.heading("Fuel & payload"))
	_slider(right, "Fuel per tank", "fuel_gal", 3.0, 28.0, 1.0, "gal")
	_slider(right, "Front passenger", "copilot_kg", 0.0, 120.0, 5.0, "kg")
	_slider(right, "Rear passengers (total)", "rear_kg", 0.0, 220.0, 5.0, "kg")
	_slider(right, "Baggage", "baggage_kg", 0.0, 54.0, 2.0, "kg")
	_weight = Label.new()
	_weight.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_weight)
	right.add_child(MenuTheme.note("Pilot 82 kg is included. Over-weight is allowed but you will feel it: longer takeoff roll, slower climb, higher stall speed."))
	var dir := DirAccess.open("res://aircraft")
	if dir:
		for d in dir.get_directories():
			var f := "res://aircraft/%s/aircraft.json" % d
			if FileAccess.file_exists(f):
				var j = JSON.parse_string(FileAccess.get_file_as_string(f))
				if j is Dictionary:
					var i := _list.add_item(j.name)
					_list.set_item_metadata(i, j)
					if j.id == Session.setup.aircraft:
						_list.select(i)
						_show(j)
	_list.item_selected.connect(func(i):
		Session.setup.aircraft = _list.get_item_metadata(i).id
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
	sl.value = float(Session.setup[key])
	v.text = "%.0f %s" % [sl.value, unit]
	sl.value_changed.connect(func(x):
		Session.setup[key] = x
		v.text = "%.0f %s" % [x, unit]
		_update_weight())
	parent.add_child(sl)
	_sliders[key] = sl


func _show(j: Dictionary) -> void:
	_ac = j
	_name.text = j.name
	_cat.text = j.get("category", "")
	_desc.text = j.get("description", "")
	_credit.text = j.get("model_credit", "")
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
	var fuel := 2.0 * float(s.fuel_gal) * KG_PER_GAL
	var w: float = float(_ac.empty_kg) + float(_ac.pilot_kg) + float(s.copilot_kg) + float(s.rear_kg) + float(s.baggage_kg) + fuel
	var over := w > float(_ac.mtow_kg)
	_weight.text = "Takeoff weight %d kg (%d lb) of %d kg max%s\nFuel %d gal ≈ %.1f h at 75 %% power" % [
		int(w), int(w / 0.4536), int(_ac.mtow_kg), "  — OVER MTOW" if over else "",
		int(2.0 * float(s.fuel_gal)), maxf(2.0 * float(s.fuel_gal) - 3.0, 0.0) / 9.0]
	_weight.add_theme_color_override("font_color", Color(1, 0.4, 0.3) if over else MenuTheme.TEXT)
	changed.emit()
