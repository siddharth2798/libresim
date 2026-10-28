class_name AfFma
extends RefCounted
## Text of the PFD's flight mode annunciator, the strings ap/fma/{thrust, vertical, lateral, approach,
## misc} that ui/displays/pfd.gd draws (lines separated by "\n": the first line is an engaged mode in
## green, the following ones are armed modes in cyan / blue). Pure function of the mode objects.
##   thrust    SPEED MACH THR CLB THR IDLE THR DES RETARD A.FLOOR TOGA LK | MAN TOGA / MAN FLX 50 / MAN THR | LVR CLB
##   vertical  SRS ALT ALT* ALT CRZ V/S OP CLB OP DES CLB DES G/S* G/S LAND (+ armed lines ALT, G/S)
##   lateral   RWY HDG NAV LOC* LOC LAND (+ armed LOC)
##   approach  CAT1 while the localizer is followed in an approach
##   misc      AP1 / AP2 / AP1+2, 1FD2 (flight director), A/THR


static func thrust(thr: AfThrust, i: AfInputs, above_reduction: bool) -> String:
	return thr.fma(i, above_reduction)


static func vertical(v: AfVertical, on_ground_armed: bool) -> String:
	var lines: Array = []
	if v.mode == "":
		if on_ground_armed:
			lines.append("")
			lines.append("SRS")
		return "\n".join(lines)
	var m := "ALT CRZ" if v.mode == "ALT" and v.crz else v.mode
	lines.append("LAND" if v.land and (v.mode == "G/S" or v.mode == "G/S*") else m)
	lines.append_array(v.armed)
	return "\n".join(lines)


static func lateral(l: AfLateral, v: AfVertical, on_ground_armed: bool) -> String:
	if l.mode == "":
		return "\nRWY" if on_ground_armed else ""
	var m := "LAND" if v.land and l.captured() else l.mode
	return m if l.armed == "" else m + "\n" + l.armed


static func approach(l: AfLateral, appr: bool) -> String:
	return "CAT1" if appr and l.captured() else ""


static func misc(ap1: bool, ap2: bool, fd: bool, athr: bool) -> String:
	var lines: Array = []
	lines.append("AP1+2" if ap1 and ap2 else ("AP1" if ap1 else ("AP2" if ap2 else "")))
	lines.append("1FD2" if fd else "")
	lines.append("A/THR" if athr else "")
	var s := "\n".join(lines)
	return s if s.strip_edges() != "" else ""
