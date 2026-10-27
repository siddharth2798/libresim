class_name Atmosphere
extends RefCounted
## Single-scattering sky (Rayleigh + Mie + ozone) on a spherical planet with exponential
## density, the CPU twin of atmo_sky() in world/sky_clouds.gdshader (keep both in step: same
## constants, same sample layout). SkyTime samples it for the fog / haze colour so terrain,
## trees and buildings fade into the same colour as the sky behind them, at every time of day.
## Directions are in the render frame (y up); only the angle to the vertical and to the sun
## matter. Results are linear colours. No allocation-heavy work: ~40 samples, cached by SkyTime.

const RE := 6371000.0
const TOP := 60000.0  # atmosphere height
const D_TOP := 2.0 * RE * TOP + TOP * TOP  # r_top^2 - RE^2
const HR := 8000.0  # Rayleigh scale height
const HM := 1200.0  # Mie (aerosol) scale height
const OBS_H := 300.0
const CAP := 80000.0  # view rays are integrated to 80 km: the haze colour, not the far limb
const BETA_R := Vector3(5.8e-6, 13.5e-6, 33.1e-6)  # per metre at sea level, R G B
const BETA_O := Vector3(0.65e-6, 1.881e-6, 0.085e-6) * 1.5  # ozone absorption
const BETA_M := 21e-6 * 0.1  # aerosol scattering at aerosol = 1 (clear Indian air); extinction = / 0.9
const SUN_E := 30.0
const NV := 8
const NS := 4


static func _vexp(v: Vector3) -> Vector3:
	return Vector3(exp(v.x), exp(v.y), exp(v.z))


static func _height(a: float) -> float:
	return a / (sqrt(a + RE * RE) + RE)  # a = r^2 - RE^2, no cancellation


static func _ext(h: float, bm: float) -> Vector3:
	var oz := maxf(1.0 - absf(h - 25000.0) / 15000.0, 0.0)
	return BETA_R * exp(-h / HR) + Vector3.ONE * (bm / 0.9 * exp(-h / HM)) + BETA_O * oz


## Aerosol amount for a meteorological visibility (m): 1 at 25 km, whiter and hazier below.
static func aerosol_for_visibility(vis_m: float) -> float:
	return clampf(25000.0 / maxf(vis_m, 500.0), 0.5, 10.0)


## Brightness after sunset: the model keeps the sun on the horizon (the glow and the long-path
## colours of dusk) and fades it: 1 above the horizon, 0.3 at -6 deg (civil twilight), gone by
## -12 deg where the night sky takes over.
static func twilight_gain(el_deg: float) -> float:
	var depr := maxf(-el_deg, 0.0)
	return exp(-depr / 5.0) * (1.0 - smoothstep(6.0, 12.0, depr))


## Sky colour (linear) towards dir with the sun at `sun` (both unit, render frame, y up).
static func sky(dir: Vector3, sun_in: Vector3, aerosol: float, gain: float) -> Color:
	var sun := Vector3(sun_in.x, maxf(sun_in.y, 0.0), sun_in.z).normalized()  # below the horizon: on it
	var d := Vector3(dir.x, maxf(dir.y, 0.0), dir.z).normalized()
	var bm := BETA_M * aerosol
	var r0 := RE + OBS_H
	var a0 := 2.0 * RE * OBS_H + OBS_H * OBS_H
	var b0 := r0 * d.y
	var tm := minf(-b0 + sqrt(maxf(b0 * b0 - (a0 - D_TOP), 0.0)), CAP)
	var cg := d.dot(sun)
	var ph_r := 3.0 / (16.0 * PI) * (1.0 + cg * cg)
	const G := 0.76
	var ph_m := 3.0 / (8.0 * PI) * ((1.0 - G * G) * (1.0 + cg * cg)) / ((2.0 + G * G) * pow(1.0 + G * G - 2.0 * G * cg, 1.5))
	var tv := Vector3.ZERO
	var sr := Vector3.ZERO
	var sm := Vector3.ZERO
	for i in NV:
		var u0 := pow(float(i) / NV, 2.0)
		var u1 := pow(float(i + 1) / NV, 2.0)
		var t := tm * (u0 + u1) * 0.5
		var dt := tm * (u1 - u0)
		var a := a0 + 2.0 * b0 * t + t * t
		var h := _height(a)
		var rr := exp(-h / HR)
		var rm := exp(-h / HM)
		tv += _ext(h, bm) * dt
		var ps := r0 * sun.y + t * cg  # P . sun
		if ps < 0.0 and a < ps * ps:
			continue  # the planet shadows this sample
		var ts := -ps + sqrt(maxf(ps * ps - (a - D_TOP), 0.0))
		var tsun := Vector3.ZERO
		for j in NS:
			var v0 := pow(float(j) / NS, 2.0)
			var v1 := pow(float(j + 1) / NS, 2.0)
			var q := ts * (v0 + v1) * 0.5
			var aq := maxf(a + 2.0 * ps * q + q * q, 0.0)
			tsun += _ext(_height(aq), bm) * (ts * (v1 - v0))
		var tr := _vexp(-(tv + tsun))
		sr += tr * (rr * dt)
		sm += tr * (rm * dt)
	var l := (sr * BETA_R * ph_r + sm * (bm * ph_m)) * SUN_E * gain
	return _finish(l, d.y)


## Saturation and exposure shaping shared with the shader: deeper blue overhead, paler and
## dimmer at the horizon (stands in for multiple scattering and the sRGB gamut).
static func _finish(l: Vector3, y: float) -> Color:
	var s := sqrt(clampf(y, 0.0, 1.0))
	var sat := lerpf(0.8, 1.35, s)
	var k := lerpf(0.55, 0.72, s)
	var luma := l.dot(Vector3(0.2126, 0.7152, 0.0722))
	var c := (Vector3.ONE * luma + (l - Vector3.ONE * luma) * sat) * k
	return Color(maxf(c.x, 0.0), maxf(c.y, 0.0), maxf(c.z, 0.0))


## Colour of the direct sun (linear, brightest channel 1) after the atmosphere: white-yellow high
## up, orange at 8 deg, deep red-orange at the horizon. Softened (^0.5) so the lit world keeps its colours.
static func sun_color(el_deg: float) -> Color:
	var el := deg_to_rad(maxf(el_deg, -0.5))
	var s := Vector3(0.0, sin(el), cos(el))
	var r0 := RE + OBS_H
	var a0 := 2.0 * RE * OBS_H + OBS_H * OBS_H
	var ps := r0 * s.y
	var ts := -ps + sqrt(maxf(ps * ps - (a0 - D_TOP), 0.0))
	var tau := Vector3.ZERO
	const N := 8
	for j in N:
		var v0 := pow(float(j) / N, 2.0)
		var v1 := pow(float(j + 1) / N, 2.0)
		var q := ts * (v0 + v1) * 0.5
		tau += _ext(_height(maxf(a0 + 2.0 * ps * q + q * q, 0.0)), BETA_M) * (ts * (v1 - v0))
	var t := _vexp(-tau)
	var m := maxf(t.x, maxf(t.y, t.z))
	return Color(pow(t.x / m, 0.5), pow(t.y / m, 0.5), pow(t.z / m, 0.5))
