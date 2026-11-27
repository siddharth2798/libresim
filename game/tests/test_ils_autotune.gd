extends "res://tests/ils_test_base.gd"
## The ILS auto-tune node (avionics/ils_autotune.gd) tuning NAV2, the MCDU RAD NAV page (ui/displays/mcdu_radnav.gd), and the
## radios receiving what it tuned: every ILS runway, whatever its frequency, gives a valid localizer and glide slope.
## Which ILS is chosen is in tests/test_ils_pick.gd. Stations come from the NavDatabase (ils_test_base.gd).

const MANUAL_MHZ := 117.5


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func test_node_tunes_the_arrival_ils() -> String:
	begin()
	var s: Dictionary = stations()[0]
	var n := node()
	plan_of(s)
	fly(far(s, 80.0), float(s.course_true))
	n.update(0.25)
	if not _near(mhz(), float(s.mhz)) or str(Props.get_v("avionics/ils_auto/ident")) != s.ident:
		return "%s %s: NAV2 %s ident %s" % [s.airport, s.runway, mhz(), Props.get_v("avionics/ils_auto/ident")]
	if not Props.get_b("avionics/ils_auto/active") or Props.get_b("avionics/ils_auto/manual"):
		return "the tuning should show as active, not manual"
	if absf(wrapf(Props.get_f("controls/nav2/obs_deg") - (float(s.course_true) + 0.3), -180.0, 180.0)) > 0.3:
		return "the course follows: %s" % Props.get_f("controls/nav2/obs_deg")
	var labels := PfdIls.tuned_labels()
	if labels != [str(s.ident), "%.2f" % float(s.mhz)]:
		return "PFD shows the tuned ILS before it is received: %s" % [labels]
	Props.set_v("controls/efis/ls", false)
	if not PfdIls.tuned_labels().is_empty():
		return "LS off: nothing on the PFD"
	return ""


func test_node_uses_the_mcdu_plan_without_a_route() -> String:
	begin()
	var p := pair()
	if p.is_empty():
		return "no airport with two ILS runways in the data"
	var n := node()
	Props.set_v("mcdu/init/from_to", "VABB/" + str(p[1].airport))  # typed on INIT: no route/dest
	Props.set_v("mcdu/init/arr_rwy", str(p[1].runway))
	fly(far(p[1], 60.0), float(p[1].course_true))
	n.update(0.25)
	return "" if _near(mhz(), float(p[1].mhz)) else "ARR RWY %s typed: NAV2 %s, want %s" % [p[1].runway, mhz(), p[1].mhz]


func test_node_lineup_without_a_plan_and_armed_trigger() -> String:
	begin()
	var s: Dictionary = stations()[0]
	var n := node()
	fly(final(s, 15.0, 8000.0), float(s.course_true))  # far above the path
	n.update(0.25)
	if not _near(mhz(), START_MHZ):
		return "too high: left alone, NAV2 %s" % mhz()
	Props.set_v("controls/fcu/appr", true)
	n.update(0.25)
	return "" if _near(mhz(), float(s.mhz)) else "APPR armed with a clear candidate: tune, NAV2 %s want %s" % [mhz(), s.mhz]


func test_node_no_retune_during_capture() -> String:
	begin()
	var p := pair()
	if p.is_empty():
		return "no airport with two ILS runways in the data"
	var n := node()
	plan_of(p[0])
	fly(far(p[0], 20.0), float(p[0].course_true))
	n.update(0.25)
	plan_of(p[1])  # the plan changes while the localizer is captured
	Props.set_v("ap/fma/lateral", "LOC*")
	n.update(0.25)
	if not _near(mhz(), float(p[0].mhz)):
		return "LOC* engaged: no retune, NAV2 %s" % mhz()
	Props.set_v("ap/fma/lateral", "NAV\nLOC")  # only armed
	Props.set_v("avionics/nav2/kind", "ILS")  # NAV2 receives the ILS that was tuned
	Props.set_v("avionics/nav2/valid", true)
	Props.set_v("avionics/nav2/ident", p[0].ident)
	n.update(0.25)
	if not _near(mhz(), float(p[0].mhz)):
		return "receiving the tuned ILS: no retune, NAV2 %s" % mhz()
	Props.set_v("avionics/nav2/valid", false)  # signal gone (missed approach): the plan takes over
	n.update(0.25)
	return "" if _near(mhz(), float(p[1].mhz)) else "no signal: tune the plan's runway, NAV2 %s want %s" % [mhz(), p[1].mhz]


