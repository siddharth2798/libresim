class_name LiveFetch
extends RefCounted
## Fallback order, with no network: a METAR inside 50 km (model fills the gaps), else the model,
## else the last cache, else the preset the pilot already chose. `replies` is {noaa, meteo}, each
## {code, body}. code 0 is a timeout or a transport error. 429 and bad JSON fail that source only.


static func decide(replies: Dictionary, place: Dictionary, cache: Dictionary, now: int, last_dir: float, day: bool, preset: String) -> Dictionary:
	var model := {}
	var meteo: Dictionary = replies.get("meteo", {})
	if int(meteo.get("code", 0)) == 200:
		model = LiveOpenMeteo.parse_body(str(meteo.get("body", "")))
	var station := {}
	var noaa: Dictionary = replies.get("noaa", {})
	if int(noaa.get("code", 0)) == 200:
		station = LiveNoaa.nearest(str(noaa.get("body", "")), float(place.lat), float(place.lon))
	var metar: Dictionary = station.get("metar", {})
	if not metar.is_empty() and not metar.has("elev_m"):
		metar["elev_m"] = float(place.get("elev_m", 0.0))
	if not model.is_empty() and not model.has("elevation_m"):
		model["elevation_m"] = float(place.get("elev_m", 0.0))
	if not metar.is_empty():
		var weather := LiveApply.for_sim(LiveMap.map(metar, model, last_dir, day))
		var obs := int(metar.get("obs_unix", now))
		var line := "%s, observed %s, %s, %d km away" % [str(station.get("icao", place.get("icao", ""))), _zulu(obs), age_text(float(now - obs)), int(round(float(station.distance_km)))]
		return _live("metar" if model.is_empty() else "metar+model", line, weather, place, now, station, obs)
	if not model.is_empty():
		var weather := LiveApply.for_sim(LiveMap.map({}, model, last_dir, day))
		return _live("model", "%s: model" % str(place.get("name", place.get("icao", "model"))), weather, place, now, {}, now)
	var saved: Dictionary = cache.get("weather", {}) if cache.get("weather", {}) is Dictionary else {}
	if not saved.is_empty():
		var age := float(now - int(cache.get("fetched_unix", now)))
		return {"tier": "cache", "status": "No connection. Using the last data (%s)" % age_text(age), "weather": saved, "persist": false, "save": {}}
	return {"tier": "preset", "status": "Using the %s preset." % preset, "weather": {}, "persist": false, "save": {}}


static func age_text(seconds: float) -> String:
	var s := maxf(seconds, 0.0)
	if s < 5400.0:
		return "%d min ago" % int(round(s / 60.0))
	return "%d h old" % int(round(s / 3600.0))


static func _zulu(unix: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix)
	return "%02d:%02dZ" % [int(dt.hour), int(dt.minute)]


static func _live(tier: String, status: String, weather: Dictionary, place: Dictionary, now: int, station: Dictionary, obs: int) -> Dictionary:
	return {
		"tier": tier, "status": status, "weather": weather, "persist": true,
		"save": {
			"fetched_unix": now, "lat": float(place.get("lat", 0.0)), "lon": float(place.get("lon", 0.0)),
			"tier": tier, "station": str(station.get("icao", "")), "distance_km": float(station.get("distance_km", 0.0)),
			"obs_unix": obs, "weather": weather, "raw": str(weather.get("live_metar", "")),
		},
	}
