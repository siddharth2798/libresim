class_name Autoflight
extends Node
## Autopilot, flight director and autothrust of an airliner (AP1 / AP2, FD, A/THR with the FCU modes), as a
## system node ticked in _physics_process; the logic is in autoflight_logic.gd (+ _lateral, _vertical,
## _thrust, _speeds, _fma, _inputs). Group saveable (core/situation_systems.gd).
## Reads (Props): see AfInputs; the FCU: controls/fcu/{ap1, ap2, athr, loc, appr, fd (default on), spd_kt,
## hdg_deg (magnetic), alt_ft, vs_fpm, spd_managed, hdg_managed, vs_managed, ap_disc, athr_disc (pulses,
## consumed), vert_select ("OPEN" | "MANAGED" | "VS", consumed)}.
## Writes: ap/{ap1, ap2, athr (armed or active), athr_active, fd, loc, appr, fd_pitch_rad, fd_roll_rad,
## thrust_limit, spd_target_kt, fma/{thrust, vertical, lateral, approach, misc}, disconnect (0.5 s pulse),
## disconnect_warning, disconnect_count}; for the control law ap/cmd/{active, nz_g (g increment, + pull),
## roll_rate_dps (+ right)}; for the engines ap/cmd/lever_<n> (used instead of controls/throttle_<n> by
## FdmNode while ap/athr_active); and back to the FCU the request flags controls/fcu/{ap1, ap2, athr} (the
## state, so a refused or dropped engagement un-presses the button) and, when the autoflight picks a mode
## from the present state, the set-points controls/fcu/{hdg_deg, vs_fpm}.
## The control law sets ap/cmd/takeover (sidestick moved: the AP disconnects) and fcs/alpha_floor.

var logic: AfLogic
var db: NavDatabase  # the ILS geometry (set by the wiring, like Gps.db)
var inp := AfInputs.new()


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
	inp.read(dt, db)
	logic.update(inp)
	_write_props()
	for k in ["ap_disc", "athr_disc"]:  # pulses: consumed
		Props.set_v("controls/fcu/" + k, false)
	Props.set_v("controls/fcu/vert_select", "")


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
	for k in l.fma:
		Props.set_v("ap/fma/" + k, l.fma[k])
	Props.set_v("ap/disconnect", l.disc_pulse)
	Props.set_v("ap/disconnect_warning", l.warning)
	Props.set_v("ap/disconnect_count", l.disconnect_count)
	Props.set_v("ap/cmd/active", l.engaged())
	Props.set_v("ap/cmd/nz_g", l.nz_g)
	Props.set_v("ap/cmd/roll_rate_dps", rad_to_deg(l.roll_rate))
	for n in maxi(int(Props.get_v("engine/count", 2)), 2):
		Props.set_v("ap/cmd/lever_%d" % (n + 1), l.thr.lever_cmd)
	_sync_fcu()


## The FCU flags show what the autoflight did; set-points it chose from the present state go back too.
func _sync_fcu() -> void:
	var l := logic
	Props.set_v("controls/fcu/ap1", l.ap1)
	Props.set_v("controls/fcu/ap2", l.ap2)
	Props.set_v("controls/fcu/athr", l.thr.armed)
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
