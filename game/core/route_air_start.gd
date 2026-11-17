class_name RouteAirStart
extends RefCounted
## "In the air" on a leg of the planned route (setup.start == "air" and route.air_at = k >= 0, see RouteSetup.air_leg):
## leg k goes from point k to point k + 1 of [departure, wps..., dest]. The aircraft starts PAST_M beyond point k (half
## way on a leg shorter than twice that), heading along the leg, at the leg's altitude (RouteSetup.leg_alts) but at least
## MIN_AGL_FT above the highest ground from there to AHEAD_M along the leg, clean (gear up, flaps 0), at its cruise
## speed (cruise_kias). The GPS flies point k + 1 (RouteSetup.gps_plan). Otherwise the start is the usual one on final.
## world/flight.gd calls spawn() from _ready (speed, gear, flaps) and place() from _reset.

const NM := 1852.0
const PAST_M := 2.0 * NM
const AHEAD_M := 3.0 * NM
const MIN_AGL_FT := 1000.0
const CRUISE_OF_VNO := 0.85      # derived cruise IAS: 85 % of Vno (C172: 110 KIAS)
const CRUISE_OF_VS1 := 2.2       # no Vno: 2.2 x Vs1
const FALLBACK_KIAS := 100.0     # neither
const SPEED_LIMIT_KIAS := 250.0  # below 10,000 ft
const SPEED_LIMIT_FT := 10000.0
const MAX_MACH := 0.78           # never faster than this at altitude (an airliner's cruise Mach)


## Where on leg `k` of `pts` (Vector2 ENU m) the aircraft starts. `alts` = leg altitudes (ft MSL), `ground_m` =
## Callable(east, north) -> ground height (m). {pos, hdg_deg (true), alt_m, agl_ft, target (index of the next point)}.
static func placement(pts: Array, alts: Array, k: int, ground_m: Callable) -> Dictionary:
	k = clampi(k, 0, pts.size() - 2)
	var a: Vector2 = pts[k]
	var b: Vector2 = pts[k + 1]
	var leg := a.distance_to(b)
	var dir := (b - a) / leg if leg > 1.0 else Vector2(0.0, 1.0)
	var along := minf(PAST_M, leg * 0.5)
	var pos := a + dir * along
	var here := float(ground_m.call(pos.x, pos.y))
	var high := here
	var ahead := minf(AHEAD_M, leg - along)
	for i in range(1, 7):  # every half nm up to AHEAD_M, never past the next point
		var d := AHEAD_M * i / 6.0
		if d > ahead:
			break
		var q := pos + dir * d
		high = maxf(high, float(ground_m.call(q.x, q.y)))
	var alt_ft := float(alts[k]) if k < alts.size() else MIN_AGL_FT
	var alt_m := maxf(alt_ft * 0.3048, high + MIN_AGL_FT * 0.3048)
	return {"pos": pos, "hdg_deg": RoutePlan.bearing_deg(a, b) if leg > 1.0 else 0.0, "alt_m": alt_m,
		"agl_ft": (alt_m - here) / 0.3048, "target": k + 1}


## Cruise IAS (kt) at `alt_ft`: aircraft.json start.air.cruise_kias, else an airliner's managed cruise speed (AfSpeeds
## cfg.cruise_kt, 280 kt), else CRUISE_OF_VNO x limits.vno_kias (no Vno:
## CRUISE_OF_VS1 x vs1_kias; neither: FALLBACK_KIAS), rounded to 5 kt; at most 250 kt below 10,000 ft and MAX_MACH
## (ISA) above; then inside AirStart.kias_range (clean).
static func cruise_kias(def: AircraftDef, alt_ft: float) -> float:
	var own = def.section("start").get("air", {}) if def != null else {}
	var lim: Dictionary = def.section("limits") if def != null else {}
	var kt := 0.0
	if own is Dictionary and float(own.get("cruise_kias", 0.0)) > 0.0:
		kt = float(own.cruise_kias)
	elif def != null and AirlinerNodes.wanted(def):  # the autoflight's managed cruise speed, so A/THR holds what it starts at
		kt = float(AfSpeeds.new(lim).cfg.cruise_kt)
	elif float(lim.get("vno_kias", 0.0)) > 0.0:
		kt = roundf(CRUISE_OF_VNO * float(lim.vno_kias) / 5.0) * 5.0
	elif float(lim.get("vs1_kias", 0.0)) > 0.0:
		kt = roundf(CRUISE_OF_VS1 * float(lim.vs1_kias) / 5.0) * 5.0
	else:
		kt = FALLBACK_KIAS
	if alt_ft < SPEED_LIMIT_FT:
		kt = minf(kt, SPEED_LIMIT_KIAS)
	kt = minf(kt, floorf(mach_kias(MAX_MACH, alt_ft) / 5.0) * 5.0)
	return AirStart.clamp_kias(def, kt, 0)


