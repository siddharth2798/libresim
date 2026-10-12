class_name AtcPhraseology
extends RefCounted
## Radio phrases from atc/phraseology.json: section -> message key -> unit role -> template
## (a string, or a list of variants picked by a counter). Templates hold {slots}; fill()
## formats each slot by its name in the written (transcript) or spoken (voice) form, see
## atc_speech.gd. Slots whose name starts with opt_ may be empty.

const PATH := "res://atc/phraseology.json"
## Every slot a template may use, with a sample value (also used by the template check in the tests).
const SAMPLE := {
	"callsign": "VT-FSM", "fac": "Pune Tower", "fac2": "Pune Ground", "apt": "Pune", "rwy": "09L",
	"wind": [270.0, 12.0, 20.0], "qnh": 1012.0, "squawk": "4521", "info": "Alpha", "vis": 8000.0, "temp": 31.0,
	"clouds": ["scattered", 3000.0], "alt": 2500.0, "alt_limit": 2000.0, "freq": 118.1, "freq2": 121.9,
	"pos": "8 miles south-west of the field", "where": "stand 12", "join": "join left-hand downwind runway 09L",
	"opt_via": " via A, B", "opt_info": "information Alpha, ", "opt_route": "via the Lonavala route, ",
	"opt_wx": "light rain, "}

var data := {}


func _init(path := PATH) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		data = parsed
	else:
		push_error("atc: cannot read " + path)


func has(section: String, key: String) -> bool:
	return data.get(section, {}).has(key)


## Template for a unit role ("*" = any); a list of variants is indexed by n. "" if missing.
func template(section: String, key: String, role := "*", n := 0) -> String:
	var by_role: Variant = data.get(section, {}).get(key, null)
	if not (by_role is Dictionary):
		push_warning("atc: no phrase %s.%s" % [section, key])
		return ""
	var t: Variant = by_role.get(role, by_role.get("*", ""))
	if t is Array:
		return str(t[n % t.size()]) if not t.is_empty() else ""
	return str(t)


func text(section: String, key: String, role: String, slots: Dictionary, spoken := false, n := 0) -> String:
	return fill(template(section, key, role, n), slots, spoken)


## Every template: [[section, key, role, text], ...] (variants listed separately).
func all_templates() -> Array:
	var out := []
	for sec in data:
		if sec.begins_with("_") or not (data[sec] is Dictionary) or sec == "version":
			continue
		for key in data[sec]:
			for role in data[sec][key]:
				var t: Variant = data[sec][key][role]
				for v in (t if t is Array else [t]):
					out.append([sec, key, role, str(v)])
	return out


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
		"alt", "alt_limit": return AtcSpeech.altitude(float(v)) if sp else str(int(round(float(v) / 100.0)) * 100)
		"freq", "freq2": return AtcSpeech.frequency(float(v), sp)
		"clouds":
			if not (v is Array) or str(v[0]) == "":
				return "no significant cloud"
			return "%s %s feet" % [v[0], AtcSpeech.altitude(float(v[1])) if sp else str(int(round(float(v[1]) / 100.0)) * 100)]
		"opt_via": return AtcSpeech.speak_text(AtcSpeech.taxiways(str(v))) if sp else str(v)
	return AtcSpeech.speak_text(str(v)) if sp else str(v)


## Collapse the gaps that empty opt_ slots leave behind.
static func _tidy(s: String) -> String:
	var t := s
	for pair in [["  ", " "], [" ,", ","], [",,", ","], [", ,", ","], [" .", "."], ["..", "."], [",.", "."]]:
		while t.contains(pair[0]):
			t = t.replace(pair[0], pair[1])
	return t.strip_edges()
