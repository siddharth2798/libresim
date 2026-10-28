class_name GroundParams
extends RefCounted
## What the ground operations (pushback, taxi, stands, service vehicles) need to know about the
## aircraft, read from its aircraft.json "ground" and "pushback" sections. Every key has a default;
## the defaults are the C172's, so an aircraft only spells out what differs. All lengths in metres,
## structural frame about the CG (+x forward). Each reader takes an AircraftDef, null = the current one.
##
## ground:   tow_ahead_m (tug origin ahead of the CG), ahead_m / behind_m / across_m / height_m (footprint),
##           cg_to_door_m (L1 door ahead of the CG, jetbridge gates only), door_height_m (door sill height,
##           what a jetway must clear instead of height_m), nose_gear_m (nose wheel ahead of the CG, where the
##           stop bar is), taxi_half_m (taxiway corridor half width), max_taxi_kt (advice only, absent = none),
##           follow_gap_m (follow-me car ahead of the CG), hold_short_m ("hold short" call distance),
##           min_runway_m, stand_class ("any" | "ga" | "gate"), tug_scale, service {gpu, baggage, fuel, bus}
##           (each [forward, right] from the door; absent = the legacy fixed offsets, see AirportOps).
## pushback: straight_m, radius_m, speed_mps (path = PushbackPath).

const GROUND := {"tow_ahead_m": 3.2, "ahead_m": 3.3, "behind_m": 7.4, "across_m": 6.7, "height_m": 2.5,
	"cg_to_door_m": 0.0, "nose_gear_m": 0.0, "taxi_half_m": 8.0, "follow_gap_m": 35.0, "hold_short_m": 40.0,
	"min_runway_m": 0.0, "stand_class": "any", "tug_scale": 1.0}
const PUSHBACK := {"straight_m": 30.0, "radius_m": 18.0, "speed_mps": 1.4}
const MAX_TAXI_KT_NONE := 0.0


static func _def(def: AircraftDef) -> AircraftDef:
	return def if def != null else AircraftDef.current()


## The "ground" section over the defaults (max_taxi_kt, door_height_m and service only when given).
static func ground(def: AircraftDef = null) -> Dictionary:
	return _def(def).section_or("ground", GROUND)


static func pushback(def: AircraftDef = null) -> Dictionary:
	return _def(def).section_or("pushback", PUSHBACK)


static func max_taxi_kt(def: AircraftDef = null) -> float:
	return float(ground(def).get("max_taxi_kt", MAX_TAXI_KT_NONE))


## Height a jetway part must clear (OpsSolids): the door sill when the aircraft has one, else its height.
static func jetway_clear_m(def: AircraftDef = null) -> float:
	var g := ground(def)
	return float(g.get("door_height_m", g.height_m))


## Follow-me car target gap ahead of the CG: the nose offset + 25 m, never below the C172's 35 m.
static func follow_gap_m(def: AircraftDef = null) -> float:
	var g := ground(def)
	if _def(def).section("ground").has("follow_gap_m"):
		return float(g.follow_gap_m)
	return maxf(float(GROUND.follow_gap_m), float(g.ahead_m) + 25.0)


## Where the CG goes at a stand: a jetbridge gate's point is the L1 door, so the CG sits cg_to_door_m behind
## it along the stand heading; any other stand point is the CG itself.
static func cg_at_stand(st: Dictionary, def: AircraftDef = null) -> Vector2:
	var p := Vector2(st.x, st.y)
	if st.get("jetbridge", false):
		var hd := deg_to_rad(float(st.heading_deg))
		p -= Vector2(sin(hd), cos(hd)) * float(ground(def).cg_to_door_m)
	return p


## The point service-vehicle offsets are measured from: the door (the gate's point, or CG + cg_to_door_m ahead).
static func door_point(st: Dictionary, def: AircraftDef = null) -> Vector2:
	var p := Vector2(st.x, st.y)
	if not st.get("jetbridge", false):
		var hd := deg_to_rad(float(st.heading_deg))
		p += Vector2(sin(hd), cos(hd)) * float(ground(def).cg_to_door_m)
	return p
