class_name PushbackPath
extends RefCounted
## The pushback tug's path (GroundOps): straight back STRAIGHT metres, then a 90 degree swing of
## radius RADIUS with the tail toward `side` (+1 right, -1 left). Shared with OpsSolids, which keeps
## ground vehicles out of the swept area.

const STRAIGHT := 30.0
const RADIUS := 18.0


static func length() -> float:
	return STRAIGHT + RADIUS * PI / 2.0


## Pose after s metres: [position Vector2 ENU, heading rad compass]. p0 / h0: start position and heading.
static func pose(p0: Vector2, h0: float, side: float, s: float) -> Array:
	var back := -Vector2(sin(h0), cos(h0))  # tail direction (east, north)
	if s <= STRAIGHT:
		return [p0 + back * s, h0]
	var a := minf((s - STRAIGHT) / RADIUS, PI / 2)
	var right := Vector2(cos(h0), -sin(h0))
	var centre := p0 + back * STRAIGHT + right * side * RADIUS
	var rel := -right * side * RADIUS
	return [centre + rel.rotated(side * a), h0 - side * a]  # keeps moving tail-first around the arc
