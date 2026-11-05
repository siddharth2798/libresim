class_name CaptainWatch
extends Node
## Start-screen helper: shows the Captain Pack offer (captain_offer.gd) at most once per launch. It checks on the first
## frame, every 0.5 s for the first 5 s (SDL on macOS lists pads a moment after start) and whenever a pad connects.
## Rules (core/captain_detect.gd): pack plugged in, nothing answered yet, saved table not already the profile. It waits
## while the start screen has another modal open (the "Fly anyway?" question, a flight loading) or shows the Controls
## page. `auto` is off outside an interactive run (tests, probes, --shot): then only an explicit check() can show it.

const POLL_S := 5.0
const EVERY_S := 0.5

var host: Control  # the start screen: cur, modal_open()
var auto := true
var shown := false  # the offer was shown this launch (or is open now)
var offer: CaptainOffer  # the open prompt, or null
var _t := 0.0
var _next := 0.0


func _ready() -> void:
	auto = Session.interactive()
	set_process(auto)
	if auto:
		Input.joy_connection_changed.connect(func(_d, _c): check())


func _process(dt: float) -> void:
	_t += dt
	if _t >= _next:
		_next = _t + EVERY_S
		check()
	if shown or _t > POLL_S:
		set_process(false)


## Shows the offer if every rule allows it now; true when it was shown by this call.
func check() -> bool:
	if shown or host == null or host.modal_open() or host.cur == "controls" or not CaptainDetect.offer_now():
		return false
	shown = true
	offer = CaptainOffer.new()
	offer.chosen.connect(_closed)
	host.add_child(offer)
	return true


func _closed(_what: String) -> void:
	if offer != null:
		offer.queue_free()
		offer = null
