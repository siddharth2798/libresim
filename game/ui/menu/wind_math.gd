class_name WindMath
extends RefCounted
## Pure maths of the wind dial (ui/menu/wind_dial.gd) and of the Weather page's wind line:
## the direction a click on the dial means, the head / cross components on the chosen runway
## and how serious they are for the chosen aircraft. The components and the limits are the
## readiness check's own (core/setup_checks.gd), so the page agrees with "Fly anyway".

enum Level { OK, WARN, BAD }

const SNAP_DEG := 10.0  # the wind direction slider's step
const WARN_FRACTION := 0.8  # amber from this share of the crosswind limit
const WARN_TAIL_KT := 2.0  # and from this much tailwind (red above SetupChecks.TAILWIND_KT)


## Wind direction ("from", degrees true, 0..350 in SNAP_DEG steps) for a point `offset` pixels from
## the dial centre (x right, y down: up is north). -1 for the centre itself, which has no direction.
static func dir_from_offset(offset: Vector2, snap := SNAP_DEG) -> float:
	if offset.length() < 4.0:
		return -1.0
	var deg := rad_to_deg(atan2(offset.x, -offset.y))
	return fposmod(snappedf(deg, snap), 360.0)


## Unit offset (x right, y down) of a bearing in degrees: the inverse of dir_from_offset.
static func offset_of(bearing_deg: float) -> Vector2:
	var r := deg_to_rad(bearing_deg)
	return Vector2(sin(r), -cos(r))


## Vector2(head, cross) in knots: head negative = tailwind, cross positive = from the right.
static func components(wind_dir_deg: float, wind_kt: float, runway_heading_deg: float) -> Vector2:
	return SetupChecks.wind_components(wind_dir_deg, wind_kt, runway_heading_deg)


## The aircraft's crosswind limit in knots (limits.max_crosswind_kt of its aircraft.json).
static func limit_kt(aircraft_id: String) -> float:
	var ac := AircraftDef.load_def(aircraft_id)
	return SetupChecks.max_crosswind_kt(ac) if ac != null else SetupChecks.DEFAULT_MAX_CROSSWIND_KT


## Level of the components against the limit. BAD is exactly what SetupChecks asks "Fly anyway" for
## (crosswind above the limit, tailwind above 5 kt); WARN is the approach to it.
static func level(comp: Vector2, limit: float) -> Level:
	var cross := absf(comp.y)
	var tail := -comp.x
	if cross > limit or tail > SetupChecks.TAILWIND_KT:
		return Level.BAD
	if cross > limit * WARN_FRACTION or tail > WARN_TAIL_KT:
		return Level.WARN
	return Level.OK


static func color(lv: Level) -> Color:
	match lv:
		Level.BAD: return MenuTheme.BAD
		Level.WARN: return MenuTheme.WARN
	return MenuTheme.ACCENT


## The page's wind line: "Rwy 27: headwind 8 kt, crosswind 0 kt right", or the wind alone without a runway.
static func line(ident: String, wind_dir_deg: float, wind_kt: float, comp: Vector2, has_runway: bool) -> String:
	if not has_runway:
		return "Wind %03d° at %d kt. A stand start has no runway: no head or crosswind." % [roundi(wind_dir_deg), roundi(wind_kt)]
	return "Rwy %s: %s %d kt, crosswind %d kt %s" % [ident, "headwind" if comp.x > -0.5 else "TAILWIND",
		roundi(absf(comp.x)), roundi(absf(comp.y)), "right" if comp.y >= 0.0 else "left"]
