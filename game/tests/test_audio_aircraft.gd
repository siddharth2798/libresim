extends Node
## Both aircraft's audio sections: the C172 on layers with the same curves as its old hard-coded path (aircraft_audio.gd
## at 137acc3), AircraftAudio building the layer engine, every file present and credited in its SOURCES.md.

const C172_FILES := ["engine-idle", "engine", "engine-crank", "gyro", "wind1", "tires-rolling-asphalt", "rumble",
	"stall2", "flaps-motor", "trim", "avionics-400Hz", "rain", "rain-windshield", "engine-start", "engine-cut", "click",
	"click2", "double-click", "lever", "keys", "flaps-click"]
const TL := preload("res://tests/test_audio_layers.gd")


func layers_of(id: String) -> Array:
	return TL.layers_of(id)


func _draft() -> Array:
	return layers_of("a320")


func _near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _ctx(vals: Dictionary, view := "outside", rates := {}) -> Dictionary:
	return {"view": view, "values": vals, "rates": rates}


func _dispose(n: Node) -> void:
	for c in n.find_children("*", "AudioStreamPlayer", true, false):
		c.stop()
	remove_child(n)
	n.free()
	OS.delay_msec(150)


# --- the C172 on layers ---------------------------------------------------------------

func _c172(id: String, vals: Dictionary, view := "cockpit") -> Dictionary:
	for l in AudioCurves.expand(layers_of("c172"), 1):
		if l.id == id:
			return AudioCurves.layer_state(l, _ctx(vals, view))
	return {"on": false, "vol": -1.0, "pitch": -1.0}


## The old aircraft_audio.gd formulas (main at 137acc3) against the C172's layer tables at sample points.
func test_audio_c172_layers_match_old_formulas() -> String:
	for rpm in [700.0, 950.0, 1200.0, 1800.0, 2400.0, 2700.0]:
		var v := {"engine/rpm": rpm, "engine/running": true, "engine/map_pa": 87000.0}
		var idle := clampf(1.0 - (rpm - 900.0) / 500.0, 0.0, 1.0) * 0.9
		var run := clampf(rpm * 0.000294118 + 0.205882353, 0.5, 0.95) * clampf((rpm - 600.0) / 400.0, 0.0, 1.0)
		var a := _c172("engine_idle", v)
		var b := _c172("engine_run", v)
		var load := AudioCurves.interp([[35000, 0.85], [100000, 1.1]], 87000.0)
		if not _near(a.vol, idle) or not _near(a.pitch, clampf(rpm / 700.0, 0.6, 1.6)):
			return "idle at %d rpm: %s, old %.3f" % [rpm, a, idle]
		if not _near(b.vol, run * load) or not _near(b.pitch, rpm * 0.000434783 + 0.01):
			return "run at %d rpm: %s, old %.3f x load %.3f" % [rpm, b, run, load]
	for kt in [10.0, 40.0, 90.0, 140.0]:
		var mps: float = kt / 1.943844
		var w := _c172("wind", {"fdm/tas_mps": mps, "fdm/alt_m": 1524.0})
		var old := clampf(kt * 0.0015, 0.03, 0.25) * clampf(1.0 - 5000.0 * 0.000015, 0.1, 1.0)
		if not _near(w.vol, old, 0.005) or not _near(w.pitch, kt * 0.0035 + 1.25, 0.01):
			return "wind at %d kt: %s, old %.3f / %.3f" % [kt, w, old, kt * 0.0035 + 1.25]
	for kt in [0.5, 2.0, 8.0, 25.0, 60.0]:
		var r := _c172("tyre_roll", {"fdm/groundspeed_mps": kt / 1.943844, "fdm/wow": true})
		if not _near(r.vol, clampf(log(1.0 + kt) * 0.25, 0.0, 1.0) * 0.7, 0.03):
			return "tyre roll at %.1f kt: %s" % [kt, r]
	if _c172("engine_run", {"engine/rpm": 2400.0, "engine/running": false}).vol != 0.0:
		return "a stopped engine plays no run loop"
	var wm := _c172("engine_windmill", {"engine/rpm": 800.0, "engine/running": false})
	if not _near(wm.vol, clampf(800.0 / 2500.0, 0.0, 0.4) * 0.5):
		return "windmilling: %s" % wm
	if _c172("gyro", {"systems/vacuum/suction_inhg": 5.0}, "outside").vol != 0.0:
		return "the gyro is heard in the cockpit only"
	return ""


