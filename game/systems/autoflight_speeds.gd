class_name AfSpeeds
extends RefCounted
## Speed targets of the autoflight (pure, no Props): V2 / SRS speed, the managed speed schedule and the
## limits a target is held inside (Vls ... Vmax - 5 kt). There is no FMGC, so "managed" is a simple
## schedule: SRS V2 + 10; flaps out: Vls of the configuration plus a margin that shrinks to 5 kt at FULL
## (the approach speed); clean below 10,000 ft 250 kt; above it 300 kt in a climb or 280 kt otherwise, but
## never above Mach 0.78 (the MACH mode then). Rules of thumb on the AirSpeeds tables (aircraft.json
## limits.speeds); optional limits.autoflight {v2_kt, green_dot_kt, below_limit_kt, limit_alt_ft, climb_kt,
## cruise_kt, mach, accel_agl_ft, land_disconnect_ft} override the defaults, green dot = 2 x mass (t) + 85 kt.

const DEFAULTS := {"below_limit_kt": 250.0, "limit_alt_ft": 10000.0, "climb_kt": 300.0, "cruise_kt": 280.0, "mach": 0.78,
	"accel_agl_ft": 1500.0, "land_disconnect_ft": 50.0}
const SRS_CLIMB_MODES := ["SRS", "CLB", "OP CLB"]

var spec: Dictionary
var cfg: Dictionary


func _init(limits := {}) -> void:
	spec = AirSpeeds.spec_of(limits.get("speeds", {}))
	cfg = DEFAULTS.duplicate()
	cfg.merge(limits.get("autoflight", {}), true)


func markers(i: AfInputs) -> Dictionary:
	return AirSpeeds.markers(spec, i.mass_kg, i.ext_deg, i.gear_down, i.pressure_pa)


## V2 (kt) in the current configuration: 1.2 x the 1 g stall speed (or limits.autoflight.v2_kt).
func v2_kt(i: AfInputs) -> float:
	if cfg.has("v2_kt"):
		return float(cfg.v2_kt)
	return 1.2 * AirSpeeds.table(spec.vs1g_kt, i.ext_deg) * sqrt(maxf(i.mass_kg, 1.0) / float(spec.ref_mass_kg))


func green_dot_kt(i: AfInputs) -> float:
	return float(cfg.get("green_dot_kt", 2.0 * i.mass_kg / 1000.0 + 85.0))


## SRS target (m/s): V2 + 10 kt, or the speed the aircraft has when that is higher, up to V2 + 15 kt.
func srs_target(i: AfInputs) -> float:
	var v2 := v2_kt(i)
	return Units.kt_to_mps(clampf(Units.mps_to_kt(i.cas), v2 + 10.0, v2 + 15.0))


## {cas (m/s), mach (bool: the Mach limit decided it)} of the managed schedule for a vertical mode.
func managed(i: AfInputs, vmode: String) -> Dictionary:
	var kt: float
	var mach_lim := false
	if i.flap_lever >= 1 or i.ext_deg > 1.0:
		kt = markers(i).vls + 5.0 * (6 - clampi(i.flap_lever, 1, 5))
	elif Units.m_to_ft(i.alt_m) < float(cfg.limit_alt_ft):
		kt = float(cfg.below_limit_kt)
	else:
		kt = float(cfg.climb_kt if vmode in SRS_CLIMB_MODES else cfg.cruise_kt)
		var cas_m := AirSpeeds.cas_kt_at_mach(float(cfg.mach), i.pressure_pa)
		if cas_m < kt:
			kt = cas_m
			mach_lim = true
	return {"cas": limited(i, Units.kt_to_mps(kt)), "mach": mach_lim}


## A target (m/s) kept between Vls and Vmax - 5 kt.
func limited(i: AfInputs, cas: float) -> float:
	var mk := markers(i)
	return Units.kt_to_mps(minf(maxf(Units.mps_to_kt(cas), mk.vls), mk.vmax - 5.0))
