class_name TickRate
extends RefCounted
## Runs slower work off the 120 Hz physics tick (docs/USAGE.md "Tick rates"). A script keeps its _physics_process and asks
## the accumulator whether this tick is due:
##   var _tick := TickRate.new(30.0)
##   func _physics_process(dt: float) -> void:
##       var h := _tick.step(dt)
##       if h > 0.0:
##           update(h)
## `step` returns the TRUE time since the work last ran (the sum of the dt it was fed), so an integrator
## (battery charge, a lag filter, a timer) is exactly as right as at 120 Hz; it returns 0.0 on the ticks in between. The count is
## in physics ticks, not frames, so it is the same at 30 or 144 fps and the same run to run. The first call always runs.
## Rates that are not a whole number of ticks (45 Hz = 2.67 ticks) run every 2nd or 3rd tick and keep the average.
## A dt longer than the period (a test calling with 0.1 s) simply runs on every call with that dt.

const EPS := 1e-6  # s; float noise of summing 1/120 four times against 1/30

var period: float  # s between runs
var _since := 0.0  # s of dt fed since the work last ran
var _wait := 0.0  # s until the next run is due (<= EPS: due now)


func _init(hz: float = 30.0) -> void:
	period = 1.0 / maxf(hz, 0.001)


## Feed one physics tick. Returns the seconds to run the work with, or 0.0 when it is not due.
func step(dt: float) -> float:
	_since += dt
	_wait -= dt
	if _wait > EPS:
		return 0.0
	var h := _since
	_since = 0.0
	_wait = clampf(_wait + period, 0.0, period)  # keeps the average rate when a tick overshoots
	return h


## The next call runs, whatever the count (after a load, a reset, a teleport).
func due_now() -> void:
	_wait = 0.0
