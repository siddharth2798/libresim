class_name AtcAssist
extends RefCounted
## Radio assist (UserOptions radio_assist, default on; the controller's `assist` flag). On: every
## call first tunes COM1 to the unit that answers it, the next call of the flight is suggested
## ("Next: ask Ground for taxi") and heads the short call list. Off (realistic): you tune COM1
## yourself, the list offers "Tune COM1 to ..." first when needed and nothing is suggested.
## Pure logic over the controller and the world snapshot (atc_world.gd), no nodes.

const MAX_ACTIONS := 4
const INBOUND_NM := 25.0  # "ask for landing" is suggested within this distance of the airport
const FINAL_NM := 6.5     # "report final" is suggested this close (the controller asks at 5.5 nm)


## The call that comes next in the flight (an intent id), "" when none fits now (taxiing, climbing,
## on final: you just fly). Only a call that the state allows is returned.
static func next_call(c: AtcController, w: Dictionary) -> String:
	var s: Dictionary = c.s
	var want := ""
	match str(s.state):
		"parked", "clearance":
			if str(w.get("ctl", "")) == "uncontrolled":
				want = "taxi"
			elif not bool(s.info_heard) and AtcFacilities.has_role(w, "ATIS"):
				want = "atis"
			elif not bool(s.cleared):
				want = "clearance"
			else:
				want = "taxi"
		"taxi", "hold_short":
			want = "ready"
		"lined_up":
			want = "" if bool(s.cleared_takeoff) else "ready"
		"enroute":
			want = "inbound" if float(w.get("apt_dist_nm", 1e9)) <= INBOUND_NM else ""
		"inbound":
			want = "final" if float(w.get("apt_dist_nm", 1e9)) <= FINAL_NM or c.flag("st_rf") else ""
		"vacated":
			want = "taxi_stand"
	return want if want in AtcState.available(s, w) else ""


## The menu entry of the next call, {} when assist is off or nothing is due.
static func recommended(c: AtcController, w: Dictionary) -> Dictionary:
	if not c.assist:
		return {}
	var id := next_call(c, w)
	for e in c.menu(w):
		if e.kind == "call" and e.id == id:
			return e
	return {}


## The short list the radio shows (at most 4): the suggested call first (assist on) or the tune
## entry first (assist off), then the other calls. "Say again" is not in it.
static func actions(c: AtcController, w: Dictionary) -> Array:
	var m := c.menu(w)
	var calls := m.filter(func(e): return e.kind == "call")
	var out := []
	var r := recommended(c, w)
	if not r.is_empty():
		out.append(r)
		calls = calls.filter(func(e): return e.id != r.id)
	else:
		out = m.filter(func(e): return e.kind == "tune")
	return (out + calls).slice(0, MAX_ACTIONS)


## One line for the radio bar: "Next: ask Ground for taxi". A dead radio is always explained; the
## suggestion itself only shows with assist on.
static func next_hint(c: AtcController, w: Dictionary) -> String:
	if not bool(w.get("com1_ok", true)):
		if str(w.get("com1_why", "")) == "unpowered":
			return "Radio off: switch on avionics (Shift+V)"
		return "COM1 has failed: no radio calls"
	if not c.assist:
		return ""
	if str(w.get("apt", "")) == "":
		return "No airport in radio range"
	var r := recommended(c, w)
	if not r.is_empty():
		return "Next: " + _lower(str(r.label))
	return _state_hint(c, w)


static func _state_hint(c: AtcController, w: Dictionary) -> String:
	var rwy := c.runway_for(w)
	match str(c.s.state):
		"taxi":
			return "Next: taxi to runway %s, report ready" % rwy if rwy != "" else "Next: taxi to the runway, report ready"
		"lined_up":
			return "Next: you are cleared for takeoff"
		"takeoff":
			return "Next: take off, no call needed"
		"departed":
			return "Next: climb out, no call needed yet"
		"enroute":
			return "Next: fly on, no call needed yet"
		"inbound":
			return "Next: join the circuit, report final"
		"final":
			return "Next: wait for the landing clearance" if c.flag("land_wait") else "Next: land, or report going around"
		"landed":
			return "Next: vacate the runway"
	return ""


## With assist on: what the call will do to COM1 ("COM1 will tune to 121.900 (Pune Ground)"), else "".
static func tune_note(c: AtcController, w: Dictionary, entry: Dictionary) -> String:
	if not c.assist or str(entry.get("kind", "")) != "call" or str(w.get("ctl", "")) != "published":
		return ""
	var svc := AtcState.service_of(str(entry.id))
	if svc == "" or AtcFacilities.handles(w, svc):
		return ""
	var f := AtcFacilities.facility_for(w, svc)
	return "COM1 will tune to %.3f (%s)" % [f.mhz, f.name] if float(f.mhz) > 0.0 else ""


## Assist on and the call needs another unit: tune COM1 to it, say so, and return the world as it
## is now (a copy with the new frequency). Otherwise the world comes back unchanged.
static func tune_for(c: AtcController, id: String, w: Dictionary, now: float) -> Dictionary:
	if not c.assist or str(w.get("ctl", "")) != "published":
		return w
	var svc := AtcState.service_of(id)
	if svc == "" or AtcFacilities.handles(w, svc):
		return w
	var f := AtcFacilities.facility_for(w, svc)
	if float(f.mhz) <= 0.0:
		return w
	c.hook("tune", f.mhz)
	c.say("system", "tuned_auto", "*", c.slots(w, {"fac2": f.name, "freq3": f.mhz}), now)
	var out := w.duplicate()
	out.com1_mhz = float(f.mhz)
	return out


static func _lower(t: String) -> String:
	return t.substr(0, 1).to_lower() + t.substr(1)
