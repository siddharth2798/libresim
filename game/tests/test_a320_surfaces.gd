extends RefCounted
## Ground-spoiler latch and slat/flap lead on the A320's AirlinerControls.

const A := preload("res://tests/test_fdm_a320.gd")
const B := preload("res://tests/test_fbw_a320.gd")


func test_ground_spoilers_latch_through_a_bounce() -> String:
	var c := _controls()
	c.airborne = false
	c.ground_speed = 10.0
	c.thrust_idle = true
	c._direct()
	if c.ground_spoilers or c.spoiler_cmd[0] > 0.1:
		return "below 15 m/s must not arm: %.1f" % c.spoiler_cmd[0]
	c.ground_speed = 40.0
	c._direct()
	if not c.ground_spoilers or c.spoiler_cmd[0] < 49.0 or c.spoiler_cmd[9] < 49.0:
		return "deploy: %s" % [c.spoiler_cmd]
	c.airborne = true
	c.ground_speed = 5.0
	c._direct()
	if not c.ground_spoilers or c.spoiler_cmd[0] < 49.0:
		return "bounce retracted the spoilers"
	c.thrust_idle = false
	c.speedbrake_cmd = 0.0
	c._direct()
	if c.ground_spoilers or c.spoiler_cmd[0] > 0.1:
		return "thrust must release the latch"
	return ""


func test_slats_lead_and_flaps_lead() -> String:
	var c := _controls()
	c.flap_cmd = 1
	c.update(2.0)
	if c.flap_deg > 0.01 or c.slat_deg < 2.6:
		return "detent 1 moves only slats: flap %.2f slat %.2f" % [c.flap_deg, c.slat_deg]
	c.flap_cmd = 5
	c.flap_deg = 0.0
	c.slat_deg = 0.0
	c.update(1.0)
	if c.flap_deg > 0.05 or c.slat_deg < 1.3:
		return "full extension starts with slats: flap %.2f slat %.2f" % [c.flap_deg, c.slat_deg]
	var saw := false
	for _i in 40:
		var before: float = c.flap_deg
		c.update(1.0)
		if c.flap_deg > 0.05 and c.slat_deg < 25.0:
			return "flaps moved before slats were within 2 deg: flap %.2f slat %.2f" % [c.flap_deg, c.slat_deg]
		if c.slat_deg >= 25.0 and c.flap_deg > before + 0.5:
			saw = true
			break
	if not saw:
		return "flaps never followed the slats: flap %.2f slat %.2f" % [c.flap_deg, c.slat_deg]
	c.snap_flaps()
	c.flap_cmd = 0
	c.update(1.0)
	if c.slat_deg < 26.9 or c.flap_deg > 34.0:
		return "retraction starts with flaps: flap %.2f slat %.2f" % [c.flap_deg, c.slat_deg]
	return ""


func test_fbw_still_commands_ground_spoilers() -> String:
	B.new()._reset_props()
	var f := FDM.new(B.new()._def())
	f.set_on_ground(0.0, 0.0, 0.0)
	f.fcs.airborne = false
	f.fcs.ground_speed = 40.0
	f.fcs.thrust_idle = true
	f.fcs.law.update(0.02, f)
	var c: AirlinerControls = f.fcs
	if not c.ground_spoilers or c.spoiler_cmd[0] < 49.0:
		return "normal law left ground spoilers at %.1f" % c.spoiler_cmd[0]
	var d: Dictionary = JSON.parse_string(JSON.stringify(Situation.capture_fdm(f)))
	var g := FDM.new(B.new()._def())
	Situation.apply_fdm(g, d)
	return "" if g.fcs.ground_spoilers else "saved latch was lost"


## FCOM: CONF FULL, a thrust lever above MCT or alpha protection pull the speedbrake in; it stays in until the cause has
## gone and the lever is back at RET. Ground spoilers still deploy in CONF FULL.
func test_speedbrake_inhibition() -> String:
	var c := _controls()
	c.airborne = true
	c.thrust_idle = true
	c.speedbrake_cmd = 1.0
	c._direct()
	if c.spoiler_cmd[2] < 49.0:
		return "lever full out, CONF 0: speedbrake panel at %.1f" % c.spoiler_cmd[2]
	for cause in ["flaps", "thrust", "alpha"]:
		c.flap_cmd = 5 if cause == "flaps" else 3
		c.thrust_lever.fill(1.0 if cause == "thrust" else 0.556)
		c.alpha_prot = cause == "alpha"
		c._direct()
		if c.spoiler_cmd[2] > 0.1 or not c.speedbrake_inhibited:
			return "%s: speedbrake not inhibited (panel %.1f)" % [cause, c.spoiler_cmd[2]]
		c.flap_cmd = 3
		c.thrust_lever.fill(0.556)
		c.alpha_prot = false
		c._direct()
		if c.spoiler_cmd[2] > 0.1:
			return "%s gone, lever still out: the panels came back out without a lever reset" % cause
		c.speedbrake_cmd = 0.0
		c._direct()
		c.speedbrake_cmd = 1.0
		c._direct()
		if c.speedbrake_inhibited or c.spoiler_cmd[2] < 49.0:
			return "%s: lever reset did not release the inhibition (panel %.1f)" % [cause, c.spoiler_cmd[2]]
	c.thrust_lever.fill(0.778)
	c._direct()
	if c.spoiler_cmd[2] < 49.0:
		return "levers at MCT must not inhibit"
	c.flap_cmd = 5
	c._direct()
	var f := A.new()._fdm()
	f.fcs.flap_cmd = 5
	f.fcs.speedbrake_cmd = 1.0
	f.fcs._direct()
	var d: Dictionary = JSON.parse_string(JSON.stringify(Situation.capture_fdm(f)))
	var g := FDM.new(B.new()._def())
	Situation.apply_fdm(g, d)
	if not g.fcs.speedbrake_inhibited:
		return "saved inhibition latch was lost"
	c.airborne = false
	c.ground_speed = 40.0
	c._direct()
	if not c.ground_spoilers or c.spoiler_cmd[2] < 49.0 or c.spoiler_cmd[0] < 49.0:
		return "CONF FULL must not inhibit the ground spoilers: %s" % [c.spoiler_cmd]
	return ""


func _controls() -> AirlinerControls:
	return A.new()._fdm().fcs
