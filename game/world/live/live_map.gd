class_name LiveMap
extends RefCounted
## A parsed METAR and/or Open-Meteo model to the sim's weather keys. No nodes, no network.
## Observed fields win. Cloud bases are stored AMSL, which is what weather/cloud_base_ft is.
## One deck: the ceiling (lowest BKN/OVC), else the lowest layer; higher cloud becomes cirrus.
## docs/LIVE-WEATHER-PLAN.md (W0).


const LAPSE := 0.0065
const ISA_H := 44330.77
const ISA_EXP := 5.25588
const MS_KT := 1.943844
const CEILING := ["BKN", "OVC", "VV"]


static func qnh_from_qfe(qfe_hpa: float, elev_m: float) -> float:
	var x := 1.0 - elev_m / ISA_H
	if x <= 0.2:
		return qfe_hpa
	return qfe_hpa / pow(x, ISA_EXP)


## Slider that makes weather.gd's clear-air sigma, below 300 m, match the mapped target.
static func turbulence_of(wind_kt: float, gust_kt: float) -> float:
	var wind_mps := wind_kt * Units.KT
	var spread := maxf(gust_kt - wind_kt, 0.0) * Units.KT
	var target := maxf(0.1 * wind_mps, spread / 5.0)
	var factor := (1.0 + wind_mps * 0.15) * 1.4
	return 0.0 if factor <= 0.0 else clampf(target / factor, 0.0, 1.0)


static func map(metar: Dictionary, model: Dictionary, last_dir := 270.0, day := true) -> Dictionary:
	var elev := float(metar.get("elev_m", model.get("elevation_m", 0.0)))
	var out := {}
	var dir := last_dir
	var spd := 0.0
	var gust := 0.0
	if metar.has("wind_kt"):
		spd = float(metar.wind_kt)
		if metar.get("vrb", false) or spd < 0.5:
			dir = last_dir
			if metar.get("vrb", false):
				spd = minf(spd, 2.9)
		else:
			dir = float(metar.get("wind_dir", last_dir))
		gust = float(metar.get("gust_kt", 0.0))
	elif model.has("wind_ms"):
		spd = float(model.wind_ms) * MS_KT
		dir = float(model.get("wind_deg", last_dir))
		gust = float(model.get("gust_ms", 0.0)) * MS_KT
	out["wind_dir_deg"] = fposmod(dir, 360.0)
	out["wind_kt"] = spd
	out["gust_kt"] = gust if gust > spd else 0.0
	var table := _table(model, elev)
	out["wind_table"] = table
	var aloft: Array = _aloft(table, out.wind_dir_deg, spd)
	out["aloft_dir_deg"] = aloft[0]
	out["aloft_kt"] = aloft[1]
	var field_t := float(metar.get("temp_c", model.get("temp_c", 15.0)))
	var field_d := float(metar.get("dew_c", model.get("dew_c", field_t)))
	out["temp_c"] = field_t + LAPSE * elev
	out["dewpoint_c"] = field_d
	if metar.has("qnh_hpa"):
		out["qnh_hpa"] = float(metar.qnh_hpa)
	elif model.has("surface_hpa"):
		out["qnh_hpa"] = qnh_from_qfe(float(model.surface_hpa), elev)
	if metar.has("vis_m"):
		out["visibility_m"] = clampf(float(metar.vis_m), 200.0, 40000.0)
		out["visibility_includes_precip"] = true
	elif model.has("vis_m"):
		out["visibility_m"] = clampf(float(model.vis_m), 200.0, 40000.0)
		out["visibility_includes_precip"] = true
	else:
		out["visibility_includes_precip"] = false
	var deck := _deck(metar, model, elev, field_t, field_d)
	out["cloud_cover"] = deck.cover
	out["cloud_base_ft"] = deck.base_ft
	out["cirrus"] = deck.cirrus
	var wx := str(metar.get("wx", ""))
	var precip := LiveMetar.precip_of(wx) if wx != "" else -1.0
	if precip < 0.0:
		precip = clampf(float(model.get("rain_mm_h", 0.0)) / 10.0, 0.0, 1.0)
		var code := int(model.get("weather_code", -1))
		if code >= 80 and code <= 82:
			precip = minf(precip, 0.25)
	out["precip"] = precip
	var cape := float(model.get("cape", -1.0))
	var convective := bool(metar.get("cb", false)) or (int(model.get("weather_code", -1)) >= 95 and int(model.get("weather_code", -1)) <= 99)
	out["storms"] = 0.7 if convective and cape > 1000.0 else 0.0
	out["icing"] = _icing(model, convective)
	var conv := 0.0
	if day and model.has("boundary_m"):
		conv = clampf((float(model.boundary_m) - 500.0) / 2000.0, 0.0, 1.0)
		conv *= 1.0 - 0.7 * smoothstep(0.6, 1.0, float(out.cloud_cover))
	out["convection"] = conv
	out["turbulence"] = turbulence_of(spd, float(out.gust_kt))
	if metar.has("raw") and str(metar.raw) != "":
		out["live_metar"] = str(metar.raw)
	if metar.has("obs_unix"):
		var ist := _ist(int(metar.obs_unix))
		out["time_h"] = ist.time_h
		out["day_of_year"] = ist.day_of_year
	return out


