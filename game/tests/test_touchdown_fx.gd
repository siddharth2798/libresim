extends Node
## Touchdown effects (world/touchdown_fx.gd): which wheel spins up (touchdown_detect.gd), the per-wheel 3D squeal
## (tyre_squeal.gd), the soft white tyre smoke (tyre_smoke.gd), and no rubber marks.

const CONTACTS := [
	{"name": "NOSE", "wheel": true, "role": "nose"},
	{"name": "LEFT_MAIN", "wheel": true, "role": "main"},
	{"name": "RIGHT_MAIN", "wheel": true, "role": "main"},
	{"name": "TAIL_SKID", "wheel": false, "role": "tail_skid"},
]

var _nodes: Array = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			for p in n.find_children("*", "AudioStreamPlayer3D", true, false):
				p.stop()
			n.free()
	_nodes.clear()


## gear.info for the wheels named in `on` touching (sink m/s, sideways m/s), the others in the air.
static func _info(on: Array, sink := 1.0, vlat := 0.0) -> Dictionary:
	var d := {}
	for c in CONTACTS:
		d[c.name] = {"depth": 0.02, "vz": sink, "vlat": vlat, "n": 0.0, "e": 0.0} if c.name in on else {"depth": 0.0}
	return d


static func _names(evs: Array) -> Array:
	var out: Array = evs.map(func(e): return e.wheel)
	out.sort()
	return out


## Ticks of 1/120 s with the given contact state; returns every event.
static func _run(det: TouchdownDetect, seconds: float, on: Array, gs: float, sink := 1.0, vlat := 0.0) -> Array:
	var out: Array = []
	for i in int(round(seconds * 120.0)):
		out.append_array(det.step(CONTACTS, _info(on, sink, vlat), Vector3(gs, 0, 0), 1.0 / 120.0))
	return out


func test_fx_first_touchdown_spins_up_each_main_once() -> String:
	var det := TouchdownDetect.new()
	_run(det, 0.5, [], 28.0)  # an air start: the wheels have never turned
	var evs := _run(det, 0.02, ["LEFT_MAIN", "RIGHT_MAIN"], 28.0)
	if _names(evs) != ["LEFT_MAIN", "RIGHT_MAIN"]:
		return "the two mains touching should give one event each, got %s" % [_names(evs)]
	if absf(float(evs[0].slip) - 28.0) > 0.01:
		return "a stopped tyre slides at the full ground speed (slip %.1f)" % evs[0].slip
	if not _run(det, 1.0, ["LEFT_MAIN", "RIGHT_MAIN"], 27.0).is_empty():
		return "rolling on gives no more events"
	if not _run(det, 0.5, ["LEFT_MAIN", "RIGHT_MAIN", "NOSE"], 26.0).is_empty():
		return "a straight nose-down does not squeal or smoke"
	return ""


func test_fx_short_hop_and_taxi_bump_stay_quiet() -> String:
	var det := TouchdownDetect.new()
	_run(det, 0.2, ["LEFT_MAIN", "RIGHT_MAIN", "NOSE"], 28.0)  # rolling (first seen on the ground: no event)
	_run(det, 0.4, ["NOSE"], 28.0)  # a 0.4 s hop of the mains (the old wow edge squealed here)
	if not _run(det, 0.1, ["LEFT_MAIN", "RIGHT_MAIN", "NOSE"], 28.0).is_empty():
		return "a tyre back down after a short hop is still turning: no event"
	_run(det, 0.3, [], 6.0)
	if not _run(det, 0.1, ["LEFT_MAIN", "RIGHT_MAIN", "NOSE"], 6.0).is_empty():
		return "a bump at taxi speed gives no event"
	_run(det, 30.0, [], 30.0)  # a circuit: the wheels have run down
	if _names(_run(det, 0.02, ["LEFT_MAIN", "RIGHT_MAIN"], 30.0)) != ["LEFT_MAIN", "RIGHT_MAIN"]:
		return "the next real touchdown spins the mains up again"
	return ""


