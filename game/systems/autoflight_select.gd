class_name AfSelect
extends RefCounted
## Vertical mode selection from the FCU (split from autoflight_logic.gd, which owns the state this reads and writes):
##   ALT pulled (OPEN) -> OP CLB / OP DES (ALT when already there);  ALT pushed (MANAGED) -> CLB / DES / ALT
##   V/S pulled -> V/S at the preset (within 45 s) or at the present vertical speed;  V/S pushed (LEVEL) -> V/S 0
##   ALT turned alone -> the mode stays; a target on the wrong side of an OP / managed climb or descent, or > 250 ft away in ALT*,
##   reverts to V/S (Airbus: "mode reversion", the V/S is the preset within 45 s, else the present one)
## and the defaults when guidance starts in flight. Returns the mode picked by the pilot ("" = none).


const ALT_STAR_REVERT_M := 76.2  # 250 ft: a bigger FCU altitude change in ALT* is a V/S


## `L` is the AfLogic (untyped on purpose: AfLogic names AfSelect, so a typed reference would be a cycle).
static func modes(L, i: AfInputs) -> String:
	var f := i.f
	var alt_err: float = f.alt - i.alt_m
	if L.lat.mode == "" and L.vert.mode == "":  # guidance has just started in flight
		L.lat.start_hdg()
		L.lat.bank_cmd = i.roll
		if not f.hdg_mgd:
			L.writes["hdg"] = i.heading
		if absf(alt_err) < 30.0:
			L.vert.set_mode("ALT")
		elif f.vs_mgd:
			L.vert.set_mode("CLB" if alt_err > 0.0 else "DES")
		else:
			L.vert.set_mode("V/S")
			L.writes["vs"] = i.vs_mps
	var vm: String = L.vert.mode
	if vm == "SRS" or vm == "G/S" or vm == "G/S*" or L._last.is_empty():
		return ""
	var up := alt_err > 0.0
	var pick := ""
	if f.select == "OPEN":
		pick = "ALT" if absf(alt_err) < 30.0 else ("OP CLB" if up else "OP DES")
	elif f.select == "MANAGED" or (f.vs_mgd and not L._last.vs_mgd):
		pick = "ALT" if absf(alt_err) < 30.0 else ("CLB" if up else "DES")
	elif f.select == "LEVEL":
		pick = "V/S"
		set_vs(L, i, 0.0)
	elif f.select == "VS" or (not f.vs_mgd and L._last.vs_mgd):
		pick = "V/S"
		if vm != "V/S" and L.vs_preset <= 0.0:  # dashes in the window: fly the present vertical speed
			set_vs(L, i, i.vs_mps)
	elif absf(f.alt - L._last.alt) > 1.0:
		pick = _alt_turned(L, i, alt_err)
	if pick != "":
		L.vert.set_mode(pick)
		if pick == "V/S":
			L.preview.vs = 0.0  # the window shows the flown target now
			if f.vs_mgd:  # V/S ends managed guidance: the ALT window loses its dot
				L.writes["vs_mgd"] = false
	return pick


## The V/S target set by the autoflight (back to the FCU through `writes`; this tick flies it already).
static func set_vs(L, i: AfInputs, mps: float) -> void:
	L.writes["vs"] = mps
	i.f.vs = mps


static func _alt_turned(L, i: AfInputs, alt_err: float) -> String:
	var m: String = L.vert.mode
	var wrong: bool = (m in ["OP CLB", "CLB"] and alt_err < -30.0) or (m in ["OP DES", "DES"] and alt_err > 30.0) \
		or (m == "ALT*" and absf(i.f.alt - L._last.alt) > ALT_STAR_REVERT_M)
	if not wrong:
		return ""
	if L.vs_preset <= 0.0:
		set_vs(L, i, i.vs_mps)
	return "V/S"
