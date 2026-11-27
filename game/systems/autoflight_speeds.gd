class_name AfSpeeds
extends RefCounted
## Speed targets of the autoflight (pure, no Props): V2 / SRS speed, the managed speed schedule, the selected speed (knots or a
## Mach number held as a CAS, `selected`, and the SPD/MACH window conversion `converted`) and the
## limits a target is held inside (Vls ... Vmax - 5 kt). There is no FMGC, so "managed" is a simple
## schedule: SRS V2 + 10; flaps out: Vls of the configuration plus a margin that shrinks to 5 kt at FULL
## (the approach speed), but at least the S / F speed of the detent (Vls of one detent less + 5 kt; before, CONF 1 asked
## 183 kt while S was 196, so a crew waiting for S never retracted); clean in the approach phase (approach()) green dot; clean below 10,000 ft 250 kt; above it 300 kt in a climb or 280 kt otherwise, but
## never above Mach 0.78 (the MACH mode then). Rules of thumb on the AirSpeeds tables (aircraft.json
## limits.speeds); optional limits.autoflight {v2_kt, green_dot_kt, below_limit_kt, limit_alt_ft, climb_kt,
## cruise_kt, mach, accel_agl_ft, land_disconnect_ft} override the defaults, green dot = 2 x mass (t) + 85 kt.

const DEFAULTS := {"below_limit_kt": 250.0, "limit_alt_ft": 10000.0, "climb_kt": 300.0, "cruise_kt": 280.0, "mach": 0.78,
	"accel_agl_ft": 1500.0, "land_disconnect_ft": 50.0}
const KT_MIN := 100.0  # FCU speed window range
const KT_MAX := 399.0
const MACH_MIN := 0.10  # FCU Mach window range
const MACH_MAX := 0.99
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
		var lever := clampi(i.flap_lever, 1, 5)
		kt = markers(i).vls + 5.0 * (6 - lever)
		if lever < 5:  # at least the S / F speed (Vls of one detent less + 5): the flaps can come in at the target
			kt = maxf(kt, vls_at_lever(i, lever - 1) + 5.0)
	elif approach(i):
		kt = minf(green_dot_kt(i), float(cfg.below_limit_kt))
	elif Units.m_to_ft(i.alt_m) < float(cfg.limit_alt_ft):
		kt = float(cfg.below_limit_kt)
	else:
		kt = float(cfg.climb_kt if vmode in SRS_CLIMB_MODES else cfg.cruise_kt)
		var cas_m := AirSpeeds.cas_kt_at_mach(float(cfg.mach), i.pressure_pa)
		if cas_m < kt:
			kt = cas_m
			mach_lim = true
	return {"cas": limited(i, Units.kt_to_mps(kt)), "mach": mach_lim}


## Vls (kt) in the configuration of flap-lever detent `lever` (the Vs1g table has one row per detent, in lever order), at the present
## mass; the present Vls when the table has no such row.
func vls_at_lever(i: AfInputs, lever: int) -> float:
	var rows: Array = spec.vs1g_kt
	if lever < 0 or lever >= rows.size():
		return markers(i).vls
	var vs1g := float(rows[lever][1]) * sqrt(maxf(i.mass_kg, 1.0) / float(spec.ref_mass_kg))
	return vs1g * float(spec.vls_k)


## The approach phase: the FMS says APPR (avionics/vertical_profile.gd, the DECEL point of the route), or LOC / APPR is armed or
## captured below 7,200 ft radio altitude (the FMGC's own approach-phase height; a vectored approach without a route). Clean,
## managed speed is then green dot, so the flaps can come out (before, 250 kt stayed until the first flap: above VFE CONF 1).
const APPR_RA_M := 7200.0 * 0.3048


static func approach(i: AfInputs) -> bool:
	return not i.wow and (i.fms_phase == "APPR" or ((bool(i.f.appr) or bool(i.f.loc)) and i.ra_m < APPR_RA_M))


## The selected FCU speed as a CAS (m/s): the knots of the window, or with SPD/MACH on the Mach of the window converted at the
## present static pressure (so a Mach target is held as the altitude changes: CAS follows pressure, TAS follows temperature too).
func selected(i: AfInputs) -> float:
	if i.f.spd_mach:
		return AtmosphereISA.cas_at_mach(float(i.f.mach_sel), i.pressure_pa)
	return i.f.spd


## The window value after SPD/MACH is pressed: {"kt", "mach"} with the one that was not shown recomputed from the one that was
## (`to_mach` = the button now says MACH). Knots round to 1 and clamp 100..399, Mach to 0.01 and 0.10..0.99 (the FCU window ranges).
static func converted(to_mach: bool, kt: float, mach: float, pressure_pa: float) -> Dictionary:
	if to_mach:
		mach = clampf(roundf(AtmosphereISA.mach_from_cas(Units.kt_to_mps(kt), pressure_pa) * 100.0) / 100.0, MACH_MIN, MACH_MAX)
	else:
		kt = clampf(roundf(Units.mps_to_kt(AtmosphereISA.cas_at_mach(mach, pressure_pa))), KT_MIN, KT_MAX)
	return {"kt": kt, "mach": mach}


## A target (m/s) kept between Vls and Vmax - 5 kt.
func limited(i: AfInputs, cas: float) -> float:
	var mk := markers(i)
	return Units.kt_to_mps(minf(maxf(Units.mps_to_kt(cas), mk.vls), mk.vmax - 5.0))
