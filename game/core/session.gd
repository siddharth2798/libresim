extends Node
## Autoload "Session": the flight setup chosen on the start screen (or on the command
## line), handed to the flight scene. Saved to user://last_flight.json so the start
## screen reopens with the previous choices.
## Command-line flight options (after "--") skip the start screen; see world/flight.gd.

const SAVE := "user://last_flight.json"
const DEFAULT := {
	"airport": "VAJJ", "runway": "", "start": "runway",  # runway | stand | air
	"stand": "", "air_ft": 1500.0, "air_nm": 5.0, "cold": false,
	"aircraft": "c172",
	"fuel_gal": 17.0, "copilot_kg": 0.0, "rear_kg": 0.0, "baggage_kg": 0.0,  # per tank / per station
	"weather": "Fair", "time_h": 10.0, "time_rate": 1.0, "day_of_year": 45.0,
	"wind_dir_deg": 270.0, "wind_kt": 8.0, "gust_kt": 0.0, "turbulence": 0.15,
	"visibility_m": 20000.0, "cloud_cover": 0.3, "cloud_base_ft": 4500.0,
	"qnh_hpa": 1012.0, "temp_c": 30.0, "precip": 0.0,
	"failures": {},  # id -> [mode index (FailureCatalog.MODES), value]
	"random": {"enabled": false, "count": 1, "from_min": 2.0, "to_min": 30.0,
		"categories": ["Engine", "Fuel", "Electrical", "Vacuum & gyros", "Pitot-static", "Flight controls", "Avionics"]},
	"notify": true,
	"record": false, "record_dir": "", "record_height": 720, "record_fps": 30, "record_mp4": true,  # tell the pilot when a failure happens (off = find out yourself)
}
## Weather presets: name -> weather/* values (wind is chosen separately).
## precip: rain 0..1 (below 0.3 it comes and goes in showers; visibility_m is between showers).
const WEATHER := {
	"Clear": {"cloud_cover": 0.0, "cloud_base_ft": 6000.0, "visibility_m": 40000.0, "turbulence": 0.05, "precip": 0.0},
	"Fair": {"cloud_cover": 0.3, "cloud_base_ft": 4500.0, "visibility_m": 20000.0, "turbulence": 0.15, "precip": 0.0},
	"Scattered": {"cloud_cover": 0.5, "cloud_base_ft": 3000.0, "visibility_m": 15000.0, "turbulence": 0.2, "precip": 0.0},
	"Broken": {"cloud_cover": 0.75, "cloud_base_ft": 2500.0, "visibility_m": 10000.0, "turbulence": 0.3, "precip": 0.12},
	"Overcast": {"cloud_cover": 0.95, "cloud_base_ft": 1800.0, "visibility_m": 7000.0, "turbulence": 0.3, "precip": 0.3},
	"Winter haze": {"cloud_cover": 0.05, "cloud_base_ft": 5000.0, "visibility_m": 3000.0, "turbulence": 0.05, "precip": 0.0},
	"Monsoon": {"cloud_cover": 1.0, "cloud_base_ft": 1200.0, "visibility_m": 5000.0, "turbulence": 0.55, "precip": 0.9},
}
const WEATHER_KEYS := ["wind_dir_deg", "wind_kt", "gust_kt", "turbulence", "visibility_m",
	"cloud_cover", "cloud_base_ft", "qnh_hpa", "temp_c", "time_h", "time_rate", "day_of_year", "precip"]

var setup := {}
## Training: lesson id ("" = free flight) and assist level (full | light | off). A lesson
## rewrites `setup` for its own airport / weather; the free-flight setup is kept here and
## restored when the menu opens again (end_lesson).
var training := ""
var assist := "full"
var _lesson_backup := {}
var skip_menu := false  # flight options were given on the command line
## Test / capture options (command line only).
var shot := ""
var shot_time := 6.0
var view := ""
var clean := false  # hide all UI (for promo shots)


func _ready() -> void:
	setup = DEFAULT.duplicate(true)
	_load()
	_parse_cmdline()


func _load() -> void:
	if not FileAccess.file_exists(SAVE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if d is Dictionary:
		for k in d:
			if setup.has(k):
				setup[k] = d[k]


## Start a lesson: remember the free-flight setup, then let `fn` overwrite it for the lesson.
func begin_lesson(id: String, lesson_setup: Dictionary, assist_level: String) -> void:
	if _lesson_backup.is_empty():
		_lesson_backup = setup.duplicate(true)
	if lesson_setup.has("weather"):
		apply_weather_preset(lesson_setup.weather)
	for k in lesson_setup:
		setup[k] = lesson_setup[k]
	setup.failures = {}
	setup.random = {"enabled": false, "count": 1, "from_min": 2.0, "to_min": 30.0, "categories": []}
	setup.record = false
	training = id
	assist = assist_level


func end_lesson() -> void:
	if not _lesson_backup.is_empty():
		setup = _lesson_backup
		_lesson_backup = {}
	training = ""


func save() -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(setup, "\t"))


