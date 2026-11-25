extends RefCounted
## Tick rates (core/tick_rate.gd, docs/USAGE.md "Tick rates"): the accumulator itself, the list of which script runs at which
## rate (a new _physics_process script must be classified here), and the systems whose timing is visible: failure trips,
## icing, replay recording. The twin tests run a node at the old 120 Hz (its `_tick` replaced by TickRate.new(120.0), a call every
## physics tick as before the change) and at its new rate, fed the same Props, and compare the outputs with stated tolerances.
## More twins: tests/test_tick_systems.gd (power, fuel, hydraulics) and tests/test_tick_instruments.gd (gauges, radios, GPS).

const I := preload("res://tests/test_icing.gd")
const DT := 1.0 / 120.0

## Every script under game/ (not tests/) with a _physics_process, and its rate in Hz: 120 = every tick, as before.
const RATES := {
	"res://fdm/fdm_node.gd": 120.0, "res://systems/autoflight.gd": 120.0, "res://world/weather.gd": 120.0,
	"res://world/ground_ops.gd": 120.0, "res://world/touchdown_fx.gd": 120.0, "res://world/tyre_smoke.gd": 120.0,
	"res://avionics/gps.gd": 30.0, "res://avionics/nav_radios.gd": 30.0, "res://instruments/adirs.gd": 30.0,
	"res://instruments/air_data_instruments.gd": 30.0, "res://instruments/airliner_air_data.gd": 30.0,
	"res://instruments/airliner_engines.gd": 30.0, "res://instruments/engine_instruments.gd": 30.0,
	"res://instruments/gyro_instruments.gd": 30.0, "res://instruments/magnetic_compass.gd": 30.0,
	"res://instruments/nd_feed.gd": 2.0, "res://systems/airliner_cabin.gd": 30.0, "res://systems/airliner_electrical.gd": 60.0,
	"res://systems/airliner_fuel.gd": 60.0, "res://systems/airliner_hydraulics.gd": 60.0, "res://systems/airliner_lights.gd": 30.0,
	"res://systems/airliner_warnings.gd": 2.0, "res://systems/apu.gd": 60.0, "res://systems/electrical.gd": 60.0,
	"res://systems/failure_manager.gd": 30.0, "res://systems/fuel.gd": 60.0, "res://systems/icing.gd": 60.0,
	"res://systems/pitot_static.gd": 30.0, "res://systems/replay.gd": 60.0, "res://systems/vacuum.gd": 30.0,
	"res://training/training_session.gd": 30.0,
}


func test_tick_accumulator_runs_at_the_rate_with_true_dt() -> String:
	for hz in [120.0, 60.0, 30.0, 20.0, 45.0]:
		var t := TickRate.new(hz)
		var runs := 0
		var total := 0.0
		var longest := 0.0
		var first := -1.0
		for i in 1200:  # 10 s of 120 Hz ticks
			var h := t.step(DT)
			if h > 0.0:
				runs += 1
				total += h
				longest = maxf(longest, h)
				if first < 0.0:
					first = h
		var want: float = hz * 10.0
		if absf(runs - want) > want * 0.1 + 1.0:  # 45 Hz is 2.67 ticks: runs every 2nd or 3rd tick, the average stays close
			return "%.0f Hz: %d runs in 10 s, expected about %.0f" % [hz, runs, want]
		if absf(total - 10.0) > 1.0 / hz + 1e-6:  # the time handed out is the time fed (less what waits for the next run)
			return "%.0f Hz: handed out %.4f s of 10 s" % [hz, total]
		if longest > 1.0 / hz + DT + 1e-6:
			return "%.0f Hz: one run covered %.4f s" % [hz, longest]
		if absf(first - DT) > 1e-9:
			return "%.0f Hz: the first call must run at once with its own dt, got %.5f" % [hz, first]
	var t2 := TickRate.new(30.0)
	t2.step(DT)
	if t2.step(DT) != 0.0:
		return "second tick at 30 Hz ran"
	t2.due_now()
	if absf(t2.step(DT) - 2.0 * DT) > 1e-9:
		return "due_now: the next call must run with the 2 ticks since the last run"
	var slow := TickRate.new(30.0)
	for k in 3:  # a dt longer than the period (tests call with 0.1 s): every call runs, with that dt
		if absf(slow.step(0.1) - 0.1) > 1e-9:
			return "dt 0.1 at 30 Hz must run on every call with 0.1 s"
	return ""


func test_tick_is_deterministic() -> String:
	var a := TickRate.new(30.0)
	var b := TickRate.new(30.0)
	for i in 5000:
		var dt := DT * (1.0 + 0.0 * i)
		if a.step(dt) != b.step(dt):
			return "two accumulators fed the same ticks disagree at tick %d" % i
	return ""


func test_every_physics_script_has_a_declared_rate() -> String:
	var found: Dictionary = {}
	_scan("res://", found)
	for p in found:
		if not RATES.has(p):
			return "%s has a _physics_process and no entry in RATES (tick rates: pick 120 / 60 / 30 Hz and add it to docs/USAGE.md)" % p
	for p in RATES:
		if not found.has(p):
			return "%s is listed in RATES but has no _physics_process" % p
		var src := FileAccess.get_file_as_string(p)
		var hz: float = RATES[p]
		if hz >= 120.0:
			if "TickRate" in src:
				return "%s runs at 120 Hz but uses TickRate" % p
			continue
		var m := RegEx.create_from_string("const TICK_HZ := ([0-9.]+)").search(src)
		if m != null:
			if absf(float(m.get_string(1)) - hz) > 1e-6:
				return "%s: TICK_HZ %s, RATES says %.0f" % [p, m.get_string(1), hz]
			if not "TickRate.new(TICK_HZ)" in src:
				return "%s declares TICK_HZ but does not use it" % p
		elif hz > 2.0 or not ("PERIOD" in src):  # the two 2 Hz scripts keep their own half-second timer
			return "%s: no TICK_HZ constant" % p
	return ""


