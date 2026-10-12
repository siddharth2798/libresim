class_name AtcController
extends RefCounted
## The air traffic controller's memory: state machine value (s), the transcript (log) and the
## queue of transmissions waiting for their time (replies come 0.6-1.5 s after the call,
## readbacks a moment later). Pure logic: no nodes, time is passed in, so tests drive it with a
## fake world dictionary (atc_world.gd). What the controller says to each call is in
## atc_replies.gd; what it says unprompted and the advisories are in atc_monitor.gd.
## Everything here is advisory: nothing blocks the simulation.

const LOG_MAX := 30
const ALT_LIMIT_FT := 2000.0  # "climb not above" in the VFR clearance

var phr: AtcPhraseology
var s := {}  # published state, see blank()
var log: Array = []  # [{kind, who, text, spoken, t}]; kind = pilot | atc | system | advisory
var rev := 0  # bumped on every change (the session publishes /atc/* when it moves)
var tx_serial := 0  # counts released transmissions (the panel shows itself when it moves)
var hooks := {}  # name -> Callable: start_pushback, request_taxi, taxi_to_stand, tune
var delay := Vector2(0.6, 1.5)  # s between a call and the reply
var readback_gap := 1.3  # s between the reply and the pilot's readback
var on_tx := Callable()  # called with every released transmission (voice)
var _q: Array = []
var _seq := 0
var _n := 0
var _rng := RandomNumberGenerator.new()


func _init(callsign := "VT-FSM", p: AtcPhraseology = null, rng_seed := -1) -> void:
	phr = p if p != null else AtcPhraseology.new()
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	s = blank(callsign)


func blank(callsign: String) -> Dictionary:
	return {"state": "parked", "airport": "", "runway": "", "squawk": "%d%d%d%d" % [_rng.randi_range(2, 6),
		_rng.randi_range(0, 7), _rng.randi_range(0, 7), _rng.randi_range(0, 7)], "callsign": callsign,
		"info_i": 0, "info_sig": "", "info_heard": false, "cleared": false, "cleared_takeoff": false,
		"cleared_land": false, "lineup_ok": false, "pushed": false, "arrived": false, "handoff": "",
		"handoff_at": 0.0, "last_instr": "", "last_instr_spoken": "", "last_who": "", "last_tx": "",
		"flags": {}, "park_e": 0.0, "park_n": 0.0}


static func initial_state(w: Dictionary) -> String:
	if not bool(w.get("wow", true)):
		return "enroute"
	if bool(w.get("on_runway", false)) and bool(w.get("aligned", false)) and float(w.get("gs", 0.0)) < 3.0:
		return "lined_up"
	return "parked"


## New flight (or a jump in the world): callsign, squawk and ATIS letter stay.
func reset(w: Dictionary) -> void:
	var keep := {}
	for k in ["callsign", "squawk", "info_i", "info_sig"]:
		keep[k] = s[k]
	s = blank(s.callsign)
	for k in keep:
		s[k] = keep[k]
	_q.clear()
	s.airport = str(w.get("apt", ""))
	s.runway = str(w.get("rwy", ""))
	s.state = initial_state(w)
	var p: Vector2 = w.get("pos", Vector2.ZERO)
	s.park_e = p.x
	s.park_n = p.y
	rev += 1


## The runway in use: the one given to this flight at this airport, else the into-wind one.
func runway_for(w: Dictionary) -> String:
	if s.runway != "" and s.airport == str(w.get("apt", "")):
		return str(s.runway)
	return str(w.get("rwy", ""))


func set_callsign(cs: String) -> void:
	if cs != "" and cs != s.callsign:
		s.callsign = cs
		rev += 1


func set_state(st: String) -> void:
	if s.state == st:
		return
	s.state = st
	for k in s.flags.keys():
		if str(k).begins_with("st_"):  # state-scoped flags end with the state
			s.flags.erase(k)
	rev += 1


func flag(n: String) -> bool:
	return bool(s.flags.get(n, false))


func set_flag(n: String) -> void:
	s.flags[n] = true
	rev += 1


func clear_flag(n: String) -> void:
	if s.flags.has(n):
		s.flags.erase(n)
		rev += 1


func info_word() -> String:
	return AtcSpeech.NATO.values()[int(s.info_i) % 26]


## The ATIS letter moves on when the weather changes materially (wind 10 deg / 4 kt,
## QNH 1 hPa, visibility 5 km, rain 1/3).
func refresh_info(w: Dictionary) -> void:
	var sig := "%d/%d/%d/%d/%d" % [int(round(float(w.get("wind_dir", 0.0)) / 10.0)) % 36, int(float(w.get("wind_kt", 0.0)) / 4.0),
		int(round(float(w.get("qnh", 1013.0)))), int(float(w.get("vis", 20000.0)) / 5000.0), int(float(w.get("precip", 0.0)) * 3.0)]
	if s.info_sig == "":
		s.info_sig = sig
	elif sig != s.info_sig:
		s.info_sig = sig
		s.info_i = (int(s.info_i) + 1) % 26
		s.info_heard = false
		rev += 1


