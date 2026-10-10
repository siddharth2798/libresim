extends RefCounted
## Failure scheduler (systems/failure_manager.gd): scheduled triggers and random failures.


func _setup(failures: Dictionary, random: Dictionary) -> FailureManager:
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.failures = failures
	if not random.is_empty():
		Session.setup.random = random
	Props.set_v("fdm/wow", true)
	Props.set_v("fdm/agl_m", 0.0)
	Props.set_v("fdm/cas_mps", 0.0)
	var m := FailureManager.new()
	m._ready()
	m.restart()
	return m


func test_fail_scheduled_triggers() -> String:
	var m := _setup({"vacuum_pump": [1, 0.0], "alternator": [2, 5.0], "pitot_blocked": [3, 1000.0], "flaps": [4, 100.0]}, {})
	if not Props.get_b("failures/vacuum_pump"):
		return "'at start' failure not active at start"
	m.elapsed = 299.0
	m._check()
	if Props.get_b("failures/alternator"):
		return "time failure tripped early"
	m.elapsed = 301.0
	m._check()
	if not Props.get_b("failures/alternator"):
		return "time failure did not trip after 5 min"
	Props.set_v("fdm/agl_m", 400.0)  # 1312 ft, but still on the ground -> must not trip
	m._check()
	if Props.get_b("failures/pitot_blocked"):
		return "altitude failure tripped on the ground"
	Props.set_v("fdm/wow", false)
	m._check()
	Props.set_v("fdm/cas_mps", 110.0 * 0.514444)
	m._check()
	var ok := Props.get_b("failures/pitot_blocked") and Props.get_b("failures/flaps")
	print("    at start, 5 min, 1000 ft AGL, 100 kt -> all tripped: %s; event '%s'" % [ok, Props.get_v("failures/event")])
	m.free()
	FailureCatalog.clear_all()
	return "" if ok else "altitude / airspeed failure did not trip"


func test_fail_random_window() -> String:
	var m := _setup({"engine": [1, 0.0]}, {"enabled": true, "count": 3, "from_min": 10.0, "to_min": 20.0, "categories": ["Electrical", "Avionics"]})
	var r: Array = m.armed.filter(func(a): return a.random)
	var allowed := FailureCatalog.ids_in(["Electrical", "Avionics"])
	for a in r:
		if not a.id in allowed or a.value < 10.0 or a.value > 20.0:
			return "random failure %s at %.1f min outside the choice" % [a.id, a.value]
	m.elapsed = 9.9 * 60.0
	m._check()
	var early := FailureCatalog.all_ids().filter(func(id): return Props.get_b("failures/" + id) and id != "engine")
	m.elapsed = 20.1 * 60.0
	m._check()
	var late := FailureCatalog.all_ids().filter(func(id): return Props.get_b("failures/" + id) and id != "engine")
	print("    3 random in 10-20 min from Electrical/Avionics: %s" % [late])
	m.free()
	FailureCatalog.clear_all()
	if r.size() != 3:
		return "expected 3 random failures, got %d" % r.size()
	if not early.is_empty():
		return "random failure before the window"
	return "" if late.size() == 3 else "random failures did not all trip by the end of the window"