func _parse_cmdline() -> void:
	var cmd := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		cmd[kv[0]] = kv[1] if kv.size() > 1 else ""
	if cmd.keys().all(func(k): return k in ["quality", "menu"]):
		return  # no flight options: start screen with the last setup
	# a command-line flight starts from the defaults, not from the last saved setup
	setup = DEFAULT.duplicate(true)
	skip_menu = not cmd.has("menu")
	for k in cmd:
		var v: String = cmd[k]
		match k:
			"airport": setup.airport = v.to_upper()
			"runway": setup.runway = v
			"air":
				setup.start = "air"
				setup.air_ft = float(v) if v != "" else 1500.0
			"air-nm": setup.air_nm = float(v)  # distance out on final for --air
			"stand":
				setup.start = "stand"
				setup.stand = v
			"cold": setup.cold = true
			"tod": setup.time_h = float(v)
			"day": setup.day_of_year = float(v)  # day of the year (moon phase, sun times)
			"vis": setup.visibility_m = float(v)
			"rain": setup.precip = clampf(float(v), 0.0, 1.0)  # --rain=0..1
			"wind": _wind(v)
			"clouds": _clouds(v)
			"weather":
				for n in WEATHER:  # case-insensitive: "winter haze", "MONSOON"
					if n.to_lower() == v.to_lower().replace("_", " "):
						apply_weather_preset(n)
			"fail":  # --fail=engine,vacuum_pump (at start) or engine@5 (after 5 min)
				for f in v.split(","):
					var p := f.split("@")
					setup.failures[p[0]] = [2, float(p[1])] if p.size() > 1 else [1, 0.0]
			"random-failures": setup.random.enabled = true
			"shot": shot = v
			"time": shot_time = float(v) + 6.0
			"view": view = v
			"clean": clean = true
			"record": setup.record = true
	if cmd.has("lesson"):  # --lesson=landing[,light]
		var parts: PackedStringArray = str(cmd.lesson).split(",")
		var lesson := TrainingLogic.find(parts[0])
		if lesson.is_empty():
			push_warning("unknown lesson: " + parts[0])
		else:
			begin_lesson(lesson.id, lesson.setup, parts[1] if parts.size() > 1 else "full")
			skip_menu = true


func _wind(v: String) -> void:  # "270/15" or "270/15G25"
	var p := v.split("/")
	setup.wind_dir_deg = float(p[0])
	var sp := p[1].split("G")
	setup.wind_kt = float(sp[0])
	setup.gust_kt = float(sp[1]) if sp.size() > 1 else 0.0


func _clouds(v: String) -> void:  # "0.5@3500" = cover@base_ft
	var p := v.split("@")
	setup.cloud_cover = float(p[0])
	if p.size() > 1:
		setup.cloud_base_ft = float(p[1])


func apply_weather_preset(name: String) -> void:
	if not WEATHER.has(name):
		return
	setup.weather = name
	for k in WEATHER[name]:
		setup[k] = WEATHER[name][k]


## Push the chosen environment into Props (called by the flight scene before it builds)
## and clear leftovers from a previous flight in this session.
func apply_to_props() -> void:
	for k in WEATHER_KEYS:
		Props.set_v("weather/" + k, float(setup[k]))
	# wind aloft: veers ~10 deg and roughly 1.6x the surface wind, as weather.gd expects
	Props.set_v("weather/aloft_dir_deg", float(setup.wind_dir_deg) + 10.0)
	Props.set_v("weather/aloft_kt", float(setup.wind_kt) * 1.6)
	FailureCatalog.clear_all()
	for k in ["ops/stand", "ops/taxi_route", "controls/gps/target"]:
		Props.set_v(k, "")


## One-line summary for the start screen.
func summary() -> String:
	var where: String = {"runway": "runway %s" % (setup.runway if setup.runway != "" else "(longest)"),
		"stand": "stand %s" % (setup.stand if setup.stand != "" else "(gate)"),
		"air": "%d ft, %.0f nm final" % [int(setup.air_ft), float(setup.air_nm)]}[setup.start]
	var t := float(setup.time_h)
	var nf := 0
	for id in setup.failures:
		if int(setup.failures[id][0]) > 0:
			nf += 1
	return "%s · %s%s · %s · %02d:%02d IST · wind %03d/%d%s · %d failure(s)%s" % [setup.airport, where,
		" · cold & dark" if (setup.cold and setup.start == "runway") or setup.start == "stand" else "", setup.weather, int(t), int(fmod(t, 1.0) * 60.0),
		int(setup.wind_dir_deg), int(setup.wind_kt), ("G%d" % int(setup.gust_kt)) if setup.gust_kt > setup.wind_kt else "",
		nf, " + random" if setup.random.enabled else ""] + ("  · ● REC" if setup.get("record", false) else "")
