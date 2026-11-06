class_name LiveNoaa
extends RefCounted
## NOAA Aviation Weather METAR request. One bbox call; the nearest station within 50 km is used.
## No HTTP here. The real feed is an array of the same objects LiveMetar.parse reads.


const URL := "https://aviationweather.gov/api/data/metar"
const MAX_KM := 50.0


static func url(lat: float, lon: float) -> String:
	return "%s?format=json&bbox=%.2f,%.2f,%.2f,%.2f" % [URL, lat - 0.6, lon - 0.6, lat + 0.6, lon + 0.6]


static func km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var p1 := deg_to_rad(lat1)
	var p2 := deg_to_rad(lat2)
	var dp := deg_to_rad(lat2 - lat1)
	var dl := deg_to_rad(lon2 - lon1)
	var a := sin(dp * 0.5) ** 2 + cos(p1) * cos(p2) * sin(dl * 0.5) ** 2
	return 6371.0 * 2.0 * asin(sqrt(clampf(a, 0.0, 1.0)))


## {metar, distance_km, icao} for the nearest station inside 50 km, or {}.
static func nearest(body: String, lat: float, lon: float) -> Dictionary:
	var parsed = JSON.parse_string(body)
	if typeof(parsed) != TYPE_ARRAY:
		return {}
	var best := {}
	var bd := MAX_KM
	for item in parsed:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var la = item.get("lat", item.get("latitude"))
		var lo = item.get("lon", item.get("longitude"))
		if la == null or lo == null:
			continue
		var d := km(lat, lon, float(la), float(lo))
		if d <= bd:
			bd = d
			best = {"metar": LiveMetar.parse(item), "distance_km": d, "icao": str(item.get("icaoId", ""))}
	return best