func _scan(dir: String, out: Dictionary) -> void:
	for d in DirAccess.get_directories_at(dir):
		if d in ["tests", "addons", ".godot", "ui", "tools"] and dir == "res://":
			continue
		_scan(dir + d + "/", out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and "\nfunc _physics_process" in FileAccess.get_file_as_string(dir + f):
			out[dir + f] = true


func _twin(cls: GDScript) -> Array:
	var ref: Node = cls.new()
	var now: Node = cls.new()
	ref._tick = TickRate.new(120.0)
	return [ref, now]


func test_tick_failure_trips_come_within_one_tick() -> String:
	var fdm_node := FdmNode.new()
	fdm_node.fdm = FDM.new()
	var snap: Dictionary = Props._p.duplicate(true)
	var err := ""
	var trips := []
	for pair in [[2, 6.0 / 60.0], [3, 150.0], [4, 60.0]]:  # 6 s after the start, through 150 ft AGL, above 60 kt
		var tw := _twin(FailureManager)
		var at := []
		for k in 2:
			var fm: FailureManager = tw[k]
			fm.fdm_node = fdm_node
			fm.armed = [{"id": "flaps", "mode": pair[0], "value": pair[1], "random": false}]
			Props.set_v("failures/flaps", false)
			Props.set_v("fdm/wow", false)
			var t := 0.0
			var tripped := -1.0
			for i in 2400:  # 20 s: climb 20 ft/s (6 m/s), accelerate 5 kt/s
				t += DT
				Props.set_v("fdm/agl_m", 6.0 * t)
				Props.set_v("fdm/cas_mps", 5.0 * Units.KT * t)
				fm._physics_process(DT)
				if tripped < 0.0 and Props.get_b("failures/flaps"):
					tripped = t
			at.append(tripped)
			fm.free()
		trips.append(at)
		if at[0] < 0.0 or absf(at[0] - at[1]) > 1.0 / 30.0 + 1e-6:
			err = "mode %d: tripped at %.3f s at 120 Hz, %.3f s at 30 Hz (more than one 30 Hz tick apart)" % [pair[0], at[0], at[1]]
			break
	Props._p = snap
	fdm_node.free()
	print("    failure trips (120 Hz vs 30 Hz): time %s, altitude %s, speed %s" % [trips[0], trips[1], trips[2]])
	return err


func test_tick_icing_accretion_and_pitot_block_match() -> String:
	return I._guard(func():
		Props.set_v("controls/electrical/pitot_heat", false)
		var tw := _twin(Icing)
		var res := []
		for k in 2:
			var ic: Icing = tw[k]
			ic.def = AircraftDef.load_def("c172")
			ic._ready()
			var blocked := -1.0
			for i in int(240.0 / DT):  # 4 min in cold dense cloud
				ic._physics_process(DT)
				if blocked < 0.0 and Props.get_b("icing/pitot_blocked"):
					blocked = i * DT
			res.append([ic.airframe, ic.pitot, blocked])
			ic.free()
		print("    icing after 4 min (120 Hz / 60 Hz): airframe %.4f / %.4f, probe %.4f / %.4f, pitot blocked at %.3f / %.3f s" % [
			res[0][0], res[1][0], res[0][1], res[1][1], res[0][2], res[1][2]])
		if absf(res[0][0] - res[1][0]) > 0.002 or absf(res[0][1] - res[1][1]) > 0.002:
			return "ice level drifts: airframe %.4f vs %.4f, probe %.4f vs %.4f" % [res[0][0], res[1][0], res[0][1], res[1][1]]
		if res[0][2] < 0.0 or absf(res[0][2] - res[1][2]) > 1.0 / 60.0 + 1e-6:
			return "pitot block time %.3f vs %.3f s" % [res[0][2], res[1][2]]
		return "")


func test_tick_replay_records_the_same_frames() -> String:
	var fdm_node := FdmNode.new()
	fdm_node.fdm = FDM.new()
	fdm_node.fdm.set_airborne(0.0, 0.0, 800.0, 0.0, 40.0)
	var tw := _twin(Replay)
	for r in tw:
		r.setup(fdm_node)
	var f := fdm_node.fdm
	for i in int(20.0 / DT):  # 20 s, the aircraft moving 40 m/s east so every frame has its own position
		f.pos_e += 40.0 * DT
		for r in tw:
			r._physics_process(DT)
	var a: ReplayBuffer = tw[0].buffer
	var b: ReplayBuffer = tw[1].buffer
	var sa := a.sample(10.0)
	var sb := b.sample(10.0)
	print("    replay 20 s (120 Hz / 60 Hz): %d / %d frames, end %.3f / %.3f s, position at 10 s %.2f / %.2f m" % [
		a.size(), b.size(), a.end_time(), b.end_time(), sa.pos[0], sb.pos[0]])
	for r in tw:
		r.free()
	fdm_node.free()
	if absi(a.size() - b.size()) > 1:
		return "frames %d vs %d: the 60 Hz recorder must still sample at 20 Hz" % [a.size(), b.size()]
	if absf(a.end_time() - b.end_time()) > 0.05 + 1e-6:
		return "recording ends at %.3f vs %.3f s" % [a.end_time(), b.end_time()]
	if absf(sa.pos[0] - sb.pos[0]) > 0.05 * 40.0 / 2.0:
		return "position at 10 s: %.2f vs %.2f m" % [sa.pos[0], sb.pos[0]]
	return ""
