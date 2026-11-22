class_name TreeLook
extends RefCounted
## Impostor sway and the stable per-instance colour seed. tree.gdshader uses the same
## sway numbers (uniforms set from here): none at the trunk base, a few centimetres at
## the crown, one cycle every SWAY_PERIOD_S. Trees has no quality flag, so the sway is
## this small on every preset. dryness() is the season tint (TreeSpecies order in DRY_RESPONSE).

const SWAY_PERIOD_S := 4.5
const SWAY_CROWN_M := 0.045
## Season: how dry the leaves look through the year (west coast of India: green from the monsoon in June to October,
## drying from November to the end of May). [day of year, dryness 0..1], eased between the points.
const DRY_YEAR := [[0.0, 0.55], [60.0, 0.8], [121.0, 1.0], [158.0, 0.95], [196.0, 0.1], [230.0, 0.0], [290.0, 0.05],
	[335.0, 0.3], [365.0, 0.55]]
## How strongly each species shows it (TreeSpecies order); tree_tint.gdshaderinc has the same numbers.
const DRY_RESPONSE := [0.8, 0.12, 0.9, 0.2, 0.3]


## 0 lush (after the monsoon) .. 1 dry (May), for day of year `day` (1..365, wraps).
static func dryness(day: float) -> float:
	var d := fposmod(day, 365.0)
	for k in DRY_YEAR.size() - 1:
		var a: Array = DRY_YEAR[k]
		var b: Array = DRY_YEAR[k + 1]
		if d <= b[0]:
			return lerpf(a[1], b[1], smoothstep(a[0], b[0], d))
	return DRY_YEAR[0][1]


## Metres of horizontal sway. height_01 is 0 at the trunk base and 1 at the crown.
static func sway_amplitude(height_01: float) -> float:
	return SWAY_CROWN_M * clampf(height_01, 0.0, 1.0)


static func sway_m(height_01: float, time_s: float, phase: float) -> float:
	return sin(TAU * time_s / SWAY_PERIOD_S + phase) * sway_amplitude(height_01)


## Same bits for the same index. Feeds colour_unit, which is stored in INSTANCE_CUSTOM.
static func colour_hash(index: int) -> int:
	var n: int = index * 747796405 + 2891336453
	n = (n ^ (n >> 13)) * 1274126177
	return n ^ (n >> 16)


## 0..1 tint seed for land cell (ci, cj). channel 0 is hue, 1 is value. Stable, no time.
static func colour_unit(ci: int, cj: int, channel: int) -> float:
	var h: int = absi(colour_hash(ci * 131 + cj * 17 + channel * 104729))
	return float(h % 100003) / 100003.0
