class_name CameraMotion
extends RefCounted
## Chase-camera lag and the cockpit seat dip. Kept off CameraRig so that script stays under 300 lines.


## One chase-camera step. `back` is the aircraft's horizontal aft direction; the smoothed copy eases toward it at
## `follow` 1/s (cornering lag). The extra distance is ground speed / follow, eased over about a second, so a speed
## change or a long frame does not zoom the picture. A zero smoothed direction snaps to `back`.
static func chase_step(back_s: Vector3, trail: float, back: Vector3, speed: float, follow: float, dt: float) -> Dictionary:
	var k := 1.0 - exp(-maxf(follow, 0.0) * maxf(dt, 0.0))
	var b := back
	if back_s.length() > 0.1:
		b = back_s.lerp(back, k)
		b = b.normalized() if b.length() > 0.1 else back
	var target := 0.0 if follow <= 0.0 else speed / follow
	var trail_k := 1.0 - exp(-maxf(dt, 0.0) / 1.2)
	return {"back": b, "trail": lerpf(trail, target, trail_k)}


## One step of the cockpit eye. It sags a few centimetres when the vertical load rises and eases back,
## so the touchdown is a dip rather than the picture stopping dead. Returns [offset m, rate m/s].
static func seat_step(offset: float, vel: float, nz: float, dt: float) -> Vector2:
	var target := clampf((1.0 - nz) * 0.028, -0.04, 0.015)
	var acc := (target - offset) * 55.0 - vel * 8.0
	vel += acc * dt
	offset = clampf(offset + vel * dt, -0.045, 0.02)
	return Vector2(offset, vel)
