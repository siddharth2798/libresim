class_name FbwReversion
extends RefCounted
## Which flight control law is active, from failures and configuration (a simplified A320 reversion logic).
##   NORMAL    everything: load factor / roll rate laws, auto-trim, protections, yaw damper, turn coordination
##   ALTERNATE load factor law and auto-trim stay, protections are lost (stall warning only), roll is direct
##   DIRECT    stick to surface, gearing only; the trim wheel moves the THS
## Triggers (Props "failures/<id>" flags, set by the failure manager or the systems):
##   adr, adirs           air data / inertial reference lost         -> ALTERNATE
##   elac (or elac_1 and elac_2)  both ELACs lost                    -> ALTERNATE (with sec: DIRECT)
##   hyd_g, hyd_b, hyd_y  two circuits lost -> ALTERNATE, all three -> DIRECT
##   fac                  no yaw damper, no rudder travel limit (the law itself is unchanged)
## and the configuration: ALTERNATE with the landing gear down (gear_pos > 0.5) becomes DIRECT.
## `fcs/law_force` (Props, 0..2, absent = automatic) forces at least that law (tests, debugging).

enum {NORMAL, ALTERNATE, DIRECT}
const NAMES := ["NORMAL", "ALTERNATE", "DIRECT"]


## Returns [law, reason] ("" when NORMAL).
static func evaluate(gear_pos: float) -> Array:
	var law := NORMAL
	var why := ""
	if Props.get_b("failures/adr"):
		law = ALTERNATE
		why = "ADR"
	elif Props.get_b("failures/adirs"):
		law = ALTERNATE
		why = "ADIRS"
	var hyd := ""
	for c in ["g", "b", "y"]:
		if Props.get_b("failures/hyd_" + c):
			hyd += ("+" if hyd != "" else "") + c.to_upper()
	if hyd.length() >= 3 and law < ALTERNATE:
		law = ALTERNATE
		why = "HYD " + hyd
	var elac := Props.get_b("failures/elac") or (Props.get_b("failures/elac_1") and Props.get_b("failures/elac_2"))
	if elac and law < ALTERNATE:
		law = ALTERNATE
		why = "ELAC"
	if (elac and Props.get_b("failures/sec")) or hyd.length() >= 5:
		law = DIRECT
		why = "ELAC+SEC" if elac else "HYD " + hyd
	if law == ALTERNATE and gear_pos > 0.5:
		law = DIRECT
		why += " + GEAR DOWN"
	var forced: int = int(Props.get_v("fcs/law_force", -1))
	if forced > law:
		law = forced
		why = "FORCED"
	return [law, why]
