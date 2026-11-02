class_name AtcProfile
extends RefCounted
## How the aircraft talks to ATC: the "atc" section of aircraft.json.
##   profile         "ga" (default: VFR circuit phrases, registration call sign) | "airline" (IFR style)
##   wake            L | M | H | J (H and J add "heavy" / "super" to the call sign)
##   telephony       airline radio name, fictional only ("Skyline"); flight_no "123"
##   callsign_style  "registration" (default) | "airline" (telephony + flight number)
## Without the section an aircraft is a GA one. Phrases per profile: phraseology.json "profiles".

const GA := "ga"
const AIRLINE := "airline"
## Generic numbers of the airline phrases (no real SID or STAR is modelled).
const INITIAL_ALT_FT := 5000.0   # initial climb in the IFR clearance
const CLIMB_FL := 100            # "climb flight level 100" after the handover to Approach
const GO_AROUND_ALT_FT := 3000.0  # missed approach: straight ahead to this altitude
const MIN_LEG_M := 100000.0      # the destination is a large airport at least this far away
const DEFAULTS := {"profile": GA, "wake": "L", "telephony": "", "flight_no": "", "callsign_style": "registration"}


## The section with defaults filled in.
static func of(def: AircraftDef) -> Dictionary:
	var out := DEFAULTS.duplicate()
	if def != null:
		out.merge(def.section("atc"), true)
	out.profile = str(out.profile)
	return out


static func is_airline(profile: String) -> bool:
	return profile == AIRLINE


## "Skyline 123" (+ " heavy" for wake H, " super" for J) or "" when the aircraft uses its registration.
## An airline-form call sign typed on the setup screen wins over the aircraft's own flight number.
static func radio_callsign(def: AircraftDef, typed := "") -> String:
	var a := of(def)
	if str(a.callsign_style) != "airline":
		return ""
	var cs := AtcSpeech.normalize_airline_callsign(typed)
	if cs == "":
		cs = AtcSpeech.normalize_airline_callsign("%s %s" % [a.telephony, a.flight_no])
	if cs == "":
		return ""
	var wake := {"H": " heavy", "J": " super"}.get(str(a.wake), "") as String
	return cs if wake == "" or cs.ends_with(wake) else cs + wake


## Tell a controller which aircraft it talks for (profile, radio name).
static func apply(c: AtcController, def: AircraftDef) -> void:
	c.profile = str(of(def).profile)
	c.type_name = str(def.data.get("radio_type", "")) if def != null else ""


## "ILS" when the runway has an ILS (w.ils = idents of the airport's ILS runways), else "visual".
static func approach_kind(w: Dictionary, rwy: String) -> String:
	return "ILS" if rwy != "" and rwy in w.get("ils", []) else "visual"


## Where the flight is going: a large airport in the data (w.dest), else a generic phrase.
static func dest_text(w: Dictionary) -> String:
	var d := str(w.get("dest", ""))
	return d if d != "" else "the filed destination"


## Destination for an airport: the nearest large airport at least MIN_LEG_M away (a name), "" if none.
## Cached in env.dest_cache (the airport list does not change in a flight).
static func dest_for(env: Dictionary, icao: String, pos: Vector2) -> String:
	var cache: Dictionary = env.get("dest_cache", {})
	if cache.has(icao):
		return cache[icao]
	var best := ""
	var bd := 1e12
	for a in env.get("airports", []):
		var id: String = a.icao if str(a.get("icao", "")) != "" else str(a.get("ident", ""))
		if str(a.get("type", "")) != "large_airport" or id == icao:
			continue
		var d := pos.distance_to(Vector2(a.x, a.y))
		if d >= MIN_LEG_M and d < bd:
			bd = d
			best = AtcFacilities.apt_name(id, str(a.get("name", id)))
	cache[icao] = best
	env["dest_cache"] = cache
	return best
