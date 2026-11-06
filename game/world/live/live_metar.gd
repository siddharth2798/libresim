class_name LiveMetar
extends RefCounted
## One NOAA METAR JSON object, or a raw METAR string, as a normalised observation.
## The raw visibility group is metres (9999 means 10 km or more, stored as 12 km).
## The JSON visib field is statute miles. No network.


const SM := 1609.344
const COVER := {"FEW": 0.2, "SCT": 0.45, "BKN": 0.75, "OVC": 1.0, "VV": 1.0}
const KINDS := ["FEW", "SCT", "BKN", "OVC", "VV"]


static func parse(src) -> Dictionary:
	if src is String:
		return _from_raw(src, {})
	if src is Dictionary:
		return _from_raw(str(src.get("rawOb", "")), src)
	return {}


static func precip_of(wx: String) -> float:
	var p := -1.0
	for tok in wx.split(" ", false):
		var heavy := tok.begins_with("+")
		var light := tok.begins_with("-")
		if "DZ" in tok:
			p = maxf(p, 0.15)
		if "TS" in tok:
			p = maxf(p, 0.85 if heavy else 0.5)
		elif "RA" in tok or ("SH" in tok and "TS" not in tok):
			var v := 0.85 if heavy else (0.25 if light else 0.5)
			if "SH" in tok:
				v = minf(v, 0.25)
			p = maxf(p, v)
	return p


static func _from_raw(raw: String, j: Dictionary) -> Dictionary:
	var obs := {"raw": raw, "layers": [], "clear": false, "wx": "", "vrb": false, "cb": false}
	if j.has("icaoId"):
		obs["icao"] = str(j.icaoId)
	if j.has("elev") and j.elev != null:
		obs["elev_m"] = float(j.elev)
	if j.has("obsTime") and j.obsTime != null:
		obs["obs_unix"] = int(j.obsTime)
	var past := not raw.contains("Z")
	var wx: PackedStringArray = []
	for tok in raw.split(" ", false):
		if tok.ends_with("Z") and tok.length() >= 6:
			past = true
			continue
		if not past or tok in ["METAR", "SPECI", "COR", "AUTO", "NIL", "NOSIG"]:
			continue
		if tok.begins_with("R") and "/" in tok:
			continue
		var wind := _wind(tok)
		if not wind.is_empty() and not obs.has("wind_kt"):
			obs["vrb"] = wind.vrb
			obs["wind_kt"] = wind.spd
			if wind.dir >= 0.0:
				obs["wind_dir"] = wind.dir
			if wind.gust >= 0.0:
				obs["gust_kt"] = wind.gust
			continue
		var vis := _vis(tok)
		if vis >= 0.0 and not obs.has("vis_m"):
			obs["vis_m"] = vis
			if tok == "CAVOK":
				obs["clear"] = true
			continue
		var layer := _cloud(tok)
		if not layer.is_empty():
			obs["clear"] = false
			(obs.layers as Array).append(layer)
			if layer.cb:
				obs["cb"] = true
			continue
		if tok in ["NSC", "SKC", "NCD", "CLR", "CAVOK"]:
			obs["clear"] = (obs.layers as Array).is_empty()
			continue
		var td := _temp(tok)
		if not td.is_empty() and not obs.has("temp_c"):
			obs["temp_c"] = td[0]
			obs["dew_c"] = td[1]
			continue
		var qnh := _qnh(tok)
		if qnh >= 0.0 and not obs.has("qnh_hpa"):
			obs["qnh_hpa"] = qnh
			continue
		if _is_wx(tok):
			wx.append(tok)
	if not wx.is_empty():
		obs["wx"] = " ".join(wx)
		if "TS" in obs.wx:
			obs["cb"] = true
	_fill_json(obs, j)
	return obs


static func _fill_json(obs: Dictionary, j: Dictionary) -> void:
	if not obs.has("wind_kt") and j.has("wspd") and j.wspd != null:
		obs["wind_kt"] = float(j.wspd)
		if j.get("wdir") == null or str(j.wdir) == "VRB":
			obs["vrb"] = true
		else:
			obs["wind_dir"] = float(j.wdir)
	if not obs.has("gust_kt") and j.get("wgst") != null:
		obs["gust_kt"] = float(j.wgst)
	if not obs.has("vis_m"):
		var vis := _visib_field(j.get("visib"))
		if vis >= 0.0:
			obs["vis_m"] = vis
	if not obs.has("qnh_hpa") and j.get("altim") != null:
		obs["qnh_hpa"] = _altim(float(j.altim))
	if not obs.has("temp_c") and j.get("temp") != null:
		obs["temp_c"] = float(j.temp)
		if j.get("dewp") != null:
			obs["dew_c"] = float(j.dewp)
	if (obs.layers as Array).is_empty() and not obs.clear:
		for c in j.get("clouds", []):
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var kind := str(c.get("cover", ""))
			if not COVER.has(kind) or c.get("base") == null:
				continue
			var cb := str(c.get("type", "")) in ["CB", "TCU"]
			(obs.layers as Array).append({"kind": kind, "cover": COVER[kind], "base_ft": float(c.base), "cb": cb})
			if cb:
				obs["cb"] = true
	if obs.wx == "" and j.get("wxString") != null:
		obs["wx"] = str(j.wxString)
		if "TS" in obs.wx:
			obs["cb"] = true


