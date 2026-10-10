extends RefCounted
## Landing / damage test cards: a good landing is fine and matches the POH roll; bad
## landings and limit violations fail the way they would for real.

const KT := 0.514444
const FT := 0.3048


## Fly a stabilised approach and touch down. sink_fpm: target final descent rate,
## flare: whether to flare at 15 ft, nose_down: push the nose over at touchdown.
func _approach(sink_fpm: float, flare: bool, nose_down := false, gross := 2550.0) -> FdmHarness:
	var h := FdmHarness.new(gross)
	var f := h.f
	f.fcs.flap_cmd = 3
	f.fcs.flap_deg = 30.0
	f.set_airborne(0, 0, 60.0, 0.0, 65 * KT, 0.0)
	f.prop.rpm = 1700.0
	f.engine.throttle = 0.25
	h.mode = "speed"
	h.target_cas = 65 * KT
	var i_vs := [0.0]
	h.run(60.0, func():
		var agl := f.agl
		var vs := -f.velocity_ned().z / FT * 60.0
		if agl > 5.0:
			# throttle holds the descent rate, pitch (autopilot) holds 65 kt
			i_vs[0] += (vs + sink_fpm) * 1e-6
			f.engine.throttle = clampf(0.25 - (vs + sink_fpm) * 0.0004 - i_vs[0], 0.0, 1.0)
		else:
			f.engine.throttle = 0.0
			if flare:
				h.target_pitch = deg_to_rad(6.0)
				h.mode = "pitch"
			elif nose_down:
				h.mode = "pitch"
				h.target_pitch = deg_to_rad(-6.0)
		return f.gear.wow or f.damage.crashed)
	return h


func _rollout(h: FdmHarness) -> float:
	var f := h.f
	var n0 := f.pos_n
	h.mode = "none"
	f.fcs.pitch = 0.0
	f.gear.brake_left = 1.0
	f.gear.brake_right = 1.0
	h.run(40.0, func(): return Vector2(f.velocity_ned().x, f.velocity_ned().y).length() < 0.5)
	return (f.pos_n - n0) / FT


func test_land_normal_and_roll() -> String:
	var h := _approach(450.0, true)
	var td: Dictionary = h.f.damage.last_touchdown
	var roll := _rollout(h)
	print("    touchdown %.0f fpm %.0f KIAS, damage %s, ground roll %.0f ft (POH 575 ft)" % [
		td.get("sink_fpm", -1), td.get("kias", -1), h.f.damage.events, roll])
	if h.f.damage.crashed or h.f.damage.structure_damaged:
		return "a normal flared landing caused damage: %s" % [h.f.damage.events]
	if absf(roll - 575.0) > 575.0 * 0.25:
		return "landing ground roll %.0f ft outside 25%% of POH 575 ft" % roll
	return ""


func test_land_hard_collapses_gear() -> String:
	var h := _approach(1200.0, false)
	h.run(3.0)
	print("    events: %s" % [h.f.damage.events])
	if h.f.damage.gear_failed.is_empty() and not h.f.damage.crashed:
		return "1200 fpm unflared arrival did not damage the gear"
	return ""


func test_land_nose_first_prop_strike() -> String:
	var h := _approach(700.0, false, true)
	h.run(3.0)
	print("    events: %s" % [h.f.damage.events])
	if not h.f.damage.gear_failed.has("NOSE") and not h.f.damage.prop_destroyed and not h.f.damage.crashed:
		return "pushing over onto the nose wheel at 700 fpm caused no damage"
	return ""


func test_ditching() -> String:
	var h2 := FdmHarness.new()
	h2.f.surface = func(_n: float, _e: float) -> int: return 255
	h2.f.set_airborne(0, 0, 20.0, 0.0, 60 * KT, 0.0)
	h2.f.engine.throttle = 0.0
	h2.mode = "pitch"
	h2.target_pitch = deg_to_rad(4.0)
	h2.run(30.0, func(): return h2.f.damage.crashed)
	print("    %s" % h2.f.damage.crash_reason)
	return "" if h2.f.damage.crash_reason.contains("water") else "landing on water did not end the flight"


func test_vne_structural_failure() -> String:
	var h := FdmHarness.new()
	var f := h.f
	f.set_airborne(0, 0, 3000.0, 0.0, 120 * KT, -0.3)
	f.prop.rpm = 2600.0
	f.engine.throttle = 1.0
	h.mode = "pitch"
	h.target_pitch = deg_to_rad(-45.0)
	h.run(60.0, func(): return f.damage.crashed)
	print("    %s" % [f.damage.events])
	return "" if f.damage.crash_reason.contains("structural") else "a full-power 45 deg dive never failed the structure"


func test_overstress_pull() -> String:
	var h := FdmHarness.new(2000.0)
	var f := h.f
	f.set_airborne(0, 0, 2000.0, 0.0, 145 * KT, 0.0)
	f.prop.rpm = 2500.0
	h.mode = "none"
	f.fcs.pitch = 1.0  # full aft yoke, well above VA (105 kt)
	h.run(3.0, func(): return f.damage.structure_damaged or f.damage.crashed)
	print("    max events: %s" % [f.damage.events])
	return "" if f.damage.structure_damaged or f.damage.crashed else "full aft yoke at 145 kt did not overstress the airframe"


func test_flap_overspeed() -> String:
	var h := FdmHarness.new()
	var f := h.f
	f.set_airborne(0, 0, 1000.0, 0.0, 120 * KT, 0.0)
	f.prop.rpm = 2400.0
	f.engine.throttle = 0.7
	h.target_alt = 1000.0
	f.fcs.flap_cmd = 3
	h.run(10.0)
	print("    %s" % [f.damage.events])
	return "" if f.damage.flaps_jammed else "flaps 30 at 120 kt (VFE 85) did not damage the flaps"


func test_land_crosswind_drift_side_load() -> String:
	# 15 kt direct crosswind, wings level and no correction: the aircraft drifts sideways at touchdown
	var h := FdmHarness.new(2550.0)
	var f := h.f
	f.wind_ned = Vector3(0.0, 15.0 * KT, 0.0)  # air moving east = wind from the west
	f.fcs.flap_cmd = 3
	f.fcs.flap_deg = 30.0
	f.set_airborne(0, 0, 15.0, 0.0, 60 * KT, 0.0)
	f.engine.throttle = 0.0
	h.mode = "pitch"
	h.target_pitch = deg_to_rad(4.0)
	h.run(30.0, func():
		f.fcs.yaw = clampf(-3.0 * wrapf(f.euler().z, -PI, PI), -1, 1)  # keep the nose on the runway heading: no crab
		return f.gear.wow)
	h.run(2.0)
	print("    events: %s" % [f.damage.events])
	return "" if f.damage.structure_damaged or not f.damage.gear_failed.is_empty() else "touching down drifting in a 15 kt crosswind caused no side load"
