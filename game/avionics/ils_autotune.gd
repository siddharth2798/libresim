class_name IlsAutotune
extends Node
## Tunes NAV2 to the ILS being flown, like the A320's FMGC auto-tuning of the arrival runway's ILS (IlsPick decides which).
## On the A320 always; on other aircraft only with Options > Radio > "Auto-tune ILS" (UserOptions ils_autotune, off by
## default: the C172 pilot tunes the radio). NAV2 is where the PFD and the autoflight look first (PfdIls.source).
## In: route/dest and mcdu/init/{from_to, arr_rwy} (the plan), fdm/{position_enu, track_rad, wow}, avionics/fms/phase,
## controls/fcu/{loc, appr}, avionics/nav2/{kind, valid, ident}, ap/fma/lateral, controls/nav2/freq_mhz.
## Out: controls/nav2/freq_mhz (and obs_deg = the course) when it tunes; avionics/ils_auto/{ident, mhz, active, manual, why}.
## Rules (docs/USAGE.md "ILS auto-tune"):
##   * only airborne, with the avionics powered, at most TICK_S apart;
##   * a frequency the pilot sets (anything that changes controls/nav2/freq_mhz and is not this node) is a manual tune: it wins
##     until the plan's arrival changes (another destination or ARR RWY), or the MCDU RAD NAV page sends AUTO (controls/ils_auto/resume);
##   * never retuned while the ILS is in use: NAV2 receives the ILS this node tuned, or the localizer is armed-and-captured (LOC*, LOC, LAND);
##   * nothing wanted (no ILS, too far, off course): the radio is left alone and nothing is flagged.

const TICK_S := 0.25
const NM := 1852.0
const VAR_DEG := -0.3  # magnetic variation, as in avionics/gps.gd
const CAPTURED := ["LOC*", "LOC", "LAND", "FLARE", "ROLL OUT"]
const EPS := 0.001

var db: NavDatabase
var airliner := false  # the A320: always on
var _t := 0.0
var _seen := -1.0  # controls/nav2/freq_mhz as last looked at
var _set := -1.0  # what this node last wrote there
var _tuned := ""  # ident of the ILS this node tuned
var _manual := false
var _manual_plan := ""


## Adds the node to the flight scene's Avionics node.
static func add(avionics: Node, nav_db: NavDatabase, is_airliner: bool) -> IlsAutotune:
	var n := IlsAutotune.new()
	n.name = "IlsAutotune"
	n.db = nav_db
	n.airliner = is_airliner
	avionics.add_child(n)
	return n


func enabled() -> bool:
	return airliner or bool(UserOptions.get_v("ils_autotune"))


## A new flight or restart: forget what was tuned and any manual override.
func restart() -> void:
	_seen = -1.0
	_set = -1.0
	_tuned = ""
	_manual = false
	_manual_plan = ""
	_publish("", 0.0, "", false)


func _process(dt: float) -> void:
	_t += dt
	if _t >= TICK_S:
		update(_t)
		_t = 0.0


## One look at the radio and the plan; `dt` only matters to _process.
func update(_dt: float) -> void:
	if db == null or not enabled() or not Props.get_b("systems/electrical/avionics_powered", true):
		return
	var cur := Props.get_f("controls/nav2/freq_mhz")
	var plan := _plan()
	if Props.get_b("controls/ils_auto/resume"):  # AUTO on the MCDU RAD NAV page
		Props.set_v("controls/ils_auto/resume", false)
		_manual = false
	elif _seen >= 0.0 and absf(cur - _seen) > EPS and absf(cur - _set) > EPS:
		_manual = true  # the pilot tuned it
		_manual_plan = plan.key
	_seen = cur
	if _manual and _manual_plan != plan.key:
		_manual = false  # a new arrival: the plan is back in charge
	if _manual or Props.get_b("fdm/wow"):
		_publish(_tuned, _set, "", _manual)
		return
	var w := IlsPick.wanted(plan.ctx)
	if w.s.is_empty() or _in_use():
		_publish(_tuned, _set, "", false)
		return
	var s: Dictionary = w.s
	if absf(cur - float(s.mhz)) > EPS:
		Props.set_v("controls/nav2/freq_mhz", float(s.mhz))
		Props.set_v("controls/nav2/obs_deg", fposmod(float(s.course_true) - VAR_DEG, 360.0))
	_set = float(s.mhz)
	_seen = _set
	_tuned = str(s.ident)
	_publish(_tuned, _set, str(w.why), false)


## NAV2 receives the ILS this node tuned, or the autoflight has the localizer.
func _in_use() -> bool:
	if str(Props.get_v("avionics/nav2/kind", "")) == "ILS" and Props.get_b("avionics/nav2/valid") \
			and str(Props.get_v("avionics/nav2/ident", "")) == _tuned and _tuned != "":
		return true
	var lat := str(Props.get_v("ap/fma/lateral", "")).split("\n")[0]
	return lat in CAPTURED


## {key: the arrival being planned ("VAPO/28", "lineup" without a plan), ctx: for IlsPick.wanted}.
func _plan() -> Dictionary:
	var dest := _destination()
	var ap := db.airport(dest) if dest != "" else {}
	var names: Array = [str(ap.get("icao", "")), str(ap.get("ident", ""))] if not ap.is_empty() else []
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var rwy := str(Props.get_v("mcdu/init/arr_rwy", ""))
	return {"key": "%s/%s" % [dest, rwy] if dest != "" else "lineup", "ctx": {"stations": db.ils, "names": names,
		"dest": Vector2(ap.x, ap.y) if not ap.is_empty() else null, "arr_rwy": rwy, "pos": p,
		"track": Props.get_f("fdm/track_rad"), "phase": str(Props.get_v("avionics/fms/phase", "")),
		"armed": Props.get_b("controls/fcu/loc") or Props.get_b("controls/fcu/appr")}}


## The destination airport of the plan: the last airport of the MCDU FROM/TO, else the route's destination.
func _destination() -> String:
	var parts := str(Props.get_v("mcdu/init/from_to", "")).split("/", false)
	for i in range(parts.size() - 1, 0, -1):  # the first is the departure
		if not db.airport(parts[i]).is_empty():
			return parts[i]
	var d := str(Props.get_v(RouteSetup.DEST_PROP, ""))
	return d if not db.airport(d).is_empty() else ""


func _publish(ident: String, mhz: float, why: String, manual: bool) -> void:
	Props.set_v("avionics/ils_auto/ident", ident)
	Props.set_v("avionics/ils_auto/mhz", mhz)
	Props.set_v("avionics/ils_auto/why", why)
	Props.set_v("avionics/ils_auto/manual", manual)
	Props.set_v("avionics/ils_auto/active", ident != "" and not manual and absf(Props.get_f("controls/nav2/freq_mhz") - mhz) <= EPS)
