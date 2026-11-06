class_name LiveWeatherBar
extends VBoxContainer
## The Live weather switch on the Weather step: source line, METAR, refresh, and "Use as base".
## The first time it is turned on, a panel on the menu says what is sent. Lessons never reach this with the
## switch on (Session.begin_lesson clears it).


const SEEN := "user://live_weather_notice"

var seen_path := SEEN  # tests point this at a scratch file

signal changed

var _live: CheckButton
var _update: CheckButton
var _status: Label
var _metar: Label
var _refresh: Button
var _base: Button
var _src: LiveSources
var _busy := false
var _armed := false
var _spin := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_live = CheckButton.new()
	_live.text = "Live weather"
	_live.toggled.connect(_on_live)
	add_child(_live)
	_update = CheckButton.new()
	_update.text = "Update during flight"
	_update.toggled.connect(func(on):
		Session.setup.live_update = on
		changed.emit())
	add_child(_update)
	_status = MenuTheme.note("")
	add_child(_status)
	_metar = MenuTheme.note("")
	_metar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_metar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_refresh = Button.new()
	_refresh.text = "Refresh"
	_refresh.pressed.connect(_fetch)
	row.add_child(_refresh)
	_base = Button.new()
	_base.text = "Use as base"
	_base.pressed.connect(_as_base)
	row.add_child(_base)
	_src = LiveSources.new()
	add_child(_src)
	_src.finished.connect(_on_result)


func sync() -> void:
	var on := bool(Session.setup.get("live_weather", false))
	_live.set_pressed_no_signal(on)
	_update.set_pressed_no_signal(bool(Session.setup.get("live_update", false)))
	_lock(_update, not on)
	_lock(_refresh, not on or _busy)
	_lock(_base, not on)
	if on and not _armed and not _busy:
		_armed = true
		_fetch()


func _on_live(on: bool) -> void:
	if on and not FileAccess.file_exists(seen_path):
		_ask()
		return
	Session.setup.live_weather = on
	if not on:
		Session.setup.live_pack = {}
		_status.text = ""
		_metar.text = ""
		_busy = false
	else:
		_armed = true
		_fetch()
	changed.emit()


func _ask() -> void:
	var host := _screen()
	if host.get_node_or_null("LiveWeatherNotice") != null:
		return
	var d := LiveWeatherNotice.new()
	host.add_child(d)
	d.accepted.connect(func():
		var f := FileAccess.open(seen_path, FileAccess.WRITE)
		if f:
			f.store_string("ok")
		Session.setup.live_weather = true
		_fetch()
		d.queue_free())
	d.declined.connect(func():
		_live.set_pressed_no_signal(false)
		Session.setup.live_weather = false
		changed.emit()
		d.queue_free())


## The start screen, so the panel covers the menu in UI units. A window dialog would ignore the UI scale.
func _screen() -> Node:
	var n: Node = self
	while n != null:
		if n.has_method("modal_open"):
			return n
		n = n.get_parent()
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return self


func _process(dt: float) -> void:
	if not _busy:
		return
	_spin += dt * 3.0
	var dots := ".".repeat(1 + int(_spin) % 3)
	_status.text = "Reading the weather" + dots


func _fetch() -> void:
	if not bool(Session.setup.get("live_weather", false)):
		return
	_busy = true
	_spin = 0.0
	_status.text = "Reading the weather."
	_lock(_refresh, true)
	var place := LivePlace.of(str(Session.setup.get("airport", "VAJJ")))
	var rs := DayMath.sun_times(float(Session.setup.get("day_of_year", 45.0)))
	var h := float(Session.setup.get("time_h", 10.0))
	var preset := str(Session.setup.get("weather", "Fair"))
	if preset == "Live":
		preset = "Fair"
	_src.start(place, float(Session.setup.get("wind_dir_deg", 270.0)), h > rs.x and h < rs.y, preset)


func _on_result(r: Dictionary) -> void:
	_busy = false
	_status.text = str(r.get("status", ""))
	var weather: Dictionary = r.get("weather", {})
	if not weather.is_empty() and str(r.get("tier", "")) != "preset":
		LiveApply.into_setup(Session.setup, weather)
		_metar.text = str(weather.get("live_metar", ""))
	elif str(r.get("tier", "")) == "preset":
		Session.setup.live_pack = {}
		_metar.text = ""
	changed.emit()


func _lock(b: BaseButton, off: bool) -> void:
	b.disabled = off
	b.focus_mode = Control.FOCUS_NONE if off else Control.FOCUS_ALL


func _as_base() -> void:
	Session.setup.live_weather = false
	Session.setup.live_pack = {}
	_status.text = "Copied into the sliders."
	_metar.text = ""
	_busy = false
	changed.emit()
