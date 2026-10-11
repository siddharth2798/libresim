class_name RunwayLightLayout
extends RefCounted
## ICAO Annex 14 / FAA runway lights for one runway (pure layout, no nodes):
## edge lights every <= 60 m (white; last 600 m or last third yellow toward the far end on
## instrument runways), green threshold / red end bars across the full width, green wing
## bars on long or precision runways, centreline lights every 15 m (white, alternating
## red/white 900-300 m from the end, red in the last 300 m) and touchdown-zone barrettes
## over the first 900 m of ILS ends.
## A runway descriptor r (built by AirportLights.describe) has: a, b (Vector2 ENU ends),
## len, width, u (unit a->b), ils (Array[bool] per end), instrument, centreline.

const WHITE := Color(1.0, 0.92, 0.78)
const YELLOW := Color(1.0, 0.68, 0.18)
const GREEN := Color(0.12, 1.0, 0.45)
const RED := Color(1.0, 0.09, 0.04)
const BLUE := Color(0.12, 0.28, 1.0)

const EDGE_SPACING := 60.0
const CENTRE_SPACING := 15.0
const EDGE_LIFT := 0.35  # elevated fixtures
const INSET_LIFT := 0.08


## All runway-surface lights of r into s.
static func build(r: Dictionary, hf: Callable, s: LightSet) -> void:
	edges(r, hf, s)
	for i in 2:
		threshold_bar(r, i, hf, s)
	if r.centreline:
		centreline(r, hf, s)
	for i in 2:
		if r.ils[i]:
			touchdown_zone(r, i, hf, s)


## Threshold position and inward unit vector of end i (0 = a, 1 = b).
static func end_frame(r: Dictionary, i: int) -> Array:
	return [r.a, r.u] if i == 0 else [r.b, -r.u]


## Colour of an edge light dist_to_end metres before the far end, seen by a pilot rolling toward it.
static func edge_color(dist_to_end: float, r: Dictionary) -> Color:
	if r.instrument and dist_to_end < minf(600.0, r.len / 3.0):
		return YELLOW
	return WHITE


## Colour of the k-th centreline light dist_to_end metres before the far end.
static func centre_color(dist_to_end: float, k: int) -> Color:
	if dist_to_end < 300.0:
		return RED
	if dist_to_end < 900.0:
		return RED if k % 2 == 0 else WHITE
	return WHITE


static func edges(r: Dictionary, hf: Callable, s: LightSet) -> void:
	var u: Vector2 = r.u
	var side: Vector2 = Vector2(u.y, -u.x) * (r.width * 0.5 + 1.5)
	var n := maxi(ceili(r.len / EDGE_SPACING), 1)
	for k in n + 1:
		var along: float = r.len * k / n
		var c: Vector2 = r.a + u * along
		for sg in [-1.0, 1.0]:
			var p: Vector2 = c + side * sg
			var h: float = hf.call(p.x, p.y) + EDGE_LIFT
			if r.instrument:  # two beams: each direction shows its own caution zone
				s.add(p.x, p.y, h, edge_color(r.len - along, r), -u, 3.0, 0.12)
				s.add(p.x, p.y, h, edge_color(along, r), u, 3.0, 0.12)
			else:
				s.add(p.x, p.y, h, WHITE, u, 2.0, 0.25, true)


## Green threshold lights (beam out along the approach) and red end lights (beam back
## along the runway) across the full width of end i, plus wing bars on long runways.
static func threshold_bar(r: Dictionary, i: int, hf: Callable, s: LightSet) -> void:
	var f := end_frame(r, i)
	var t: Vector2 = f[0]
	var d: Vector2 = f[1]
	var side := Vector2(d.y, -d.x)
	var half: float = r.width * 0.5
	var n := maxi(int(r.width / 3.0), 4)
	for k in n + 1:
		var p: Vector2 = t + side * (-half + r.width * k / n) - d * 0.5
		var h: float = hf.call(p.x, p.y) + INSET_LIFT
		s.add(p.x, p.y, h, GREEN, -d, 2.0, 0.04, false, 0.0, 1.1)
		if k % 2 == 0:
			s.add(p.x, p.y, h, RED, d, 2.0, 0.03, false, 0.0, 1.0)
	if r.ils[i] or r.len >= 1800.0:
		for sg in [-1.0, 1.0]:
			for k in 5:
				var p2: Vector2 = t + side * sg * (half + 4.0 + k * 2.5) - d * 0.5
				s.add(p2.x, p2.y, hf.call(p2.x, p2.y) + EDGE_LIFT, GREEN, -d, 2.0, 0.04, false, 0.0, 1.1)


## Inset centreline lights every 15 m, each with a beam per direction.
static func centreline(r: Dictionary, hf: Callable, s: LightSet) -> void:
	var u: Vector2 = r.u
	var n := int((r.len - CENTRE_SPACING) / CENTRE_SPACING)
	for k in n + 1:
		var along: float = CENTRE_SPACING * 0.5 + k * CENTRE_SPACING
		if along > r.len:
			break
		var p: Vector2 = r.a + u * along + Vector2(u.y, -u.x) * 0.6
		var h: float = hf.call(p.x, p.y) + INSET_LIFT
		s.add(p.x, p.y, h, centre_color(r.len - along, k), -u, 6.0, 0.02, false, 0.0, 0.75)
		s.add(p.x, p.y, h, centre_color(along, n - k), u, 6.0, 0.02, false, 0.0, 0.75)


## Touchdown-zone lights: pairs of 3-light white barrettes every 30 m over the first 900 m.
static func touchdown_zone(r: Dictionary, i: int, hf: Callable, s: LightSet) -> void:
	var f := end_frame(r, i)
	var t: Vector2 = f[0]
	var d: Vector2 = f[1]
	var side := Vector2(d.y, -d.x)
	var along := 60.0
	while along <= minf(900.0, r.len * 0.5):
		for sg in [-1.0, 1.0]:
			for k in 3:
				var p: Vector2 = t + d * along + side * sg * (9.0 + k * 1.5)
				s.add(p.x, p.y, hf.call(p.x, p.y) + INSET_LIFT, WHITE, -d, 4.0, 0.02, false, 0.0, 0.7)
		along += 30.0
