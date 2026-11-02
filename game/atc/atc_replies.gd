class_name AtcReplies
extends RefCounted
## What the controller answers to each pilot call (atc_state.gd INTENTS). First the frequency
## is checked: no airport / uncontrolled field (blind call, nobody answers) / wrong unit
## (it says which one to call, or nobody answers). Then the exchange is played: the pilot's
## call, the reply after a short delay, the pilot's readback, and for a clearance "readback
## correct". State changes happen when the reply is heard. Phrases: atc/phraseology.json.


static func run(c: AtcController, id: String, w: Dictionary, now: float) -> void:
	if str(w.get("apt", "")) == "":
		c.system("no_airport", w, now)
		return
	var svc := AtcState.service_of(id)
	if str(w.get("ctl", "")) == "uncontrolled":
		_blind(c, id, w, now)
	elif not AtcFacilities.handles(w, svc):
		_wrong_freq(c, id, w, now, svc)
	else:
		_exchange(c, id, w, now, AtcFacilities.role_for(w, svc))


static func _pkey(c: AtcController, id: String) -> String:
	return "ready_lined" if id == "ready" and c.s.state == "lined_up" else id


static func _exchange(c: AtcController, id: String, w: Dictionary, now: float, role: String) -> void:
	var x := {"fac": AtcFacilities.name_of(w, role)}
	var key := id
	var rb := ""
	var rb_ok := false
	var then := Callable()
	match id:
		"atis":
			x.rwy = c.runway_for(w)
			then = func(): c.s.info_heard = true
		"clearance":
			x.rwy = c.runway_for(w)
			then = func():
				c.s.cleared = true
				c.s.airport = w.apt
				c.s.runway = x.rwy
				if c.s.state == "parked":
					c.set_state("clearance")
			rb = "clearance"
			rb_ok = true
		"pushback":
			c.hook("start_pushback")
			c.s.pushed = true
			rb = "pushback"
		"taxi":
			var route := parse_route(str(c.hook("request_taxi")))
			x.rwy = route.rwy if route.rwy != "" else c.runway_for(w)
			x.opt_via = route.via
			key = "taxi" if c.s.cleared else "taxi_sq"
			rb = key
			then = func():
				c.s.cleared = true
				c.s.airport = w.apt
				c.s.runway = x.rwy
				if c.s.state in ["parked", "clearance"]:
					c.set_state("taxi")
		"ready":
			x.rwy = c.runway_for(w)
			if c.s.state == "lined_up":
				key = "takeoff_clear"
				rb = key
				then = func():
					c.s.cleared_takeoff = true
					c.s.lineup_ok = true
			elif float(w.get("rwy_dist", 1e9)) > AtcState.NEAR_RWY:
				key = "ready_far"
			else:
				key = "lineup"
				rb = key
				then = func(): c.s.lineup_ok = true
		"inbound":
			var rwy := arrival_runway(c, w)
			var handoff := role == "APP" and AtcFacilities.differs(w, "APP", "TWR")
			x.rwy = rwy
			x.join = join_text(w, rwy)
			if handoff:
				x.fac2 = AtcFacilities.name_of(w, "TWR")
				x.freq = AtcFacilities.freq_of(w, "TWR")
			key = "inbound_join_ho" if handoff else "inbound_join"
			rb = key
			then = func():
				c.s.airport = w.apt
				c.s.runway = rwy
				c.s.cleared_land = false
				c.s.handoff = "TWR" if handoff else ""
				c.s.handoff_at = now
				c.set_state("inbound")
		"final":
			var rwy2 := c.runway_for(w) if c.s.state == "inbound" else arrival_runway(c, w)
			x.rwy = rwy2
			if bool(w.get("rwy_free", true)):
				key = "land_clear"
				rb = key
				then = func():
					c.s.cleared_land = true
					c.s.runway = rwy2
					c.s.handoff = ""
					c.set_state("final")
			else:
				key = "land_wait"
				then = func():
					c.s.cleared_land = false
					c.s.runway = rwy2
					c.set_flag("land_wait")
					c.set_state("final")
		"goaround":
			x.rwy = c.runway_for(w)
			rb = "goaround"
			then = func():
				c.s.cleared_land = false
				c.set_state("inbound")
		"taxi_stand":
			var back := parse_route(str(c.hook("taxi_to_stand")))
			x.opt_via = back.via
			if back.stand != "":
				x.stand = back.stand
			x.rwy = c.runway_for(w)
			rb = "taxi_stand"
			then = func(): c.set_state("taxi")
	if x.has("rwy"):
		x.appr = AtcProfile.approach_kind(w, str(x.rwy))  # airline phrases: ILS or visual approach
	var sl := c.slots(w, x)
	var t := c.say("pilot", _pkey(c, id), role, sl, now)
	var tr := c.reply_time(t)
	c.say("controller", key, role, sl, tr, then, id != "atis")
	if rb != "":
		var trb := tr + c.readback_gap
		c.say("readback", rb, "*", sl, trb)
		if rb_ok:
			c.say("controller", "readback_ok", role, sl, trb + 1.0)


