class_name Situation
extends RefCounted
## Saved flight situations ("save flight" / "load flight"), milestone M8.
## capture() snapshots a running flight scene (world/flight.tscn) into a JSON-safe
## Dictionary: FDM state (core/situation_fdm.gd), the pilot's controls / radios /
## failures / weather / instrument settings from Props, the systems' and gyros'
## internal state, the failure scheduler, the camera and the Session setup.
## apply() puts it all back. Files: user://saves/<name>.json + <name>.png (320x180).
## A crashed aircraft cannot be saved.

const VERSION := 1
const QUICK := "quicksave"
## Props saved with a situation (everything else is recomputed by the modules each tick).
const PROP_PREFIXES := ["controls/", "failures/", "weather/", "instruments/", "systems/", "fuel/",
	"engine/", "fdm/", "atmosphere/", "environment/"]

## Set by the start screen's saves page; world/flight.gd loads it at the end of _ready.
static var pending_load := ""


## Called by world/flight.gd at the end of _ready: resumes the save chosen on the start screen.
static func load_pending(root: Node) -> String:
	if pending_load == "":
		return ""
	var file := pending_load
	pending_load = ""
	var err := load_file(root, file)
	if err != "":
		push_error(err)
	return err


static func capture_fdm(f: FDM) -> Dictionary:
	return SituationFdm.capture(f)


static func apply_fdm(f: FDM, d: Dictionary) -> void:
	SituationFdm.apply(f, d)


## "" if the flight can be saved now, else the reason.
static func why_not_save(root: Node) -> String:
	var fn: FdmNode = root.get_node("Fdm")
	if fn.fdm.damage.crashed:
		return "Cannot save: the aircraft has crashed"
	return ""


static func capture(root: Node) -> Dictionary:
	var fn: FdmNode = root.get_node("Fdm")
	var f := fn.fdm
	var props := {}
	for pre in PROP_PREFIXES:
		var dump := Props.dump(pre)
		for k in dump:
			props[k] = _enc(dump[k])
	var gy: GyroInstruments = root.get_node("Instruments/Gyros")
	var cmp: MagneticCompass = root.get_node("Instruments/Compass")
	var fm: FailureManager = root.get_node("Systems/Failures")
	var kc: Node = root.get_node("Controls")
	var cam: CameraRig = root.get_node("Camera")
	var enu := fn.position_enu()
	return {
		"version": VERSION,
		"meta": _meta(root, enu),
		"enu": [enu.x, enu.y, enu.z],
		"fdm": capture_fdm(f),
		"props": props,
		"systems": {
			"soc": root.get_node("Systems/Electrical").soc,
			"suction": root.get_node("Systems/Vacuum").suction,
			"fuel_line": root.get_node("Systems/Fuel")._line,
			"pitot_frozen": root.get_node("Systems/PitotStatic")._pitot_frozen,
			"static_frozen": root.get_node("Systems/PitotStatic")._static_frozen,
		},
		"gyros": {"down": SituationFdm.vec(gy._down), "ai_spin": gy._ai_spin, "hi_spin": gy._hi_spin,
			"hi_offset": gy._hi_offset, "hi_drift_dir": gy._hi_drift_dir, "tc": gy._tc, "ball": gy._ball},
		"compass": {"card": cmp._card, "rate": cmp._rate},
		"failures": {"elapsed": fm.elapsed, "armed": fm.armed.duplicate(true)},
		"controls": {"parking_brake": Props.get_b("controls/parking_brake"), "pitch": kc.pitch, "roll": kc.roll, "yaw": kc.yaw},
		"camera": cam.mode,
		"setup": Session.setup.duplicate(true),
	}


