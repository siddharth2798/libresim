class_name AfLand
extends RefCounted
## Autoland of the autoflight (pure logic, no Props). Phases, with the radio altitude of the wheels:
##   LAND      below 400 ft with LOC and G/S engaged, both APs on, the ILS received, gear down, CONF 3 or FULL: the FMA says LAND
##             (vertical column), the glide slope law goes on
##   FLARE     below 40 ft: the flare law holds a sink rate that falls with the height (an exponential flare onto a floor of
##             about 160 ft/min); thrust to idle from 30 ft ("THR IDLE"), the RETARD word from 10 ft; below 20 ft the crab is
##             taken out with the rudder (`yaw`), the roll law keeps the track on the runway axis
##   ROLL OUT  from touchdown: the nose is lowered (`ground_pitch`), the rudder and the nose wheel (`yaw`, the pedal equivalent)
##             keep the runway axis from the localizer geometry, the thrust stays at idle. The AP drops quietly below 20 kt of
##             ground speed, or when the pilot disconnects it (button, sidestick, TOGA is a go-around)
## Without both APs, without the ILS or without the landing configuration none of this engages: the AP disconnects at 50 ft as
## before (AfLogic). Losing the localizer above 15 ft or the glide slope above 100 ft in LAND / FLARE returns true from update():
## the caller disconnects the AP with the warning (the real aircraft lights the AUTOLAND warning; not modelled).
## Sources and what is not modelled: docs/A320-FCU-REFERENCE.md "Autoland".

const FT := 0.3048
const LAND_RA_M := 400.0 * FT
const FLARE_RA_M := 40.0 * FT
const IDLE_RA_M := 30.0 * FT
const RETARD_RA_M := 10.0 * FT
const DECRAB_RA_M := 20.0 * FT
const LOC_LOST_RA_M := 15.0 * FT
const GS_LOST_RA_M := 100.0 * FT
const CONF_MIN := 4  # flap lever detent (0 = UP, 1, 2 = 1+F, 3 = CONF 2, 4 = CONF 3, 5 = FULL): CONF 3 or FULL
const VS_FLOOR := 0.5  # m/s: the sink the flare ends on (about 100 ft/min)
const K_FLARE := 0.33  # 1/s: sink per metre of height
const T_LEAD := 1.0  # s: the height the aircraft will have in this time is what the profile is read at (the flight path lags the load factor)
const TAU_FLARE := 1.0  # s, flight path loop in the flare
const NZ_FLARE := 0.5
const K_DECRAB := 6.0  # pedal per rad of heading error
const K_DECRAB_R := 6.0  # pedal per rad/s of yaw rate
const DECRAB_MAX := 0.8
const ROLLOUT_END_MPS := 20.0 * 0.514444
const K_OFF := 0.003  # rad of heading offset per metre off the axis on the roll out
const OFF_MAX := deg_to_rad(8.0)
const K_HDG_ROLL := 3.4  # pedal per rad of heading error on the roll out
const K_R_ROLL := 2.9  # pedal per rad/s of yaw rate
const YAW_MAX := 1.0

var phase := ""  # "", LAND, FLARE, ROLLOUT
var gamma_cmd := 0.0
var nz_g := 0.0
var yaw := 0.0  # pedal equivalent, + right (rudder and nose wheel)
var ground_pitch := 0.0  # stick equivalent on the ground, + aft
var retard := 0  # 0 none, 1 thrust idle (from 30 ft), 2 RETARD (from 10 ft and on the roll out)
var _ils := {}  # the geometry at LAND: kept when the signal goes (below 15 ft the aircraft flies on)


func reset() -> void:
	phase = ""
	gamma_cmd = 0.0
	nz_g = 0.0
	yaw = 0.0
	ground_pitch = 0.0
	retard = 0
	_ils = {}


func active() -> bool:
	return phase != ""


func rolling() -> bool:
	return phase == "ROLLOUT"


