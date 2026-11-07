extends RefCounted
## A restart (F5, or another flight in the same process) puts the cockpit back to the start
## defaults. A tiller dragged in the cockpit is only a property, so it used to survive.


func test_restart_clears_a_tiller_the_pilot_set() -> String:
	var snap := _snap()
	var aircraft := str(Session.setup.get("aircraft", "c172"))
	Session.setup["aircraft"] = "a320"
	var ctl := AircraftControls.for_def(AircraftDef.load_def("a320"))
	ctl.seed_props()
	Props.set_v("controls/tiller", 0.8)
	Props.set_v("controls/rudder_trim", -0.4)
	Props.set_v("controls/speedbrake", 1.0)
	Props.set_v("controls/fcu/ap1", true)
	Props.set_v("controls/mixture", 0.2)
	Props.set_v("systems/alternate_static", true)
	ctl.seed_props()  # a loaded situation must keep its values; only a restart overwrites
	var kept: bool = is_equal_approx(Props.get_f("controls/tiller"), 0.8)
	var node := FdmNode.new()
	node._defaults()
	ctl.restore_defaults()
	var kb := KeyboardControls.new()
	kb.tiller = 0.8
	kb.reset_flight()
	kb._process(0.05)
	var err := ""
	if not kept:
		err = "seeding a second time cleared the tiller"
	elif not is_equal_approx(Props.get_f("controls/tiller"), 0.0) or not is_equal_approx(kb.tiller, 0.0):
		err = "tiller prop %.2f member %.2f" % [Props.get_f("controls/tiller"), kb.tiller]
	elif not is_equal_approx(Props.get_f("controls/rudder_trim"), 0.0) or not is_equal_approx(Props.get_f("controls/speedbrake"), 0.0):
		err = "trim %.2f speedbrake %.2f" % [Props.get_f("controls/rudder_trim"), Props.get_f("controls/speedbrake")]
	elif Props.get_b("controls/fcu/ap1") or Props.get_b("systems/alternate_static"):
		err = "ap1 or alternate static stayed on"
	elif not is_equal_approx(Props.get_f("controls/mixture"), 1.0) or int(Props.get_v("controls/magnetos")) != 3:
		err = "mixture %.2f magnetos %s" % [Props.get_f("controls/mixture"), Props.get_v("controls/magnetos")]
	kb.free()
	node.free()
	Session.setup["aircraft"] = aircraft
	_restore(snap)
	return err


func _snap() -> Dictionary:
	var d := Props.dump("controls/")
	d["systems/alternate_static"] = Props.get_v("systems/alternate_static", null)
	return d


func _restore(snap: Dictionary) -> void:
	for k in Props.dump("controls/").keys():
		if snap.has(k):
			Props.set_v(k, snap[k])
		else:
			Props._p.erase(k)
	if snap["systems/alternate_static"] == null:
		Props._p.erase("systems/alternate_static")
	else:
		Props.set_v("systems/alternate_static", snap["systems/alternate_static"])
