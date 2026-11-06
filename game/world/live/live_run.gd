class_name LiveRun
extends Node
## In the flight: one fetch at start when the menu did not already fetch, then a blend.
## A new fetch every 15 minutes only when "Update during flight" is on. A loaded save
## stops this node from writing, so the saved weather stays.


const PERIOD := 900.0

var _src: LiveSources
var _origin := {}
var _target := {}
var _elapsed := 0.0
var _blending := false
var _next := -1.0
var _gen := 0


static func wanted() -> bool:
	return bool(Session.setup.get("live_weather", false)) and str(Session.training) == "" and Situation.pending_load == ""


func _ready() -> void:
	if not wanted():
		return
	_gen = int(Props.get_v("meta/situation", 0))
	_src = LiveSources.new()
	add_child(_src)
	_src.finished.connect(_on_fetch)
	_next = PERIOD if bool(Session.setup.get("live_update", false)) else -1.0
	if (Session.setup.get("live_pack", {}) as Dictionary).is_empty():
		_fetch()


func _process(dt: float) -> void:
	var gen := int(Props.get_v("meta/situation", 0))
	if gen != _gen:
		_gen = gen
		_blending = false
		_next = -1.0
		return
	if _blending:
		_elapsed += dt
		var now := LiveBlend.at(_origin, _target, _elapsed)
		LiveBlend.write_props(now)
		if LiveBlend.arrived(now, _target):
			_blending = false
	if _next < 0.0:
		return
	_next -= dt
	if _next <= 0.0:
		_next = PERIOD
		_fetch()


func _fetch() -> void:
	var place := LivePlace.of(str(Session.setup.get("airport", "VAJJ")))
	var rs := DayMath.sun_times(float(Session.setup.get("day_of_year", 45.0)))
	var h := float(Session.setup.get("time_h", 10.0))
	_src.start(place, float(Props.get_v("weather/wind_dir_deg", Session.setup.get("wind_dir_deg", 270.0))), h > rs.x and h < rs.y, str(Session.setup.get("weather", "Fair")))


func _on_fetch(r: Dictionary) -> void:
	var weather: Dictionary = r.get("weather", {})
	if weather.is_empty():
		return
	_origin = LiveBlend.read_props()
	_target = weather
	_elapsed = 0.0
	_blending = true
	if str(weather.get("live_metar", "")) != "":
		Props.set_v("weather/live_metar", str(weather.live_metar))
