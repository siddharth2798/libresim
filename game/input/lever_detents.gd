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


## A joystick lever with a reverse range whose idle detent was calibrated (binding "lo" = raw at
## idle, input_bindings.gd): from idle up it is the forward position `fwd`, behind idle it is reverse,
## down to REV MAX at raw `rev_raw` (the direction of "behind" is the one towards rev_raw, so a lever
## that reads rising towards reverse works as well as one that reads falling). The idle detent has some
## play (IDLE_BAND of raw travel) that reads as idle, not as reverse thrust: reverse starts that far
## behind the calibrated idle and grows linearly to REV MAX.
const IDLE_BAND := 0.05


static func calibrated_pos(raw: float, fwd: float, idle_raw: float, rev_raw := -1.0) -> float:
	var dir := 1.0 if rev_raw >= idle_raw else -1.0
	var behind := (raw - idle_raw) * dir - IDLE_BAND  # raw travel behind the idle detent's play
	if behind <= 0.0:
		return fwd
	return -clampf(behind / maxf(absf(rev_raw - idle_raw) - IDLE_BAND, 0.05), 0.0, 1.0)


## Forward lever position of a raw value, piecewise linear through the lever's physical clicks:
## idle_raw -> 0, each click (raw, play, and the aircraft detent it names) -> that detent's position over
## +-play of raw, full_raw -> 1. A click whose detent the aircraft does not have is skipped, so a lever on
## an aircraft without such detents is linear idle..full. Beyond idle or full it clamps.
## clicks = [{"raw": r, "detent": "CL", "play": 0.03}], detents = aircraft.json controls.levers.throttle.detents.
static func forward_pos(raw: float, idle_raw: float, full_raw: float, clicks: Array, detents: Array) -> float:
	var span := full_raw - idle_raw
	if absf(span) < 0.05:
		return 0.0
	var knots := [[0.0, 0.0]]  # [progress 0..1 from idle to full, position]
	for c in clicks:
		var pos = detent_pos(detents, str(c.get("detent", "")))
		if pos == null:
			continue
		var play := float(c.get("play", 0.0))
		var u0: float = (float(c.raw) - play - idle_raw) / span
		var u1: float = (float(c.raw) + play - idle_raw) / span
		knots.append([minf(u0, u1), pos])
		knots.append([maxf(u0, u1), pos])
	knots.append([1.0, 1.0])
	knots.sort_custom(func(a, b): return a[0] < b[0])
	var u := clampf((raw - idle_raw) / span, 0.0, 1.0)
	for i in range(1, knots.size()):
		if u <= knots[i][0]:
			var u_prev: float = knots[i - 1][0]
			var du: float = knots[i][0] - u_prev
			var t: float = 0.0 if du < 1e-6 else (u - u_prev) / du
			return lerpf(knots[i - 1][1], knots[i][1], t)
	return 1.0


## Lever position of a raw axis value for a binding (input_bindings.gd) on an aircraft with these detents and
## reverse_frac: calibrated (binding "lo") = forward_pos through the binding's clicks and, with a reverse range,
## reverse behind idle towards "rev"; not calibrated = the first reverse_frac of the shaped travel `v` is reverse.
## The result is snapped to the detents.
static func from_binding(b: Dictionary, raw: float, v: float, detents: Array, reverse_frac: float) -> float:
	if not b.has("lo"):
		return snap(axis_to_pos(v, reverse_frac), detents)
	var fwd := v
	if b.get("clicks") is Array and not detents.is_empty():
		fwd = forward_pos(raw, float(b.lo), float(b.get("hi", 1.0)), b.clicks, detents)
	if reverse_frac > 0.0:
		fwd = calibrated_pos(raw, fwd, float(b.lo), float(b.get("rev", -1.0)))
	return snap(fwd, detents)


## Position of the detent called `name`, null when the aircraft has none.
static func detent_pos(detents: Array, name: String) -> Variant:
	for d in detents:
		if str(d.name) == name:
			return float(d.pos)
	return null


static func clamp_pos(pos: float, reverse: bool) -> float:
	return clampf(pos, -1.0 if reverse else 0.0, 1.0)

