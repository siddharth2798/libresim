class_name VerticalProfile
extends RefCounted
## Lite managed profile. There is no constraint list and no published descent path.
## The cruise flight level is the climb target. Top of descent is 300 ft per nautical mile
## plus 8 nm, so the aircraft can level at the destination elevation plus 3,000 ft
## (or plus 1,000 ft when the cruise level is already near that). The caller writes the
## FCU altitude once, when `descend` becomes true.


const FT_PER_NM := 300.0
const FINAL_NM := 8.0
const APPROACH_AGL_FT := 3000.0
const MIN_ABOVE_FT := 400.0


## {approach_ft, tod_nm, descend, phase}. phase is CLB, CRZ or DES.
static func decide(cruise_ft: float, current_ft: float, dist_nm: float, dest_elev_ft: float) -> Dictionary:
	var approach := dest_elev_ft + APPROACH_AGL_FT
	if cruise_ft > 0.0 and approach >= cruise_ft - 500.0:
		approach = dest_elev_ft + 1000.0
	if cruise_ft > 0.0:
		approach = minf(approach, cruise_ft)
	var descent_nm := 0.0
	if current_ft > approach + MIN_ABOVE_FT:
		descent_nm = (current_ft - approach) / FT_PER_NM + FINAL_NM
	var descend := dist_nm > 0.5 and descent_nm > 0.0 and dist_nm <= descent_nm
	var phase := "DES" if descend else ("CLB" if cruise_ft > current_ft + 300.0 else "CRZ")
	return {"approach_ft": approach, "tod_nm": descent_nm, "descend": descend, "phase": phase}
