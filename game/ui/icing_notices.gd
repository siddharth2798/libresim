class_name IcingNotices
extends RefCounted
## In-flight cards for icing (ui/notifications.gd polls it): the first ice on the airframe, a pitot blocked by
## ice, ice in an engine inlet. Each card shows once per episode (the level has to fall back before it can
## show again). Reads icing/{airframe, pitot_blocked, engine_<n>} (systems/icing.gd).

const AIRFRAME_AT := 0.05  # ice level that counts as "first ice"
const AIRFRAME_OFF := 0.02
const ENGINE_AT := 0.15
const ENGINE_OFF := 0.05

var _frame := false
var _pitot := false
var _engine := false


## New cards as [title, detail, level (Notifications.CAUTION / WARNING), key]; empty most of the time.
func poll(anti_ice: bool) -> Array:
	var out := []
	var ice := Props.get_f("icing/airframe")
	if ice > AIRFRAME_AT and not _frame:
		out.append(["Ice accretion — leave icing conditions",
			"Wing and engine anti-ice (J: controls)" if anti_ice else "Only the pitot is heated: get out of the cloud or to warmer air", Notifications.CAUTION, "ice:frame"])
	_frame = ice > AIRFRAME_OFF if _frame else ice > AIRFRAME_AT
	var blocked := Props.get_b("icing/pitot_blocked")
	if blocked and not _pitot:
		out.append(["Pitot icing — airspeed unreliable", "Pitot heat on; fly attitude and power, cross-check with GPS ground speed", Notifications.WARNING, "ice:pitot"])
	_pitot = blocked
	var worst := 0.0
	for i in maxi(int(Props.get_f("engine/count", 1.0)), 1):
		worst = maxf(worst, Props.get_f("icing/engine_%d" % (i + 1)))
	if worst > ENGINE_AT and not _engine:
		out.append(["Engine icing", "Power is falling: " + ("engine anti-ice on" if anti_ice else "alternate air (controls/alt_air) or leave the cloud"), Notifications.CAUTION, "ice:engine"])
	_engine = worst > ENGINE_OFF if _engine else worst > ENGINE_AT
	return out
