class_name LiveryFrame
extends RefCounted
## Camera distance for the livery turntable. A long fuselage fills the frame at a mild field of view;
## fitting the bounding sphere leaves the side view small, and a wide lens bends the nose.


const FOV := 32.0


static func axes(dir: Vector3) -> Dictionary:
	var forward := dir.normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3(0, 0.25, 1).normalized()
	var up_ref := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
	var right := up_ref.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	return {"forward": forward, "right": right, "up": up}


## Distance from the box centre along `dir` (pointing from the aircraft toward the camera).
static func distance(aabb: AABB, dir: Vector3, aspect: float, margin := 1.08) -> float:
	var ax := axes(dir)
	var tan_v := tan(deg_to_rad(FOV) * 0.5) / margin
	var tan_h := tan_v * maxf(aspect, 0.25)
	var half := aabb.size * 0.5
	var d := 0.5
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := Vector3(sx, sy, sz) * half
				d = maxf(d, absf(p.dot(ax.right)) / tan_h - p.dot(ax.forward))
				d = maxf(d, absf(p.dot(ax.up)) / tan_v - p.dot(ax.forward))
	return d


## How much of the frame the box uses at `dist` (1 touches the edge, above 1 is clipped).
static func frame_use(aabb: AABB, dir: Vector3, aspect: float, dist: float) -> float:
	var ax := axes(dir)
	var tan_v := tan(deg_to_rad(FOV) * 0.5)
	var tan_h := tan_v * maxf(aspect, 0.25)
	var half := aabb.size * 0.5
	var use := 0.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var p := Vector3(sx, sy, sz) * half
				var depth := dist + p.dot(ax.forward)
				if depth <= 0.05:
					return 99.0
				use = maxf(use, absf(p.dot(ax.right)) / (depth * tan_h))
				use = maxf(use, absf(p.dot(ax.up)) / (depth * tan_v))
	return use
