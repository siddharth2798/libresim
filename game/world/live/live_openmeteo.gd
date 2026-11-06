class_name LiveOpenMeteo
extends RefCounted
## Open-Meteo forecast URL. Coordinates are rounded to 0.01 degree. Winds are requested in m/s,
## which is what LiveModel.parse expects. No HTTP here. Swap this file to retire the source.


const URL := "https://api.open-meteo.com/v1/forecast"
const LEVELS := [1000, 925, 850, 700, 500, 400, 300, 250]


static func url(lat: float, lon: float) -> String:
	var current := "temperature_2m,dew_point_2m,surface_pressure,wind_speed_10m,wind_direction_10m,wind_gusts_10m,visibility,rain,weather_code,cloud_cover_low,cloud_cover_mid,cloud_cover_high"
	var hourly := "cape,boundary_layer_height,wind_speed_80m,wind_direction_80m,wind_speed_120m,wind_direction_120m,wind_speed_180m,wind_direction_180m"
	for lvl in LEVELS:
		hourly += ",wind_speed_%dhPa,wind_direction_%dhPa,geopotential_height_%dhPa,temperature_%dhPa,relative_humidity_%dhPa" % [lvl, lvl, lvl, lvl, lvl]
	return "%s?latitude=%.2f&longitude=%.2f&current=%s&hourly=%s&forecast_days=1&wind_speed_unit=ms&timezone=UTC" % [URL, lat, lon, current, hourly]


## A parsed model, or {} when the body is not a forecast (error page, bad JSON, HTTP failure).
static func parse_body(body: String) -> Dictionary:
	var parsed = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY or bool(parsed.get("error", false)):
		return {}
	if not parsed.has("current") and not parsed.has("hourly"):
		return {}
	return LiveModel.parse(parsed)
