class_name FlightPlan
extends RefCounted
## Lite flight-management route. The active leg is controls/gps/target and the rest is
## controls/gps/route_next, which Gps sequences and the autopilot flies in NAV (heading managed).
## A waypoint is an airport, VOR, NDB, an airway fix, or a synthetic runway fix.
## Airway designators are expanded by airway.gd before file(). No SID or STAR.
## `known` is Callable(ident) -> bool.

const NOT_IN_DB := "NOT IN DATABASE"


static func split_from_to(text: String) -> Array:
	var out := []
	for p in text.split("/", false):
		var s := str(p).strip_edges()
		if s != "":
			out.append(s)
	return out


## File FROM/VIA/TO. The aircraft is at the origin, so the active waypoint is the next one.
## One ident is a direct-to with no origin. Unknown idents are rejected whole.
static func file(parts: Array, known: Callable) -> Dictionary:
	if parts.is_empty():
		return {"ok": false, "error": NOT_IN_DB, "origin": "", "target": "", "next": []}
	for id in parts:
		if not known.call(str(id)):
			return {"ok": false, "error": NOT_IN_DB, "origin": "", "target": "", "next": []}
	if parts.size() == 1:
		return {"ok": true, "error": "", "origin": "", "target": str(parts[0]), "next": []}
	var rest: Array = parts.slice(1)
	return {"ok": true, "error": "", "origin": str(parts[0]), "target": str(rest[0]), "next": rest.slice(1)}


## Departure fix after the origin, arrival fix before the destination. Empty runway strings
## insert nothing. A direct-to (no origin) is unchanged. Runways are not checked here.
static func with_procedures(filed: Dictionary, dep_rwy: String, arr_rwy: String) -> Dictionary:
	if not filed.get("ok", false) or str(filed.get("origin", "")) == "":
		return filed
	var wps: Array = [str(filed.target)]
	for id in filed.next:
		wps.append(str(id))
	var dep := dep_rwy.strip_edges()
	var arr := arr_rwy.strip_edges()
	if dep != "":
		wps.push_front(RunwayWaypoints.ident(str(filed.origin), dep, "D"))
	if arr != "" and not wps.is_empty():
		wps.insert(wps.size() - 1, RunwayWaypoints.ident(str(wps.back()), arr, "F"))
	return {"ok": true, "error": "", "origin": filed.origin, "target": str(wps[0]), "next": wps.slice(1)}


## Direct-to. An ident already in the plan is skipped to (waypoints before it are dropped).
## A new ident is flown next, then the previous plan resumes. Empty scratch copies the target.
static func direct(scratch: String, target: String, next: Array, known: Callable) -> Dictionary:
	if scratch == "":
		return {"target": target, "next": next, "scratch": target, "error": ""}
	if not known.call(scratch):
		return {"target": target, "next": next, "scratch": NOT_IN_DB, "error": NOT_IN_DB}
	var plan := ([target] if target != "" else []) + next
	var at := plan.find(scratch)
	if at >= 0:
		return {"target": scratch, "next": plan.slice(at + 1), "scratch": "", "error": ""}
	var resume := ([target] if target != "" else []) + next
	return {"target": scratch, "next": resume, "scratch": "", "error": ""}


## Replace or append waypoint `i` (0-based). Empty scratch copies that ident into the scratchpad.
static func edit(wps: Array, i: int, scratch: String, known: Callable) -> Dictionary:
	if scratch == "":
		var copy := str(wps[i]) if i >= 0 and i < wps.size() else ""
		return {"wps": wps, "scratch": copy, "error": ""}
	if not known.call(scratch):
		return {"wps": wps, "scratch": NOT_IN_DB, "error": NOT_IN_DB}
	var out := wps.duplicate()
	if i >= out.size():
		out.append(scratch)
	else:
		out[i] = scratch
	return {"wps": out, "scratch": "", "error": ""}
