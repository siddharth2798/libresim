class_name FlapSpeeds
extends RefCounted
## Flap limit speeds (VFE) from aircraft.json "limits" (pure functions). Used by the damage model (fdm/damage.gd) and
## the round airspeed indicator's red flap marks (ui/gauges/asi_gauge.gd); the airliner PFD tape uses the same table
## through instruments/airliner_air_data.gd.
## limits.vfe_kias [[deg, KIAS], ...] with limits.vfe_by:
##   "flap" (default): keyed by flap deg, in steps: the first row whose angle is not exceeded (C172: 110 up to 10 deg,
##     85 beyond, as the POH gives them).
##   "slat_flap": keyed by slat + flap deg, one row per lever detent, blended between detents (A320), so a surface
##     on its way in has a limit between the two detents' VFE, the same Vmax the PFD shows.


## VFE (KIAS) at high-lift angle `ext` (flap deg, or slat + flap deg).
static func vfe(limits: Dictionary, ext: float) -> float:
	var rows: Array = limits.vfe_kias
	if str(limits.get("vfe_by", "flap")) == "slat_flap":
		return AirSpeeds.table(rows, ext)
	for row in rows:
		if ext <= float(row[0]):
			return float(row[1])
	return float(rows[-1][1])


## The VFE of each flap detent past 0 (detent flap angles `degs`), detents with the same VFE merged:
## [[kt, label], ...] fastest first; label "10°", or "20-30°" for a merged run.
static func marks(limits: Dictionary, degs: Array) -> Array:
	var out := []
	for d in degs:
		var deg := float(d)
		if deg <= 0.0:
			continue
		var kt := vfe(limits, deg)
		if not out.is_empty() and is_equal_approx(float(out[-1][0]), kt):
			out[-1][2] = deg
		else:
			out.append([kt, deg, deg])
	var res := []
	for m in out:
		res.append([m[0], ("%d°" % m[1]) if m[1] == m[2] else ("%d-%d°" % [m[1], m[2]])])
	return res
