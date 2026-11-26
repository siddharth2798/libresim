class_name Autoflight
extends Node
## Autopilot, flight director and autothrust of an airliner (AP1 / AP2, FD, A/THR with FCU modes), a system node ticked in
## _physics_process; logic is in autoflight_logic.gd (+ _lateral, _vertical, _thrust, _speeds, _fma, _inputs). Group saveable
## (core/situation_systems.gd).
## Reads (Props): see AfInputs; the FCU: controls/fcu/{ap1, ap2, athr, loc, appr, fd (default on), spd_kt, mach_sel (the SPD window
## with spd_mach on), spd_mach, hdg_deg (magnetic),
## alt_ft, vs_fpm, spd_managed, hdg_managed, vs_managed, ap_disc, athr_disc (pulses, consumed), vert_select ("OPEN" | "MANAGED" |
## "VS" (V/S knob pulled) | "LEVEL" (pushed), consumed)}.
## Writes: ap/{ap1, ap2, athr (armed or active), athr_active, fd, loc, appr, fd_pitch_rad, fd_roll_rad, thrust_limit,
## spd_target_kt, vs_preset (the FCU V/S window shows a preset turned outside V/S, ui/displays/fcu_windows.gd), fma/{thrust, vertical, lateral, approach, misc}, disconnect (0.5 s pulse), disconnect_warning,
## disconnect_count}; for the control law ap/cmd/{active, nz_g (g increment, + pull), roll_rate_dps (+ right), yaw (pedal equivalent, autoland only), ground_pitch (stick equivalent on the ground, autoland roll out)}; ap/land_phase ("", LAND, FLARE, ROLLOUT); for the engines
## ap/cmd/lever_<n> (used instead of controls/throttle_<n> by FdmNode while ap/athr_active); back to the FCU the request flags
## controls/fcu/{ap1, ap2, athr, loc, appr} (the state, so a refused engagement or arming un-presses the button) and, when the
## autoflight picks a mode from the present state, the set-points controls/fcu/{hdg_deg, vs_fpm}; hdg_managed is withdrawn when
## NAV cannot engage (no route) and vs_managed when V/S takes over. ap/{hdg, spd}_preset: a managed window shows a turned value
## (systems/autoflight_preview.gd).
## The control law sets ap/cmd/takeover (sidestick moved: the AP disconnects) and fcs/alpha_floor.

var logic: AfLogic
var db: NavDatabase  # the ILS geometry (set by the wiring, like Gps.db)
var inp := AfInputs.new()
var _mach_seen := -1  # controls/fcu/spd_mach at the last tick (-1 = none yet)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	if logic == null:
		setup(AircraftDef.current().section("limits"))


## limits = aircraft.json "limits" (speeds, autoflight overrides).
func setup(limits: Dictionary) -> void:
	logic = AfLogic.new(limits)


func _physics_process(dt: float) -> void:
	tick(dt)


func tick(dt: float) -> void:
	if logic == null:
		setup({})
	_spd_mach_pressed()
	inp.read(dt, db)
	logic.update(inp)
	_write_props()
	for k in ["ap_disc", "athr_disc"]:  # pulses: consumed
		Props.set_v("controls/fcu/" + k, false)
	Props.set_v("controls/fcu/vert_select", "")


## SPD/MACH (the 3D button, the 2D card and the key all flip controls/fcu/spd_mach): the window changes between knots (spd_kt) and
## Mach (mach_sel), and the value it did not show is recomputed from the one it did at the present altitude, so the target stays the
## same speed ("changes the SPD target to the corresponding MACH target and vice versa", FBW FCU page).
func _spd_mach_pressed() -> void:
	if not Props.has("controls/fcu/mach_sel"):
		Props.set_v("controls/fcu/mach_sel", 0.78)
	var on := 1 if Props.get_b("controls/fcu/spd_mach") else 0
	if _mach_seen >= 0 and on != _mach_seen:
		var c := AfSpeeds.converted(on == 1, Props.get_f("controls/fcu/spd_kt", 250.0), Props.get_f("controls/fcu/mach_sel", 0.78),
			Props.get_f("atmosphere/pressure_pa", 101325.0))
		Props.set_v("controls/fcu/mach_sel" if on == 1 else "controls/fcu/spd_kt", c.mach if on == 1 else c.kt)
	_mach_seen = on


