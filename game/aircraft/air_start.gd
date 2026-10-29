class_name AirStart
extends RefCounted
## The "In the air" start of an aircraft: how high, how far out on final, how fast, and the gear and
## flap setting it begins with. Read from aircraft.json `start.air`, every key optional:
##   {"alt_ft": 1500, "dist_nm": 5, "kias": 90, "gear": "down" | "up", "flaps": <detent index>,
##    "limits": {"alt_ft": [min, max], "dist_nm": [min, max]}}
## A key the aircraft does not give is derived from its speeds, so a new aircraft needs no block:
##   kias     start.air.kias, else start.air_kt (the older key), else 1.3 x limits.vs1_kias rounded to 5 kt
##            (no vs1: 90)
##   dist_nm  from the approach speed (1.3 x vs1): under 120 kt 5 nm, up to 160 kt 8 nm, above that 11 nm
##   alt_ft   the 3 degree path at that distance: dist_nm x 318 ft rounded to 100 ft
##   gear     "down" (retractable gear only; fixed gear ignores it); flaps 0
##   limits   height 300..12,000 ft, distance 1..25 nm
## The numbers stay in ft / nm / KIAS, what the start screen shows (Session.setup keeps them so too); flight.gd converts.
## The block describes the aircraft's own start. A pilot who sets another airspeed (--air-kt, a lesson)
## gets the gear by that speed instead (up at 200 kt or more) and flaps 0 (world/flight.gd).

const FT_PER_NM_3DEG := 318.0  # 1 nm x tan(3 deg), in ft
const LIMITS := {"alt_ft": [300.0, 12000.0], "dist_nm": [1.0, 25.0]}
const FALLBACK_KIAS := 90.0


## The merged start of `def` (an AircraftDef; null = the default aircraft): {alt_ft, dist_nm, kias, gear, flaps, limits}.
static func of(def: AircraftDef) -> Dictionary:
	var start: Dictionary = def.section("start") if def != null else {}
	var own = start.get("air", {})
	own = own if own is Dictionary else {}
	var vs1 := float(def.section("limits").get("vs1_kias", 0.0)) if def != null else 0.0
	var vapp := vs1 * 1.3
	var kias := float(own.get("kias", start.get("air_kt", roundf(vapp / 5.0) * 5.0 if vs1 > 0.0 else FALLBACK_KIAS)))
	var dist := float(own.get("dist_nm", 5.0 if vapp < 120.0 else (8.0 if vapp <= 160.0 else 11.0)))
	var out := {
		"kias": kias, "dist_nm": dist,
		"alt_ft": float(own.get("alt_ft", roundf(dist * FT_PER_NM_3DEG / 100.0) * 100.0)),
		"gear": "up" if str(own.get("gear", "down")) == "up" else "down",
		"flaps": maxi(int(own.get("flaps", 0)), 0),
		"limits": limits_of(own),
	}
	var lim: Dictionary = out.limits
	out.alt_ft = clampf(out.alt_ft, lim.alt_ft[0], lim.alt_ft[1])
	out.dist_nm = clampf(out.dist_nm, lim.dist_nm[0], lim.dist_nm[1])
	return out


## {alt_ft: [min, max], dist_nm: [min, max]}: the aircraft's own, else LIMITS (a malformed pair is ignored).
static func limits_of(own: Dictionary) -> Dictionary:
	var out := {}
	var given = own.get("limits", {})
	for k in LIMITS:
		var pair = given.get(k) if given is Dictionary else null
		if pair is Array and pair.size() == 2 and float(pair[0]) < float(pair[1]):
			out[k] = [float(pair[0]), float(pair[1])]
		else:
			out[k] = LIMITS[k].duplicate()
	return out


## The setup keys (Session.setup) of the start: {air_ft, air_nm, air_kt}.
static func setup_values(def: AircraftDef) -> Dictionary:
	var a := of(def)
	return {"air_ft": a.alt_ft, "air_nm": a.dist_nm, "air_kt": a.kias}
