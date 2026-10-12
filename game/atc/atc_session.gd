class_name AtcSession
extends RefCounted
## Glue between the radio panel and the ATC logic: takes a world snapshot four times a second,
## runs the monitor, releases due transmissions (and speaks them), and publishes the state in
## the property tree: /atc/state, airport, runway, squawk, callsign, cleared_takeoff,
## cleared_land, facility, last_tx (+ info, handoff, flags, log). Saved flights keep /atc/*
## (core/situation.gd): a restored copy is told apart by its stamp and adopted.
## Everything is advisory: a failure here must never stop the simulation.

const SNAP_EVERY := 0.25

var c: AtcController
var mon: AtcMonitor
var voice := AtcVoice.new()
var env := {}
var w := {}  # latest world snapshot
var now := 0.0  # sim time (stops while paused)
var _snap_t := 0.0
var _stamp := ""
var _sid := 0
var _pub_rev := -1


static func callsign() -> String:
	var n := AtcSpeech.normalize_callsign(str(Session.setup.get("callsign", "")))
	if n == "":
		n = AtcSpeech.normalize_callsign(str(UserOptions.get_v("callsign")))
	return n if n != "" else "VT-FSM"


## A training lesson is active: ATC stays quiet (no advisories, clearances implied).
static func in_lesson() -> bool:
	return str(Session.training) != ""


func setup(e: Dictionary, hooks: Dictionary) -> void:
	env = e
	c = AtcController.new(callsign())
	c.hooks = hooks
	c.on_tx = func(entry: Dictionary): voice.speak(entry)
	mon = AtcMonitor.new(c)
	_sid = randi()
	w = AtcWorld.snapshot(env, now)


func ready() -> bool:
	return c != null


func tick(dt: float) -> void:
	if c == null or Props.get_b("replay/active"):
		return
	now += dt
	var stamp := str(Props.get_v("atc/stamp", ""))
	if stamp != "" and stamp != _stamp:  # a saved flight was loaded: take its ATC state back
		c.adopt(Props.dump("atc/"))
		c.set_callsign(callsign())
		w = AtcWorld.snapshot(env, now)
		mon.rebase(w)
		_stamp = stamp
		_pub_rev = -1
	mon.silent = in_lesson()
	_snap_t -= dt
	if _snap_t <= 0.0:
		_snap_t = SNAP_EVERY
		w = AtcWorld.snapshot(env, now)
		c.set_callsign(callsign())
		voice.poll()
		mon.step(w, now)
		Props.set_v("atc/facility", AtcFacilities.tuned(w).name)
	c.update(now)
	publish()


## Menu entries for the panel (see AtcController.menu).
func menu() -> Array:
	return c.menu(w) if c != null else []


## The pilot picked a menu entry.
func pick(entry: Dictionary) -> void:
	if c == null:
		return
	w = AtcWorld.snapshot(env, now)
	c.request(str(entry.id), w, now, float(entry.get("mhz", 0.0)), str(entry.get("name", "")))


func publish() -> void:
	if c.rev == _pub_rev:
		return
	_pub_rev = c.rev
	var d := c.export()
	for k in d:
		Props.set_v(k, d[k])
	_stamp = "%d:%d" % [_sid, c.rev]
	Props.set_v("atc/stamp", _stamp)


## The flight scene is going away: the next flight starts with a clean ATC state.
func close() -> void:
	Props.set_v("atc/stamp", "")