func _write_props() -> void:
	var l := logic
	var f := inp.f
	Props.set_v("ap/ap1", l.ap1)
	Props.set_v("ap/ap2", l.ap2)
	Props.set_v("ap/athr", l.thr.armed)
	Props.set_v("ap/athr_active", l.thr.active)
	Props.set_v("ap/fd", l.fd)
	Props.set_v("ap/loc", f.loc and (l.lat.armed == "LOC" or l.lat.captured()))
	Props.set_v("ap/appr", f.appr and (l.lat.armed == "LOC" or l.lat.captured()))
	Props.set_v("ap/fd_pitch_rad", l.fd_pitch)
	Props.set_v("ap/fd_roll_rad", l.fd_roll)
	Props.set_v("ap/thrust_limit", l.thrust_limit)
	Props.set_v("ap/spd_target_kt", Units.mps_to_kt(l.spd_target))
	Props.set_v("ap/spd_sel_kt", Units.mps_to_kt(l.speeds.selected(inp)))  # the selected speed as a CAS (a Mach selection converted): PFD bug
	Props.set_v("ap/vs_preset", l.vs_preset > 0.0)
	Props.set_v("ap/hdg_preset", l.hdg_preset > 0.0)
	Props.set_v("ap/spd_preset", l.spd_preset > 0.0)
	for k in l.fma:
		Props.set_v("ap/fma/" + k, l.fma[k])
	Props.set_v("ap/disconnect", l.disc_pulse)
	Props.set_v("ap/disconnect_warning", l.warning)
	Props.set_v("ap/disconnect_count", l.disconnect_count)
	Props.set_v("ap/cmd/active", l.engaged())
	Props.set_v("ap/cmd/nz_g", l.nz_g)
	Props.set_v("ap/cmd/roll_rate_dps", rad_to_deg(l.roll_rate))
	_put("ap/cmd/yaw", l.land.yaw if l.engaged() else 0.0)  # autoland: crab out in the flare, rudder and nose wheel on the roll out
	_put("ap/cmd/ground_pitch", l.land.ground_pitch if l.engaged() else 0.0)  # autoland roll out: the nose comes down
	_put("ap/land_phase", l.land.phase)
	for n in maxi(int(Props.get_v("engine/count", 2)), 2):
		Props.set_v("ap/cmd/lever_%d" % (n + 1), l.thr.lever_cmd)
	_sync_fcu()


## Written only when it changed (the autoland values are zero or empty outside an autoland).
func _put(path: String, v: Variant) -> void:
	if not Props.has(path) or Props.get_v(path) != v:
		Props.set_v(path, v)


## The FCU flags show what the autoflight did; set-points it chose from the present state go back too.
func _sync_fcu() -> void:
	var l := logic
	Props.set_v("controls/fcu/ap1", l.ap1)
	Props.set_v("controls/fcu/ap2", l.ap2)
	Props.set_v("controls/fcu/athr", l.thr.armed)
	for k in ["loc", "appr"]:  # a press that arms nothing (no guidance) springs back, like a refused AP engagement
		Props.set_v("controls/fcu/" + k, Props.get_b("ap/" + k))
	if l.writes.has("hdg_mgd"):  # NAV refused: the window shows the heading again
		Props.set_v("controls/fcu/hdg_managed", bool(l.writes.hdg_mgd))
	if l.writes.has("vs_mgd"):  # V/S took over: managed vertical guidance is over (no dot in the ALT window)
		Props.set_v("controls/fcu/vs_managed", bool(l.writes.vs_mgd))
	if l.writes.has("hdg"):
		Props.set_v("controls/fcu/hdg_deg", fposmod(roundf(rad_to_deg(l.writes.hdg) - AfInputs.VAR_DEG), 360.0))
	if l.writes.has("vs"):
		Props.set_v("controls/fcu/vs_fpm", roundf(Units.mps_to_fpm(l.writes.vs) / 100.0) * 100.0)


func save_key() -> String:
	return "autoflight"


func save_state() -> Dictionary:
	return logic.save_state() if logic else {}


func load_state(d: Dictionary) -> void:
	if logic == null:
		setup({})
	logic.load_state(d)
	Props.set_v("controls/fcu/ap1", logic.ap1)  # the requests follow the loaded state
	Props.set_v("controls/fcu/ap2", logic.ap2)
	Props.set_v("controls/fcu/athr", logic.thr.armed)
