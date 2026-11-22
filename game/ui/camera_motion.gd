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


## The cockpit eye in the aircraft frame: the mouse-look offset on the -0.12 rad rest pitch, raised by the seat dip.
## Zoomed in, the dip shrinks with the field of view (full at 70 deg and wider). A 2 mm head movement would otherwise
## sweep a 15 deg view of the overhead by about 10 px, a bob the eye does not see while it studies one panel.
static func cockpit_eye(eye: Vector3, look: Vector2, seat: float, fov_deg: float) -> Transform3D:
	var k := clampf(fov_deg / 70.0, 0.0, 1.0)
	return Transform3D(Basis.from_euler(Vector3(look.y - 0.12, look.x, 0.0)), eye + Vector3.UP * seat * k)
