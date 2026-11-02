class_name AudioSettings
extends RefCounted
## Audio buses and their volumes. Buses are created at runtime if missing (no
## default_bus_layout.tres needed), all routed to Master. Volumes (linear 0..1) and
## mute flags persist in user://audio.cfg. Call AudioSettings.apply() once at startup.
##   Engine      engine run/idle/crank, start/cut
##   Environment wind, rain, tyres, rumble, touchdown squeal
##   Cockpit     gyro, avionics fan, stall horn, flap motor, trim, switch clicks
##   Radio       ATC / radio voice (future)
##   UI          menu sounds (future)

const CFG := "user://audio.cfg"
const BUSES := ["Master", "Engine", "Environment", "Cockpit", "Radio", "UI"]
const LABELS := {"Master": "Master", "Engine": "Engine", "Environment": "Wind & environment",
	"Cockpit": "Cockpit (clicks, horn)", "Radio": "Radio / ATC", "UI": "Menus"}

static var _vol := {}
static var _mute := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	var ok := cf.load(CFG) == OK
	for b in BUSES:
		_vol[b] = clampf(float(cf.get_value("volume", b, 1.0)) if ok else 1.0, 0.0, 1.0)
		_mute[b] = bool(cf.get_value("mute", b, false)) if ok else false


## Create any missing bus (sending to Master).
static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, b)
		AudioServer.set_bus_send(i, "Master")


## Create buses and push the saved volumes / mutes to the AudioServer.
static func apply() -> void:
	_load()
	ensure_buses()
	for b in BUSES:
		var i := AudioServer.get_bus_index(b)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(_vol[b], 0.0001)))
		AudioServer.set_bus_mute(i, _mute[b] or _vol[b] <= 0.0)


static func volume(bus: String) -> float:
	_load()
	return _vol.get(bus, 1.0)


static func muted(bus: String) -> bool:
	_load()
	return _mute.get(bus, false)


static func set_volume(bus: String, v: float) -> void:
	_load()
	_vol[bus] = clampf(v, 0.0, 1.0)
	apply()
	save()


static func set_muted(bus: String, m: bool) -> void:
	_load()
	_mute[bus] = m
	apply()
	save()


static func save() -> void:
	if not Session.interactive():
		return
	var cf := ConfigFile.new()
	for b in BUSES:
		cf.set_value("volume", b, _vol[b])
		cf.set_value("mute", b, _mute[b])
	cf.save(CFG)
