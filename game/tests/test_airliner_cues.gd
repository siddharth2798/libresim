extends Node
## A320 cues: OVERSPEED over VFE / VLE as well as VMO (the PFD's vmax), CONF 1+F auto-retraction to CONF 1 above 210 kt,
## MASTER WARN / CAUT acknowledgement silencing the chimes, and the tyre layers on grass and under braking.

const TL := preload("res://tests/test_audio_layers.gd")


static func _guard(f: Callable) -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	var err: String = f.call()
	Props._p = snap
	return err


func _warn() -> AirlinerWarnings:
	var w := AirlinerWarnings.new()
	w.def = AircraftDef.load_def("a320")
	w._ready()
	return w


func _texts() -> Array:
	return (Props.get_v("ewd/warnings", []) as Array).map(func(l): return l[0])


func test_cues_overspeed_at_vfe() -> String:
	return _guard(func():
		var w := _warn()
		Props.set_v("fdm/wow", false)
		Props.set_v("fdm/agl_m", 2000.0)
		Props.set_v("fdm/gear_pos", 0.0)
		Props.set_v("instruments/pfd/vmax_kt", 200.0)  # CONF 2
		Props.set_v("fdm/cas_mps", 203.0 * Units.KT)
		w.update()
		var under := _texts().has("OVERSPEED")
		Props.set_v("fdm/cas_mps", 206.0 * Units.KT)
		w.update()
		var over := _texts().has("OVERSPEED")
		var red := Props.get_b("ewd/master_warning")
		w.free()
		if under or not over or not red:
			return "OVERSPEED from VFE + 4: at 203 kt %s, at 206 kt %s (master %s)" % [under, over, red]
		return "")


func test_cues_master_ack_silences_until_new() -> String:
	var acked := {}
	var w := [[70, "OVERSPEED", "red"], [40, "HYD G SYS LO PR", "amber"]]
	if AirlinerWarnings.master_flags(w, acked, false) != [true, true]:
		return "unacknowledged warnings light both"
	if AirlinerWarnings.master_flags(w, acked, true) != [false, false]:
		return "a press acknowledges what shows"
	if AirlinerWarnings.master_flags(w, acked, false) != [false, false]:
		return "and it stays quiet while they show"
	var more := w + [[100, "ENG 1 FIRE", "red"]]
	if AirlinerWarnings.master_flags(more, acked, false) != [true, false]:
		return "a new red lights the warning again"
	AirlinerWarnings.master_flags([], acked, false)
	if AirlinerWarnings.master_flags(w, acked, false) != [true, true]:
		return "a warning that cleared and came back is new again"
	return _guard(func():
		var n := _warn()
		Props.set_v("fdm/wow", false)
		Props.set_v("fdm/agl_m", 2000.0)
		Props.set_v("fdm/gear_pos", 0.0)
		Props.set_v("fdm/cas_mps", 360.0 * Units.KT)
		n.update()
		var before := Props.get_b("ewd/master_warning")
		Props.set_v("controls/ewd/master_ack", true)
		n.update()
		var after := Props.get_b("ewd/master_warning")
		var consumed := not Props.get_b("controls/ewd/master_ack")
		var still := _texts().has("OVERSPEED")
		n.free()
		if not before or after or not consumed or not still:
			return "MASTER WARN press: lit %s, after %s, consumed %s, line stays %s" % [before, after, consumed, still]
		return "")


func test_cues_flap_auto_retract() -> String:
	var rule: Dictionary = AircraftDef.load_def("a320").config().controls.flaps.get("auto_retract", {})
	if rule.is_empty():
		return "a320 config controls.flaps.auto_retract missing"
	if AirlinerControls.auto_retract(rule, 2, 215.0, false) != 1:
		return "1+F retracts to 1 above 210 kt"
	if AirlinerControls.auto_retract(rule, 2, 205.0, false) != 2 or AirlinerControls.auto_retract(rule, 2, 230.0, true) != 2:
		return "not below 210 kt, never on the ground"
	if AirlinerControls.auto_retract(rule, 3, 230.0, false) != 3 or AirlinerControls.auto_retract({}, 2, 300.0, false) != 2:
		return "only from 1+F, and only with a rule"
	return ""


func test_cues_tyres_on_grass_and_brakes() -> String:
	for ac in ["c172", "a320"]:
		var by := {}
		for l in AudioCurves.expand(TL.layers_of(ac), 2):
			by[l.id] = l
		var roll := {"fdm/wow": true, "fdm/groundspeed_mps": 10.0}
		var grass := roll.merged({"ground/unpaved": 1.0})
		var st := func(id: String, v: Dictionary) -> float: return AudioCurves.layer_state(by[id], {"view": "cockpit", "values": v}).vol
		if st.call("grass_roll", roll) != 0.0 or st.call("grass_roll", grass) <= 0.0:
			return "%s: grass roll only off the pavement" % ac
		if st.call("tyre_roll", grass) >= st.call("tyre_roll", roll):
			return "%s: the asphalt roll fades on grass" % ac
		var slow := {"fdm/wow": true, "fdm/groundspeed_mps": 2.0, "controls/brake_left": 1.0}
		if st.call("brake_squeal", slow) <= 0.0:
			return "%s: brakes squeal at walking pace" % ac
		if st.call("brake_squeal", slow.merged({"fdm/groundspeed_mps": 0.0}, true)) != 0.0 \
				or st.call("brake_squeal", slow.merged({"fdm/groundspeed_mps": 30.0}, true)) != 0.0:
			return "%s: not standing still, not at speed" % ac
	return ""
