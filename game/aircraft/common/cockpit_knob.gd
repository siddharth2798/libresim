class_name CockpitKnob
extends RefCounted
## A rotary knob on the cockpit panel (aircraft.json cockpit.levers "kind": "knob"; CockpitPick hands it the drag and
## the click). Item fields:
##   step       value per detent (default 1);  step_px  pointer pixels per detent (default 6, pointer up = more)
##   step_alt   {"prop": bool property, "step": detent while it is set} (the FCU ALT 100 / 1000 selector); a big
##              detent first lands on a whole multiple of itself
##   range      [lo, hi]: clamped, or with "wrap": true wrapped (heading 0..359)
##   values     [a, b, ...]: detents are these values instead (ND range and mode)
##   fallback   property read while the drive was never set (BARO: the weather QNH)
##   push       {prop: value, ...} written on a click; pull: the same on Shift+click (FCU managed / selected,
##              BARO QNH / STD). A knob with `values` and no push / pull steps to the next / previous value instead.


static func turn(item: Dictionary, drag_dy: float) -> void:
	var acc := float(item.get("acc", 0.0)) - drag_dy / maxf(float(item.get("step_px", 6.0)), 1.0)
	var n := int(acc)  # whole detents, toward zero
	item["acc"] = acc - n
	if n != 0:
		Props.set_v(str(item.drive), value_after(item, current(item), n))


## A click (push) or Shift+click (pull).
static func click(item: Dictionary, pull: bool) -> void:
	var spec: Variant = item.get("pull" if pull else "push")
	if spec is Dictionary:
		for p in spec:
			Props.set_v(str(p), spec[p])
	elif item.get("values") is Array:
		Props.set_v(str(item.drive), value_after(item, current(item), -1 if pull else 1, true))


## The drive now: the property, else the fallback property, else the bottom of the range (or the first value).
static func current(item: Dictionary) -> float:
	var drive := str(item.get("drive", ""))
	if Props.has(drive):
		return Props.get_f(drive)
	var fb := str(item.get("fallback", ""))
	if fb != "" and Props.has(fb):
		return Props.get_f(fb)
	var vals: Variant = item.get("values")
	if vals is Array and not (vals as Array).is_empty():
		return float(vals[0])
	var r: Array = item.get("range", [0.0, 0.0])
	return float(r[0])


## The value `n` detents on from `v`. `cycle` wraps a list of values (a click); a drag stops at the ends.
static func value_after(item: Dictionary, v: float, n: int, cycle := false) -> float:
	var vals: Variant = item.get("values")
	if vals is Array and not (vals as Array).is_empty():
		var list: Array = vals
		var i := 0
		for k in list.size():
			if absf(float(list[k]) - v) < absf(float(list[i]) - v):
				i = k
		i = posmod(i + n, list.size()) if cycle else clampi(i + n, 0, list.size() - 1)
		return float(list[i])
	var st := step_of(item)
	var out := v
	var off_grid := absf(v / st - roundf(v / st)) > 1.0e-4
	if st > float(item.get("step", 1.0)) + 1.0e-6 and off_grid:  # the first big detent lands on the next multiple
		out = (ceilf(v / st) if n > 0 else floorf(v / st)) * st
		n -= signi(n)
	out += n * st
	var r: Array = item.get("range", [])
	if r.size() == 2:
		var lo := float(r[0])
		var hi := float(r[1])
		if item.get("wrap", false):
			return wrapf(out, lo, hi + float(item.get("step", 1.0)))
		return clampf(out, lo, hi)
	return out


static func step_of(item: Dictionary) -> float:
	var alt: Variant = item.get("step_alt")
	if alt is Dictionary and Props.get_b(str(alt.get("prop", ""))):
		return float(alt.get("step", 1.0))
	return float(item.get("step", 1.0))