func test_fx_nose_counts_only_sliding_sideways() -> String:
	var det := TouchdownDetect.new()
	_run(det, 2.0, [], 28.0)
	if _names(_run(det, 0.02, ["NOSE"], 28.0, 1.0, 2.0)) != ["NOSE"]:
		return "a nose wheel landing sideways (2 m/s) scrubs"
	if TouchdownDetect.spins_up("nose", 28.0, 28.0, 0.0, 2.0):
		return "a straight nose wheel does not"
	if not TouchdownDetect.spins_up("main", 28.0, 28.0, 0.0, 2.0) or TouchdownDetect.spins_up("main", 2.0, 28.0, 0.0, 2.0):
		return "a main wheel needs a speed difference at contact"
	return ""


func test_fx_squeal_and_smoke_scale_with_sink_and_slip() -> String:
	if TouchdownFx.puff(2.0, 1.0) != 0.0 or TyreSqueal.volume(1.0, 30.0) <= TyreSqueal.volume(0.2, 30.0):
		return "no smoke without slip; a firmer touchdown squeals louder"
	if not (TouchdownFx.puff(28.0, 2.4) > TouchdownFx.puff(15.0, 0.3) and TouchdownFx.puff(15.0, 0.3) > 0.0):
		return "smoke grows with slip and sink"
	if TyreSqueal.volume(0.3, 10.0) <= 0.1:
		return "a soft touchdown still chirps"
	return ""


func test_fx_smoke_is_soft_and_fades_out() -> String:
	var tex := TyreSmoke.texture().get_image()
	var n := tex.get_width()
	for i in n:
		for p in [Vector2i(i, 0), Vector2i(i, n - 1), Vector2i(0, i), Vector2i(n - 1, i)]:
			if tex.get_pixelv(p).a > 0.01:
				return "the puff texture must be clear at the quad edge (no visible squares): %s a=%.3f" % [p, tex.get_pixelv(p).a]
	if tex.get_pixel(n / 2, n / 2).a < 0.6:
		return "the puff has a dense middle"
	if TyreSmoke.alpha_at(0.0) != 0.0 or TyreSmoke.alpha_at(1.0) != 0.0 or TyreSmoke.alpha_at(0.03) < 0.2:
		return "a puff fades in, is dense, and is gone at the end of its life"
	var prev := 1.0
	for i in range(1, 21):
		var a := TyreSmoke.alpha_at(0.03 + 0.97 * i / 20.0)
		if a > prev + 1e-4:
			return "after its peak a puff only thins (life %.2f)" % (0.03 + 0.97 * i / 20.0)
		prev = a
	var m := TyreSmoke._material()
	if not m.billboard_keep_scale or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return "puffs keep their particle scale (else all are 1 m) and are lit by the scene (no glow at night)"
	var big := TyreSmoke.shape(1.0, 1.34, 70.0)
	var small := TyreSmoke.shape(0.3, 0.2, 28.0)
	if big.size <= small.size or big.amount <= small.amount or small.lifetime < 3.0:
		return "a hard airliner touchdown throws more and bigger smoke; it lasts a few seconds"
	return ""


func test_fx_takeoff_roll_and_liftoff_stay_quiet() -> String:
	var det := TouchdownDetect.new()
	var evs: Array = []
	var all := ["LEFT_MAIN", "RIGHT_MAIN", "NOSE"]
	for i in 30 * 120:  # 30 s: accelerate to 30 m/s, an oleo flicker of the mains, rotate, lift off, climb
		var t := i / 120.0
		var gs := minf(t * 1.5, 30.0)
		var on: Array = all
		if t > 12.0 and t < 12.08:
			on = ["NOSE"]  # the mains unload for a moment on a bump
		if t > 19.0:
			on = ["LEFT_MAIN", "RIGHT_MAIN"]  # rotation: nose up
		if t > 21.0:
			on = []  # liftoff
		evs.append_array(det.step(CONTACTS, _info(on, -0.3 if t > 20.5 else 0.0), Vector3(gs, 0, 0), 1.0 / 120.0))
	if not evs.is_empty():
		return "a takeoff roll, rotation and liftoff must not smoke or squeal: %s" % [_names(evs)]
	det.clear()  # a restart / a flight placed on the ground at a stand: the tyres settle onto the ground
	_run(det, 0.05, [], 0.0)
	if not _run(det, 1.0, all, 0.0).is_empty():
		return "settling on the gear at rest is not a touchdown"
	det.clear()  # a flight loaded on the runway at speed
	if not _run(det, 1.0, all, 25.0, 0.0).is_empty():
		return "a flight loaded rolling on the ground is not a touchdown"
	return ""


