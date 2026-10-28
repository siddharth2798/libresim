class_name AircraftDef
extends RefCounted
## One aircraft = one folder res://aircraft/<id>/ with an aircraft.json that describes it. Everything
## that differs between aircraft is read from here, nothing else in the game names an aircraft:
##   files    optional {key: path relative to the folder}, defaults in FILES
##   model    exterior / interior glb, control-surface pivots, propeller pivots (aircraft_model.gd)
##   cockpit  gauge spots in the glb, panel layout (panel.json), eye point (cockpit.gd)
##   lights   nav / beacon / strobe / lamp positions (aircraft_lights.gd)
##   audio    sound folder and the engine / wind mappings (aircraft_audio.gd)
##   limits   V-speeds and load limits (damage.gd, ASI arcs, training lessons): vne_kias, vd_kias,
##            vfe_kias [[max flap deg, kias], ...], g_pos, g_neg, vs0_kias, vs1_kias, vno_kias,
##            asi_min_kias / asi_max_kias; tach {max_rpm, green [lo, hi], red}; gauges {fuel_gal,
##            oil_temp_f, oil_press_psi, egt_f, fuel_flow_gph, suction_inhg, ammeter_a: {min, max,
##            green [lo, hi], red}} (the engine strip, ui/gauges/*.gd)
##   damage   touchdown and gear thresholds, propeller hub positions (damage.gd)
##   systems  electrical / fuel / pitot_static numbers (systems/*.gd, keys in each script's header)
##   radio_type  how the pilot calls the aircraft on the radio ("Cessna 172", atc/atc_phraseology.gd)
##   atc      {profile: "ga" | "airline", wake: L | M | H | J, and for an airline telephony (fictional name),
##            flight_no, callsign_style: "airline"}: how ATC talks to the aircraft (atc/atc_profile.gd)
##   cameras  chase / wing / tail / orbit view positions (ui/camera_rig.gd), see camera()
##   registration  tail number painted at flight start: {source: callsign | fixed, text, texture, targets: [{erase, text, align, color, italic}]} (common/registration_paint.gd)
##   start    pitch_trim of a parked start, air_kt of an airborne one (world/flight.gd)
##   fcs      {"law": "airbus_fbw"}: fly-by-wire control law (fdm/fbw_law.gd); absent = direct control
##   callouts optional {alive_kt, rotate_kt, v1_kt, low_kt, heights}: the training callouts (ui/callouts.gd)
##   ground   footprint, height, tow point, optional min_runway_m (the start screen flags shorter runways) for stands, taxi corridors and jetways (world/ops_*.gd); all keys in world/ground_params.gd
##   pushback  straight_m, radius_m, speed_mps of the pushback path (world/pushback_path.gd)
##   payload  start-screen fuel slider and stations (ui/menu/aircraft_page.gd, weight_balance.gd):
##            fuel_kg_per_gal, cruise_gph, reserve_gal, fuel_slider {min, max, step, unit},
##            stations [{key (Session.setup), label, max, step, masses [config point-mass names]}]
##   failures optional {"disabled": [failure ids]} (systems/failure_catalog.gd)
##   icing    optional {protection: none | pitot_only | wing_and_engine, drag_k, clmax_k, power_loss_k, egt_k, pitot_heat_prop,
##            wing_anti_ice_prop, engine_anti_ice_prop, bleed_wing, bleed_engine, rain_cl_k, rain_cd_k, rain_n1_k}: ice and rain
##            (systems/icing.gd DEFAULTS, fdm/environment_effects.gd); absent = the C172's numbers
## The flight-model numbers (aero, mass, gear, tanks, engines) are in config.json and aero.json.

const ROOT := "res://aircraft/"
const DEFAULT_ID := "c172"
const FILES := {
	"config": "config.json", "aero": "aero.json", "hull": "hull.json", "checklists": "checklists.json",
	"panel": "panel.json", "exterior": "models/exterior.glb", "interior": "models/interior.glb",
	"sounds": "sounds/",
}

static var _cache := {}

var id := ""
var dir := ""  # "res://aircraft/<id>" (no trailing slash)
var data := {}  # aircraft.json
var _config := {}


