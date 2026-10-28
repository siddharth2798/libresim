class_name Trim
## Steady level-flight trim: Newton iteration on (alpha, pitch trim, throttle)
## so that u_dot, w_dot and q_dot are ~0 at the given TAS, wings level.
## Accelerations are measured by taking one tiny step from a reset state.


static func _accel(f: FDM, x: Vector3, tas: float, hdg: float, base: Array) -> Vector3:
	f.pos_n = base[0]; f.pos_e = base[1]; f.pos_d = base[2]
	f.q = FDM.euler_to_quat(0.0, x.x, hdg)  # gamma = 0 -> theta = alpha
	f.v_b = _v_body(f, tas, x.x)
	f.w_b = Vector3.ZERO
	f.fcs.pitch_trim = x.y
	f.fcs.pitch = 0.0
	f.fcs.settle()
	f.set_throttle(x.z)
	f._alpha_prev = x.x
	# settle propeller RPM for this throttle/airspeed
	f.atmo.update(-f.pos_d)
	for i in 300:
		for u in f.units:
			u.update(0.01, f.atmo, tas * cos(x.x), tas)
	var v0 := f.v_b
	var w0 := f.w_b
	var dt := 1e-3
	f.step(dt)
	return Vector3((f.v_b.x - v0.x) / dt, (f.v_b.z - v0.z) / dt, (f.w_b.y - w0.y) / dt * 5.0)


static func trim_level(f: FDM, tas: float) -> void:
	var base := [f.pos_n, f.pos_e, f.pos_d]
	var hdg := f.euler().z
	var x := Vector3(0.05, 0.0, 0.6)
	var steps := Vector3(0.002, 0.01, 0.01)
	for it in 12:
		var r := _accel(f, x, tas, hdg, base)
		if r.length() < 0.01:
			break
		var j := Basis()
		var cols: Array[Vector3] = []
		for k in 3:
			var xp := x
			xp[k] += steps[k]
			cols.append((_accel(f, xp, tas, hdg, base) - r) / steps[k])
		j = Basis(cols[0], cols[1], cols[2])
		if absf(j.determinant()) < 1e-9:
			break
		var dx := j.inverse() * (-r)
		x += dx.limit_length(0.3)
		x = Vector3(clampf(x.x, -0.1, 0.3), clampf(x.y, -1.0, 1.0), clampf(x.z, 0.05, 1.0))
	_accel(f, x, tas, hdg, base)  # leave the aircraft in the trimmed state
	f.pos_n = base[0]; f.pos_e = base[1]; f.pos_d = base[2]
	f.q = FDM.euler_to_quat(0.0, x.x, hdg)
	f.v_b = _v_body(f, tas, x.x)
	f.w_b = Vector3.ZERO
	f.time = 0.0


## Body velocity over the ground for air-relative TAS at alpha (no sideslip; crabs into wind).
static func _v_body(f: FDM, tas: float, alpha: float) -> Vector3:
	return Vector3(tas * cos(alpha), 0.0, tas * sin(alpha)) + Basis(f.q).transposed() * f.wind_ned
