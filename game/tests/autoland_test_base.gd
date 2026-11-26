extends RefCounted
## Shared helpers of the autoland and glide slope tests (test_autoland_calm.gd, test_autoland_wind.gd, test_autoland_modes.gd,
## test_glide_slope_capture.gd): the ILS stations come from the NavDatabase (two runways with different frequencies), a landing is
## flown through the closed-loop rig (tests/af_ils_rig.gd: the real A320 and its fly-by-wire law, the real autoflight, calm air or a
## wind with light turbulence) and the numbers of the touchdown and the roll out are checked against the stated tolerances.

const TD_ALONG_M := [300.0, 900.0]  # touchdown zone, past the threshold
const TD_CROSS_M := 5.0  # from the axis at touchdown
const TD_SINK_FPM := 300.0
const ROLL_CROSS_M := 7.0  # worst offset from the axis on the roll out
const TD_PITCH_DEG := 10.0  # the tail clearance (A320 about 11.7 deg)

var _db: NavDatabase


func db() -> NavDatabase:
	if _db == null:
		_db = NavDatabase.new()
	return _db


## The ILS record of airport `apt` runway `rwy` (the NavDatabase record, simulated or real).
func station(apt: String, rwy: String) -> Dictionary:
	for s in db().ils:
		if str(s.airport) == apt and str(s.runway) == rwy:
			return s
	return {}


## Two stations with different frequencies at two airports, long runways: [{apt, rwy}, {apt, rwy}].
func runways() -> Array:
	return [["VABB", "27"], ["VAPO", "28"]]


## Fly the approach to the end of the roll out (ground speed below 15 kt) or `max_s` s. Returns the rig (the caller frees it).
func land(st: Dictionary, o: Dictionary, max_s := 260.0) -> AfIlsRig:
	var r := AfIlsRig.new(db(), st, o)
	var rolled := 0.0
	for k in int(max_s / AfIlsRig.DT):
		r.step()
		if r.crashed:
			break
		if not r.td.is_empty():
			rolled += AfIlsRig.DT
			if r.gs_kt() < 15.0 or rolled > 80.0:
				break
	return r


## "" or what is wrong with the touchdown and the roll out of `r`.
func check_landing(r: AfIlsRig, label: String) -> String:
	if r.crashed:
		return "%s: crashed" % label
	if r.td.is_empty():
		return "%s: no touchdown, FMA %s" % [label, r.fma_all()]
	var td := r.td
	var line := "    %s: touchdown %.0f m past the threshold, %.1f m from the axis, sink %.0f ft/min, pitch %.1f, heading %.1f deg off, roll out worst %.1f m" % [
		label, td.along, td.cross, -td.vs_fpm, td.pitch, td.heading_err, r.max_cross]
	print(line)
	if td.along < TD_ALONG_M[0] or td.along > TD_ALONG_M[1]:
		return "%s: touchdown %.0f m past the threshold, want %s" % [label, td.along, TD_ALONG_M]
	if absf(td.cross) > TD_CROSS_M:
		return "%s: touchdown %.1f m from the axis, want %.0f at most" % [label, td.cross, TD_CROSS_M]
	if -td.vs_fpm > TD_SINK_FPM:
		return "%s: sink %.0f ft/min at touchdown, want under %.0f" % [label, -td.vs_fpm, TD_SINK_FPM]
	if td.pitch > TD_PITCH_DEG:
		return "%s: pitch %.1f deg at touchdown (tail strike)" % [label, td.pitch]
	if r.max_cross > ROLL_CROSS_M:
		return "%s: %.1f m off the axis on the roll out, want %.0f at most" % [label, r.max_cross, ROLL_CROSS_M]
	return ""


## The FMA words appeared in this order: LAND, FLARE (vertical), ROLL OUT (lateral), THR IDLE then RETARD (thrust).
func check_words(r: AfIlsRig, label: String) -> String:
	var v: Array = r.words.vertical
	var l: Array = r.words.lateral
	var t: Array = r.words.thrust
	var iv := [v.find("G/S"), v.find("LAND"), v.find("FLARE")]
	if iv[0] < 0 or iv[1] <= iv[0] or iv[2] <= iv[1]:
		return "%s: vertical column %s, want G/S, LAND, FLARE in this order" % [label, v]
	if not "ROLL OUT" in l or l.find("LOC") > l.find("ROLL OUT"):
		return "%s: lateral column %s, want LOC then ROLL OUT" % [label, l]
	if not "THR IDLE" in t or not "RETARD" in t or t.find("THR IDLE") > t.find("RETARD"):
		return "%s: thrust column %s, want THR IDLE then RETARD in the flare" % [label, t]
	if not "CAT3 DUAL" in r.words.approach:
		return "%s: approach column %s, want CAT3 DUAL" % [label, r.words.approach]
	return ""