## IAS (kt, = EAS, no compressibility) of `mach` at `alt_ft` in the ISA.
static func mach_kias(mach: float, alt_ft: float) -> float:
	var h := maxf(alt_ft, 0.0) * 0.3048
	var t := maxf(288.15 - 0.0065 * h, 216.65)
	var rho_ratio: float
	if h <= 11000.0:
		rho_ratio = pow(t / 288.15, 4.2559)
	else:
		rho_ratio = pow(216.65 / 288.15, 4.2559) * exp(-(h - 11000.0) / 6341.6)
	var tas := mach * sqrt(1.4 * 287.05 * t)
	return tas * sqrt(rho_ratio) / 0.514444


## The airborne start of flight.gd (AirStart.spawn's {kias, gear_up, flaps, asked}) for a start on the route: cruise
## speed at the leg altitude, gear up, flaps 0. `a` unchanged when the start is not on the route.
static func spawn(def: AircraftDef, s: Dictionary, a: Dictionary) -> Dictionary:
	var k := RouteSetup.air_leg(s)
	if k < 0:
		return a
	var alts := RouteSetup.leg_alts(RouteSetup.repair(s.get("route", {})))
	return {"kias": cruise_kias(def, float(alts[k])), "asked": -1.0, "gear_up": true, "flaps": 0}


## [departure, wps..., dest] positions, or [] when the departure or the destination is unknown.
static func points(s: Dictionary, db: NavDatabase) -> Array:
	var r := RouteSetup.repair(s.get("route", {}))
	var dep: Variant = db.position_of(str(s.get("airport", ""))) if db != null else null
	if dep == null or r.is_empty():
		return []
	var out: Array = [dep]
	for w in r.wps:
		out.append(Vector2(float(w.x), float(w.y)))
	if str(r.dest) != "":
		var p: Variant = db.position_of(str(r.dest))
		if p == null:
			return []
		out.append(p)
	return out


## flight.gd _reset: put the aircraft on its route leg. False (nothing done) when the start is not on the route.
static func place(f: Node) -> bool:
	var s: Dictionary = Session.setup
	var k := RouteSetup.air_leg(s)
	var pts := points(s, f.get_node("Avionics/Nav").db) if k >= 0 else []
	if pts.size() < 2:
		return false
	var terrain: TerrainQuadtree = f.terrain
	var pl := placement(pts, RouteSetup.leg_alts(RouteSetup.repair(s.route)), k,
		func(x: float, y: float) -> float: return terrain.height_at(x, y))
	var pos: Vector2 = pl.pos
	FloatingOrigin.set_origin(pos)
	var agl_m := float(pl.agl_ft) * 0.3048
	f.fdm_node.place_airborne(pos.x, pos.y, pl.alt_m, pl.hdg_deg, f._air_kt, f.get_node("Weather").wind_at(agl_m), f._air_flaps)
	f._air_ft = pl.agl_ft  # the start lights go by the height above the ground
	if AirlinerNodes.wanted(AircraftDef.current()):
		cruise_state()
	return true


## An airliner in cruise: thrust levers in the CL detent (AirlinerNodes.start_state copies controls/throttle to each
## engine), A/THR armed and managed speed, so A/THR is active and engaging the autopilot flies the route. Trimmed levers
## above CL would leave thrust manual (MAN THR): a managed descent would then climb to lose speed.
static func cruise_state() -> void:
	Props.set_v("controls/throttle", AfThrust.CL)
	Props.set_v("controls/fcu/athr", true)
	Props.set_v("controls/fcu/spd_managed", true)