func test_audio_c172_uses_layers() -> String:
	var prev = Session.setup.get("aircraft")
	Session.setup["aircraft"] = "c172"
	var err := ""
	var a := AircraftAudio.new()
	add_child(a)
	if a.layers == null or a.is_processing():
		err = "the c172 plays through AudioLayers"
	else:
		var files := {}
		for l in a.layers.layers:
			files[str(l.file).get_file().get_basename()] = true
		for f in C172_FILES:
			if not files.has(f):
				err = "c172 lost the %s sound" % f
	_dispose(a)
	if prev == null:
		Session.setup.erase("aircraft")
	else:
		Session.setup["aircraft"] = prev
	return err


func test_audio_a320_aircraft_uses_layers() -> String:
	var def := AircraftDef.make("a320x", {"audio": {"layers": _draft()}}, "res://aircraft/a320")
	var prev = Session.setup.get("aircraft")
	AircraftDef._cache["a320x"] = def
	Session.setup["aircraft"] = "a320x"
	var a := AircraftAudio.new()
	add_child(a)
	var err := ""
	if a.is_processing() or not a.get_children().any(func(c): return c is AudioLayers):
		err = "an aircraft with audio.layers uses AudioLayers"
	_dispose(a)
	AircraftDef._cache.erase("a320x")
	if prev == null:
		Session.setup.erase("aircraft")
	else:
		Session.setup["aircraft"] = prev
	return err


# --- both aircraft's sections and their credits ----------------------------------------

func test_audio_sections_files_exist_and_are_credited() -> String:
	for id in ["c172", "a320"]:
		var err := _check_section(id)
		if not err.is_empty():
			return "%s: %s" % [id, err]
	return ""


func _check_section(id: String) -> String:
	var layers := layers_of(id)
	if layers.size() < 20:
		return "audio section missing or too short (%d layers)" % layers.size()
	var own := "res://aircraft/%s/sounds/" % id
	var mds := {}
	for d in ["res://aircraft/a320/sounds/", "res://aircraft/c172/sounds/", "res://world/sounds/"]:
		mds[d] = FileAccess.get_file_as_string(d + "SOURCES.md")
		if mds[d].is_empty():
			return d + "SOURCES.md missing"
	var ids := {}
	for l in AudioCurves.expand(layers, 2):
		var f: String = l.get("file", "")
		if ids.has(l.id):
			return "duplicate layer id %s" % l.id
		ids[l.id] = true
		if not l.get("bus", "Cockpit") in AudioCurves.BUSES:
			return "layer %s: unknown bus %s" % [l.id, l.get("bus")]
		var path := f if f.begins_with("res://") else own + f
		if not FileAccess.file_exists(path):
			return "layer %s: %s does not exist" % [l.id, path]
		var md: String = mds.get(path.get_base_dir() + "/", "")
		if not md.contains(path.get_file().get_basename()):
			return "%s is not listed in its SOURCES.md" % path
		if l.get("loop", true) == false and not l.has("trigger"):
			return "one-shot layer %s needs a trigger" % l.id
		for k in AudioCurves.watched(l):
			if k.contains("{n}"):
				return "layer %s uses {n} without per_engine" % l.id
	for d in mds:
		for f in DirAccess.open(d).get_files():
			if (f.ends_with(".wav") or f.ends_with(".ogg")) and not mds[d].contains(f.get_basename()):
				return "%s%s is not in SOURCES.md" % [d, f]
	return ""
