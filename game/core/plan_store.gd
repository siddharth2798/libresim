class_name PlanStore
extends RefCounted
## Saved route plans of the Free-flight Route step: one JSON file per plan in `dir` (user://plans/; tests point it
## elsewhere). A plan file: {version, name, departure (setup.airport), aircraft, created (ISO local time), route
## (Session.setup.route, RouteSetup.repair'd)}. Names are what the player typed; the file name is a safe form of it, so
## saving the same name again replaces that plan.

const VERSION := 1
const MAX_NAME := 40

static var dir := "user://plans/"


## "VABB to VAPO" -> "vabb_to_vapo"; "" when nothing usable is left.
static func file_key(name: String) -> String:
	var out := ""
	for ch in name.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch in [" ", "-", "_", "."] and not out.ends_with("_") and out != "":
			out += "_"
	return out.trim_suffix("_").left(MAX_NAME)


static func path_of(name: String) -> String:
	return dir.path_join(file_key(name) + ".json")


## A name for the setup's plan: "VABB to VAPO" (or "VABB route" without a destination).
static func default_name(setup: Dictionary) -> String:
	var r := RouteSetup.repair(setup.get("route", {}))
	var dep := str(setup.get("airport", ""))
	if r.is_empty():
		return dep + " route"
	var to: String = str(r.dest) if str(r.dest) != "" else (str(r.wps.back().id) if not r.wps.is_empty() else "")
	return "%s to %s" % [dep, to] if to != "" else dep + " route"


static func exists(name: String) -> bool:
	return file_key(name) != "" and FileAccess.file_exists(path_of(name))


## Save the setup's route as `name`: {ok, error, path}.
static func save(name: String, setup: Dictionary) -> Dictionary:
	var key := file_key(name)
	var r := RouteSetup.repair(setup.get("route", {}))
	if key == "":
		return {"ok": false, "error": "Give the plan a name (letters or digits)", "path": ""}
	if not RouteSetup.active(r):
		return {"ok": false, "error": "There is no route to save", "path": ""}
	DirAccess.make_dir_recursive_absolute(dir)
	var data := {"version": VERSION, "name": name.strip_edges().left(MAX_NAME), "departure": str(setup.get("airport", "")),
		"aircraft": str(setup.get("aircraft", "")), "created": Time.get_datetime_string_from_system(false, true), "route": r}
	var p := path_of(name)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Could not write %s" % p, "path": ""}
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return {"ok": true, "error": "", "path": p}


## Every saved plan, newest first: [{name, key, departure, dest, aircraft, created, wps (count)}].
static func list() -> Array:
	var out := []
	for fn in DirAccess.get_files_at(dir):
		if not fn.ends_with(".json"):
			continue
		var p := read(fn.trim_suffix(".json"))
		if p.is_empty():
			continue
		out.append({"name": p.name, "key": fn.trim_suffix(".json"), "departure": p.departure, "dest": str(p.route.get("dest", "")),
			"aircraft": p.aircraft, "created": p.created, "wps": (p.route.get("wps", []) as Array).size()})
	out.sort_custom(func(a, b): return str(a.created) > str(b.created))
	return out


## The plan stored under file key `key` (a file_key), repaired; {} when missing or unreadable.
static func read(key: String) -> Dictionary:
	var p := dir.path_join(key + ".json")
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not d is Dictionary or not RouteSetup.active(d.get("route")):
		return {}
	return {"name": str(d.get("name", key)), "departure": str(d.get("departure", "")).to_upper(),
		"aircraft": str(d.get("aircraft", "")), "created": str(d.get("created", "")), "route": RouteSetup.repair(d.route)}


static func remove(key: String) -> bool:
	var p := dir.path_join(key + ".json")
	return FileAccess.file_exists(p) and DirAccess.remove_absolute(p) == OK


## Put `plan` (read()) into `setup`: the route, and the departure when it differs (runway and stand then cleared).
## {ok, error, airport_changed, text (what to tell the player)}. A departure the nav data `d` does not know: error.
static func apply(plan: Dictionary, setup: Dictionary, d: NavDatabase) -> Dictionary:
	var dep := str(plan.get("departure", ""))
	if dep == "" or (d != null and d.position_of(dep) == null):
		return {"ok": false, "error": "The plan's departure %s is not in libresim's world" % (dep if dep != "" else "(none)"),
			"airport_changed": false, "text": ""}
	var changed := dep != str(setup.get("airport", ""))
	if changed:
		setup.airport = dep
		setup.runway = ""
		setup.stand = ""
	setup.route = RouteSetup.repair(plan.route).duplicate(true)
	var text := "Plan \"%s\" loaded." % str(plan.get("name", ""))
	if changed:
		text += " The departure is now %s (Airport & start step)." % dep
	var ac := str(plan.get("aircraft", ""))
	if ac != "" and ac != str(setup.get("aircraft", "")):
		text += " It was planned for the %s." % _ac_name(ac)
	return {"ok": true, "error": "", "airport_changed": changed, "text": text}


static func _ac_name(id: String) -> String:
	var def := AircraftDef.load_def(id)
	return str(def.data.get("short_name", def.data.get("name", id))) if def != null else id
