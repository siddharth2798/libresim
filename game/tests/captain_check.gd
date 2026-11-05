class_name CaptainCheck
extends RefCounted
## The checklist behind tests/check_a320_controls.gd: every Captain Pack control to be moved once on the real hardware, with the
## game's response that proves it works. Pure logic: feed() it a snapshot of the control state each frame and it ticks the items
## whose condition is met. An item that needs a move first (back to IDLE, back to 0, ON again) ticks only after the lever or switch
## has been seen elsewhere.
##
## Snapshot keys (what the game computed, not raw hardware): pitch, roll, yaw (-1..1), thr1, thr2 (lever position 0..1),
## name1, name2 (detent name at that position), rev1, rev2 (0..1), flaps (setting number, A320: 0, 1, 1+F = 2, 2 = 3,
## 3 = 4, FULL = 5), sb (speed brake 0..1), mode (0 NORM, 1 CRANK, 2 IGN/START), gear (0 up, 1 down), ab (auto brake
## 0..3), m1, m2 (engine masters), park (parking brake), btn (Dictionary: pad button number -> pressed, buttons 21..25).

## [group, [[id, label], ...]] in the order the window shows them.
const GROUPS := [
	["Sidestick", [["pitch_fwd", "Push FORWARD (nose down)"], ["pitch_back", "Pull BACK (nose up)"],
		["roll_l", "Roll LEFT"], ["roll_r", "Roll RIGHT"], ["yaw_l", "Twist LEFT"], ["yaw_r", "Twist RIGHT"]]],
	["Thrust lever 1 (left)", [["l1_cl", "CLB click"], ["l1_flx", "FLX/MCT click"], ["l1_toga", "TOGA (full forward)"],
		["l1_idle", "Back to IDLE, seated in the detent"], ["l1_rev", "REVERSE (pull behind idle, to the stop)"]]],
	["Thrust lever 2 (right)", [["l2_cl", "CLB click"], ["l2_flx", "FLX/MCT click"], ["l2_toga", "TOGA (full forward)"],
		["l2_idle", "Back to IDLE, seated in the detent"], ["l2_rev", "REVERSE (pull behind idle, to the stop)"]]],
	["Flaps lever", [["fl_1", "Notch 1  (shows 1+F on the ground)"], ["fl_2", "Notch 2"], ["fl_3", "Notch 3"],
		["fl_full", "Notch FULL"], ["fl_0", "Back to 0"]]],
	["Speed brake lever", [["sb_25", "Stop 2"], ["sb_50", "Stop 3"], ["sb_75", "Stop 4"],
		["sb_100", "Fully deployed"], ["sb_0", "Back to retracted"]]],
	["Engine mode selector", [["mode_crank", "CRANK"], ["mode_ign", "IGN/START"], ["mode_norm", "Back to NORM"]]],
	["Gear lever", [["gear_up", "UP"], ["gear_dn", "DOWN again"]]],
	["Auto brake dial", [["ab_btv", "BTV"], ["ab_low", "LOW"], ["ab_2", "2"], ["ab_3", "3"], ["ab_hi", "HI"],
		["ab_off", "Back to DISARM"]]],
	["Engine masters", [["m1_off", "ENG 1 master OFF"], ["m1_on", "ENG 1 master ON again"],
		["m2_off", "ENG 2 master OFF"], ["m2_on", "ENG 2 master ON again"]]],
	["Parking brake switch", [["park_on", "ON"], ["park_off", "OFF again"]]],
]
const WARMUP := 0.6  # s: the start-up sync of the switches is not a movement

var done := {}
var _seen := {}
var _t := 0.0


func total() -> int:
	var n := 0
	for g in GROUPS:
		n += g[1].size()
	return n


func checked() -> int:
	return done.size()


func is_done(id: String) -> bool:
	return done.has(id)


func reset() -> void:
	done.clear()
	_seen.clear()
	_t = 0.0


## [[group, label], ...] of what has not been ticked.
func unchecked() -> Array:
	var out := []
	for g in GROUPS:
		for it in g[1]:
			if not done.has(it[0]):
				out.append([g[0], it[1]])
	return out


## Tick what this snapshot proves; returns the ids that became ticked now.
func feed(s: Dictionary, dt: float) -> Array:
	_t += dt
	if _t < WARMUP:
		return []
	_update_seen(s)
	var fresh := []
	for g in GROUPS:
		for it in g[1]:
			if not done.has(it[0]) and _test(it[0], s):
				done[it[0]] = true
				fresh.append(it[0])
	return fresh


func _update_seen(s: Dictionary) -> void:
	var flags := {
		"moved1": s.thr1 > 0.1, "moved2": s.thr2 > 0.1, "flaps": s.flaps > 0, "sb": s.sb > 0.1, "mode": s.mode != 0,
		"gear_up": s.gear == 0, "m1_off": not s.m1, "m2_off": not s.m2, "park_on": s.park,
		"ab": _any_ab(s),
	}
	for k in flags:
		if flags[k]:
			_seen[k] = true


func _any_ab(s: Dictionary) -> bool:
	for b in range(21, 26):
		if s.btn.get(b, false):
			return true
	return false


func _test(id: String, s: Dictionary) -> bool:
	if id.begins_with("l1_") or id.begins_with("l2_"):
		return _lever(id.substr(3), id[1], s)
	match id:
		"pitch_fwd": return s.pitch <= -0.95
		"pitch_back": return s.pitch >= 0.95
		"roll_l": return s.roll <= -0.95
		"roll_r": return s.roll >= 0.95
		"yaw_l": return s.yaw <= -0.95
		"yaw_r": return s.yaw >= 0.95
		"fl_1": return s.flaps == 2 or s.flaps == 1  # 1+F on the ground, 1 in the air
		"fl_2": return s.flaps == 3
		"fl_3": return s.flaps == 4
		"fl_full": return s.flaps == 5
		"fl_0": return s.flaps == 0 and _seen.has("flaps")
		"sb_25": return absf(s.sb - 0.25) < 0.03
		"sb_50": return absf(s.sb - 0.5) < 0.03
		"sb_75": return absf(s.sb - 0.75) < 0.03
		"sb_100": return s.sb >= 0.98
		"sb_0": return s.sb < 0.01 and _seen.has("sb")
		"mode_crank": return s.mode == 1
		"mode_ign": return s.mode == 2
		"mode_norm": return s.mode == 0 and _seen.has("mode")
		"gear_up": return s.gear == 0
		"gear_dn": return s.gear == 1 and _seen.has("gear_up")
		"ab_btv": return s.btn.get(21, false) and s.ab == 1
		"ab_low": return s.btn.get(22, false) and s.ab == 1
		"ab_2": return s.btn.get(23, false) and s.ab == 2
		"ab_3": return s.btn.get(24, false) and s.ab == 2
		"ab_hi": return s.btn.get(25, false) and s.ab == 3
		"ab_off": return s.ab == 0 and not _any_ab(s) and _seen.has("ab")
		"m1_off": return not s.m1
		"m1_on": return s.m1 and _seen.has("m1_off")
		"m2_off": return not s.m2
		"m2_on": return s.m2 and _seen.has("m2_off")
		"park_on": return s.park
		"park_off": return not s.park and _seen.has("park_on")
	return false


func _lever(what: String, n: String, s: Dictionary) -> bool:
	match what:
		"cl": return s["name" + n] == "CL"
		"flx": return s["name" + n] == "FLX/MCT"
		"toga": return s["name" + n] == "TOGA"
		"idle": return s["name" + n] == "IDLE" and _seen.has("moved" + n)
		"rev": return s["rev" + n] >= 0.98
	return false
