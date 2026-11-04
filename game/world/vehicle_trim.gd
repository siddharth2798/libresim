class_name VehicleTrim
extends RefCounted
## Trim for the procedural ground vehicles: lamps (recorded in VehicleGeo.lamps for the night light points),
## rotating beacons and warning bars (their lenses carry a pivot, the shader turns the beam), reflective
## tape and chevrons, fleet-number plates, grilles, mirrors, steps, grab rails, wipers, hoses.

const P := preload("res://world/vehicle_parts.gd")


static func _m(c: Color, k: int) -> Color:
	return VehicleGeo.mat(c, k)


## Amber rotating beacon (side 0 / 1: two beacons turn half a turn apart): base, dome with a pivot.
static func beacon(g: VehicleGeo, p: Vector3, side: int, size := 0.14) -> void:
	var k := VehicleGeo.K.LENS_L if side == 0 else VehicleGeo.K.LENS_R
	g.box(p + Vector3(0, size * 0.12, 0), Vector3(size * 1.5, size * 0.24, size * 1.5), _m(P.BLACK, VehicleGeo.K.PLASTIC), size * 0.08)
	var dome := PackedVector2Array([Vector2(0.0, size * 0.5), Vector2(size * 0.62, size * 0.5), Vector2(size * 0.95, size * 0.4), Vector2(size * 1.1, 0.0)])
	var c := p + Vector3(0, size * 0.24, 0)
	g.pivot = Vector4(c.x, c.y, c.z, VehicleGeo.BEACON)
	g.lathe_x(dome, c, 10, _m(P.AMBER, k), Basis(Vector3.BACK, PI / 2))
	g.pivot = Vector4.ZERO
	g.lamps.append(["beacon", c + Vector3(0, size * 0.6, 0), side])


## Low warning light bar across a roof at p (width w): black base, two amber end lenses that turn.
static func light_bar(g: VehicleGeo, p: Vector3, w: float) -> void:
	g.box(p + Vector3(0, 0.05, 0), Vector3(w, 0.1, 0.28), _m(P.BLACK, VehicleGeo.K.PLASTIC), 0.03)
	g.box(p + Vector3(0, 0.12, 0), Vector3(w * 0.4, 0.06, 0.22), _m(Color(0.85, 0.86, 0.88), VehicleGeo.K.PLASTIC), 0.02)
	for s in [-1, 1]:
		var c: Vector3 = p + Vector3(s * w * 0.32, 0.12, 0)
		g.pivot = Vector4(c.x, c.y, c.z, VehicleGeo.BEACON)
		g.box(c + Vector3(0, 0.02, 0), Vector3(w * 0.3, 0.12, 0.24), _m(P.AMBER, VehicleGeo.K.LENS_L if s < 0 else VehicleGeo.K.LENS_R), 0.04)
		g.pivot = Vector4.ZERO
		g.lamps.append(["beacon", c + Vector3(0, 0.08, 0), 0 if s < 0 else 1])


## Headlamp: a dark bezel with the lens in it; centre p (front face), size s.
static func headlamp(g: VehicleGeo, p: Vector3, s: Vector3, record := true) -> void:
	g.box(p + Vector3(0, 0, s.z * 0.25), s + Vector3(0.03, 0.03, 0.0), _m(P.BLACK, VehicleGeo.K.PLASTIC), minf(s.y, s.x) * 0.2)
	g.box(p + Vector3(0, 0, -s.z * 0.08), s * Vector3(0.9, 0.86, 0.9), _m(Color(0.8, 0.82, 0.85), VehicleGeo.K.HEAD), minf(s.y, s.x) * 0.25)
	if record:
		g.lamps.append(["head", p + Vector3(0, 0, -s.z * 0.6), 0])


static func taillamp(g: VehicleGeo, p: Vector3, s: Vector3, record := true) -> void:
	g.box(p, s + Vector3(0.02, 0.02, 0.0), _m(P.BLACK, VehicleGeo.K.PLASTIC), minf(s.y, s.x) * 0.2)
	g.box(p + Vector3(0, 0, s.z * 0.12), s * Vector3(0.88, 0.86, 1.0), _m(Color(0.7, 0.03, 0.03), VehicleGeo.K.TAIL), minf(s.y, s.x) * 0.25)
	if record:
		g.lamps.append(["tail", p + Vector3(0, 0, s.z * 0.7), 0])


