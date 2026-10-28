class_name AirSpeeds
extends RefCounted
## Airliner speed markers for the PFD tape (pure functions, SI in / kt out): Vls (lowest selectable
## speed), Vsw (stall warning) and Vmax (the lowest of Vmo, the Mmo speed, Vfe for the flap / slat
## setting and Vle with the gear down). Public rules of thumb, scaled from a reference mass:
## Vs1g ~ sqrt(mass / ref_mass), Vls = vls_k * Vs1g, Vsw = vsw_k * Vs1g. Tables are keyed by the high-lift
## extension index = slat_deg + flap_deg (0 clean ... ~62 full). Per aircraft in aircraft.json
## "limits.speeds" (any key may be omitted, the defaults are an A320-class 64 t twin-jet):
##   ref_mass_kg, vs1g_kt [[ext, kt]], vls_k, vsw_k, vmo_kt, mmo, vfe_kt [[ext, kt]], vle_kt

const DEFAULTS := {
	"ref_mass_kg": 64000.0,
	"vs1g_kt": [[0.0, 134.0], [18.0, 121.0], [28.0, 116.0], [37.0, 112.0], [42.0, 109.0], [62.0, 105.0]],
	"vls_k": 1.23, "vsw_k": 1.04,
	"vmo_kt": 350.0, "mmo": 0.82,
	"vfe_kt": [[0.0, 350.0], [18.0, 230.0], [28.0, 215.0], [37.0, 200.0], [42.0, 185.0], [62.0, 177.0]],
	"vle_kt": 280.0,
}


## `spec` over the defaults.
static func spec_of(limits_speeds: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate(true)
	for k in limits_speeds:
		s[k] = limits_speeds[k]
	return s


## Piecewise-linear lookup in [[x, y], ...] (sorted by x), clamped at the ends.
static func table(rows: Array, x: float) -> float:
	if x <= rows[0][0]:
		return float(rows[0][1])
	for i in range(1, rows.size()):
		if x <= rows[i][0]:
			var t: float = (x - rows[i - 1][0]) / (rows[i][0] - rows[i - 1][0])
			return lerpf(rows[i - 1][1], rows[i][1], t)
	return float(rows[-1][1])


## CAS (kt) at Mach `m` for static pressure `p_pa` (the Mmo speed).
static func cas_kt_at_mach(m: float, p_pa: float) -> float:
	var qc := p_pa * (pow(1.0 + 0.2 * m * m, 3.5) - 1.0)
	return Units.mps_to_kt(AtmosphereISA.cas_from_qc(qc))


## {vls, vsw, vmax} in kt.
static func markers(spec: Dictionary, mass_kg: float, ext_deg: float, gear_down: bool, p_pa: float) -> Dictionary:
	var vs1g := table(spec.vs1g_kt, ext_deg) * sqrt(maxf(mass_kg, 1.0) / float(spec.ref_mass_kg))
	var vmax := minf(float(spec.vmo_kt), table(spec.vfe_kt, ext_deg))
	if p_pa > 1000.0:
		vmax = minf(vmax, cas_kt_at_mach(float(spec.mmo), p_pa))
	if gear_down:
		vmax = minf(vmax, float(spec.vle_kt))
	return {"vls": vs1g * float(spec.vls_k), "vsw": vs1g * float(spec.vsw_k), "vmax": vmax}


## Speed trend: the speed in `seconds` if the acceleration (kt/s) persisted, limited to +-`limit` kt.
static func trend_kt(accel_kt_s: float, seconds := 10.0, limit := 40.0) -> float:
	return clampf(accel_kt_s * seconds, -limit, limit)
