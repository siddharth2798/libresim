class_name LiveSources
extends Node
## The one HTTP client for live weather. NOAA and Open-Meteo each have their own URL builder, so
## either source can be removed without touching the fallback. 10 s timeout. No API key.


const TIMEOUT := 10.0
const AGENT := "libresim/1 (https://github.com/siddharth2798/libresim)"

signal finished(result: Dictionary)

var _place := {}
var _last_dir := 270.0
var _day := true
var _preset := "Fair"
var _left := 0
var _got := {}
var _ticket := 0


func start(place: Dictionary, last_dir: float, day: bool, preset: String) -> void:
	_place = place
	_last_dir = last_dir
	_day = day
	_preset = preset
	_got = {}
	_left = 2
	_ticket += 1
	var ticket := _ticket
	_ask(LiveNoaa.url(float(place.lat), float(place.lon)), "noaa", ticket)
	_ask(LiveOpenMeteo.url(float(place.lat), float(place.lon)), "meteo", ticket)


func _ask(url: String, key: String, ticket: int) -> void:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, body):
		if ticket != _ticket:
			http.queue_free()
			return
		_got[key] = {"code": code if result == HTTPRequest.RESULT_SUCCESS else 0, "body": body.get_string_from_utf8()}
		http.queue_free()
		_done(ticket))
	if http.request(url, ["User-Agent: " + AGENT]) != OK:
		_got[key] = {"code": 0, "body": ""}
		http.queue_free()
		_done(ticket)


func _done(ticket: int) -> void:
	if ticket != _ticket:
		return
	_left -= 1
	if _left > 0:
		return
	var out := LiveFetch.decide(_got, _place, LiveCache.read(), int(Time.get_unix_time_from_system()), _last_dir, _day, _preset)
	if bool(out.get("persist", false)):
		LiveCache.write(out.save)
	finished.emit(out)
