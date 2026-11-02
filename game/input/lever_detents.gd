class_name LeverDetents
extends RefCounted
## Pure logic of a thrust lever with named detents (aircraft.json controls.levers.throttle
## "detents": [{"name": "IDLE", "pos": 0.0, "zone": 0.03}, ...]).
## Lever position: forward travel 0 (idle) .. 1 (full), reverse travel 0 .. -1 (REV MAX).
## A detent grabs the lever when it is within `zone` of it (default DEFAULT_ZONE).
## An A320 lever as pos = thrust lever angle / 45 deg: IDLE 0, CL 0.556, FLX/MCT 0.778, TOGA 1.

const DEFAULT_ZONE := 0.025
const EPS := 1e-4


## Detents sorted by position (the data is not required to be).
static func sorted(detents: Array) -> Array:
	var out := detents.duplicate()
	out.sort_custom(func(a, b): return float(a.pos) < float(b.pos))
	return out


## The lever position, pulled onto a detent when it is inside that detent's zone.
static func snap(pos: float, detents: Array, default_zone := DEFAULT_ZONE) -> float:
	var best := pos
	var best_d := INF
	for d in detents:
		var dist := absf(pos - float(d.pos))
		if dist <= float(d.get("zone", default_zone)) and dist < best_d:
			best = float(d.pos)
			best_d = dist
	return best


## Name of the detent the lever sits on ("" between detents).
static func name_at(pos: float, detents: Array, tol := 0.005) -> String:
	for d in detents:
		if absf(pos - float(d.pos)) <= tol:
			return str(d.name)
	return ""


## Next detent above (dir > 0) or below (dir < 0) the lever; the lever position when there is none.
## reverse_ok false ignores the detents in the reverse range.
static func step(pos: float, detents: Array, dir: int, reverse_ok := true) -> float:
	var best := pos
	var found := false
	for d in sorted(detents):
		var p := float(d.pos)
		if p < 0.0 and not reverse_ok:
			continue
		if dir > 0 and p > pos + EPS:
			return p
		if dir < 0 and p < pos - EPS:
			best = p
			found = true
	return best if found else pos


## Axis travel 0..1 (shaped "half" axis, 0 = lever fully back) -> lever position. With a reverse
## range, the first `reverse_frac` of the travel is reverse (REV MAX at 0, idle at reverse_frac).
static func axis_to_pos(v: float, reverse_frac: float) -> float:
	v = clampf(v, 0.0, 1.0)
	if reverse_frac <= 0.0:
		return v
	if v < reverse_frac:
		return -(1.0 - v / reverse_frac)
	return (v - reverse_frac) / (1.0 - reverse_frac)


static func pos_to_axis(pos: float, reverse_frac: float) -> float:
	pos = clampf(pos, -1.0 if reverse_frac > 0.0 else 0.0, 1.0)
	if reverse_frac <= 0.0:
		return pos
	return (1.0 + pos) * reverse_frac if pos < 0.0 else reverse_frac + pos * (1.0 - reverse_frac)


static func clamp_pos(pos: float, reverse: bool) -> float:
	return clampf(pos, -1.0 if reverse else 0.0, 1.0)