func test_node_manual_tune_wins() -> String:
	begin()
	var p := pair()
	if p.is_empty():
		return "no airport with two ILS runways in the data"
	var n := node()
	plan_of(p[0])
	fly(far(p[0], 80.0), float(p[0].course_true))
	n.update(0.25)
	Props.set_v("controls/nav2/freq_mhz", MANUAL_MHZ)  # the pilot
	n.update(0.25)
	n.update(0.25)
	if not _near(mhz(), MANUAL_MHZ) or not Props.get_b("avionics/ils_auto/manual"):
		return "manual tune must stay: NAV2 %s manual %s" % [mhz(), Props.get_b("avionics/ils_auto/manual")]
	Props.set_v("controls/ils_auto/resume", true)  # AUTO on the RAD NAV page
	n.update(0.25)
	if not _near(mhz(), float(p[0].mhz)) or Props.get_b("avionics/ils_auto/manual"):
		return "AUTO: the FMGC tunes again, NAV2 %s" % mhz()
	Props.set_v("controls/nav2/freq_mhz", MANUAL_MHZ)
	n.update(0.25)
	plan_of(p[1])  # a new arrival runway cancels the override
	n.update(0.25)
	return "" if _near(mhz(), float(p[1].mhz)) else "new ARR RWY: NAV2 %s want %s" % [mhz(), p[1].mhz]


func test_node_leaves_the_radio_alone_without_an_ils() -> String:
	begin()
	var n := node()
	var ils_airports := {}
	for s in stations():
		ils_airports[s.airport] = true
	var bare := ""
	for a in _db.airports:
		if not ils_airports.has(a.icao) and not ils_airports.has(a.ident) and a.icao != "":
			bare = a.icao
			break
	if bare == "":
		return "no airport without an ILS in the data"
	var ap := _db.airport(bare)
	plan(bare, "09")
	fly(Vector3(ap.x - 30.0 * NM, ap.y + 4.0 * NM, 4000.0), 90.0)
	n.update(0.25)
	if not _near(mhz(), START_MHZ) or str(Props.get_v("avionics/ils_auto/ident")) != "":
		return "%s has no ILS: NAV2 stays, got %s" % [bare, mhz()]
	if Props.get_b("avionics/ils_auto/active") or Props.get_b("avionics/ils_auto/manual") or not PfdIls.tuned_labels().is_empty():
		return "nothing to show"
	return ""


func test_node_off_for_the_c172_unless_the_option_is_on() -> String:
	begin()
	_opt = UserOptions.get_v("ils_autotune")
	UserOptions.set_v("ils_autotune", false)
	var s: Dictionary = stations()[0]
	var n := node(false)
	plan_of(s)
	fly(far(s, 60.0), float(s.course_true))
	n.update(0.25)
	if not _near(mhz(), START_MHZ) or UserOptions.DEFAULTS.get("ils_autotune") != false:
		return "off by default: the C172 pilot tunes"
	UserOptions.set_v("ils_autotune", true)
	n.update(0.25)
	return "" if _near(mhz(), float(s.mhz)) else "option on: tunes, NAV2 %s" % mhz()


func test_node_waits_for_the_air() -> String:
	begin()
	var s: Dictionary = stations()[0]
	var n := node()
	plan_of(s)
	Props.set_v("fdm/wow", true)
	fly(far(s, 60.0, 100.0), float(s.course_true))
	n.update(0.25)
	return "" if _near(mhz(), START_MHZ) else "on the ground: NAV2 stays"


