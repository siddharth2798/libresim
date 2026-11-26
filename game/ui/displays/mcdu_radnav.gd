class_name McduRadNav
extends RefCounted
## The RAD NAV page of the MCDU-lite (ui/displays/mcdu.gd): VOR1 frequency and course (NAV1), and the ILS (NAV2).
## The ILS frequency is the one the FMGC tuned for the arrival runway (avionics/ils_autotune.gd): its ident, frequency and
## course show here with AUTO beside them. A frequency typed on the ILS line is a manual tune, which wins over the auto-tune
## (MANUAL); typing AUTO on that line gives the tuning back to the FMGC (controls/ils_auto/resume).
## Keys: L1 VOR1 FREQ, R1 VOR1 CRS, L2 ILS FREQ. Frequencies 108.00 to 117.95 MHz, courses 0 to 360.

const MIN_MHZ := 108.0
const MAX_MHZ := 117.95
const NAV1_FREQ := "controls/nav1/freq_mhz"
const NAV2_FREQ := "controls/nav2/freq_mhz"
const NAV1_CRS := "controls/nav1/obs_deg"
const DIM := Color(0.4, 0.6, 0.7)


## True for a frequency the receivers can tune ("109.5", "110.30").
static func valid_mhz(s: String) -> bool:
	return s.is_valid_float() and float(s) >= MIN_MHZ - 0.001 and float(s) <= MAX_MHZ + 0.001


## One line key on the page: empty scratchpad copies the value into it, a frequency or course tunes, AUTO on the ILS line
## resumes the auto-tune. Writes Props (mcdu/scratch on an error or a copy).
static func line_key(side: String, row: int, s: String) -> void:
	if side == "l" and row == 2 and s.to_upper() == "AUTO":
		Props.set_v("controls/ils_auto/resume", true)
		Props.set_v("mcdu/scratch", "")
		return
	var prop := ""
	var is_freq := true
	if side == "l" and row == 1:
		prop = NAV1_FREQ
	elif side == "l" and row == 2:
		prop = NAV2_FREQ
	elif side == "r" and row == 1:
		prop = NAV1_CRS
		is_freq = false
	if prop == "":
		return
	if s == "":
		Props.set_v("mcdu/scratch", ("%.2f" % Props.get_f(prop)) if is_freq else str(roundi(Props.get_f(prop))))
	elif not s.is_valid_float() or (is_freq and not valid_mhz(s)) or (not is_freq and (float(s) < 0.0 or float(s) > 360.0)):
		Props.set_v("mcdu/scratch", "FORMAT ERROR")
	else:
		Props.set_v(prop, float(s) if is_freq else fposmod(float(s), 360.0))
		Props.set_v("mcdu/scratch", "")


## The ILS line: {ident, mhz, crs, mode ("AUTO" | "MANUAL" | "")}. The ident is the received station's, else the auto-tuned one.
static func ils_state() -> Dictionary:
	var mhz := Props.get_f(NAV2_FREQ)
	var ident := ""
	if str(Props.get_v("avionics/nav2/kind", "")) == "ILS" and Props.get_b("avionics/nav2/valid"):
		ident = str(Props.get_v("avionics/nav2/ident", ""))
	elif Props.get_b("avionics/ils_auto/active"):
		ident = str(Props.get_v("avionics/ils_auto/ident", ""))
	var mode := "MANUAL" if Props.get_b("avionics/ils_auto/manual") else ("AUTO" if Props.get_b("avionics/ils_auto/active") else "")
	return {"ident": ident, "mhz": mhz, "crs": roundi(Props.get_f("controls/nav2/obs_deg")), "mode": mode}


static func paint(d: MCDU) -> void:
	_pair(d, 0, "VOR1 FREQ", "%.2f" % Props.get_f(NAV1_FREQ), "VOR1 CRS", "%03d" % roundi(Props.get_f(NAV1_CRS)))
	var s := ils_state()
	_pair(d, 1, "ILS FREQ", "%.2f" % float(s.mhz), "ILS", str(s.ident) if s.ident != "" else MCDU.DASH)
	d.txt(Vector2(16, 50 + 2 * 44 + 20), str(s.mode), 20, MCDU.GREEN if s.mode == "AUTO" else MCDU.CYAN)
	if s.ident != "":
		d.txt(Vector2(400, 50 + 2 * 44), "CRS", 12, MCDU.WHITE, 1)
		d.txt(Vector2(400, 50 + 2 * 44 + 20), "%03d" % int(s.crs), 20, MCDU.GREEN, 1)
	if s.mode == "MANUAL":
		d.txt(Vector2(16, 50 + 3 * 44 + 20), "AUTO + L2 = FMGC TUNES", 14, DIM)


static func _pair(d: MCDU, row: int, l_label: String, l_val: String, r_label: String, r_val: String) -> void:
	var y := 50.0 + row * 44.0
	d.txt(Vector2(16, y), l_label, 12, MCDU.WHITE)
	d.txt(Vector2(16, y + 20), l_val, 20, MCDU.CYAN)
	d.txt(Vector2(400, y), r_label, 12, MCDU.WHITE, 1)
	d.txt(Vector2(400, y + 20), r_val, 20, MCDU.GREEN if r_val != MCDU.DASH else DIM, 1)
