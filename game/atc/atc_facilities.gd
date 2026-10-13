class_name AtcFacilities
extends RefCounted
## Which ATC unit COM1 is tuned to, and which one should be called for a service. Works on
## the world snapshot w (atc_world.gd): w.apt (ICAO, "" = none), w.apt_name, w.coms (the
## airport's published frequencies, [{type, desc, mhz}]), w.ctl (control mode) and w.com1_mhz.
## Control modes: "published" (frequencies in the data: tune the right one), "any"
## (controlled, but no frequency in the data: any COM1 frequency is answered), "uncontrolled"
## (no ATC: calls are blind), "none" (no airport in range).
## A unit that is missing at an airport is covered by the next one: clearance DEL -> GND ->
## TWR, ground GND -> TWR, approach APP -> TWR; with no ATIS the tower gives airport information.

const ROLES := ["TWR", "APP", "GND", "DEL", "ATIS"]  # display preference when units share a frequency
const WORD := {"ATIS": "ATIS", "DEL": "Delivery", "GND": "Ground", "TWR": "Tower", "APP": "Approach"}
const TYPE_ROLE := {"ATIS": "ATIS", "CLD": "DEL", "DEL": "DEL", "GND": "GND", "TWR": "TWR", "APP": "APP"}
const SERVICE_ROLES := {
	"atis": ["ATIS"], "info": ["TWR", "APP", "GND", "DEL"], "clearance": ["DEL", "GND", "TWR"],
	"ground": ["GND", "TWR"], "tower": ["TWR"], "approach": ["APP", "TWR"]}
const SKIP_WORDS := ["international", "domestic", "airport", "aerodrome", "airfield", "air", "station",
	"naval", "force", "base", "heliport", "helipad", "civil", "enclave", "ins", "afs", "nas"]
const CONFIG := "res://atc/facilities.json"

static var _cfg := {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		_cfg = d if d is Dictionary else {"names": {}, "controlled_unpublished": [], "departure_routes": {}}
	return _cfg


## Published VHF units: [{role, mhz, desc}]. Other entries (area control, company radio,
## frequencies outside 118-137 MHz) are not airport units and are dropped.
static func entries(coms: Array) -> Array:
	var out := []
	for f in coms:
		var role: String = TYPE_ROLE.get(str(f.get("type", "")), "")
		var mhz: Variant = f.get("mhz", null)
		if role != "" and mhz != null and float(mhz) >= 118.0 and float(mhz) <= 137.0:
			out.append({"role": role, "mhz": float(mhz), "desc": str(f.get("desc", ""))})
	return out


static func control_mode(coms: Array, apt_type: String, icao: String) -> String:
	if not entries(coms).is_empty():
		return "published"
	if icao in config().get("controlled_unpublished", []) or apt_type in ["large_airport", "medium_airport"]:
		return "any"
	return "uncontrolled"


## Spoken airport name for call signs ("Pune Tower"): override, else the airport name without
## generic words ("Juhu Aerodrome" -> "Juhu").
static func apt_name(icao: String, db_name: String) -> String:
	var names: Dictionary = config().get("names", {})
	if names.has(icao):
		return str(names[icao])
	var keep: Array[String] = []
	for wd in db_name.split(" ", false):
		if not (wd.to_lower() in SKIP_WORDS) and not wd.contains("/"):
			keep.append(wd)
	return " ".join(keep) if not keep.is_empty() else icao


static func freq_of(w: Dictionary, role: String) -> float:
	for e in entries(w.get("coms", [])):
		if e.role == role:
			return e.mhz
	return -1.0


static func has_role(w: Dictionary, role: String) -> bool:
	return str(w.get("ctl", "")) == "published" and freq_of(w, role) > 0.0


static func name_of(w: Dictionary, role: String) -> String:
	return "%s %s" % [w.get("apt_name", w.get("apt", "")), WORD.get(role, "ATC")]


## The unit that answers a service: "" if none (uncontrolled or no airport).
static func role_for(w: Dictionary, service: String) -> String:
	match str(w.get("ctl", "none")):
		"any":
			return "TWR"
		"published":
			var svc := service
			if service == "atis" and freq_of(w, "ATIS") <= 0.0:
				svc = "info"
			for r in SERVICE_ROLES.get(svc, []):
				if freq_of(w, r) > 0.0:
					return r
			if svc != "atis":  # whatever unit the airport has covers the rest
				for r in ["TWR", "APP", "GND", "DEL"]:
					if freq_of(w, r) > 0.0:
						return r
	return ""


## What COM1 is tuned to: {mode, role, name, mhz, label}. role "" = no facility on this frequency.
static func tuned(w: Dictionary) -> Dictionary:
	var mode := str(w.get("ctl", "none"))
	var mhz := float(w.get("com1_mhz", 0.0))
	var apt := str(w.get("apt", ""))
	var out := {"mode": mode, "role": "", "name": "", "mhz": mhz, "label": "no facility on this frequency"}
	match mode:
		"none":
			out.label = "no airport in range"
		"uncontrolled":
			out.label = "%s: no ATC (blind calls only)" % apt
		"any":
			out.role = "TWR"
			out.name = name_of(w, "TWR")
			out.label = "%s ATC (answers on any frequency)" % apt
		"published":
			var roles := []
			for e in entries(w.get("coms", [])):
				if absf(e.mhz - mhz) < 0.004:
					roles.append(e.role)
			for r in ROLES:
				if r in roles:
					out.role = r
					out.name = name_of(w, r)
					out.label = "%s %s %.3f" % [apt, WORD[r], mhz]
					break
	return out


## The radio bar's unit text: {text, tone}. tone: ok (a unit answers on this frequency), warn (no
## facility on it), dim (nothing to call: no airport, no ATC), dead (COM1 off or failed).
static func summary(w: Dictionary) -> Dictionary:
	if not bool(w.get("com1_ok", true)):
		return {"text": "off (no power)" if str(w.get("com1_why", "")) == "unpowered" else "failed", "tone": "dead"}
	var t := tuned(w)
	if t.role != "":
		return {"text": str(t.name), "tone": "ok"}
	match str(w.get("ctl", "none")):
		"published":
			return {"text": "no facility", "tone": "warn"}
		"uncontrolled":
			return {"text": "%s has no ATC" % str(w.get("apt_name", w.get("apt", ""))), "tone": "dim"}
	return {"text": "no airport in range", "tone": "dim"}


## Does the unit COM1 is tuned to answer this service?
static func handles(w: Dictionary, service: String) -> bool:
	match str(w.get("ctl", "none")):
		"any":
			return true
		"published":
			var want := role_for(w, service)
			var f := freq_of(w, want) if want != "" else -1.0
			return f > 0.0 and absf(f - float(w.get("com1_mhz", 0.0))) < 0.004
	return false


## The unit to call for a service: {role, name, mhz} (mhz < 0 = not published).
static func facility_for(w: Dictionary, service: String) -> Dictionary:
	var role := role_for(w, service)
	if role == "":
		return {"role": "", "name": "", "mhz": -1.0}
	var f := freq_of(w, role)
	return {"role": role, "name": name_of(w, role), "mhz": f if f > 0.0 else float(w.get("com1_mhz", 0.0))}


## Is there a separate unit for `role` (own frequency) apart from the tower's?
static func separate(w: Dictionary, role: String) -> bool:
	return differs(w, role, "TWR")


## Both units exist and use different frequencies.
static func differs(w: Dictionary, a: String, b: String) -> bool:
	return has_role(w, a) and has_role(w, b) and absf(freq_of(w, a) - freq_of(w, b)) > 0.004
