class_name Gpws
extends RefCounted
## A320 stall horn and lite GPWS cues. Pure: no Props, no nodes.
## agl_ft and vs_fpm are feet and feet per minute, the callout units CalloutLogic
## already uses. The rest of the sim stays in SI; the player converts at the boundary.
##
## step(state, {agl_ft, vs_fpm, wow, stall, ap_disconnect_edge}, dt_s) -> cue:
##   "stall"  every frame while stall is true (the player loops the horn)
##   "ap"     when ap_disconnect_edge is true
##   "sink"   at most once per 4 s, airborne, below 500 ft, vertical speed < -1000 fpm
##   "alt"    once per approach on a downward crossing of 500, 100, 50, 30, 20 or 10 ft
##   ""       otherwise
## Altitude calls re-arm after weight-on-wheels or after climbing above 700 ft.
## The first sample only arms the altitude tracker. Priority: stall, ap, sink, alt.
## An altitude call that loses its frame stays pending. The autopilot edge does not.

const HEIGHTS := [500, 100, 50, 30, 20, 10]  # ft AGL, high to low
const REARM_FT := 700.0
const SINK_FT := 500.0
const SINK_FPM := -1000.0
const SINK_S := 4.0


static func new_state() -> Dictionary:
	return {"t": 0.0, "agl": 0.0, "armed": false, "fired": {}, "pending": false, "sink_at": -1.0e9}


## dt is seconds since the previous sample (the sink-rate gap). Omitted dt does not advance the clock.
static func step(s: Dictionary, i: Dictionary, dt: float = 0.0) -> String:
	var agl: float = i.agl_ft
	var vs: float = i.vs_fpm
	var wow: bool = i.wow
	s.t = float(s.t) + dt
	var prev: float = float(s.agl)
	var armed: bool = s.armed
	if wow or agl > REARM_FT:
		s.fired = {}
		s.pending = false
	if armed and not wow and vs < 0.0:
		for h in HEIGHTS:
			if prev > float(h) and agl <= float(h) and not s.fired.get(h, false):
				s.fired[h] = true
				s.pending = true
	s.agl = agl
	s.armed = true
	if i.stall:
		return "stall"
	if i.ap_disconnect_edge:
		return "ap"
	if not wow and agl < SINK_FT and vs < SINK_FPM and float(s.t) - float(s.sink_at) >= SINK_S:
		s.sink_at = s.t
		return "sink"
	if s.pending:
		s.pending = false
		return "alt"
	return ""
