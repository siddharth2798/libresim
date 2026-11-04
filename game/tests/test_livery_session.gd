extends RefCounted
## Session.setup.livery (core/session.gd, aircraft/common/livery.gd entry / repair_setup / parse_cli): saved with the flight setup,
## repaired on load, set from the command line. The path of the save file is redirected, the player's last flight is never touched.

const FILE := "user://test_livery_session.json"

var _old_setup := {}
var _old_path := ""
var _old_override := -1
var _old_skip := false
var _backed := false


func _backup() -> void:
	if _backed:
		return
	_backed = true
	_old_setup = Session.setup.duplicate(true)
	_old_path = Session.save_path
	_old_override = Session.interactive_override
	_old_skip = Session.skip_menu
	Session.save_path = FILE
	Session.interactive_override = 1


func teardown() -> void:
	if not _backed:
		return
	Session.setup = _old_setup
	Session.save_path = _old_path
	Session.interactive_override = _old_override
	Session.skip_menu = _old_skip
	_backed = false
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(FILE)


func _write(d: Dictionary) -> void:
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))


func _fresh_load() -> void:
	Session.setup = Session.DEFAULT.duplicate(true)
	Session._load()


func test_livery_session_default_is_the_factory_livery() -> String:
	if not Session.DEFAULT.has("livery") or not Session.DEFAULT.livery.is_empty():
		return "Session.DEFAULT.livery must exist and be empty"
	var lv := Livery.of(AircraftDef.load_def("c172"))
	if not Livery.is_identity(lv, Livery.colors_of(lv, Livery.entry(Session.DEFAULT.livery, "c172"))):
		return "a missing entry is the factory livery"
	for junk in [null, 5, "x", [], {"c172": 5}, {"c172": "x"}]:
		if not Livery.entry(junk, "c172").is_empty():
			return "entry(%s) must be {}" % [junk]
	return ""


func test_livery_session_round_trip_through_save_and_load() -> String:
	_backup()
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.livery = {"c172": {"colors": {"body": "#c8101a", "struts": "#102030"}}}
	Session.save()
	if not FileAccess.file_exists(FILE):
		return "save() wrote nothing"
	_fresh_load()
	var e: Dictionary = Livery.entry(Session.setup.livery, "c172")
	if e.get("colors", {}) != {"body": "#c8101a", "struts": "#102030"}:
		return "round trip: %s" % [Session.setup.livery]
	var lv := Livery.of(AircraftDef.load_def("c172"))
	var c := Livery.colors_of(lv, e)
	if Livery.is_identity(lv, c) or Livery.to_hex(c.struts) != "#102030" or Livery.to_hex(c.accent) != Livery.to_hex(lv.regions[1].default):
		return "colours after the round trip: %s" % [c]
	return ""


func test_livery_session_malformed_entries_are_repaired_not_fatal() -> String:
	_backup()
	var cases := [
		["a string", "junk", {}],
		["a list", [1, 2], {}],
		["null", null, {}],
		["an entry that is not a dictionary", {"c172": 5}, {}],
		["unknown aircraft", {"c999": {"colors": {"body": "#fff000"}}}, {}],
		["colors that are not a dictionary", {"c172": {"colors": "red"}}, {}],
		["only bad values", {"c172": {"colors": {"body": "red", "accent": "#12345", "stripe": 7, "ghost": "#ffffff"}}}, {}],
		["good, bad and unknown mixed", {"c172": {"colors": {"body": "#C8101A", "accent": "blue", "ghost": "#ffffff", "stripe": "0A0B0C"}}},
			{"c172": {"colors": {"body": "#c8101a", "stripe": "#0a0b0c"}}}],
	]
	for c in cases:
		var d := Session.DEFAULT.duplicate(true)
		d.livery = c[1]
		_write(d)
		_fresh_load()
		if Session.setup.livery != c[2]:
			return "%s: got %s, want %s" % [c[0], Session.setup.livery, c[2]]
	_write({"airport": "VABB", "livery": {"c172": {"colors": {"body": "#c8101a"}, "stickers": {"fin": {"scale": 1.0}}}}})
	_fresh_load()
	if not Session.setup.livery.c172.has("stickers") or Session.setup.airport != "VABB":
		return "other keys of an entry (the stickers of L3) are kept, the rest of the setup still loads: %s" % [Session.setup.livery]
	_write({"airport": "VABB"})  # saved before the livery existed
	_fresh_load()
	return "" if Session.setup.livery == {} and Session.setup.airport == "VABB" else "an old save has no livery: %s" % [Session.setup.livery]


func test_livery_cli_value_parse() -> String:
	var a := Livery.parse_cli("body=#C8101A,accent=f2f2f2", "c172")
	if a != {"c172": {"colors": {"body": "#c8101a", "accent": "#f2f2f2"}}}:
		return "plain form: %s" % [a]
	var b := Livery.parse_cli("c172:body=#102030,a320:fin=#405060, ,x,=#fff,body=zzz,stripe", "c172")
	if b != {"c172": {"colors": {"body": "#102030"}}, "a320": {"colors": {"fin": "#405060"}}}:
		return "per-aircraft form and bad items: %s" % [b]
	return "" if Livery.parse_cli("", "c172").is_empty() else "empty value"


func test_livery_cli_option_sets_the_setup() -> String:
	_backup()
	Session._parse_args(PackedStringArray(["--livery=body=#c8101a,accent=#f2f2f2,ghost=#123456,stripe=nope", "--airport=VABB"]))
	var e := Livery.entry(Session.setup.livery, str(Session.setup.aircraft))
	if e.get("colors", {}) != {"body": "#c8101a", "accent": "#f2f2f2"}:
		return "--livery on the chosen aircraft: unknown region and bad hex are dropped: %s" % [Session.setup.livery]
	if not Session.skip_menu:
		return "--livery is a flight option: the start screen is skipped"
	Session._parse_args(PackedStringArray(["--livery=c172:struts=#00aa00,c999:body=#fff000", "--aircraft=c172"]))
	if Session.setup.livery != {"c172": {"colors": {"struts": "#00aa00"}}}:
		return "per-aircraft form, unknown aircraft dropped: %s" % [Session.setup.livery]
	Session._parse_args(PackedStringArray(["--airport=VABB"]))
	return "" if Session.setup.livery.is_empty() else "a command-line flight starts from the factory livery: %s" % [Session.setup.livery]