static func _table(model: Dictionary, elev: float) -> Array:
	var rows: Array = []
	for lv in model.get("levels", []):
		var agl := float(lv.agl_m) if lv.has("agl_m") else float(lv.get("h_amsl_m", 0.0)) - elev
		if agl < 15.0:
			continue
		rows.append([agl, fposmod(float(lv.from_deg), 360.0), float(lv.ms) * MS_KT])
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return rows


static func _aloft(table: Array, dir0: float, spd0: float) -> Array:
	if table.is_empty():
		return [fposmod(dir0 + 10.0, 360.0), spd0 * 1.6]
	var best: Array = table[0]
	var best_d := absf(float(best[0]) - 1500.0)
	for row in table:
		var d := absf(float(row[0]) - 1500.0)
		if d < best_d:
			best = row
			best_d = d
	return [float(best[1]), float(best[2])]


static func _deck(metar: Dictionary, model: Dictionary, elev: float, field_t: float, field_d: float) -> Dictionary:
	var high := _frac(model.get("cloud_high", 0.0))
	var pick = null
	for ly in metar.get("layers", []):
		var base := float(ly.base_ft)
		if base > 20000.0:
			high = maxf(high, float(ly.cover))
			continue
		var ceiling := str(ly.kind) in CEILING
		if pick == null or (ceiling and str(pick.kind) not in CEILING) or (ceiling == (str(pick.kind) in CEILING) and base < float(pick.base_ft)):
			pick = ly
	if pick != null:
		return {"cover": float(pick.cover), "base_ft": float(pick.base_ft) + Units.m_to_ft(elev), "cirrus": clampf(high, 0.0, 1.0)}
	if metar.get("clear", false) or metar.has("vis_m"):
		return {"cover": 0.0, "base_ft": 12000.0, "cirrus": clampf(high, 0.0, 1.0)}
	var moist := -1.0
	for lv in model.get("levels", []):
		if float(lv.get("rh", 0.0)) < 90.0:
			continue
		var agl := float(lv.agl_m) if lv.has("agl_m") else float(lv.get("h_amsl_m", elev)) - elev
		if agl > 50.0 and (moist < 0.0 or agl < moist):
			moist = agl
	var base_m := moist if moist >= 0.0 else 125.0 * maxf(field_t - field_d, 0.0)
	var low := _frac(model.get("cloud_low", 0.0))
	return {"cover": clampf(low, 0.0, 1.0), "base_ft": Units.m_to_ft(base_m + elev), "cirrus": clampf(high, 0.0, 1.0)}


static func _frac(v) -> float:
	var x := float(v)
	if x < 0.0:
		return 0.0
	return clampf(x / 100.0 if x > 1.0 else x, 0.0, 1.0)


static func _icing(model: Dictionary, cb: bool) -> float:
	var ice := 0.0
	for lv in model.get("levels", []):
		if not lv.has("temp_c") or not lv.has("rh"):
			continue
		var tc := float(lv.temp_c)
		if float(lv.rh) >= 90.0 and tc <= 0.0 and tc >= -20.0:
			ice = 0.3
	return 0.7 if cb else ice


static func _ist(unix: int) -> Dictionary:
	var dt := Time.get_datetime_dict_from_unix_time(unix + 19800)
	var mdays := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
	var doy: int = int(mdays[int(dt.month) - 1]) + int(dt.day)
	var y := int(dt.year)
	if int(dt.month) > 2 and (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)):
		doy += 1
	return {"time_h": float(dt.hour) + float(dt.minute) / 60.0 + float(dt.second) / 3600.0, "day_of_year": doy}