## The real C172 FDM from brake release to 5 s after liftoff, through TouchdownFx: no squeal and no smoke.
func test_fx_c172_takeoff_has_no_smoke_or_squeal() -> String:
	var def := AircraftDef.load_def("c172")
	var fn := FdmNode.new()
	fn.fdm = FDM.new(def)
	_nodes.append(fn)
	var f := fn.fdm
	f.set_on_ground(0.0, 0.0, 0.0)
	f.fcs.flap_cmd = 1
	f.prop.rpm = 2300.0
	f.engine.throttle = 1.0
	var fx := TouchdownFx.new()
	add_child(fx)
	_nodes.append(fx)
	fx.setup(fn, def)
	fx.set_physics_process(false)
	fx.smoke.set_physics_process(false)
	var dt := 1.0 / 120.0
	var air_t := 0.0
	for i in 60 * 120:
		f.fcs.yaw = clampf(-3.0 * f.euler().z if f.euler().z < PI else 3.0 * (TAU - f.euler().z), -1, 1)
		f.fcs.pitch = 0.6 if f.cas > 51.0 * 0.514444 else 0.0
		for s in 2:
			f.step(dt / 2.0)
		fx._physics_process(dt)
		fx.smoke._physics_process(dt)
		air_t = air_t + dt if not f.gear.wow else 0.0
		if air_t > 5.0:
			break
	if air_t <= 5.0:
		return "the C172 never got airborne for 5 s"
	if fx.squeal.find_children("*", "AudioStreamPlayer3D", false, false).any(func(p): return p.playing):
		return "no squeal on a takeoff"
	if fx.smoke.find_children("*", "CPUParticles3D", false, false).any(func(p): return p.emitting):
		return "no tyre smoke on a takeoff"
	return ""


## The real C172 FDM dropped onto a runway: each main squeals once from its own wheel, the smoke starts, and no
## Decal (rubber mark) is made. The old code made two Decals and had no per-wheel squeal.
func test_fx_c172_touchdown_squeals_per_wheel_without_marks() -> String:
	var def := AircraftDef.load_def("c172")
	var fn := FdmNode.new()
	fn.fdm = FDM.new(def)
	_nodes.append(fn)
	var fd := fn.fdm
	fd.set_on_ground(0.0, 0.0, 0.0)
	fd.q = FDM.euler_to_quat(0.0, deg_to_rad(8.0), 0.0)
	var low := -INF
	for c in fd.gear.contacts:
		if c.wheel:
			low = maxf(low, (Basis(fd.q) * fd.mb.body_of(c.pos)).z)
	fd.pos_d = -low - 1.2
	fd.v_b = Basis(fd.q).transposed() * Vector3(28.0, 0.0, 1.5)
	var fx := TouchdownFx.new()
	add_child(fx)
	_nodes.append(fx)
	fx.setup(fn, def)
	fx.set_physics_process(false)
	fx.smoke.set_physics_process(false)
	var dt := 1.0 / 120.0
	var plays := {}
	var near := {}
	for i in 240:
		for s in 2:
			fd.step(dt / 2.0)
		fx._physics_process(dt)
		fx.smoke._physics_process(dt)
		for p in fx.squeal.find_children("*", "AudioStreamPlayer3D", false, false):
			if p.playing and not near.has(p):
				near[p] = true
				var w: String = fx.squeal._players.find_key(p)
				plays[w] = int(plays.get(w, 0)) + 1
				var d := (p as AudioStreamPlayer3D).global_position.distance_to(fx.squeal.wheel_render(w))
				if d > 0.6 or p.bus != "Environment":
					return "the %s squeal must be at that wheel on the Environment bus (%.2f m, %s)" % [w, d, p.bus]
			elif not p.playing:
				near.erase(p)
	var keys := plays.keys()
	keys.sort()
	if keys != ["LEFT_MAIN", "RIGHT_MAIN"] or plays.values().any(func(v): return v != 1):
		return "each main squeals once and the nose not at all: %s" % [plays]
	if not fx.find_children("*", "Decal", true, false).is_empty():
		return "no rubber marks are drawn"
	if not fx.smoke.find_children("*", "CPUParticles3D", false, false).any(func(p): return p.emitting):
		return "the tyres smoke"
	if load("res://aircraft/common/aircraft_audio.gd").get_script_constant_map().get("BUS", {}).has("squeal"):
		return "the old non-positional squeal in AircraftAudio is gone"
	return ""
