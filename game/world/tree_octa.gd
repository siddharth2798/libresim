class_name TreeOcta
extends RefCounted
## Hemi-octahedral impostor frames (docs/GRAPHICS-PLAN.md G8). The upper half of the view sphere is folded onto a square
## of N x N frames: frame (i, j) is the tree seen from direction frame_dir(i, j); the outer ring of frames is the
## horizon (side views), the middle is the view from straight above. TreeAtlas bakes every frame of every species,
## tree.gdshader picks the three frames around the actual view direction and blends them (select()). Twin of
## tree_octa.gdshaderinc; tests/test_tree_look.gd checks both agree on the conventions.
## Directions are in the tree's canonical frame: y up, crown width ASPECT along x and z (the unit mesh scaled by
## (aspect, 1, aspect)), pointing from the crown centre towards the camera.

const N := 8  # frames per side: 64 views, 28 of them on the horizon


## Direction (y >= 0) -> square [-1, 1]^2. Below the horizon is folded onto the horizon.
static func encode(d: Vector3) -> Vector2:
	var v := Vector3(d.x, maxf(d.y, 0.0), d.z)
	var s := absf(v.x) + v.y + absf(v.z)
	if s < 1e-9:
		return Vector2.ZERO
	var p := Vector2(v.x, v.z) / s
	return Vector2(p.x + p.y, p.x - p.y)


static func decode(e: Vector2) -> Vector3:
	var p := Vector2(e.x + e.y, e.x - e.y) * 0.5
	return Vector3(p.x, 1.0 - absf(p.x) - absf(p.y), p.y).normalized()


## Continuous grid position 0..N-1 of view direction d.
static func grid(d: Vector3) -> Vector2:
	return (encode(d) * 0.5 + Vector2(0.5, 0.5)) * float(N - 1)


static func frame_dir(i: int, j: int) -> Vector3:
	return decode(Vector2(float(i), float(j)) / float(N - 1) * 2.0 - Vector2.ONE)


## The three frames around d and their weights (sum 1): [[i, j, w], ...], largest weight first.
static func select(d: Vector3) -> Array:
	var g := grid(d)
	var c := Vector2i(clampi(floori(g.x), 0, N - 2), clampi(floori(g.y), 0, N - 2))
	var f := g - Vector2(c)
	var out: Array
	if f.x + f.y < 1.0:
		out = [[c.x, c.y, 1.0 - f.x - f.y], [c.x + 1, c.y, f.x], [c.x, c.y + 1, f.y]]
	else:
		out = [[c.x + 1, c.y + 1, f.x + f.y - 1.0], [c.x + 1, c.y, 1.0 - f.y], [c.x, c.y + 1, 1.0 - f.x]]
	out.sort_custom(func(a, b): return a[2] > b[2])
	return out


## The single nearest frame (Low / Medium draw only this one).
static func nearest(d: Vector3) -> Vector2i:
	var g := grid(d)
	return Vector2i(clampi(roundi(g.x), 0, N - 1), clampi(roundi(g.y), 0, N - 1))


## Image axes of the view from direction d: [right, up], with right x up = d. A smooth field over the whole upper
## hemisphere (the minimal rotation from straight above, where right = +x and up = -z), so neighbouring frames are
## nearly aligned and their normals can be blended in the billboard's own axes.
static func basis(d: Vector3) -> Array:
	var x := d.x
	var y := maxf(d.y, -0.999)
	var z := d.z
	var k := 1.0 / (1.0 + y)
	var right := Vector3(1.0 - x * x * k, -x, -x * z * k)
	var up := Vector3(x * z * k, z, z * z * k - 1.0)
	return [right, up]
