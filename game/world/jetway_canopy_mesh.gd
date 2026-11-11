class_name JetwayCanopyMesh
extends RefCounted
## Geometry of a jetway cab's closure (JetwayCanopy): a bellows canopy over the sides and top of the hood face and a floor plate
## with a rubber bumper under it, each reaching forward to its own depth so the front edge follows the fuselage. Canopy-local
## frame = hood frame moved to the hood face: x toward the aircraft, y up, z across. Surface 0 = rubber, 1 = floor metal.

const Y0 := 3.752  # hood bottom = cab floor = door sill (jetway.glb)
const Y1 := 6.252
const Z0 := -1.34
const Z1 := 1.26
const SIDE_N := 10  # samples up each side
const TOP_N := 14  # samples across the top
const FLOOR_N := 14
const RINGS := 12  # bellows rings from the face to the front edge; odd rings bulge out
const AMP_M := 0.06  # fold bulge
const OVERLAP_M := 0.04  # the rubber presses this far into the skin (no daylight at the seam)
const PLATE_M := 0.12  # floor plate thickness
const BUMPER_M := 0.1  # rubber bumper depth on the plate's front edge


## The U outline (left side up, across the top, right side down): [points, outward normals], both Vector3 with x = 0.
static func outline() -> Array:
	var p: Array[Vector3] = []
	var n: Array[Vector3] = []
	for i in SIDE_N:
		p.append(Vector3(0.0, lerpf(Y0, Y1, float(i) / SIDE_N), Z0))
		n.append(Vector3(0.0, 0.0, -1.0))
	for i in TOP_N + 1:
		p.append(Vector3(0.0, Y1, lerpf(Z0, Z1, float(i) / TOP_N)))
		n.append(Vector3(0.0, 1.0, 0.0))
	for i in range(1, SIDE_N + 1):
		p.append(Vector3(0.0, lerpf(Y1, Y0, float(i) / SIDE_N), Z1))
		n.append(Vector3(0.0, 0.0, 1.0))
	n[SIDE_N] = Vector3(0.0, 1.0, -1.0).normalized()  # top corners
	n[SIDE_N + TOP_N] = Vector3(0.0, 1.0, 1.0).normalized()
	return [p, n]


## Points along the floor's front edge (y = Y0), left to right.
static func floor_points() -> Array[Vector3]:
	var p: Array[Vector3] = []
	for i in FLOOR_N + 1:
		p.append(Vector3(0.0, Y0, lerpf(Z0, Z1, float(i) / FLOOR_N)))
	return p


## depths: forward distance from the face to the skin at each outline point; floor_d the same along the floor edge.
static func build(depths: PackedFloat32Array, floor_d: PackedFloat32Array) -> ArrayMesh:
	var o := outline()
	var pts: Array[Vector3] = o[0]
	var nrm: Array[Vector3] = o[1]
	var rub := SurfaceTool.new()
	rub.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		for k in RINGS:
			var a := _ring(pts[i], nrm[i], depths[i], k)
			var b := _ring(pts[i + 1], nrm[i + 1], depths[i + 1], k)
			var c := _ring(pts[i + 1], nrm[i + 1], depths[i + 1], k + 1)
			var d := _ring(pts[i], nrm[i], depths[i], k + 1)
			_quad(rub, a, b, c, d)
	var fp := floor_points()
	var metal := SurfaceTool.new()
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in fp.size() - 1:
		var d0 := maxf(floor_d[i] - BUMPER_M, 0.0)
		var d1 := maxf(floor_d[i + 1] - BUMPER_M, 0.0)
		var p0 := fp[i]
		var p1 := fp[i + 1]
		var dn := Vector3(0.0, -PLATE_M, 0.0)
		_quad(metal, p0, p1, p1 + Vector3(d1, 0.0, 0.0), p0 + Vector3(d0, 0.0, 0.0))  # walking surface
		_quad(metal, p0 + dn + Vector3(d0, 0.0, 0.0), p1 + dn + Vector3(d1, 0.0, 0.0), p1 + dn, p0 + dn)  # underside
		var e0 := floor_d[i] + OVERLAP_M
		var e1 := floor_d[i + 1] + OVERLAP_M
		var lip := Vector3(0.0, 0.03, 0.0)
		_quad(rub, p0 + Vector3(d0, 0.0, 0.0), p1 + Vector3(d1, 0.0, 0.0), p1 + lip + Vector3(e1, 0.0, 0.0), p0 + lip + Vector3(e0, 0.0, 0.0))
		_quad(rub, p0 + lip + Vector3(e0, 0.0, 0.0), p1 + lip + Vector3(e1, 0.0, 0.0), p1 + dn + Vector3(e1, 0.0, 0.0), p0 + dn + Vector3(e0, 0.0, 0.0))
		_quad(rub, p0 + dn + Vector3(e0, 0.0, 0.0), p1 + dn + Vector3(e1, 0.0, 0.0), p1 + dn + Vector3(d1, 0.0, 0.0), p0 + dn + Vector3(d0, 0.0, 0.0))
	rub.generate_normals()
	metal.generate_normals()
	var m := rub.commit()
	metal.commit(m)
	return m


## Ring k of the bellows at an outline point: k / RINGS of the way to the skin, odd rings pushed out along the normal.
static func _ring(p: Vector3, n: Vector3, depth: float, k: int) -> Vector3:
	var t := float(k) / RINGS
	var x := t * (depth + OVERLAP_M)
	var bulge := AMP_M if k % 2 == 1 else 0.0
	return p + Vector3(x, 0.0, 0.0) + n * bulge


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)