func hook(name: String, arg: Variant = null) -> Variant:
	var h: Callable = hooks.get(name, Callable())
	if not h.is_valid():
		return ""
	return h.call() if arg == null else h.call(arg)


# ---- menu and pilot calls ----

## The calls that make sense now: [{id, label, kind: call | tune | again, ...}], at most six.
func menu(w: Dictionary) -> Array:
	return AtcMenu.build(self, w)


## The pilot picks a menu entry.
func request(id: String, w: Dictionary, now: float, mhz := 0.0, unit := "") -> void:
	if id == "tune":
		hook("tune", mhz)
		var sl := slots(w, {"fac2": unit, "freq2": mhz})
		say("system", "tuned", "*", sl, now, Callable(), false)
	elif id == "say_again":
		AtcReplies.say_again(self, w, now)
	elif AtcState.INTENTS.has(id):
		if not bool(w.get("com1_ok", true)):
			system(com_key(w), w, now)
		else:
			AtcReplies.run(self, id, w, now)


## Which note a dead radio gets: no power (switch the avionics on) or a real failure (lost communications).
static func com_key(w: Dictionary) -> String:
	return "com_off" if str(w.get("com1_why", "")) == "unpowered" else "com_failed"


func system(key: String, w: Dictionary, now: float, extra := {}) -> void:
	say("system", key, "*", slots(w, extra), now, Callable(), false)


# ---- transmissions ----

func reply_time(t: float) -> float:
	return t + _rng.randf_range(delay.x, delay.y)


## Queue one transmission from a phrase (section/key/role); returns the time it is due. The
## pilot's lines are kind "pilot", the controller's "atc", advisories and system notes their own.
func say(section: String, key: String, role: String, sl: Dictionary, at: float, then := Callable(), instr := false) -> float:
	var tpl := phr.template(section, key, role, _n)
	if tpl == "":
		return at
	_n += 1
	var kind := "atc"
	var who := str(sl.get("fac", ""))
	match section:
		"pilot", "readback":
			kind = "pilot"
			who = "You"
		"advisory":
			kind = "advisory"
			who = "ATC note"
		"system":
			kind = "system"
			who = "(radio)"
	return say_raw(kind, who, phr.fill(tpl, sl), phr.fill(tpl, sl, true), at, then, instr)


## Queue a finished text (say again repeats the last instruction this way).
func say_raw(kind: String, who: String, text: String, spoken: String, at: float, then := Callable(), instr := false) -> float:
	_seq += 1
	_q.append({"at": at, "seq": _seq, "kind": kind, "who": who, "text": text, "spoken": spoken,
		"then": then, "instr": instr and kind == "atc"})
	return at


## Release every transmission that is due; returns them (the voice speaks them).
func update(now: float) -> Array:
	var due := _q.filter(func(e): return e.at <= now)
	if due.is_empty():
		return []
	_q = _q.filter(func(e): return e.at > now)
	due.sort_custom(func(a, b): return a.at < b.at or (a.at == b.at and a.seq < b.seq))
	for e in due:
		if e.then is Callable and e.then.is_valid():
			e.then.call()
		log.append({"kind": e.kind, "who": e.who, "text": e.text, "spoken": e.spoken, "t": now})
		s.last_tx = e.text
		if e.instr:
			s.last_instr = e.text
			s.last_instr_spoken = e.spoken
			s.last_who = e.who
		if on_tx.is_valid():
			on_tx.call(e)
	if log.size() > LOG_MAX:
		log = log.slice(log.size() - LOG_MAX)
	rev += 1
	tx_serial += due.size()
	return due


func pending() -> int:
	return _q.size()


# ---- slots for the phrases ----

func slots(w: Dictionary, extra := {}) -> Dictionary:
	return AtcSlots.build(self, w, extra)


# ---- publishing (the session copies these into the property tree) ----

func export() -> Dictionary:
	var d := {}
	for k in s:
		d["atc/" + k] = s[k].duplicate() if s[k] is Dictionary else s[k]
	d["atc/info"] = info_word()
	var lg := []
	for e in log:
		lg.append([e.kind, e.who, e.text, e.spoken])
	d["atc/log"] = lg
	return d


## Take the state back from saved properties (a loaded flight).
func adopt(d: Dictionary) -> void:
	var fresh := blank(s.callsign)
	for k in fresh:
		if d.has("atc/" + k):
			s[k] = d["atc/" + k]
	if not (s.flags is Dictionary):
		s.flags = {}
	log.clear()
	for e in d.get("atc/log", []):
		log.append({"kind": e[0], "who": e[1], "text": e[2], "spoken": e[3], "t": -999.0})
	_q.clear()
	rev += 1
