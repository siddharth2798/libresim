class_name Geo
## WGS84 lat/lon <-> world ENU metres, using the same local Transverse Mercator
## as the data pipeline (tools/common.py): lat_0 = 18.75, lon_0 = 73.40, k = 1.
## Snyder (USGS PP 1395) series; sub-millimetre over the +/-100 km map.

const LAT0 := 18.75
const LON0 := 73.40
const A := 6378137.0
const F := 1.0 / 298.257223563
const E2 := F * (2.0 - F)
const EP2 := E2 / (1.0 - E2)


static func _meridian(phi: float) -> float:
	var e4 := E2 * E2
	var e6 := e4 * E2
	return A * ((1.0 - E2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e6 / 256.0) * phi
		- (3.0 * E2 / 8.0 + 3.0 * e4 / 32.0 + 45.0 * e6 / 1024.0) * sin(2.0 * phi)
		+ (15.0 * e4 / 256.0 + 45.0 * e6 / 1024.0) * sin(4.0 * phi)
		- (35.0 * e6 / 3072.0) * sin(6.0 * phi))


## Returns Vector2(east, north) in metres.
static func to_enu(lat_deg: float, lon_deg: float) -> Vector2:
	var phi := deg_to_rad(lat_deg)
	var n := A / sqrt(1.0 - E2 * sin(phi) ** 2)
	var t := tan(phi) ** 2
	var c := EP2 * cos(phi) ** 2
	var a := deg_to_rad(lon_deg - LON0) * cos(phi)
	var m := _meridian(phi) - _meridian(deg_to_rad(LAT0))
	var x := n * (a + (1.0 - t + c) * a ** 3 / 6.0 + (5.0 - 18.0 * t + t * t + 72.0 * c - 58.0 * EP2) * a ** 5 / 120.0)
	var y := m + n * tan(phi) * (a * a / 2.0 + (5.0 - t + 9.0 * c + 4.0 * c * c) * a ** 4 / 24.0
		+ (61.0 - 58.0 * t + t * t + 600.0 * c - 330.0 * EP2) * a ** 6 / 720.0)
	return Vector2(x, y)


## Returns Vector2(lat_deg, lon_deg).
static func to_latlon(east: float, north: float) -> Vector2:
	var m := _meridian(deg_to_rad(LAT0)) + north
	var e4 := E2 * E2
	var mu := m / (A * (1.0 - E2 / 4.0 - 3.0 * e4 / 64.0 - 5.0 * e4 * E2 / 256.0))
	var e1 := (1.0 - sqrt(1.0 - E2)) / (1.0 + sqrt(1.0 - E2))
	var phi1 := mu + (3.0 * e1 / 2.0 - 27.0 * e1 ** 3 / 32.0) * sin(2.0 * mu) \
		+ (21.0 * e1 * e1 / 16.0 - 55.0 * e1 ** 4 / 32.0) * sin(4.0 * mu) \
		+ (151.0 * e1 ** 3 / 96.0) * sin(6.0 * mu) + (1097.0 * e1 ** 4 / 512.0) * sin(8.0 * mu)
	var c1 := EP2 * cos(phi1) ** 2
	var t1 := tan(phi1) ** 2
	var n1 := A / sqrt(1.0 - E2 * sin(phi1) ** 2)
	var r1 := A * (1.0 - E2) / pow(1.0 - E2 * sin(phi1) ** 2, 1.5)
	var d := east / n1
	var lat := phi1 - (n1 * tan(phi1) / r1) * (d * d / 2.0
		- (5.0 + 3.0 * t1 + 10.0 * c1 - 4.0 * c1 * c1 - 9.0 * EP2) * d ** 4 / 24.0
		+ (61.0 + 90.0 * t1 + 298.0 * c1 + 45.0 * t1 * t1 - 252.0 * EP2 - 3.0 * c1 * c1) * d ** 6 / 720.0)
	var lon := (d - (1.0 + 2.0 * t1 + c1) * d ** 3 / 6.0
		+ (5.0 - 2.0 * c1 + 28.0 * t1 - 3.0 * c1 * c1 + 8.0 * EP2 + 24.0 * t1 * t1) * d ** 5 / 120.0) / cos(phi1)
	return Vector2(rad_to_deg(lat), LON0 + rad_to_deg(lon))