## Both APs, the ILS received (localizer and glide slope), gear down, CONF 3 / FULL, and the localizer captured: the aircraft can
## autoland (FMA column 4 CAT3 DUAL). One AP only is CAT1 here (the real aircraft is CAT3 SINGLE: UNVERIFIED, not modelled).
static func capable(i: AfInputs, ap1: bool, ap2: bool, lat: AfLateral) -> bool:
	return ap1 and ap2 and i.gear_down and i.flap_lever >= CONF_MIN and not i.ils.is_empty() and bool(i.ils.gs_valid) and lat.captured()


## One tick. `vert` / `lat` have updated already. Returns true when a signal was lost below 400 ft (disconnect with the warning).
func update(i: AfInputs, ap1: bool, ap2: bool, vert: AfVertical, lat: AfLateral) -> bool:
	yaw = 0.0
	ground_pitch = 0.0
	retard = 0
	if phase == "":
		if not i.wow and i.ra_m <= LAND_RA_M and i.ra_m > FLARE_RA_M and vert.mode == "G/S" and lat.mode == "LOC" \
				and AfLand.capable(i, ap1, ap2, lat):
			phase = "LAND"
			_ils = i.ils.duplicate()
		return false
	if phase != "ROLLOUT" and i.wow:
		phase = "ROLLOUT"
	if phase == "ROLLOUT":
		_roll_out(i)
		return false
	var lost: bool = i.ils.is_empty() and i.ra_m > LOC_LOST_RA_M
	lost = lost or (not i.ils.is_empty() and not bool(i.ils.gs_valid) and i.ra_m > GS_LOST_RA_M)
	if phase == "LAND" and i.ra_m <= FLARE_RA_M:
		phase = "FLARE"
	if phase == "FLARE":
		_flare(i)
	return lost


func _flare(i: AfInputs) -> void:
	var glide := tan(float(_ils.gs_rad)) * maxf(i.gs_mps, 30.0)  # the sink of the glide path
	var h := maxf(i.ra_m + minf(i.vs_mps, 0.0) * T_LEAD, 0.0)
	var sink := minf(glide, maxf(VS_FLOOR, K_FLARE * h))
	gamma_cmd = asin(clampf(-sink / maxf(i.tas, 20.0), -0.5, 0.5))
	nz_g = clampf(maxf(i.tas, 20.0) / AfInputs.G * (gamma_cmd - i.gamma()) / TAU_FLARE, AfVertical.NZ_MIN, NZ_FLARE)
	if i.ra_m <= IDLE_RA_M:
		retard = 2 if i.ra_m <= RETARD_RA_M else 1
	if i.ra_m <= DECRAB_RA_M:  # the crab out with the rudder, the roll law holds the track
		var e := wrapf(float(_ils.course) - i.heading, -PI, PI)
		yaw = clampf(K_DECRAB * e - K_DECRAB_R * i.rates.z, -DECRAB_MAX, DECRAB_MAX)


func _roll_out(i: AfInputs) -> void:
	retard = 2
	var c: float = _ils.course
	var d := Vector2(i.pos.x, i.pos.y) - _ils.loc as Vector2
	var off := d.dot(Vector2(cos(c), -sin(c)))  # + = right of the axis
	var want := c - clampf(K_OFF * off, -OFF_MAX, OFF_MAX)
	yaw = clampf(K_HDG_ROLL * wrapf(want - i.heading, -PI, PI) - K_R_ROLL * i.rates.z, -YAW_MAX, YAW_MAX)
	var pitch_deg := rad_to_deg(i.pitch)
	if pitch_deg > 0.5:  # derotate at about 1.5 deg/s
		ground_pitch = clampf(0.06 * (-1.5 - rad_to_deg(i.rates.y)), -0.5, 0.1)


## The AP drops quietly at a low ground speed on the roll out.
func finished(i: AfInputs) -> bool:
	return phase == "ROLLOUT" and i.gs_mps < ROLLOUT_END_MPS


func fma_vertical() -> String:
	return phase if phase == "LAND" or phase == "FLARE" else ""