## Uncontrolled field: the call goes out, nobody answers; the pilot's own state still moves on.
static func _blind(c: AtcController, id: String, w: Dictionary, now: float) -> void:
	var apt := str(w.apt)
	if not c.flag("unc_" + apt):
		c.set_flag("unc_" + apt)
		c.system("uncontrolled", w, now)
	var rwy := arrival_runway(c, w) if id == "inbound" else c.runway_for(w)
	match id:
		"pushback":
			c.hook("start_pushback")
			c.s.pushed = true
		"taxi":
			var route := parse_route(str(c.hook("request_taxi")))
			if rwy == "":
				rwy = route.rwy
			if c.s.state in ["parked", "clearance"]:
				c.set_state("taxi")
		"taxi_stand":
			c.hook("taxi_to_stand")
			c.set_state("taxi")
		"ready":
			c.s.lineup_ok = true
			c.s.cleared_takeoff = true
		"inbound":
			c.s.airport = apt
			c.s.runway = rwy
			c.s.cleared_land = false
			c.set_state("inbound")
		"final":
			c.set_state("final")
		"goaround":
			c.set_state("inbound")
	var pkey := "blind_" + _pkey(c, id)
	if c.phr.has("pilot", pkey, c.profile):
		c.say("pilot", pkey, "*", c.slots(w, {"rwy": rwy}), now)


## The tuned unit cannot handle this call: another unit of the airport redirects the pilot,
## or nobody answers and the radio tells which frequency to tune.
static func _wrong_freq(c: AtcController, id: String, w: Dictionary, now: float, svc: String) -> void:
	var tuned := AtcFacilities.tuned(w)
	var want := AtcFacilities.facility_for(w, svc)
	var sl := c.slots(w, {"fac": want.name, "fac2": want.name, "freq": want.mhz, "freq2": want.mhz})
	if tuned.role != "":
		sl.fac = tuned.name
		var t := c.say("pilot", _pkey(c, id), tuned.role, sl, now)
		c.say("controller", "wrong_freq", tuned.role, sl, c.reply_time(t))
	else:
		c.say("pilot", _pkey(c, id), "*", sl, now)
		c.system("no_reply" if float(want.mhz) > 0.0 else "no_reply_any", w, now + 2.0,
			{"freq": float(w.get("com1_mhz", 0.0)), "fac2": want.name, "freq2": want.mhz})


static func say_again(c: AtcController, w: Dictionary, now: float) -> void:
	if not bool(w.get("com1_ok", true)):
		c.system(AtcController.com_key(w), w, now)
		return
	var sl := c.slots(w, {"fac": c.s.last_who if c.s.last_who != "" else AtcFacilities.tuned(w).name})
	var t := c.say("pilot", "say_again", "*", sl, now)
	c.say_raw("atc", c.s.last_who, c.s.last_instr, c.s.last_instr_spoken, c.reply_time(t))


## "Taxi to runway 09 via A, B — hold short" -> {rwy: "09", via: " via A, B", stand: ""}; "(stand 3)" gives stand.
static func parse_route(t: String) -> Dictionary:
	var via := ""
	var stand := ""
	var sm := RegEx.create_from_string("\\((stand [^)]+|gate [^)]+|bay [^)]+)\\)").search(t)
	if sm != null:
		stand = sm.get_string(1)
	var i := t.find(" via ")
	if i >= 0:
		via = t.substr(i)
		var j := via.find(" —")
		if j >= 0:
			via = via.substr(0, j)
	var m := RegEx.create_from_string("runway (\\w+)").search(t)
	return {"via": via, "rwy": m.get_string(1) if m != null else "", "stand": stand}


## Runway to land on: the one the aircraft is lined up with (corridor, tailwind under 6 kt), else into wind.
static func arrival_runway(c: AtcController, w: Dictionary) -> String:
	var a: Dictionary = w.get("appr", {})
	if not a.is_empty() and float(a.get("tail_kt", 0.0)) < 6.0:
		return str(a.ident)
	return str(w.get("rwy", "")) if c.s.airport != str(w.get("apt", "")) or c.s.runway == "" else str(c.s.runway)


static func join_text(w: Dictionary, rwy: String) -> String:
	var a: Dictionary = w.get("appr", {})
	if not a.is_empty() and str(a.ident) == rwy and float(a.along) < -3000.0:
		return "make straight-in approach runway " + rwy
	return "join left-hand downwind runway " + rwy
