class_name VerticalProfile
extends RefCounted
## Lite managed profile. There is no published descent path; a STAR's at-or-below limits move the top of descent (caps).
## The cruise flight level is the climb target. Top of descent is 300 ft per nautical mile
## plus 8 nm plus the deceleration allowances (6 nm, and 4 more from above 10,000 ft), so the aircraft can level at the destination
## elevation plus 2,200 ft before the 8 nm arrival fix
## (or plus 1,000 ft when the cruise level is already near that). The caller writes the
## FCU altitude once, when `descend` becomes true.
## Phases: CLB, CRZ, DES, APPR. A descent stays DES below the profile and at the approach altitude (`prev` = the phase of the
## last call; before, it fell back to CLB or CRZ as soon as the aircraft was below the 300 ft / nm line). APPR (the FMGC approach phase, normally from the DECEL point) is the descent within
## APPR_NM of the destination along the route: managed speed then slows to green dot and the flap speeds (AfSpeeds.managed).


const FT_PER_NM := 300.0
const FINAL_NM := 8.0
## Below the 3 deg path at the 8 nm arrival fix (about 2,550 ft above the threshold), so the glide slope is captured from below as
## on a real ILS intercept; at 3,000 ft (before) the aircraft arrived level above the beam and never captured it.
const APPROACH_AGL_FT := 2200.0
const MIN_ABOVE_FT := 400.0
const APPR_NM := 25.0  # route distance to the destination where the approach phase begins (decelerate before the arrival fix)
## The managed descent slows level (it never climbs to lose speed): to green dot in the approach phase, and to 250 kt at 10,000 ft
## when it starts above that. Without these the VABB - VAPO flight was still at 9,900 ft 16 nm before the arrival fix.
const DECEL_NM := 6.0
const LIMIT_DECEL_NM := 4.0
const LIMIT_FT := 10000.0


## {approach_ft, tod_nm, descend, phase}. phase is CLB, CRZ, DES or APPR.
## `caps` = [{s_nm, hi_ft}]: at-or-below limits of a STAR ahead (FmsConstraints.caps; s_nm = route distance from the aircraft).
## The descent path is then the lowest of the 300 ft / nm lines back from the approach level and from each limit, and the top of
## descent is where the aircraft meets it (tod_nm stays a distance to the destination).
static func decide(cruise_ft: float, current_ft: float, dist_nm: float, dest_elev_ft: float, prev := "", caps: Array = []) -> Dictionary:
	var approach := dest_elev_ft + APPROACH_AGL_FT
	if cruise_ft > 0.0 and approach >= cruise_ft - 500.0:
		approach = dest_elev_ft + 1000.0
	if cruise_ft > 0.0:
		approach = minf(approach, cruise_ft)
	var descent_nm := 0.0
	if current_ft > approach + MIN_ABOVE_FT:
		descent_nm = (current_ft - approach) / FT_PER_NM + FINAL_NM + DECEL_NM + (LIMIT_DECEL_NM if current_ft > LIMIT_FT else 0.0)
		for c in caps:
			if float(c.hi_ft) < current_ft - MIN_ABOVE_FT:  # start down this far before the limit: (height to lose) / 300 ft per nm
				descent_nm = maxf(descent_nm, dist_nm - float(c.s_nm) + (current_ft - float(c.hi_ft)) / FT_PER_NM)
	var descend := dist_nm > 0.5 and descent_nm > 0.0 and dist_nm <= descent_nm
	# once descending, still DES below the profile (a descent faster than 300 ft / nm) and at the approach altitude, until back
	# near the cruise level (a new cruise level, a go-around climb)
	var down := (prev == "DES" or prev == "APPR") and (cruise_ft <= 0.0 or current_ft < cruise_ft - 300.0)
	var phase := "DES" if descend or down else ("CLB" if cruise_ft > current_ft + 300.0 else "CRZ")
	if phase == "DES" and dist_nm <= APPR_NM:
		phase = "APPR"
	return {"approach_ft": approach, "tod_nm": descent_nm, "descend": descend, "phase": phase}
