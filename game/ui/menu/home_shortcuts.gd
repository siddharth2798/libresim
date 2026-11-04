class_name HomeShortcuts
extends RefCounted
## What the home screen offers besides the two big cards: "Fly again" (the last Free-flight setup, saved by
## Session.save() in user://last_flight.json) and "Continue" (the lesson after the last one flown). Pure
## functions, no nodes; each one answers {} when there is nothing to offer, so the home screen shows a
## shortcut only when its data exists. Nothing here writes a file.

const STAR := "★"
const EMPTY_STAR := "☆"


## Is there a usable saved flight? The file must parse to a Dictionary that holds at least one setup key of
## the right type; anything else (missing, empty, text, a list) counts as no save.
static func has_saved_flight() -> bool:
	if not FileAccess.file_exists(Session.save_path):
		return false
	var json := JSON.new()  # parse() reports a damaged file as a code, parse_string() would also log an error
	if json.parse(FileAccess.get_file_as_string(Session.save_path)) != OK or not json.data is Dictionary:
		return false
	var d: Dictionary = json.data
	for k in d:
		if Session.DEFAULT.has(k) and typeof(d[k]) == typeof(Session.DEFAULT[k]):
			return true
	return false


## The saved last flight as a repaired, complete setup (Session._load does the repair: unknown keys and
## wrong types dropped, air-start numbers clamped, livery cleaned), or {} when there is no usable save. The
## live Session.setup is not touched. An aircraft that is not installed any more becomes the default one,
## as AircraftDef.load_def does.
static func last_flight() -> Dictionary:
	if not has_saved_flight():
		return {}
	var keep: Dictionary = Session.setup
	Session.setup = Session.DEFAULT.duplicate(true)
	Session._load()
	var out: Dictionary = Session.setup
	Session.setup = keep
	var ac := AircraftDef.load_def(str(out.aircraft))
	if ac != null:
		out.aircraft = ac.id
	return out


## Texts for the Free-flight card: {title: "A320-family · VOMM runway 09", detail: "Fair · 10:00 · 270/8"}.
static func fly_again_info(s: Dictionary) -> Dictionary:
	if s.is_empty():
		return {}
	var ac := AircraftDef.load_def(str(s.get("aircraft", AircraftDef.DEFAULT_ID)))
	var name := str(ac.data.get("short_name", ac.id)) if ac != null else "Aircraft"
	return {"title": "%s · %s" % [name, where(s)], "detail": FlowValues.chip_text("weather", s)}


## Where the flight starts, in words: "VOMM runway 09", "VOMM runway 09 · cold & dark", "VABB stand 12",
## "VAJJ · 1,500 ft · 5 nm final".
static func where(s: Dictionary) -> String:
	var icao := str(s.get("airport", ""))
	match str(s.get("start", "runway")):
		"stand":
			var st := str(s.get("stand", ""))
			return "%s %s" % [icao, ("stand " + st) if st != "" else "gate"]
		"air":
			return "%s · %s ft · %s nm final" % [icao, _thousands(roundi(float(s.get("air_ft", 0.0)))), Session.nm_text(float(s.get("air_nm", 0.0)))]
	var rw := str(s.get("runway", ""))
	if rw == "":
		rw = str(SetupChecks.runway_of(s).get("ident", ""))
	var text := "%s runway %s" % [icao, rw] if rw != "" else "%s runway" % icao
	return text + (" · cold & dark" if bool(s.get("cold", false)) else "")


## The lessons the home screen walks through for an aircraft: those written for it, else all (as the Training page).
static func lessons(aircraft_id: String) -> Array:
	var mine := TrainingLogic.lessons_for(aircraft_id)
	return mine if not mine.is_empty() else TrainingLogic.load_lessons()


## Index of the last lesson flown (best stars above 0) in the list, -1 when none was flown yet.
static func last_done(list: Array, stars: Dictionary) -> int:
	var at := -1
	for i in list.size():
		if int(stars.get(str(list[i].id), 0)) > 0:
			at = i
	return at


## The lesson after the last one flown, or {} when nothing was flown yet or the last one was the final lesson.
static func next_lesson(list: Array, stars: Dictionary) -> Dictionary:
	var at := last_done(list, stars)
	return list[at + 1] if at >= 0 and at + 1 < list.size() else {}


## Texts for the Training card: {title: "Takeoff ★★☆", detail: "1 of 3 lessons flown"} (empty: nothing flown yet).
static func progress_info(list: Array, stars: Dictionary) -> Dictionary:
	var at := last_done(list, stars)
	if at < 0:
		return {}
	var n := list.filter(func(l): return int(stars.get(str(l.id), 0)) > 0).size()
	var got := clampi(int(stars.get(str(list[at].id), 0)), 0, 3)
	return {"title": "%s %s%s" % [list[at].title, STAR.repeat(got), EMPTY_STAR.repeat(3 - got)],
		"detail": "%d of %d lessons flown" % [n, list.size()]}


## Saved flights tile line: "No saves yet", else the newest save "Name · 11-04".
static func saves_line(saves: Array) -> String:
	if saves.is_empty():
		return "No saves yet"
	var m: Dictionary = saves[0]
	var date := str(m.get("date", ""))
	return "%s%s" % [m.get("name", m.get("file", "Saved flight")), (" · " + date.substr(5, 5)) if date.length() >= 10 else ""]


static func _thousands(n: int) -> String:
	var t := str(absi(n))
	for i in range(t.length() - 3, 0, -3):
		t = t.insert(i, ",")
	return ("-" if n < 0 else "") + t
