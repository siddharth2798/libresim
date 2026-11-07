class_name PushbackPath
extends RefCounted
## The pushback tug's path (GroundOps): straight back `straight` metres, then a swing of `turn`
## radians (default a quarter turn) and radius `radius`, tail toward `side` (+1 right, -1 left).
## Shared with OpsCorridors and OpsSolids, which keep ground vehicles out of the swept area. The path
## is that of the CG; the corridor boxes carry the whole footprint (nose to tail, half span).
## straight / radius default to the C172's; an aircraft sets them in aircraft.json "pushback"
## (GroundParams.pushback). PushbackFit shortens or turns them so the wheels stay on the pavement.

const STRAIGHT := 30.0
const RADIUS := 18.0


static func length(straight := STRAIGHT, radius := RADIUS, turn := PI / 2.0) -> float:
	return straight + radius * turn


## Pose after s metres: [position Vector2 ENU, heading rad compass]. p0 / h0: start position and heading.
static func pose(p0: Vector2, h0: float, side: float, s: float, straight := STRAIGHT, radius := RADIUS, turn := PI / 2.0) -> Array:
	var back := -Vector2(sin(h0), cos(h0))  # tail direction (east, north)
	if s <= straight:
		return [p0 + back * s, h0]
	var a := minf((s - straight) / maxf(radius, 0.05), turn)
	var right := Vector2(cos(h0), -sin(h0))
	var centre := p0 + back * straight + right * side * radius
	var rel := -right * side * radius
	return [centre + rel.rotated(side * a), h0 - side * a]  # keeps moving tail-first around the arc


## Distances along the path where a corridor is sampled: the straight part (every <= 10 m, once, side > 0)
## and the arc (every <= 8 m). For the C172 (30 m, 18 m): 0 10 20 30 and 5 arc points.
static func samples(straight := STRAIGHT, radius := RADIUS, with_straight := true, turn := PI / 2.0) -> Array:
	var ds := []
	if with_straight:
		var n := maxi(ceili(straight / 10.0), 1)
		for k in n + 1:
			ds.append(straight * k / n)
	var arc := radius * turn
	var m := maxi(ceili(arc / 8.0), 4)
	for k in m + 1:
		ds.append(straight + arc * k / m)
	return ds
