class_name AirlinerBusLogic
extends RefCounted
## Which electrical buses of an A320-style network are powered, from the sources: a pure function so
## it is easy to test (the node is airliner_electrical.gd).
## Sources: gen1 / gen2 (engine generators), apu (APU generator), ext (ground power), bat (a battery is
## connected). Each AC bus is fed by its own generator first, then ground power, then the APU generator
## (these three can feed both buses), then the other engine generator through the bus tie. AC ESS
## follows AC 1, then AC 2, then the static inverter off the batteries. TR 1 / TR 2 make DC 1 / DC 2
## from AC 1 / AC 2; DC ESS comes from either DC bus, from AC ESS (ESS TR) or from the batteries; DC BAT
## is DC 1, DC 2 or the batteries.


## in: {gen1, gen2, apu, ext, bat: bool}. out: bus booleans and the source names ("GEN1", "GEN2",
## "EXT", "APU", "TIE", "INV", "BAT", "TR1", "TR2", "ESS TR" or "" for dead).
static func solve(s: Dictionary) -> Dictionary:
	var ac1 := _ac_src(s, "gen1", "gen2")
	var ac2 := _ac_src(s, "gen2", "gen1")
	var ess := "AC1" if ac1 != "" else ("AC2" if ac2 != "" else ("INV" if s.bat else ""))
	var dc1 := ac1 != ""
	var dc2 := ac2 != ""
	var dc_ess := "TR1" if dc1 else ("TR2" if dc2 else ("ESS TR" if ess != "" else ("BAT" if s.bat else "")))
	var dc_bat := "TR1" if dc1 else ("TR2" if dc2 else ("BAT" if s.bat else ""))
	return {
		"ac1": ac1 != "", "ac2": ac2 != "", "ac_ess": ess != "", "dc1": dc1, "dc2": dc2,
		"dc_ess": dc_ess != "", "dc_bat": dc_bat != "",
		"ac1_src": ac1, "ac2_src": ac2, "ac_ess_src": ess, "dc_ess_src": dc_ess, "dc_bat_src": dc_bat,
		"tr_charging": dc1 or dc2,  # the batteries charge off a TR
	}


static func _ac_src(s: Dictionary, own: String, other: String) -> String:
	if s[own]:
		return own.to_upper()
	if s.ext:
		return "EXT"
	if s.apu:
		return "APU"
	if s[other]:
		return "TIE"
	return ""
