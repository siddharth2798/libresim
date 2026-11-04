class_name LessonInfo
extends RefCounted
## The texts of the Training page (training_page.gd) built from a lesson of training/lessons.json. Pure statics, no
## nodes, tested headless (tests/test_training_page.gd).

const MARKER_NAMES := {"centreline": "centreline marker", "hoops": "glide-path rings", "aimpoint": "aim point"}


## "About 5 minutes", "5 steps", "VAPO runway 28", "Clear · 10:00 · wind 280/4": the chips under the title.
static func chips(lesson: Dictionary) -> Array:
	var s: Dictionary = lesson.get("setup", {})
	var out := ["About %d minutes" % int(lesson.get("minutes", 5)), "%d steps" % lesson.get("steps", []).size()]
	if s.has("airport"):
		out.append("%s runway %s" % [s.airport, s.get("runway", "?")])
	out.append(conditions(s))
	return out


## "Clear · 10:00 · wind 280/4" (what the lesson's setup says; the lesson always flies in this).
static func conditions(setup: Dictionary) -> String:
	var t := float(setup.get("time_h", 10.0))
	var h := int(t) % 24
	return "%s · %02d:%02d · wind %03d/%d" % [setup.get("weather", "Clear"), h, int(round((t - floorf(t)) * 60.0)) % 60,
		int(setup.get("wind_dir_deg", 0.0)), int(setup.get("wind_kt", 0.0))]


## Where the lesson starts: on the runway, or in the air on the extended centreline.
static func where(lesson: Dictionary) -> String:
	var s: Dictionary = lesson.get("setup", {})
	var at := "%s runway %s" % [s.get("airport", "?"), s.get("runway", "?")]
	if str(s.get("start", "runway")) == "air":
		var bits := []
		if s.has("air_nm"):
			bits.append("%s nm out" % FailuresLogic.fmt(float(s.air_nm)))
		if s.has("air_ft"):
			bits.append("%d ft" % int(float(s.air_ft)))
		if s.has("air_kt"):
			bits.append("%d kt" % int(float(s.air_kt)))
		return "In the air on the approach to %s%s." % [at, (" (" + ", ".join(bits) + ")") if not bits.is_empty() else ""]
	return "On %s, engine running." % at


## "Markers: centreline marker, glide-path rings." ("" when the lesson draws none).
static func markers(lesson: Dictionary) -> String:
	var names := []
	for m in lesson.get("markers", []):
		names.append(MARKER_NAMES.get(m, str(m)))
	return "" if names.is_empty() else "Markers: %s." % ", ".join(names)


static func learn(lesson: Dictionary) -> Array:
	return lesson.get("learn", []).map(func(t): return str(t))


static func step_titles(lesson: Dictionary) -> Array:
	return lesson.get("steps", []).map(func(st): return str(st.get("title", "")))


## The aircraft a lesson is written for ("Cessna 172S"), "" for a lesson open to any aircraft.
static func aircraft_name(lesson: Dictionary) -> String:
	var ids: Array = lesson.get("aircraft", [])
	if ids.is_empty():
		return ""
	var def := AircraftDef.load_def(str(ids[0]))
	return str(def.data.get("short_name", def.display_name())) if def != null else ""