## Small amber side marker / indicator at p facing +-x (s).
static func marker(g: VehicleGeo, p: Vector3, s: float) -> void:
	g.box(p, Vector3(0.025, 0.05, 0.1), _m(P.AMBER, VehicleGeo.K.TAPE), 0.008)


## Reflective band along a body side (plane x, sign s): z0..z1, y0..y1.
static func side_band(g: VehicleGeo, x: float, z0: float, z1: float, y0: float, y1: float, col: Color, kind := VehicleGeo.K.TAPE) -> void:
	var xx: float = x + signf(x) * 0.003
	g.poly([Vector3(xx, y0, z0), Vector3(xx, y0, z1), Vector3(xx, y1, z1), Vector3(xx, y1, z0)], Vector3(signf(x), 0, 0), _m(col, kind))


## Diagonal two-colour conspicuity band on an end face (z, facing +z when back is true).
static func chevrons(g: VehicleGeo, x0: float, x1: float, y0: float, y1: float, z: float, back: bool, n: int, a: Color, b: Color) -> void:
	var w := (x1 - x0) / n
	var sh := (y1 - y0) * 0.6
	var zz := z + (0.003 if back else -0.003)
	for i in n:
		var xa := x0 + w * i
		var xb := minf(xa + w, x1)
		var xs0 := minf(xa + sh, x1)
		var xs1 := minf(xb + sh, x1)
		g.poly([Vector3(xa, y0, zz), Vector3(xb, y0, zz), Vector3(xs1, y1, zz), Vector3(xs0, y1, zz)],
			Vector3(0, 0, 1.0 if back else -1.0), _m(a if i % 2 == 0 else b, VehicleGeo.K.TAPE))


## Fleet-number plate (three digits from the vehicle's seed): centre p, size w x h, facing n (an axis).
static func plate(g: VehicleGeo, p: Vector3, w: float, h: float, n: Vector3, col := P.WHITE) -> void:
	var u := Vector3.UP.cross(n).normalized()  # left-to-right as seen from outside
	var v := Vector3.UP
	var o := p + n * 0.004
	var pts := [o - u * w * 0.5 - v * h * 0.5, o + u * w * 0.5 - v * h * 0.5, o + u * w * 0.5 + v * h * 0.5, o - u * w * 0.5 + v * h * 0.5]
	g.poly(pts, n, _m(col, VehicleGeo.K.NUMBER), [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])


## Grille on an end face at z (front = facing -z): dark recess, n horizontal slats, a bright frame.
static func grille(g: VehicleGeo, x0: float, x1: float, y0: float, y1: float, z: float, n: int, frame := Color(0.7, 0.72, 0.74)) -> void:
	var d := -1.0 if z < 0.0 else 1.0
	g.box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z + d * 0.01), Vector3(x1 - x0, y1 - y0, 0.03), _m(Color(0.012, 0.012, 0.014), VehicleGeo.K.PLASTIC))
	for i in n:
		var y := lerpf(y0, y1, (i + 0.5) / n)
		g.box(Vector3((x0 + x1) * 0.5, y, z + d * 0.03), Vector3(x1 - x0 - 0.04, (y1 - y0) / n * 0.4, 0.025), _m(P.BLACK, VehicleGeo.K.PLASTIC), 0.004)
	g.box(Vector3((x0 + x1) * 0.5, y1, z + d * 0.03), Vector3(x1 - x0 + 0.04, 0.04, 0.04), _m(frame, VehicleGeo.K.METAL), 0.01)
	g.box(Vector3((x0 + x1) * 0.5, y0, z + d * 0.03), Vector3(x1 - x0 + 0.04, 0.04, 0.04), _m(frame, VehicleGeo.K.METAL), 0.01)


