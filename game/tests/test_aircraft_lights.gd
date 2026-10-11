extends RefCounted
## Aircraft lighting rules (aircraft/c172/light_logic.gd, landing_pool.gd): start light
## state per start type and time of day, strobe / beacon timing, nav-light sectors, the
## PANEL dimmer mapping and the landing-light ground pool fade.


func test_start_state_night() -> String:
	var air := LightLogic.start_state("air", -20.0, 1500.0, false)
	for k in ["nav", "beacon", "strobe", "landing"]:
		if not air[k]:
			return "night air start below 3000 ft: %s should be on" % k
	if air.taxi:
		return "night air start: taxi light should be off"
	if LightLogic.start_state("air", -20.0, 4500.0, false).landing:
		return "night air start above 3000 ft: landing light should be off"
	var rw := LightLogic.start_state("runway", -20.0, 0.0, false)
	for k in ["nav", "beacon", "strobe", "landing", "taxi"]:
		if not rw[k]:
			return "night runway start: %s should be on" % k
	var st := LightLogic.start_state("stand", -20.0, 0.0, false)
	if not st.nav or not st.beacon or st.strobe or st.landing or st.taxi:
		return "night stand start: nav + beacon only, got %s" % st
	if not is_equal_approx(float(rw.panel), LightLogic.PANEL_NIGHT_DEFAULT):
		return "panel dimmer default %s" % rw.panel
	var dusk := LightLogic.start_state("runway", 2.0, 0.0, false)
	if not dusk.nav or not dusk.strobe:
		return "dusk (sun 2 deg) should use the night set"
	return ""


func test_start_state_day_and_cold() -> String:
	var d := LightLogic.start_state("runway", 40.0, 0.0, false)
	if not d.beacon or d.nav or d.strobe or d.landing or d.taxi:
		return "day runway start: beacon only, got %s" % d
	for kind in ["runway", "stand"]:
		var c := LightLogic.start_state(kind, -20.0, 0.0, true)
		for k in ["nav", "beacon", "strobe", "landing", "taxi"]:
			if c[k]:
				return "cold & dark %s start: %s should be off" % [kind, k]
		if float(c.panel) != 0.0:
			return "cold & dark: panel dimmer should be 0"
	return ""


func test_strobe_double_flash() -> String:
	# count rising edges over 12 s at 1 ms steps: 10 cycles x 2 flashes
	var edges := 0
	var on_time := 0.0
	var prev := false
	for i in 12000:
		var on := LightLogic.strobe_on(i * 0.001)
		if on and not prev:
			edges += 1
		if on:
			on_time += 0.001
		prev = on
	if edges != 20:
		return "expected 20 flashes in 12 s, got %d" % edges
	if absf(on_time - 20 * LightLogic.STROBE_FLASH) > 0.03:
		return "flash time %.3f s" % on_time
	if LightLogic.strobe_on(0.5):
		return "strobe should be dark mid-cycle"
	return ""


func test_beacon_timing() -> String:
	if LightLogic.beacon_level(0.05) != 1.0 or LightLogic.beacon_level(LightLogic.BEACON_PERIOD + 0.05) != 1.0:
		return "beacon should be lit at the start of each period"
	if LightLogic.beacon_level(0.6) != 0.0:
		return "beacon should be dark between flashes"
	var tail := LightLogic.beacon_level(LightLogic.BEACON_FLASH + 0.03)
	if tail <= 0.0 or tail >= 1.0:
		return "beacon flash should decay, got %.3f" % tail
	var per_min := 60.0 / LightLogic.BEACON_PERIOD
	if per_min < 40.0 or per_min > 100.0:
		return "beacon %.0f flashes/min outside 40..100" % per_min
	return ""


func test_nav_sectors() -> String:
	# left red: full ahead-left, not from the right; right green mirrored; tail white aft
	if LightLogic.nav_sector(0, -60.0) != 1.0 or LightLogic.nav_sector(0, 60.0) > 0.26:
		return "red sector wrong"
	if LightLogic.nav_sector(1, 60.0) != 1.0 or LightLogic.nav_sector(1, -60.0) > 0.26:
		return "green sector wrong"
	if LightLogic.nav_sector(2, 180.0) != 1.0 or LightLogic.nav_sector(2, 0.0) > 0.26:
		return "white tail sector wrong"
	if LightLogic.nav_sector(0, 170.0) < 0.2:
		return "wingtip lens should still glint from behind (chase view)"
	return ""


func test_panel_dimmer_mapping() -> String:
	if LightLogic.panel_brightness(0.0, 0.0, true) != 1.0 or LightLogic.panel_brightness(1.0, 0.0, false) != 1.0:
		return "daylight panel must be unchanged (1.0)"
	var lo := LightLogic.panel_brightness(0.0, 1.0, true)
	var mid := LightLogic.panel_brightness(0.7, 1.0, true)
	var hi := LightLogic.panel_brightness(1.0, 1.0, true)
	if not (lo < mid and mid < hi and hi <= 1.0 and lo > 0.05):
		return "night panel brightness not monotonic: %.2f %.2f %.2f" % [lo, mid, hi]
	if LightLogic.panel_brightness(1.0, 1.0, false) > lo + 1e-6:
		return "unpowered panel should be unlit"
	if LightLogic.display_brightness(0.0, 1.0, true) < 0.6:
		return "radio displays should stay readable at night"
	if LightLogic.flood_energy(0.7, 0.0, true) != 0.0 or LightLogic.flood_energy(0.7, 1.0, false) != 0.0:
		return "flood must be off in daylight and without power"
	if LightLogic.flood_energy(1.0, 1.0, true) <= LightLogic.flood_energy(0.3, 1.0, true):
		return "flood should follow the dimmer"
	if LightLogic.step_panel(0.7, 1) != 0.8 or LightLogic.step_panel(1.0, 1) != 1.0 or LightLogic.step_panel(0.05, -1) != 0.0:
		return "dimmer steps wrong"
	return ""


func test_night_factor_and_pool() -> String:
	if LightLogic.night_factor(30.0) != 0.0 or LightLogic.night_factor(-10.0) != 1.0:
		return "night factor ends wrong"
	if LandingPool.pool_level(true, 1.0, 1.5) != 1.0 or LandingPool.pool_level(false, 1.0, 1.5) != 0.0:
		return "pool on the ground wrong"
	if LandingPool.pool_level(true, 1.0, 300.0) != 0.0 or LandingPool.pool_level(true, 0.0, 1.5) != 0.0:
		return "pool should vanish high up and in daylight"
	return ""
