class_name CloudStorm
extends RefCounted
## Storm cells for monsoon-like (cumulonimbus) conditions: microburst downdraft at the core and
## outflow shear around it. Pure functions. The world is cut into 10 km cells; a seeded hash decides
## whether a cell holds a storm (probability about 1.3 x the `storms` setting), where in the cell, its
## radius (1-3 km) and strength. The cells drift slowly with the wind aloft, so a place and time always
## give the same answer. Wind vectors are NED (x north, y east, z down).

const CELL_M := 10000.0
const DOWNDRAFT := 10.0  # m/s at the core of a full-strength cell
const OUTFLOW := 13.0  # m/s at the surface ring of a full-strength cell
const DRIFT_K := 0.6  # cells move at this fraction of the wind aloft


## Deterministic 0..1 value for cell (i, j), channel k.
static func hash01(i: int, j: int, k: int, seed: int) -> float:
	var h := (i * 374761393 + j * 668265263 + k * 1442695041 + seed * 1274126177) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = (h ^ (h >> 16)) & 0xFFFFFFFF
	return float(h) / 4294967295.0


## The cell (i, j) of the storm field: {on, center (Vector2 east, north in the drifting frame), radius, strength}.
static func cell(i: int, j: int, storms: float, seed: int) -> Dictionary:
	var on := hash01(i, j, 1, seed) < clampf(storms * 1.3, 0.0, 1.0)
	var c := Vector2((i + 0.15 + 0.7 * hash01(i, j, 2, seed)) * CELL_M, (j + 0.15 + 0.7 * hash01(i, j, 3, seed)) * CELL_M)
	var ik := clampf(storms * 1.4, 0.0, 1.0) * (0.6 + 0.4 * hash01(i, j, 5, seed))
	return {"on": on, "center": c, "radius": 1000.0 + 2000.0 * hash01(i, j, 4, seed), "strength": ik}


## Where the storm cell (i, j) is at time t_s with the aloft wind wind_en (east, north m/s).
static func center_at(cl: Dictionary, t_s: float, wind_en: Vector2) -> Vector2:
	return (cl.center as Vector2) + wind_en * (DRIFT_K * t_s)


## Storm effect at ENU p (agl m above ground) at storm clock t_s: {wind (NED, outflow + vertical),
## intensity 0..1, core (bool), shear (m/s added by the cell), down (m/s downdraft)}.
static func sample(p: Vector3, agl: float, t_s: float, wind_en: Vector2, storms: float, base_m: float, seed := 7) -> Dictionary:
	var out := {"wind": Vector3.ZERO, "intensity": 0.0, "core": false, "shear": 0.0, "down": 0.0}
	if storms <= 0.0:
		return out
	var q := Vector2(p.x, p.y) - wind_en * (DRIFT_K * t_s)  # into the cells' frame
	var ci := floori(q.x / CELL_M)
	var cj := floori(q.y / CELL_M)
	var top := CloudField.top_m(base_m)
	var in_col := 1.0 - smoothstep(top + 300.0, top + 900.0, p.z)  # nothing high above the cloud tops
	var dd_prof := smoothstep(0.0, 80.0, agl) * (0.55 + 0.45 * smoothstep(50.0, 500.0, agl)) * in_col
	var of_prof := smoothstep(0.0, 30.0, agl) * exp(-maxf(agl - 100.0, 0.0) / 350.0) * in_col
	var wind := Vector3.ZERO
	for di in range(-1, 2):
		for dj in range(-1, 2):
			var cl := cell(ci + di, cj + dj, storms, seed)
			if not cl.on:
				continue
			var r: Vector2 = q - (cl.center as Vector2)
			var rad: float = cl.radius
			var d := r.length()
			if d > 2.6 * rad:
				continue
			var x := d / (0.55 * rad)
			var core := exp(-x * x)  # downdraft shape
			var ring := x * exp(1.0 - x)  # outflow: zero at the core, peak at 0.55 R
			var s: float = cl.strength
			var away := r / d if d > 1.0 else Vector2.ZERO
			var down := DOWNDRAFT * s * core * dd_prof
			var edge_up := 0.25 * DOWNDRAFT * s * exp(-pow((d - 1.15 * rad) / (0.35 * rad), 2.0)) * dd_prof  # lift on the gust front
			var flow := away * (OUTFLOW * s * ring * of_prof)
			wind += Vector3(flow.y, flow.x, down - edge_up)
			var inten := s * exp(-pow(d / (1.2 * rad), 2.0)) * in_col
			if inten > out.intensity:
				out.intensity = inten
				out.core = d < 0.6 * rad and in_col > 0.5
	out.wind = wind
	out.down = maxf(wind.z, 0.0)
	out.shear = wind.length()
	return out
