extends RefCounted
## Shared fixture for the ATC flow tests (test_atc_flow.gd, test_atc_rules.gd): a fake world
## (a dictionary instead of the property tree), hooks that record their calls, helpers to run the
## monitor and release transmissions, and transcript checks.

var _calls := []  # hook calls made by the controller


func _hooks() -> Dictionary:
	var push := func() -> String:
		_calls.append("pushback")
		return ""
	var taxi := func() -> String:
		_calls.append("taxi")
		return "Taxi to runway 27 via A, B \u2014 hold short"
	var stand := func() -> String:
		_calls.append("stand")
		return "Taxi to the apron (stand 3) via B"
	var tune := func(mhz: float) -> void:
		_calls.append("tune %.3f" % mhz)
	return {"start_pushback": push, "request_taxi": taxi, "taxi_to_stand": stand, "tune": tune}

func _coms(kind: String) -> Array:
	if kind == "twr":
		return [{"type": "TWR", "desc": "TWR", "mhz": 123.5}]
	return [{"type": "ATIS", "desc": "ATIS", "mhz": 126.4}, {"type": "CLD", "desc": "DEL", "mhz": 121.85},
		{"type": "GND", "desc": "GND", "mhz": 121.9}, {"type": "TWR", "desc": "TWR", "mhz": 118.1},
		{"type": "APP", "desc": "APP", "mhz": 127.9}]

func _world(mhz: float, over := {}, kind := "full") -> Dictionary:
	var w := AtcWorld.blank()
	var coms := _coms(kind) if kind != "none" else []
	w.merge({"apt": "TEST", "apt_name": "Test", "apt_type": "medium_airport", "coms": coms, "com1_mhz": mhz, "rwy": "27",
		"apt_dist": 500.0, "apt_dist_nm": 0.27,
		"ctl": AtcFacilities.control_mode(coms, "medium_airport", "TEST")}, true)
	w.merge(over, true)
	return w

func _ctl() -> AtcController:
	var c := AtcController.new("VT-FSM", AtcPhraseology.new(), 7)
	c.delay = Vector2.ZERO
	c.readback_gap = 0.0
	c.hooks = _hooks()
	_calls.clear()
	return c

## Run the monitor and release transmissions for `secs` of sim time.
func _pump(c: AtcController, mon: AtcMonitor, w: Dictionary, t: float, secs: float) -> float:
	var end := t + secs
	while t < end:
		w.t = t
		mon.step(w, t)
		c.update(t)
		t += 0.25
	return t

## Fly the fake aircraft to `to` in steps under the monitor's jump limit (a bigger jump means F5 or a load).
func _glide(c: AtcController, mon: AtcMonitor, w: Dictionary, t: float, to: Vector2) -> float:
	var from: Vector2 = w.pos
	var n := maxi(int(from.distance_to(to) / 250.0), 1)
	for i in range(1, n + 1):
		w.pos = from.lerp(to, float(i) / n)
		w.apt_dist = (w.pos as Vector2).length()
		w.apt_dist_nm = w.apt_dist / 1852.0
		t = _pump(c, mon, w, t, 0.25)
	return t

func _text(c: AtcController) -> String:
	var out := ""
	for e in c.log:
		out += "%s: %s\n" % [e.who, e.text]
	return out

func _count(c: AtcController, kind: String) -> int:
	return c.log.filter(func(e): return e.kind == kind).size()

func _ids(menu: Array) -> Array:
	return menu.map(func(m): return m.id)

## Every line of a transcript must be clean: no unfilled slot, no gaps, nothing but words when spoken.
func _clean(c: AtcController) -> String:
	for e in c.log:
		for s in [e.text, e.spoken]:
			if s.contains("{") or s.contains("}") or s.contains("  ") or s.contains(" ,") or s == "":
				return "dirty line from %s: '%s'" % [e.who, s]
		if RegEx.create_from_string("\\d").search(e.spoken) != null:
			return "digits in the spoken line '%s'" % e.spoken
	return ""

func _need(txt: String, parts: Array) -> String:
	for p in parts:
		if not txt.contains(p):
			return "missing '%s' in:\n%s" % [p, txt]
	return ""

func _air_world(mhz: float, over := {}, kind := "full") -> Dictionary:
	return _world(mhz, {"wow": false, "agl": 600.0, "alt": 700.0, "gs": 50.0, "pos": Vector2(-12000, 800), "apt_dist": 12000.0,
		"apt_dist_nm": 6.5}.merged(over, true), kind)