## Truck mirror on an arm from the cab side at p (x sign gives the side), head hanging forward.
static func mirror(g: VehicleGeo, p: Vector3, size := 1.0) -> void:
	var s := signf(p.x)
	var black := _m(P.BLACK, VehicleGeo.K.PLASTIC)
	g.strut(p + Vector3(-s * 0.18 * size, 0.12 * size, 0.05), p + Vector3(0, 0.12 * size, 0), 0.025, 0.025, black)
	g.strut(p + Vector3(-s * 0.18 * size, -0.12 * size, 0.05), p + Vector3(0, -0.12 * size, 0), 0.025, 0.025, black)
	g.box(p + Vector3(s * 0.03, 0, 0), Vector3(0.06, 0.32, 0.2) * size, black, 0.025 * size)
	g.box(p + Vector3(s * 0.03, 0, 0.101 * size), Vector3(0.05, 0.28, 0.005) * size, _m(Color(0.6, 0.65, 0.7), VehicleGeo.K.METAL))


## Step (black tread plate on a bracket) at p, width w along z, depth d out from the side.
static func step(g: VehicleGeo, p: Vector3, w: float, d := 0.22) -> void:
	g.box(p, Vector3(d, 0.04, w), _m(Color(0.2, 0.2, 0.21), VehicleGeo.K.METAL), 0.008)
	g.box(p + Vector3(0, 0.022, 0), Vector3(d - 0.02, 0.005, w - 0.03), _m(P.BLACK, VehicleGeo.K.RUBBER))


## Vertical grab rail beside a door: from p, h high, standing off the body side (x sign).
static func grab_rail(g: VehicleGeo, p: Vector3, h: float) -> void:
	var s := signf(p.x)
	var m := _m(Color(0.75, 0.77, 0.8), VehicleGeo.K.METAL)
	g.strut(p + Vector3(s * 0.05, 0, 0), p + Vector3(s * 0.05, h, 0), 0.03, 0.03, m, 0.01)
	g.box(p + Vector3(s * 0.025, 0.04, 0), Vector3(0.05, 0.03, 0.03), m)
	g.box(p + Vector3(s * 0.025, h - 0.04, 0), Vector3(0.05, 0.03, 0.03), m)


## Two wipers lying at the bottom of a front pane (x0..x1 at y, face z).
static func wipers(g: VehicleGeo, x0: float, x1: float, y: float, z: float) -> void:
	var black := _m(P.BLACK, VehicleGeo.K.PLASTIC)
	var w := (x1 - x0) * 0.5
	for i in 2:
		var a := Vector3(x0 + w * (i + 0.15), y + 0.03, z - 0.02)
		g.strut(a, a + Vector3(w * 0.7, 0.12, 0.0), 0.02, 0.02, black)


## Hose coiled on a drum: a short fat cylinder about x at c (radius r, width w).
static func hose_drum(g: VehicleGeo, c: Vector3, r: float, w: float, col := Color(0.06, 0.06, 0.065)) -> void:
	var drum := PackedVector2Array([Vector2(-w * 0.5, 0.0), Vector2(-w * 0.5, r * 1.15), Vector2(-w * 0.45, r * 1.15),
		Vector2(-w * 0.45, r), Vector2(w * 0.45, r), Vector2(w * 0.45, r * 1.15), Vector2(w * 0.5, r * 1.15), Vector2(w * 0.5, 0.0)])
	g.lathe_x(drum, c, 16, _m(col, VehicleGeo.K.RUBBER))
	g.lathe_x(PackedVector2Array([Vector2(w * 0.5, r * 1.15), Vector2(w * 0.5, 0.0)]), c, 16, _m(Color(0.6, 0.62, 0.64), VehicleGeo.K.METAL))
	g.lathe_x(PackedVector2Array([Vector2(-w * 0.5, 0.0), Vector2(-w * 0.5, r * 1.15)]), c, 16, _m(Color(0.6, 0.62, 0.64), VehicleGeo.K.METAL))


## Exhaust stack: a pipe from p up h with a cap.
static func exhaust(g: VehicleGeo, p: Vector3, h: float, r := 0.05) -> void:
	var pipe := PackedVector2Array([Vector2(0.0, r), Vector2(h, r), Vector2(h, r * 0.7)])
	g.lathe_x(pipe, p, 8, _m(Color(0.35, 0.35, 0.36), VehicleGeo.K.METAL), Basis(Vector3.BACK, PI / 2))
