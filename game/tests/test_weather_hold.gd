extends RefCounted
## The world holds while the flight is paused or a replay drives it (core/sim_hold.gd): FdmNode publishes sim/hold, and
## the weather (Weather, the storm clock), the cloud drift (SkyTime) and ice accretion (Icing) stop. A loaded save puts
## the cloud field and the storm cells back where they were (the saved environment/cloud_drift and storm_clock_s are
## taken when meta/situation is bumped, as Situation.apply does). The full flight scene round trip was also run by hand.

const DT := 1.0 / 120.0


static func _guard(f: Callable) -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	SimHold.publish(false, false)
	var err: String = f.call()
	SimHold.publish(false, false)
	Props._p = snap
	return err


## Monsoon-like weather with a strong wind aloft, the aircraft in cold cloud (icing conditions).
static func _stormy() -> void:
	for k in Weather.DEFAULTS:
		Props.set_v("weather/" + k, Weather.DEFAULTS[k])
	for k in Session.WEATHER.Monsoon:
		Props.set_v("weather/" + k, Session.WEATHER.Monsoon[k])
	Props.set_v("weather/aloft_kt", 25.0)
	Props.set_v("weather/wind_table", [])
	Props.set_v("fdm/position_enu", Vector3(0.0, 0.0, 600.0))
	Props.set_v("fdm/agl_m", 600.0)
	Props.set_v("fdm/tas_mps", 60.0)
	Props.set_v("atmosphere/temperature_k", 263.15)
	Props.set_v("environment/ac_cloud_density", 1.0)
	Props.set_v("environment/cloud_kind", CloudField.CUMULUS)
	Props.set_v("weather/icing", 1.0)


func test_weather_drift_and_icing_hold_while_paused_or_replaying() -> String:
	return _guard(func():
		_stormy()
		var node := FdmNode.new()  # only its flags: _physics_process publishes them first; a crashed FDM then stops it
		node.fdm = FDM.new()
		node.fdm.damage.crashed = true
		var w := Weather.new()
		w._ready()
		var sky := SkyTime.new()
		var ice := Icing.new()
		ice.def = AircraftDef.load_def("c172")
		ice._ready()
		var run := func(n: int) -> void:
			for i in n:
				node._physics_process(DT)
				w._physics_process(DT)
				sky.advance_drift(DT)
				ice._physics_process(DT)
		run.call(120)
		var err := ""
		for flag in ["paused", "replaying"]:
			node.set(flag, true)
			var t0: float = w.cloud._t
			var d0: Vector2 = sky._drift
			var a0 := ice.airframe
			var w0: Vector3 = Props.get_v("environment/wind_ned")
			run.call(240)
			if not SimHold.active() or w.cloud._t != t0 or sky._drift != d0 or ice.airframe != a0 or Props.get_v("environment/wind_ned") != w0:
				err = "%s: hold %s, storm clock %.3f -> %.3f, drift %s -> %s, ice %.4f -> %.4f, wind %s -> %s" % [flag,
					SimHold.active(), t0, w.cloud._t, d0, sky._drift, a0, ice.airframe, w0, Props.get_v("environment/wind_ned")]
				break
			node.set(flag, false)
			run.call(120)
			if SimHold.active() or w.cloud._t <= t0 or sky._drift == d0 or ice.airframe <= a0:
				err = "%s cleared: the weather, drift and ice should move on again" % flag
				break
		w.free()
		sky.free()
		ice.free()
		node.free()
		return err)


func test_cloud_field_and_storm_cells_stay_put_across_a_load() -> String:
	return _guard(func():
		_stormy()
		var w := Weather.new()
		w._ready()
		var sky := SkyTime.new()
		for i in 240:
			w._physics_process(DT)
			sky.advance_drift(DT)
		# save: the Props a situation keeps, through JSON as on disk
		var saved := {}
		for pre in Situation.PROP_PREFIXES:
			var dump := Props.dump(pre)
			for k in dump:
				saved[k] = Situation._enc(dump[k])
		saved = JSON.parse_string(JSON.stringify(saved, "", false, true))
		var d0: Vector2 = sky._drift
		var t0: float = w.cloud._t
		for i in 1200:  # 10 s later the clouds and cells have moved on
			w._physics_process(DT)
			sky.advance_drift(DT)
		var moved := sky._drift.distance_to(d0)
		# load, as Situation.apply does: the saved Props back, then meta/situation bumped
		var props := {}
		for k in saved:
			props[k] = Situation._dec(saved[k])
		Props.restore(props)
		Props.set_v("meta/situation", int(Props.get_v("meta/situation", 0)) + 1)
		w._physics_process(DT)
		sky.advance_drift(DT)
		var back := sky._drift.distance_to(d0)
		var dt_clock: float = w.cloud._t - t0
		w.free()
		sky.free()
		print("    clouds moved %.0f m in 10 s; after the load %.2f m from the saved field, storm clock %+.3f s from the saved one" % [moved, back, dt_clock])
		if moved < 100.0:
			return "the cloud field should drift in a 25 kt wind (moved %.0f m)" % moved
		return "" if back < 0.5 and absf(dt_clock - DT) < 1e-6 else "after a load: drift %.1f m from the save, storm clock %+.3f s" % [back, dt_clock])