## Restores a captured situation into a running flight scene. Returns "" or an error.
static func apply(root: Node, d: Dictionary) -> String:
	if int(d.get("version", 0)) < 1 or int(d.version) > VERSION:
		return "Unsupported save version %s" % str(d.get("version", "?"))
	d = _migrate(d)
	var fn: FdmNode = root.get_node("Fdm")
	var f := fn.fdm
	var setup: Dictionary = Session.DEFAULT.duplicate(true)
	setup.merge(d.setup, true)
	Session.setup = setup
	var enu := Vector3(d.enu[0], d.enu[1], d.enu[2])
	FloatingOrigin.set_origin(Vector2(enu.x, enu.y))
	# Props: failure flags are cleared first so ones repaired since the save stay off
	FailureCatalog.clear_all()
	var props := {}
	for k in d.props:
		props[k] = _dec(d.props[k])
	Props.restore(props)
	Props.set_v("failures/event", "")
	Props.set_v("controls/starter", false)
	for k in ["ops/stand", "ops/taxi_route"]:
		Props.set_v(k, "")
	var ops := root.get_node_or_null("GroundOps")
	if ops:
		ops.clear_route()
		if not ops._push.is_empty():
			ops._end_push("")
	apply_fdm(f, d.fdm)
	_settle_on_terrain(f, d.fdm)
	fn._snap()
	fn._publish()  # damage/*, fdm/* etc. consistent even while paused
	var s: Dictionary = d.systems
	root.get_node("Systems/Electrical").soc = float(s.soc)
	root.get_node("Systems/Vacuum").suction = float(s.suction)
	root.get_node("Systems/Fuel")._line = float(s.fuel_line)
	root.get_node("Systems/PitotStatic")._pitot_frozen = float(s.pitot_frozen)
	root.get_node("Systems/PitotStatic")._static_frozen = float(s.static_frozen)
	var gy: GyroInstruments = root.get_node("Instruments/Gyros")
	var g: Dictionary = d.gyros
	gy._down = SituationFdm.to_vec(g.down)
	gy._ai_spin = float(g.ai_spin)
	gy._hi_spin = float(g.hi_spin)
	gy._hi_offset = float(g.hi_offset)
	gy._hi_drift_dir = float(g.hi_drift_dir)
	gy._tc = float(g.tc)
	gy._ball = float(g.ball)
	var cmp: MagneticCompass = root.get_node("Instruments/Compass")
	cmp._card = float(d.compass.card)
	cmp._rate = float(d.compass.rate)
	var fm: FailureManager = root.get_node("Systems/Failures")
	fm.elapsed = float(d.failures.elapsed)
	fm.armed.clear()
	for a in d.failures.armed:
		fm.armed.append({"id": str(a.id), "mode": int(a.mode), "value": float(a.value), "random": bool(a.random)})
	var kc: Node = root.get_node("Controls")
	for k in d.controls:
		kc.set(k, d.controls[k])
	var cam: CameraRig = root.get_node("Camera")
	cam.set_mode(int(d.camera))
	cam._chase_pos = Vector3(1e6, 1e6, 1e6)  # snaps behind the aircraft on the next frame
	return ""


## Ground height lookups are synchronous (terrain_tile_cache.height_at reads the tile
## on demand), so the aircraft cannot fall through. If the terrain data changed since
## the save, keep the saved height above ground instead of the saved altitude.
static func _settle_on_terrain(f: FDM, d: Dictionary) -> void:
	var agl := float(d.get("agl", 1e9))
	if agl > 100.0:
		return
	var gh: float = f.ground_height.call(f.pos_n, f.pos_e)
	var now := -f.pos_d - gh
	if absf(now - agl) > 0.01:
		f.pos_d = -(gh + agl)
	f.agl = agl


## Future format changes: upgrade older dictionaries here.
static func _migrate(d: Dictionary) -> Dictionary:
	return d


# ---- files (core/situation_store.gd) ----

static func save(root: Node, name: String, thumb: Image = null) -> String:
	var err := why_not_save(root)
	if err != "":
		return err
	var d := capture(root)
	d.meta.name = name
	return SituationStore.write(d, name, thumb)


## Loads user://saves/<file>.json into the running flight. Returns "" or an error.
static func load_file(root: Node, file: String) -> String:
	var d := SituationStore.read(file)
	if d.is_empty():
		return "No saved flight '%s'" % file
	return apply(root, d)


## Metadata of every save, newest first: {name, file, unix, date, airport, alt_ft, ias_kt, thumb}.
static func list_saves() -> Array:
	return SituationStore.list()


static func delete(file: String) -> void:
	SituationStore.delete(file)


static func default_name(root: Node) -> String:
	var fn: FdmNode = root.get_node("Fdm")
	var d := Time.get_datetime_dict_from_system()
	return "%s %04d-%02d-%02d %02d%02d" % [nearest_airport(root, fn.position_enu()), d.year, d.month, d.day, d.hour, d.minute]


static func nearest_airport(root: Node, enu: Vector3) -> String:
	var best := str(Session.setup.get("airport", "?"))
	var bd := INF
	var cam := root.get_node_or_null("Camera") as CameraRig
	for a in (cam.airports if cam else []):
		var dd := Vector2(a.enu.x, a.enu.y).distance_to(Vector2(enu.x, enu.y))
		if dd < bd:
			bd = dd
			best = a.icao
	return best


static func _meta(root: Node, enu: Vector3) -> Dictionary:
	var t := Time.get_datetime_dict_from_system()
	var fn: FdmNode = root.get_node("Fdm")
	return {"name": "", "unix": Time.get_unix_time_from_system(),
		"date": "%04d-%02d-%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute],
		"airport": nearest_airport(root, enu), "alt_ft": Units.m_to_ft(fn.fdm.altitude()),
		"agl_ft": Units.m_to_ft(fn.fdm.agl), "ias_kt": Props.get_f("instruments/asi_kt", Units.mps_to_kt(fn.fdm.cas)),
		"on_ground": fn.fdm.gear.wow, "aircraft": str(Session.setup.get("aircraft", "c172"))}


## Props values: JSON-native bools / floats / strings as they are, anything else
## (ints, vectors, arrays, typed arrays) through var_to_str so the type survives.
static func _enc(v: Variant) -> Variant:
	if typeof(v) in [TYPE_BOOL, TYPE_FLOAT, TYPE_STRING]:
		return v
	return {"$var": var_to_str(v)}


static func _dec(v: Variant) -> Variant:
	if v is Dictionary and v.has("$var"):
		return str_to_var(v["$var"])
	return v
