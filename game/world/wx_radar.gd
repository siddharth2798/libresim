class_name WxRadar
extends RefCounted
## Nose weather radar, the picture on the ND. The beam is 3° wide and sweeps ±60° ahead.
## Each return is one range cell of that sweep: black, green, amber, red by reflectivity.
## Dry cloud stays black. A red cell blacks out the rest of its radial (the beam shadow).
## A cell is {az (rad, bearing from north), r0, r1 (m), level}. Level 1 green, 2 amber, 3 red.
## Reads weather/* and environment/storm_clock_s, cloud_drift only.


const COLOUR := [
	Color(0.0, 0.62, 0.16, 0.95),
	Color(0.98, 0.82, 0.0, 0.96),
	Color(0.86, 0.08, 0.05, 1.0),
]
const SCAN_DEG := 60.0
const BEAM_DEG := 3.0
const AZ := 40  # 120° / 3°
const BINS := 48
const _R_MIN := 900.0  # m, the blind range in front of the antenna


static func colour(level: int) -> Color:
	return COLOUR[clampi(level, 1, 3) - 1]


## Four corners of a cell, metres east/north from the aircraft. Slightly oversized so neighbours meet.
static func corners(az: float, r0: float, r1: float) -> PackedVector2Array:
	var half := deg_to_rad(BEAM_DEG) * 0.58
	var pad := (r1 - r0) * 0.12
	var a0 := az - half
	var a1 := az + half
	var near := maxf(r0 - pad, 0.0)
	var far := r1 + pad
	return PackedVector2Array([
		Vector2(sin(a0), cos(a0)) * near, Vector2(sin(a1), cos(a1)) * near,
		Vector2(sin(a1), cos(a1)) * far, Vector2(sin(a0), cos(a0)) * far,
	])


## Cells inside `radius_m`, nose at `heading_deg`. Empty without precip or storms.
static func sweep(origin: Vector2, heading_deg: float, radius_m: float) -> Array:
	var precip := Props.get_f("weather/precip")
	var storms := Props.get_f("weather/storms")
	if (precip < 0.08 and storms < 0.02) or radius_m < _R_MIN + 500.0:
		return []
	var cover := Props.get_f("weather/cloud_cover")
	var drift: Vector2 = Props.get_v("environment/cloud_drift", Vector2.ZERO)
	var shift := _wind_en() * (CloudStorm.DRIFT_K * Props.get_f("environment/storm_clock_s"))
	var bin := (radius_m - _R_MIN) / float(BINS)
	var out: Array = []
	for ia in AZ:
		var radial := PackedByteArray()
		radial.resize(BINS)
		var az := deg_to_rad(heading_deg - SCAN_DEG + (float(ia) + 0.5) * BEAM_DEG)
		var dir := Vector2(sin(az), cos(az))
		for ir in BINS:
			var p := origin + dir * (_R_MIN + (float(ir) + 0.5) * bin)
			var z := _rain_z(p, precip, cover, drift)
			if storms >= 0.02:
				z = maxf(z, _storm_z(p, storms, shift))
			radial[ir] = _level(z)
		radial = shade(radial)
		for ir in BINS:
			if radial[ir] == 0:
				continue
			var r0 := _R_MIN + float(ir) * bin
			out.append({"az": az, "r0": r0, "r1": r0 + bin, "level": int(radial[ir])})
	return out


## Cells beyond a red return on the same radial go black. Moderate rain does not.
static func shade(levels: PackedByteArray) -> PackedByteArray:
	var out := levels.duplicate()
	var blocked := false
	for i in out.size():
		if blocked:
			out[i] = 0
		elif int(out[i]) >= 3:
			blocked = true
	return out


static func _level(z: float) -> int:
	if z < 0.22:
		return 0
	if z < 0.48:
		return 1
	if z < 0.72:
		return 2
	return 3


## Area rain follows the thick parts of the deck. The detail noise keeps a cell from being flat.
static func _rain_z(p: Vector2, precip: float, cover: float, drift: Vector2) -> float:
	if precip < 0.08:
		return 0.0
	var q := (p + drift) / CloudField.TILE_M
	var field := CloudField.lo(q) - (1.0 - cover) * 0.55
	if field <= 0.05:
		return 0.0
	var detail := CloudField.hi(q * 2.2)
	return smoothstep(0.05, 0.45, field) * (0.4 + 0.6 * detail) * clampf(precip * 1.1, 0.0, 1.0)


## A cell's echo is lumpy, so the contour follows the beam samples instead of a ring.
static func _storm_z(p: Vector2, storms: float, shift: Vector2) -> float:
	var q := p - shift
	var ci := floori(q.x / CloudStorm.CELL_M)
	var cj := floori(q.y / CloudStorm.CELL_M)
	var z := 0.0
	for di in range(-1, 2):
		for dj in range(-1, 2):
			var cl := CloudStorm.cell(ci + di, cj + dj, storms, 7)
			if not cl.on:
				continue
			var world: Vector2 = (cl.center as Vector2) + shift
			var rad: float = cl.radius
			var d := p.distance_to(world)
			if d > rad * 3.3:
				continue
			var wobble := 0.62 + 0.75 * CloudField.hi(p / CloudField.TILE_M * 1.8 + Vector2(float(di), float(dj)) * 0.2)
			var reach := rad * 2.3 * wobble
			if d >= reach:
				continue
			var body := float(cl.strength) * pow(1.0 - d / reach, 1.35)
			if body > z:
				z = body
	return z


static func _wind_en() -> Vector2:
	var aloft := Weather._from_dir_to_ned(Props.get_f("weather/aloft_dir_deg"), Props.get_f("weather/aloft_kt") * Units.KT)
	return Vector2(aloft.y, aloft.x)