## The aircraft with this id (cached). An unknown id gives the default aircraft, so a save made with
## an aircraft that is no longer installed still starts.
static func load_def(aircraft_id: String) -> AircraftDef:
	if _cache.has(aircraft_id):
		return _cache[aircraft_id]
	var d := ROOT + aircraft_id
	if not FileAccess.file_exists(d + "/aircraft.json"):
		if aircraft_id == DEFAULT_ID:
			push_error("AircraftDef: no %s/aircraft.json" % d)
			return null
		push_warning("AircraftDef: unknown aircraft '%s', using %s" % [aircraft_id, DEFAULT_ID])
		return load_def(DEFAULT_ID)
	var j = JSON.parse_string(FileAccess.get_file_as_string(d + "/aircraft.json"))
	var def := make(aircraft_id, j if j is Dictionary else {}, d)
	_cache[aircraft_id] = def
	return def


## The aircraft chosen on the start screen (Session.setup.aircraft).
static func current() -> AircraftDef:
	return load_def(str(Session.setup.get("aircraft", DEFAULT_ID)))


## An aircraft built in code (tests, tools): data = aircraft.json content, config = flight-model
## config (empty: read config.json from `folder`). Not cached.
static func make(aircraft_id: String, aircraft_data: Dictionary, folder: String, config := {}) -> AircraftDef:
	var def := AircraftDef.new()
	def.id = aircraft_id
	def.data = aircraft_data
	def.dir = folder
	def._config = config
	return def


## Ids of every installed aircraft (a folder with an aircraft.json), sorted.
static func list_ids() -> Array:
	var out := []
	var d := DirAccess.open(ROOT)
	if d:
		for sub in d.get_directories():
			if FileAccess.file_exists(ROOT + sub + "/aircraft.json"):
				out.append(sub)
	out.sort()
	return out


static func clear_cache() -> void:
	_cache.clear()


## Full path of a file of this aircraft: the "files" entry of aircraft.json, else the default name.
func path(key: String) -> String:
	var rel: String = str(data.get("files", {}).get(key, FILES.get(key, key)))
	return dir + "/" + rel


func has_file(key: String) -> bool:
	var p := path(key)
	return ResourceLoader.exists(p) or FileAccess.file_exists(p)


## JSON file of this aircraft as a Dictionary ({} when missing or not an object).
func json(key: String) -> Dictionary:
	var p := path(key)
	if not FileAccess.file_exists(p):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(p))
	return j if j is Dictionary else {}


## The flight-model config (config.json), read once.
func config() -> Dictionary:
	if _config.is_empty():
		_config = json("config")
	return _config


## A section of aircraft.json ({} if the aircraft does not define it).
func section(name: String) -> Dictionary:
	var s = data.get(name, {})
	return s if s is Dictionary else {}


## A section merged over defaults, so an aircraft only spells out what differs.
func section_or(name: String, defaults: Dictionary) -> Dictionary:
	var out := defaults.duplicate(true)
	out.merge(section(name), true)
	return out


## Camera view positions, render frame about the CG (x right, y up, z aft): "chase" [back_m, up_m, (follow_rate_per_s)],
## "wing" [x, y, z, (yaw_deg, pitch_deg)] and "tail" [x, y, z], "orbit_m" [distance]. aircraft.json "cameras" wins; otherwise the
## C172's values scaled by wingspan.
func camera(view: String) -> Array:
	var own = section("cameras").get(view, null)
	if own is Array:
		return own
	var base := {"chase": [16.0, 4.0], "wing": [-5.6, 0.9, 1.6], "tail": [0.0, 2.4, 6.8], "orbit_m": [18.0]}
	var k: float = float(config().get("metrics", {}).get("wingspan_m", 10.91184)) / 10.91184
	var out := []
	for v in base[view if view != "orbit" else "orbit_m"]:
		out.append(v * k)
	return out


func display_name() -> String:
	return str(data.get("name", id))


## "piston" or "turbine": the type of engine 1.
func engine_type() -> String:
	var c := config()
	var e: Dictionary = c.engines[0] if c.has("engines") else c.get("engine", {})
	return str(e.get("type", "piston"))


func engine_count() -> int:
	var c := config()
	return (c.engines as Array).size() if c.has("engines") else 1
