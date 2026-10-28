class_name AtcPhraseology
extends RefCounted
## Radio phrases from atc/phraseology.json: section -> message key -> unit role -> template
## (a string, or a list of variants picked by a counter). Templates hold {slots}; fill()
## formats each slot by its name in the written (transcript) or spoken (voice) form, see
## atc_speech.gd. Slots whose name starts with opt_ may be empty.
## "profiles" -> profile -> section -> key -> role -> template overrides the base phrase for an
## aircraft profile (aircraft.json atc.profile, e.g. "airline"); a key the profile does not have
## falls back to the base ("ga") template, the role falls back to "*" in each layer.

const PATH := "res://atc/phraseology.json"
## Every slot a template may use, with a sample value (also used by the template check in the tests).
const SAMPLE := {
	"type": "Cessna 172", "callsign": "VT-FSM", "fac": "Pune Tower", "fac2": "Pune Ground", "apt": "Pune", "rwy": "09L",
	"wind": [270.0, 12.0, 20.0], "qnh": 1012.0, "squawk": "4521", "info": "Alpha", "vis": 8000.0, "temp": 31.0,
	"clouds": ["scattered", 3000.0], "alt": 2500.0, "alt_limit": 2000.0, "freq": 118.1, "freq2": 121.9, "freq3": 121.9,
	"pos": "8 miles south-west of the field", "where": "stand 12", "join": "join left-hand downwind runway 09L",
	"opt_via": " via A, B", "opt_info": "information Alpha, ", "opt_route": "via the Lonavala route, ",
	"opt_wx": "light rain, ", "dest": "Delhi", "alt_init": 5000.0, "alt_next": 8000.0, "fl": 120, "stand": "stand 3",
	"appr": "ILS"}

var data := {}


func _init(path := PATH) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("atc: cannot read " + path)


func has(section: String, key: String, profile := "ga") -> bool:
	return data.get(section, {}).has(key) or _layer(profile, section, key) is Dictionary


## The profile's role table for a phrase, or null (the base "ga" phrases are not a layer).
func _layer(profile: String, section: String, key: String) -> Variant:
	if profile == "ga" or profile == "":
		return null
	return data.get("profiles", {}).get(profile, {}).get(section, {}).get(key, null)


## Template for a unit role ("*" = any); a list of variants is indexed by n. "" if missing.
func template(section: String, key: String, role := "*", n := 0, profile := "ga") -> String:
	var by_role: Variant = data.get(section, {}).get(key, null)
	var lay: Variant = _layer(profile, section, key)
	if lay is Dictionary and (lay.has(role) or lay.has("*")):
		by_role = lay
	if not (by_role is Dictionary):
		push_warning("atc: no phrase %s.%s" % [section, key])
		return ""
	var t: Variant = by_role.get(role, by_role.get("*", ""))
	if t is Array:
		return str(t[n % t.size()]) if not t.is_empty() else ""
	return str(t)


func text(section: String, key: String, role: String, slots: Dictionary, spoken := false, n := 0, profile := "ga") -> String:
	return fill(template(section, key, role, n, profile), slots, spoken)


## Every template: [[section, key, role, text], ...] (variants listed separately); a profile's
## phrases come with the section "<profile>/<section>".
func all_templates() -> Array:
	var out := []
	for sec in data:
		if sec.begins_with("_") or not (data[sec] is Dictionary) or sec == "version" or sec == "profiles":
			continue
		_collect(out, sec, data[sec])
	for prof in data.get("profiles", {}):
		if prof.begins_with("_"):
			continue
		for sec in data.profiles[prof]:
			_collect(out, "%s/%s" % [prof, sec], data.profiles[prof][sec])
	return out


static func _collect(out: Array, sec: String, keys: Dictionary) -> void:
	for key in keys:
		for role in keys[key]:
			var t: Variant = keys[key][role]
			for v in (t if t is Array else [t]):
				out.append([sec, key, role, str(v)])


static func slot_names(tpl: String) -> Array:
	var out := []
	var i := 0
	while true:
		var a := tpl.find("{", i)
		var b := tpl.find("}", a + 1) if a >= 0 else -1
		if a < 0 or b < 0:
			break
		out.append(tpl.substr(a + 1, b - a - 1))
		i = b + 1
	return out


func fill(tpl: String, slots: Dictionary, spoken := false) -> String:
	var out := ""
	var i := 0
	while i < tpl.length():
		var a := tpl.find("{", i)
		var b := tpl.find("}", a + 1) if a >= 0 else -1
		if a < 0 or b < 0:
			out += _lit(tpl.substr(i), spoken)
			break
		out += _lit(tpl.substr(i, a - i), spoken)
		var name := tpl.substr(a + 1, b - a - 1)
		if name == "type" and not slots.has(name):  # the aircraft's radio name ("Cessna 172"), aircraft.json radio_type
			out += _lit(str(AircraftDef.current().data.get("radio_type", "aircraft")), spoken)
		else:
			out += _slot(name, slots[name], spoken) if slots.has(name) else "{%s}" % name
		i = b + 1
	return _tidy(out)


static func _lit(s: String, spoken: bool) -> String:
	return AtcSpeech.speak_text(s) if spoken else s


static func _slot(name: String, v: Variant, sp: bool) -> String:
	match name:
		"callsign": return AtcSpeech.callsign(str(v), sp)
		"rwy": return AtcSpeech.runway(str(v)) if sp else str(v)
		"wind":
			var w: Array = v
			return AtcSpeech.wind(float(w[0]), float(w[1]), float(w[2]), sp)
		"qnh": return AtcSpeech.qnh(float(v), sp)
		"squawk": return AtcSpeech.digits(str(v)) if sp else str(v)
		"vis": return AtcSpeech.visibility(float(v), sp)
		"temp": return AtcSpeech.temperature(float(v), sp)
		"alt", "alt_limit", "alt_init", "alt_next": return AtcSpeech.altitude(float(v)) if sp else str(int(round(float(v) / 100.0)) * 100)
		"freq", "freq2": return AtcSpeech.frequency(float(v), sp)
		"freq3": return AtcSpeech.frequency(float(v), true) if sp else "%.3f" % float(v)  # as on the radio display: 118.100
		"clouds":
			if not (v is Array) or str(v[0]) == "":
				return "no significant cloud"
			return "%s %s feet" % [v[0], AtcSpeech.altitude(float(v[1])) if sp else str(int(round(float(v[1]) / 100.0)) * 100)]
		"fl": return ("flight level " + AtcSpeech.digits(str(int(v)))) if sp else "flight level %d" % int(v)
		"opt_via": return AtcSpeech.speak_text(AtcSpeech.taxiways(str(v))) if sp else str(v)
	return AtcSpeech.speak_text(str(v)) if sp else str(v)


## Collapse the gaps that empty opt_ slots leave behind.
static func _tidy(s: String) -> String:
	var t := s
	for pair in [["  ", " "], [" ,", ","], [",,", ","], [", ,", ","], [" .", "."], ["..", "."], [",.", "."]]:
		while t.contains(pair[0]):
			t = t.replace(pair[0], pair[1])
	return t.strip_edges()
