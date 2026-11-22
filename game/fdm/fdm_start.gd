class_name FdmStart
extends RefCounted
## Start-up helpers for FDM, split out of fdm.gd to keep it under 300 lines: trim at a calibrated airspeed, and the
## resting attitude on the ground with every wheel touching.


## Trim for level flight at a calibrated airspeed (iterates TAS; atmosphere and wind as set).
static func trim_level_cas(f: FDM, cas_target: float) -> void:
	var tas := cas_target
	for i in 3:
		f.trim_level(tas)
		f.step(1e-4)
		tas *= cas_target / maxf(f.cas, 1.0)
		f.set_airborne(f.pos_n, f.pos_e, -f.pos_d, f.euler().z, tas)
	f.trim_level(tas)


## Start at rest on the ground in the natural sitting attitude (all wheels touching).
static func on_ground(f: FDM, n: float, e: float, heading: float) -> void:
	f.pos_n = n; f.pos_e = e
	var wheels: Array = f.gear.contacts.filter(func(c): return c.wheel)
	var steered: Array = f.gear.steered_wheels()
	var mains: Array = f.gear.main_wheels()
	if steered.is_empty() or mains.is_empty():  # a castoring wheel or a single gear line: lie level
		steered = [wheels[0]]
		mains = [wheels[-1]]
	var bn := f.mb.body_of(steered[0].pos)
	var bm := Vector3.ZERO
	for c in mains:
		bm += f.mb.body_of(c.pos) / mains.size()
	# sit with both wheel lines at the same height: dz * cos(pitch) = dx * sin(pitch) (nose or tailwheel)
	var pitch := atan((bn.z - bm.z) / (bn.x - bm.x)) if absf(bn.x - bm.x) > 1e-3 else 0.0
	f.q = FDM.euler_to_quat(0.0, pitch, heading)
	var r_bn := Basis(f.q)
	var low := -INF
	for c in wheels:
		low = maxf(low, (r_bn * f.mb.body_of(c.pos)).z)
	f.pos_d = -f.ground_height.call(n, e) - low + 0.005
	f.v_b = Vector3.ZERO
	f.w_b = Vector3.ZERO
	f.fcs.settle()
	f.fcs.restart_law()
