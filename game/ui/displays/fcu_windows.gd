class_name FcuWindows
extends RefCounted
## What the four FCU windows show (shared by the 3D glareshield LCD, aircraft/common/fcu_lcd.gd, and the FCU card,
## ui/displays/fcu.gd). Pure: reads Props, returns text and flags. A managed window shows dashes and its dot
## (a value turned while managed shows for a while first, the dot stays: ap/spd_preset 10 s, ap/hdg_preset 45 s,
## systems/autoflight_preview.gd):
##   SPD  controls/fcu/spd_managed: "---" + dot; else the selected speed, or the Mach number with controls/fcu/spd_mach
##        (display only: the Mach of the selected speed at the present speed ratio, the autothrust still flies knots)
##   HDG  controls/fcu/hdg_managed (NAV): "---" + dot; else the selected heading. controls/fcu/trk_fpa only relabels it TRK
##   ALT  always the selected altitude; dot with managed vertical (controls/fcu/vs_managed)
##   V/S  dashes unless the vertical mode is V/S (ap/fma/vertical) or the knob was just turned to preset a value
##        (ap/vs_preset, systems/autoflight_logic.gd: a pull flies it); then the selected V/S, or the flight path angle
##        of it with controls/fcu/trk_fpa (display only)
## The windows are blank without avionics power (systems/electrical/avionics_powered, default on).


static func powered() -> bool:
	return Props.get_b("systems/electrical/avionics_powered", true)


static func spd() -> Dictionary:
	var managed := Props.get_b("controls/fcu/spd_managed")
	var mach := Props.get_b("controls/fcu/spd_mach")
	var kt := Props.get_f("controls/fcu/spd_kt", 250.0)
	var shown := not managed or Props.get_b("ap/spd_preset")  # a turned value shows for 10 s while managed
	var text := ("%03d" % roundi(kt)) if shown else "---"
	if mach and shown:
		text = ".%02d" % clampi(roundi(selected_mach(kt) * 100.0), 0, 99)
	return {"text": text, "dot": managed, "label": "MACH" if mach else "SPD"}


static func hdg() -> Dictionary:
	var managed := Props.get_b("controls/fcu/hdg_managed")
	var shown := not managed or Props.get_b("ap/hdg_preset")  # a turned value shows for 45 s while managed
	var text := ("%03d" % (roundi(Props.get_f("controls/fcu/hdg_deg")) % 360)) if shown else "---"
	return {"text": text, "dot": managed, "label": "TRK" if Props.get_b("controls/fcu/trk_fpa") else "HDG"}


static func alt() -> Dictionary:
	return {"text": "%05d" % roundi(Props.get_f("controls/fcu/alt_ft", 10000.0)), "dot": Props.get_b("controls/fcu/vs_managed"),
		"label": "ALT"}


static func vs() -> Dictionary:
	var fpa := Props.get_b("controls/fcu/trk_fpa")
	var engaged := str(Props.get_v("ap/fma/vertical", "")).get_slice("\n", 0) == "V/S"  # the active mode; armed ones follow
	var fpm := Props.get_f("controls/fcu/vs_fpm")
	var text := "-----" if not (engaged or Props.get_b("ap/vs_preset")) else vs_text(fpm, fpa)
	return {"text": text, "dot": false, "label": "FPA" if fpa else "V/S"}


## "+1500" / "-0700", or with FPA the path angle "+2.5" (from the selected V/S at the present true airspeed).
static func vs_text(fpm: float, fpa: bool) -> String:
	if fpa:
		var tas := maxf(Props.get_f("fdm/tas_mps"), 50.0)
		var deg := rad_to_deg(asin(clampf(fpm * Units.FPM / tas, -0.5, 0.5)))
		return "%s%.1f" % ["-" if deg < -0.05 else "+", absf(deg)]
	var n := roundi(fpm / 100.0) * 100
	return "%s%04d" % ["-" if n < 0 else "+", absi(n)]


## The centre indication between the HDG and ALT windows.
static func mode_label() -> String:
	return "TRK FPA" if Props.get_b("controls/fcu/trk_fpa") else "HDG V/S"


## Mach of `kt` calibrated airspeed, scaled by the present Mach / CAS ratio (0.78 at cruise by default).
static func selected_mach(kt: float) -> float:
	var cas := Units.mps_to_kt(Props.get_f("fdm/cas_mps"))
	var m := Props.get_f("fdm/mach")
	if cas < 60.0 or m <= 0.0:
		return 0.78
	return kt * m / cas