static func _wind(tok: String) -> Dictionary:
	if not tok.ends_with("KT") or tok.length() < 5:
		return {}
	var body := tok.substr(0, tok.length() - 2)
	var gust := -1.0
	if "G" in body:
		var bits := body.split("G")
		body = bits[0]
		if bits.size() < 2 or not bits[1].is_valid_int():
			return {}
		gust = float(bits[1])
	if body.begins_with("VRB"):
		var spd := body.substr(3)
		if not spd.is_valid_int():
			return {}
		return {"vrb": true, "dir": -1.0, "spd": float(spd), "gust": gust}
	if body.length() < 5 or not body.substr(0, 3).is_valid_int() or not body.substr(3).is_valid_int():
		return {}
	return {"vrb": false, "dir": float(body.substr(0, 3)), "spd": float(body.substr(3)), "gust": gust}


static func _vis(tok: String) -> float:
	if tok == "CAVOK":
		return 12000.0
	if tok.length() == 4 and tok.is_valid_int():
		var m := int(tok)
		return 12000.0 if m >= 9999 else float(m)
	if not tok.ends_with("SM"):
		return -1.0
	var b := tok.substr(0, tok.length() - 2).trim_prefix("P").trim_prefix("M")
	var miles := 0.0
	if "/" in b:
		var f := b.split("/")
		if f.size() != 2 or not f[0].is_valid_float() or float(f[1]) == 0.0:
			return -1.0
		miles = float(f[0]) / float(f[1])
	elif b.is_valid_float():
		miles = float(b)
	else:
		return -1.0
	return 12000.0 if miles >= 10.0 else miles * SM


static func _visib_field(v) -> float:
	if v == null:
		return -1.0
	if typeof(v) == TYPE_STRING:
		if "+" in str(v):
			return 12000.0
		return _visib_field(float(v)) if str(v).is_valid_float() else -1.0
	var n := float(v)
	if n >= 30.0:
		return 12000.0 if n >= 9999.0 else n
	return 12000.0 if n >= 10.0 else n * SM


static func _cloud(tok: String) -> Dictionary:
	for kind in KINDS:
		if not tok.begins_with(kind):
			continue
		var rest := tok.substr(kind.length())
		var cb := false
		if rest.ends_with("TCU"):
			cb = true
			rest = rest.substr(0, rest.length() - 3)
		elif rest.ends_with("CB"):
			cb = true
			rest = rest.substr(0, rest.length() - 2)
		if rest.length() == 3 and rest.is_valid_int():
			return {"kind": kind, "cover": COVER[kind], "base_ft": float(rest) * 100.0, "cb": cb}
	return {}


static func _temp(tok: String) -> Array:
	if "/" not in tok or tok.begins_with("R"):
		return []
	var a := tok.split("/")
	if a.size() != 2 or not _temp_ok(a[0]) or not _temp_ok(a[1]):
		return []
	return [_td(a[0]), _td(a[1])]


static func _temp_ok(s: String) -> bool:
	var b := s.substr(1) if s.begins_with("M") else s
	return b.length() == 2 and b.is_valid_int()


static func _td(s: String) -> float:
	return -float(s.substr(1)) if s.begins_with("M") else float(s)


static func _qnh(tok: String) -> float:
	if tok.length() != 5:
		return -1.0
	var n := tok.substr(1)
	if not n.is_valid_int():
		return -1.0
	if tok.begins_with("Q"):
		return float(n)
	if tok.begins_with("A"):
		return float(n) / 100.0 * Units.INHG / 100.0
	return -1.0


static func _altim(n: float) -> float:
	return n * Units.INHG / 100.0 if n < 100.0 else n


static func _is_wx(tok: String) -> bool:
	var b := tok.trim_prefix("+").trim_prefix("-")
	if b.length() < 2 or b.length() > 8:
		return false
	for frag in ["RA", "DZ", "SN", "TS", "SH", "FG", "BR", "HZ", "FU", "GR", "GS", "SQ", "VA"]:
		if frag in b:
			return true
	return false
