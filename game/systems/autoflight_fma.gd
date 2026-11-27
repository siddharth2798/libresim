class_name AfFma
extends RefCounted
## Text of the PFD's flight mode annunciator, the strings ap/fma/{thrust, vertical, lateral, approach,
## misc} that ui/displays/pfd.gd draws (lines separated by "\n": the first line is an engaged mode in
## green, the following ones are armed modes in cyan / blue). Pure function of the mode objects.
##   thrust    SPEED MACH (the selected or managed target is a speed or a Mach number) THR CLB THR IDLE THR DES RETARD (the last two also in the flare) A.FLOOR TOGA LK | MAN TOGA / MAN FLX 50 / MAN THR | LVR CLB
##   vertical  SRS ALT ALT* ALT CRZ ALT CST* ALT CST V/S OP CLB OP DES CLB DES G/S* G/S LAND FLARE (+ armed lines ALT, G/S)
##   lateral   RWY HDG NAV LOC* LOC ROLL OUT (+ armed LOC)
##   approach  CAT1 or CAT3 DUAL while the localizer is followed in an approach
##   misc      AP1 / AP2 / AP1+2, 1FD2 (flight director), A/THR


static func thrust(thr: AfThrust, i: AfInputs, above_reduction: bool) -> String:
	return thr.fma(i, above_reduction)


static func vertical(v: AfVertical, on_ground_armed: bool, land: AfLand = null) -> String:
	var lines: Array = []
	if land != null and land.active():  # LAND, FLARE (nothing on the roll out: the lateral column says ROLL OUT)
		return land.fma_vertical()
	if v.mode == "":
		if on_ground_armed:
			lines.append("")
			lines.append("SRS")
		return "\n".join(lines)
	var m := "ALT CRZ" if v.mode == "ALT" and v.crz else v.mode
	if v.cst and (v.mode == "ALT" or v.mode == "ALT*"):
		m = "ALT CST" + ("*" if v.mode == "ALT*" else "")
	lines.append(m)
	lines.append_array(v.armed)
	return "\n".join(lines)


static func lateral(l: AfLateral, on_ground_armed: bool, land: AfLand = null) -> String:
	if land != null and land.rolling():
		return "ROLL OUT"
	if l.mode == "":
		return "\nRWY" if on_ground_armed else ""
	return l.mode if l.armed == "" else l.mode + "\n" + l.armed


## Approach capability (column 4, white): CAT3 DUAL with both APs, the ILS and the landing configuration (`capable`, AfLand.capable)
## or while an autoland goes on, CAT1 otherwise, while the localizer is followed in an approach.
static func approach(l: AfLateral, appr: bool, land: AfLand = null, capable := false) -> String:
	if land != null and land.active():
		return "CAT3 DUAL"
	if not (appr and l.captured()):
		return ""
	return "CAT3 DUAL" if capable else "CAT1"


## Colour of line `n` of an FMA column: "green" (engaged), "cyan" (armed), "white", "amber". `col` is the column name, `whole` the
## column text, `athr_active` = the autothrust commands the levers. Thrust column: a manual or requested state (MAN TOGA / FLX /
## MCT / THR, LVR CLB) is white (the real FMA boxes it, MAN THR in amber), LVR ASYM amber, the active modes green. Columns 2 and
## 3: line 1 engaged green, the lines below armed cyan. Column 4 white. Column 5 white; A/THR is white when active, cyan when
## only armed. docs/A320-FCU-REFERENCE.md.
static func color(col: String, n: int, whole: String, athr_active: bool) -> String:
	var line := whole.split("\n")[n] if n < whole.count("\n") + 1 else ""
	match col:
		"thrust":
			if whole.begins_with("LVR ASYM"):
				return "amber"
			return "white" if whole.begins_with("MAN") or whole.begins_with("LVR") else "green"
		"vertical", "lateral":
			return "green" if n == 0 else "cyan"
		"misc":
			return ("white" if athr_active else "cyan") if line == "A/THR" else "white"
	return "white"


## The box drawn round a thrust column text: MAN TOGA / FLX / MCT white, MAN THR amber, A.FLOOR and TOGA LK amber; "" = none
## (FBW first-column page; the white box of a changed mode is not modelled).
static func box(col: String, whole: String) -> String:
	if col != "thrust":
		return ""
	if whole.begins_with("MAN\nTHR") or whole in ["A.FLOOR", "TOGA LK"]:
		return "amber"
	return "white" if whole.begins_with("MAN") else ""


## Does the text flash (LVR CLB: the levers should go to the CL detent)?
static func flashes(col: String, whole: String) -> bool:
	return col == "thrust" and whole.begins_with("LVR CLB")


static func misc(ap1: bool, ap2: bool, fd: bool, athr: bool) -> String:
	var lines: Array = []
	lines.append("AP1+2" if ap1 and ap2 else ("AP1" if ap1 else ("AP2" if ap2 else "")))
	lines.append("1FD2" if fd else "")
	lines.append("A/THR" if athr else "")
	var s := "\n".join(lines)
	return s if s.strip_edges() != "" else ""
