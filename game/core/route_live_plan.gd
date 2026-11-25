class_name RouteLivePlan
extends RefCounted
## Saved plans and .PLN files during the flight: the pause screen's Edit route (ui/route_live_page.gd) hands these to its
## plan buttons (RoutePlansBox.save_setup / take_plan).
##   Save, Export  the whole route: the waypoints already flown, then the edited route ahead (RouteLive.join), from the
##                 flight's departure (full_setup).
##   Load, Import  replace only the route ahead (take): the aircraft's present position stays the start, the plan's
##                 waypoints behind the aircraft are left out (behind), and the waypoints the flight has already flown
##                 stay in front of the new ones when applied (RouteLive.commit). A plan from another airport brings its
##                 waypoints and destination; the flight's departure (setup.airport) never changes in the air.
## Nothing reaches the flight before Apply.


## Session.setup-shaped copy of `setup` whose route is the whole plan: flown waypoints (`sp`, RouteLive.split) + `ahead`.
static func full_setup(setup: Dictionary, sp: Dictionary, ahead: Dictionary) -> Dictionary:
	var s := setup.duplicate(true)
	s.route = RouteLive.join(sp, ahead)
	return s


## How many of `route`'s waypoints lie behind the aircraft at `here`: those before the end of the leg nearest to it.
## The legs run from `dep` (position or null) through the waypoints to the destination (`dest`, position or null).
## Before the first leg (nearest to its start) nothing is behind.
static func behind(route: Dictionary, dep: Variant, dest: Variant, here: Vector2) -> int:
	var pts: Array = []
	var off := 0
	if dep != null:
		pts.append(dep)
		off = 1
	for w in route.get("wps", []):
		pts.append(Vector2(float(w.x), float(w.y)))
	if dest != null:
		pts.append(dest)
	if pts.size() < 2:
		return 0
	var best := INF
	var leg := 0
	var at_start := false
	var past_end := false
	for j in pts.size() - 1:
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[j + 1]
		var ab := b - a
		var raw := (here - a).dot(ab) / maxf(ab.length_squared(), 1.0)
		var t := clampf(raw, 0.0, 1.0)
		var dist := here.distance_to(a + ab * t)
		if dist < best - 1.0:  # a shared corner counts for the earlier leg
			best = dist
			leg = j
			at_start = t <= 0.0
			past_end = raw > 1.0 and j == pts.size() - 2
	if leg == 0 and at_start:
		return 0
	if past_end and dest == null:  # beyond the last waypoint with no destination: all of them are flown
		return (route.get("wps", []) as Array).size()
	return clampi(leg + 1 - off, 0, (route.get("wps", []) as Array).size())


## `plan` ({name, departure, aircraft, route}: PlanStore.read, or a .PLN file through PlanImport) as the route ahead of
## the aircraft at `here`, for a flight whose setup is `flight`: {ok, error, route, dropped, text, warn}.
static func take(plan: Dictionary, flight: Dictionary, here: Vector2, d: NavDatabase) -> Dictionary:
	var r := RouteEdit.normalized(RouteSetup.repair(plan.get("route", {})), str(flight.get("aircraft", "")))
	var dep := str(plan.get("departure", "")).to_upper()
	var dep_pos: Variant = d.position_of(dep) if d != null and dep != "" else null
	var dest_pos: Variant = d.position_of(str(r.dest)) if d != null and str(r.dest) != "" else null
	var n := behind(r, dep_pos, dest_pos, here)
	r.wps = (r.wps as Array).slice(n)
	r.kind = "manual"
	r.air_at = -1
	if not RouteEdit.planned(r):
		return {"ok": false, "error": "Every point of that plan is behind the aircraft.", "route": {}, "dropped": n, "text": "",
			"warn": true}
	var text := "Plan \"%s\" loaded as the route ahead." % str(plan.get("name", ""))
	if n > 0:
		text += " %d waypoint%s behind the aircraft left out." % [n, "" if n == 1 else "s"]
	var other := dep != "" and dep != str(flight.get("airport", ""))
	if other:
		text += " It starts at %s: its waypoints and destination are used, the flight's departure stays %s." % [dep,
			str(flight.get("airport", ""))]
	var ac := str(plan.get("aircraft", ""))
	if ac != "" and ac != str(flight.get("aircraft", "")):
		text += " It was planned for another aircraft (%s)." % ac
	return {"ok": true, "error": "", "route": r, "dropped": n, "text": text + " Apply to fly it.", "warn": other or n > 0}