## Every ILS runway, tuned by the node and received by the radios, whatever its frequency (not only 108.10).
func test_every_ils_runway_gives_valid_loc_and_gs_after_the_auto_tune() -> String:
	begin()
	var radios := NavRadios.new()
	radios._ready()
	var tq := TerrainQuadtree.new()
	tq.cache = TerrainTileCache.new()
	radios.terrain = tq
	_made.append(radios)
	_made.append(tq)
	var n := node()
	var done := 0
	for s in stations():
		begin()
		plan_of(s)
		fly(final(s, 8.0), float(s.course_true))
		n.restart()
		n.update(0.25)
		radios._los_t = 0.0
		radios.update(0.1)
		if not _near(mhz(), float(s.mhz)):
			return "%s: tuned %s, want %s" % [s.ident, mhz(), s.mhz]
		if not Props.get_b("avionics/nav2/valid") or str(Props.get_v("avionics/nav2/ident")) != s.ident or not Props.get_b("avionics/nav2/gs_valid"):
			return "%s (%.2f MHz): LOC valid %s ident %s GS valid %s" % [s.ident, s.mhz, Props.get_b("avionics/nav2/valid"),
				Props.get_v("avionics/nav2/ident"), Props.get_b("avionics/nav2/gs_valid")]
		if absf(Props.get_f("avionics/nav2/cdi")) > 0.15 or absf(Props.get_f("avionics/nav2/gs")) > 0.25:
			return "%s: on the path but LOC %+.2f GS %+.2f" % [s.ident, Props.get_f("avionics/nav2/cdi"), Props.get_f("avionics/nav2/gs")]
		done += 1
	return "" if done >= 5 else "only %d runways" % done


func test_radnav_page_entries_and_auto() -> String:
	begin()
	McduRadNav.line_key("l", 2, "109.5")
	if not _near(mhz(), 109.5):
		return "ILS FREQ typed"
	McduRadNav.line_key("l", 2, "120.0")
	if str(Props.get_v("mcdu/scratch")) != "FORMAT ERROR" or not _near(mhz(), 109.5):
		return "out of band: format error, frequency kept"
	McduRadNav.line_key("l", 1, "113.8")
	McduRadNav.line_key("l", 2, "AUTO")
	if not _near(Props.get_f("controls/nav1/freq_mhz"), 113.8) or not Props.get_b("controls/ils_auto/resume"):
		return "VOR1 frequency typed, AUTO asks the FMGC to tune"
	Props.set_v("mcdu/scratch", "")
	McduRadNav.line_key("l", 2, "")
	if str(Props.get_v("mcdu/scratch")) != "109.50":
		return "an empty scratchpad copies the frequency: %s" % Props.get_v("mcdu/scratch")
	# typed on the page, then the node: manual until AUTO
	var s: Dictionary = stations()[0]
	var n := node()
	plan_of(s)
	fly(far(s, 80.0), float(s.course_true))
	Props.set_v("controls/ils_auto/resume", false)
	n.update(0.25)
	McduRadNav.line_key("l", 2, "117.5")
	n.update(0.25)
	if not _near(mhz(), 117.5) or McduRadNav.ils_state().mode != "MANUAL":
		return "typed on the RAD NAV page wins: %s" % [McduRadNav.ils_state()]
	McduRadNav.line_key("l", 2, "AUTO")
	n.update(0.25)
	var st := McduRadNav.ils_state()
	if st.mode != "AUTO" or not _near(float(st.mhz), float(s.mhz)):
		return "AUTO gives it back: %s" % [st]
	return ""


## The node looks on physics ticks at TICK_HZ (core/tick_rate.gd), not on frames: the first tick tunes, and a pilot
## retune is seen at the next look, 0.25 s (30 ticks at 120 Hz) later.
func test_node_runs_on_physics_ticks_at_4_hz() -> String:
	begin()
	var s: Dictionary = stations()[0]
	var n := node()
	plan_of(s)
	fly(far(s, 80.0), float(s.course_true))
	n._physics_process(1.0 / 120.0)
	if not _near(mhz(), float(s.mhz)):
		return "the first physics tick should tune: NAV2 %s, want %s" % [mhz(), s.mhz]
	Props.set_v("controls/nav2/freq_mhz", MANUAL_MHZ)
	var seen := -1
	for i in 60:
		n._physics_process(1.0 / 120.0)
		if seen < 0 and Props.get_b("avionics/ils_auto/manual"):
			seen = i + 1
	if seen < 25 or seen > 31:
		return "manual tune seen after %d ticks, want the next 4 Hz look (about 30)" % seen
	return ""
