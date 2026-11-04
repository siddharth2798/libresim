class_name SavesLogic
extends RefCounted
## The pure part of the Saved flights page (saves_page.gd): the texts of a save (its metadata is what
## core/situation.gd _meta wrote: name, date, airport, aircraft, alt_ft, agl_ft, ias_kt, on_ground) and Guard, the
## two-step "Delete" (the first press only asks; selecting another save or Keep it forgets the question).
## Tested headless (tests/test_saves_page.gd).


static func title(m: Dictionary) -> String:
	return str(m.get("name", "")) if str(m.get("name", "")) != "" else str(m.get("file", "?"))


## "VAPO · Cessna 172S · 2026-10-28 18:05": the line under a saved flight in the list.
static func subline(m: Dictionary) -> String:
	return "%s · %s · %s" % [m.get("airport", "?"), aircraft_name(str(m.get("aircraft", ""))), m.get("date", "")]


## The aircraft's short name; "" id (a save from before the game stored it) = the first aircraft, an unknown id as it is.
static func aircraft_name(id: String) -> String:
	if id == "":
		id = AircraftDef.DEFAULT_ID
	if not id in AircraftDef.list_ids():
		return id
	var def := AircraftDef.load_def(id)
	return str(def.data.get("short_name", def.display_name()))


## "On the ground" or "1,450 ft (1,410 ft above ground), 88 KIAS".
static func where_text(m: Dictionary) -> String:
	if bool(m.get("on_ground", false)):
		return "On the ground"
	return "%s ft (%s ft above ground), %d KIAS" % [_thousands(int(m.get("alt_ft", 0))), _thousands(int(m.get("agl_ft", 0))), int(m.get("ias_kt", 0))]


## "Fair · 18:05 IST · wind 270/8" from the setup stored in the save ("" when it has none).
static func conditions(setup: Dictionary) -> String:
	if setup.is_empty():
		return ""
	var t := float(setup.get("time_h", 10.0))
	return "%s · %02d:%02d IST · wind %03d/%d" % [setup.get("weather", "Fair"), int(t) % 24, int(round((t - floorf(t)) * 60.0)) % 60,
		int(setup.get("wind_dir_deg", 0.0)), int(setup.get("wind_kt", 0.0))]


## The detail table: [[label, value], ...].
static func rows(m: Dictionary, setup: Dictionary) -> Array:
	var out := [["Near", str(m.get("airport", "?"))], ["Aircraft", aircraft_name(str(m.get("aircraft", "")))], ["Where", where_text(m)]]
	var c := conditions(setup)
	if c != "":
		out.append(["Conditions", c])
	out.append(["Saved", str(m.get("date", ""))])
	return out


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + out


## Two-step delete: ask(file) arms it for that save, confirm(file) is true only when that save was asked about.
class Guard extends RefCounted:
	var asked := ""

	func ask(file: String) -> void:
		asked = file

	func is_asked(file: String) -> bool:
		return file != "" and asked == file

	func cancel() -> void:
		asked = ""

	## true once: the save was asked about, so it may be deleted now (and the question is forgotten).
	func confirm(file: String) -> bool:
		var ok := is_asked(file)
		asked = ""
		return ok
