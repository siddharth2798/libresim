class_name ObstacleHull
extends RefCounted
## The aircraft's solid outline: line segments (aircraft/c172/c172_hull.json) covering the
## prop disc, cowling, fuselage, wings, struts, wheels and tail. Replaces the old handful of
## contact points: a 6 m house or a tree fits between a wingtip and the CG, a segment does not.

var names := PackedStringArray()  # part name per segment ("right wingtip", "nose", ...)
var _a := PackedVector3Array()  # segment ends, structural metres (x aft, y right, z up)
var _b := PackedVector3Array()
var _ba := PackedVector3Array()  # the same ends in body axes about the CG (rebuilt when the CG moves)
var _bb := PackedVector3Array()
var _radius := 0.0
var _cg := Vector3(INF, 0.0, 0.0)


func _init(path := "res://aircraft/c172/c172_hull.json") -> void:
	var d: Dictionary = Paths.load_res_json(path)
	for pl in d.polylines:
		var pts: Array = pl.pts
		if pl.get("closed", false):
			pts = pts + [pts[0]]
		for side in (2 if pl.get("mirror", false) else 1):
			var nm: String = pl.part
			if pl.get("mirror", false):
				nm = ("right " if side == 0 else "left ") + nm
			for i in range(pts.size() - 1):
				names.append(nm)
				_a.append(_pt(pts[i], side == 1))
				_b.append(_pt(pts[i + 1], side == 1))


static func _pt(p: Array, flip: bool) -> Vector3:
	return Vector3(p[0], -p[1] if flip else p[1], p[2])


func count() -> int:
	return names.size()


func _sync(mb: MassBalance) -> void:
	if mb.cg == _cg:
		return
	_cg = mb.cg
	_ba.resize(count())
	_bb.resize(count())
	_radius = 0.0
	for i in count():
		_ba[i] = mb.body_of(_a[i])
		_bb[i] = mb.body_of(_b[i])
		_radius = maxf(_radius, maxf(_ba[i].length(), _bb[i].length()))


## Radius of the sphere about the CG that contains every segment.
func radius(mb: MassBalance) -> float:
	_sync(mb)
	return _radius


## Segment ends in ENU (east, north, up): [a0, b0, a1, b1, ...]. alt = CG altitude AMSL.
func world_points(mb: MassBalance, r_bn: Basis, pos_e: float, pos_n: float, alt: float) -> PackedVector3Array:
	_sync(mb)
	var out := PackedVector3Array()
	out.resize(count() * 2)
	for i in count():
		var pa := r_bn * _ba[i]  # NED offset from the CG
		var pb := r_bn * _bb[i]
		out[i * 2] = Vector3(pos_e + pa.y, pos_n + pa.x, alt - pa.z)
		out[i * 2 + 1] = Vector3(pos_e + pb.y, pos_n + pb.x, alt - pb.z)
	return out
