class_name WxRadar
extends RefCounted
## Nose weather radar, the picture on the ND. The beam is 3° wide and sweeps ±60° ahead.
## Each return is one range cell of that sweep: black, green, amber, red by reflectivity.
## Dry cloud stays black. Rain weakens the beam as it goes (attenuate): heavy rain dims what lies behind it.
## Widespread rain tops out at amber; red is a storm core. Off without AC power (an airliner's AC1 / AC2 bus).
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
const ATT_PER_KM := 0.035  # two-way attenuation per km of path at reflectivity 1 (exp(-att) on what follows)
const RAIN_MAX := 0.7  # area rain stays below red (0.72); a storm core reaches it
const CORE_GAIN := 1.4  # a storm core's centre reads red on its own (it no longer leans on the area rain)


## AC power for the radar: an airliner publishes systems/electrical/ac1_on / ac2_on; other aircraft have no such bus.
static func powered() -> bool:
	if not Props.has("systems/electrical/ac1_on"):
		return true
	return Props.get_b("systems/electrical/ac1_on") or Props.get_b("systems/electrical/ac2_on")


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
	if (precip < 0.08 and storms < 0.02) or radius_m < _R_MIN + 500.0 or not powered():
		return []
	var cover := Props.get_f("weather/cloud_cover")
	var drift: Vector2 = Props.get_v("environment/cloud_drift", Vector2.ZERO)
	var shift := _wind_en() * (CloudStorm.DRIFT_K * Props.get_f("environment/storm_clock_s"))
	var bin := (radius_m - _R_MIN) / float(BINS)
	var out: Array = []
	for ia in AZ:
		var zs := PackedFloat32Array()
		zs.resize(BINS)
		var az := deg_to_rad(heading_deg - SCAN_DEG + (float(ia) + 0.5) * BEAM_DEG)
		var dir := Vector2(sin(az), cos(az))
		for ir in BINS:
			var p := origin + dir * (_R_MIN + (float(ir) + 0.5) * bin)
			var z := _rain_z(p, precip, cover, drift) * RAIN_MAX
			if storms >= 0.02:
				z = maxf(z, _storm_z(p, storms, shift))
			zs[ir] = z
		var radial := attenuate(smooth(zs), bin)
		for ir in BINS:
			if radial[ir] == 0:
				continue
			var r0 := _R_MIN + float(ir) * bin
			out.append({"az": az, "r0": r0, "r1": r0 + bin, "level": int(radial[ir])})
	return out


## A 1-2-1 blur along the radial: a return spans a few range cells instead of flickering cell by cell.
static func smooth(zs: PackedFloat32Array) -> PackedFloat32Array:
	var out := zs.duplicate()
	for i in range(1, zs.size() - 1):
		out[i] = 0.25 * zs[i - 1] + 0.5 * zs[i] + 0.25 * zs[i + 1]
	return out


## Levels along one radial after the path loss: each bin dims everything behind it by exp(-ATT_PER_KM * z * km).
## A single red cell no longer blacks out the rest of the radial; a long stretch of heavy rain does fade it.
static func attenuate(zs: PackedFloat32Array, bin_m: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(zs.size())
	var att := 0.0
	for i in zs.size():
		var z := float(zs[i])
		out[i] = _level(z * exp(-att))
		att += ATT_PER_KM * z * bin_m / 1000.0
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
	var detail := CloudField.hi(q * 1.3)
	# a light touch of detail: at 0.6 weight each cell crossed a colour threshold on its own (confetti)
	return smoothstep(0.05, 0.45, field) * (0.72 + 0.28 * detail) * clampf(precip * 1.1, 0.0, 1.0)


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
			var body := minf(float(cl.strength) * CORE_GAIN * pow(1.0 - d / reach, 1.35), 1.0)
			if body > z:
				z = body
	return z


static func _wind_en() -> Vector2:
	var aloft := Weather._from_dir_to_ned(Props.get_f("weather/aloft_dir_deg"), Props.get_f("weather/aloft_kt") * Units.KT)
	return Vector2(aloft.y, aloft.x)
