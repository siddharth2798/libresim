class_name FollowMeBody
extends RefCounted
## Follow-me car, lower body: hood and cab sides (a lofted shell with wheel-arch cut-outs), cargo bed,
## bumpers, grille, lamps, arch flares, conspicuity stripes, chassis. Generic yellow double-cab
## pickup, about 5.1 x 1.9 m. Built into a VehicleGeo (see world/follow_me_shell.gd).

const YELLOW := Color(0.99, 0.76, 0.03)
const BLACK := Color(0.055, 0.055, 0.06)
const DARK := Color(0.09, 0.09, 0.10)
const WHITE := Color(0.93, 0.94, 0.92)
const RED := Color(0.78, 0.04, 0.04)
const CHROME := Color(0.8, 0.82, 0.85)
const AMBER := Color(0.95, 0.5, 0.05)
const NOSE_Z := -2.34  # front of the lofted shell
const CAB_Z := 0.84  # back of the lofted shell (the cab's rear wall)
const TAIL_Z := 2.38  # bed end
const BELT_Y := 1.10  # top of the sills / beltline
const SILL_Y := 0.30
const HALF_W := 0.95
## z, half-width, top y, bottom y, top radius, bottom radius
const KEYS := [
	[-2.34, 0.80, 0.90, 0.52, 0.08, 0.04], [-2.30, 0.88, 0.99, 0.46, 0.11, 0.05],
	[-2.20, 0.93, 1.04, 0.40, 0.12, 0.06], [-1.60, 0.95, 1.07, 0.30, 0.13, 0.07],
	[-1.00, 0.95, 1.10, 0.30, 0.12, 0.06], [0.84, 0.95, 1.10, 0.30, 0.09, 0.06]]


static func build(g: VehicleGeo) -> void:
	var paint := VehicleGeo.mat(YELLOW, VehicleGeo.K.PAINT)
	var black := VehicleGeo.mat(BLACK, VehicleGeo.K.PLASTIC)
	_shell(g, paint)
	_bed(g, paint, black)
	_front(g, paint, black)
	_arch_flares(g, black)
	_stripes(g)
	_chassis(g, black)


## Arch height at z for an axle at zc (0 outside the arch).
static func arch_y(z: float, zc: float) -> float:
	var dz := absf(z - zc)
	return FollowMeLogic.WHEEL_R + sqrt(FollowMeLogic.ARCH_R * FollowMeLogic.ARCH_R - dz * dz) if dz < FollowMeLogic.ARCH_R else 0.0


static func _key(z: float) -> Array:
	for i in range(1, KEYS.size()):
		if z <= KEYS[i][0]:
			var a: Array = KEYS[i - 1]
			var b: Array = KEYS[i]
			var t: float = (z - a[0]) / (b[0] - a[0])
			return [z, lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t), lerpf(a[4], b[4], t), lerpf(a[5], b[5], t)]
	return KEYS[-1]


static func _shell(g: VehicleGeo, paint: Color) -> void:
	var zs: Array = []
	for k in KEYS:
		zs.append(k[0])
	for i in 15:  # the front wheel arch, sampled by angle
		zs.append(FollowMeLogic.AXLE_F - FollowMeLogic.ARCH_R * cos(PI * i / 14.0))
	zs.sort()
	var rows := []
	var last := -99.0
	for z in zs:
		if z - last < 0.01:
			continue
		last = z
		var k := _key(z)
		var yb := maxf(k[3], arch_y(z, FollowMeLogic.AXLE_F))
		rows.append(VehicleGeo.ring(k[1], yb, k[2], k[4], k[5], z))
	g.loft(rows, paint)
	g.poly(rows[0], Vector3.FORWARD, paint)  # nose panel


static func _bed(g: VehicleGeo, paint: Color, black: Color) -> void:
	var zc := FollowMeLogic.AXLE_R
	var r := FollowMeLogic.ARCH_R
	var prof := PackedVector2Array([Vector2(CAB_Z + 0.02, SILL_Y), Vector2(zc - r, SILL_Y)])
	for i in 15:
		var a := PI * i / 14.0
		prof.append(Vector2(zc - r * cos(a), FollowMeLogic.WHEEL_R + r * sin(a)))
	prof.append_array([Vector2(zc + r, SILL_Y), Vector2(TAIL_Z, SILL_Y), Vector2(TAIL_Z, 1.14), Vector2(CAB_Z + 0.02, 1.14)])
	g.prism_x(prof, 0.86, HALF_W, paint)
	g.prism_x(prof, -HALF_W, -0.86, paint)
	g.box(Vector3(0, 0.79, (CAB_Z + TAIL_Z) * 0.5), Vector3(1.72, 0.06, TAIL_Z - CAB_Z), VehicleGeo.mat(Color(0.05, 0.05, 0.055), VehicleGeo.K.PLASTIC), 0.01)
	g.box(Vector3(0, 0.99, CAB_Z + 0.05), Vector3(1.72, 0.38, 0.10), paint, 0.02)
	g.box(Vector3(0, 0.82, TAIL_Z - 0.04), Vector3(1.72, 0.64, 0.07), paint, 0.02)  # tailgate
	var tail := VehicleGeo.mat(Color(0.7, 0.03, 0.03), VehicleGeo.K.TAIL)
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.905, 0.86, TAIL_Z + 0.015), Vector3(0.11, 0.34, 0.05), tail, 0.015)
	g.box(Vector3(0, 0.50, TAIL_Z + 0.09), Vector3(1.94, 0.20, 0.24), black, 0.04)  # rear bumper
	g.box(Vector3(0, 0.62, TAIL_Z + 0.09), Vector3(1.0, 0.025, 0.2), VehicleGeo.mat(Color(0.3, 0.3, 0.32), VehicleGeo.K.METAL), 0.008)  # step plate
	g.box(Vector3(0, 0.45, TAIL_Z + 0.22), Vector3(0.40, 0.11, 0.012), VehicleGeo.mat(Color(0.93, 0.9, 0.78), VehicleGeo.K.TAPE))  # plate


static func _front(g: VehicleGeo, paint: Color, black: Color) -> void:
	var lens := VehicleGeo.mat(Color(0.8, 0.82, 0.85), VehicleGeo.K.HEAD)
	g.box(Vector3(0, 0.78, NOSE_Z - 0.02), Vector3(1.04, 0.26, 0.05), black, 0.012)  # grille
	for y in [0.70, 0.78, 0.86]:
		g.box(Vector3(0, y, NOSE_Z - 0.05), Vector3(0.98, 0.022, 0.02), VehicleGeo.mat(CHROME, VehicleGeo.K.METAL))
	for s in [-1.0, 1.0]:
		g.box(Vector3(s * 0.69, 0.84, NOSE_Z + 0.02), Vector3(0.36, 0.22, 0.10), black, 0.02)  # lamp housing
		g.box(Vector3(s * 0.69, 0.84, NOSE_Z - 0.03), Vector3(0.31, 0.17, 0.05), lens, 0.02)
		g.box(Vector3(s * 0.69, 0.68, NOSE_Z - 0.01), Vector3(0.30, 0.05, 0.04), VehicleGeo.mat(AMBER, VehicleGeo.K.PLASTIC), 0.01)  # indicator
		g.box(Vector3(s * 0.80, 0.46, NOSE_Z - 0.10), Vector3(0.40, 0.20, 0.20), black, 0.05, Basis(Vector3.UP, s * 0.38))  # bumper wing
	g.box(Vector3(0, 0.46, NOSE_Z - 0.14), Vector3(1.40, 0.20, 0.22), black, 0.05)
	g.box(Vector3(0, 0.45, NOSE_Z - 0.26), Vector3(0.40, 0.11, 0.012), VehicleGeo.mat(Color(0.93, 0.9, 0.78), VehicleGeo.K.TAPE))  # plate
	g.box(Vector3(0, 0.27, NOSE_Z - 0.20), Vector3(1.0, 0.07, 0.30), black, 0.02)  # skid plate
	g.box(Vector3(0, 1.075, -1.5), Vector3(0.62, 0.025, 0.55), paint, 0.01)  # hood bulge


## Black fender flares around the four wheel arches.
static func _arch_flares(g: VehicleGeo, black: Color) -> void:
	for zc in [FollowMeLogic.AXLE_F, FollowMeLogic.AXLE_R]:
		for s in [-1.0, 1.0]:
			VehicleParts.arch_flare(g, s, HALF_W, FollowMeLogic.WHEEL_R, zc, FollowMeLogic.ARCH_R, black)


## Reflective bands: door sides, tailgate chevrons.
static func _stripes(g: VehicleGeo) -> void:
	var white := VehicleGeo.mat(WHITE, VehicleGeo.K.TAPE)
	var red := VehicleGeo.mat(RED, VehicleGeo.K.TAPE)
	for s in [-1.0, 1.0]:
		var x: float = s * (HALF_W + 0.002)
		g.poly([Vector3(x, 0.62, -0.95), Vector3(x, 0.62, 0.78), Vector3(x, 0.70, 0.78), Vector3(x, 0.70, -0.95)], Vector3(s, 0, 0), white)
		g.poly([Vector3(x, 0.55, -0.95), Vector3(x, 0.55, 0.78), Vector3(x, 0.61, 0.78), Vector3(x, 0.61, -0.95)], Vector3(s, 0, 0), red)
	var z := TAIL_Z + 0.0
	for i in 9:  # red / white chevron band on the tailgate
		var x0 := -0.80 + 0.178 * i
		g.poly([Vector3(x0, 0.58, z), Vector3(x0 + 0.178, 0.58, z), Vector3(x0 + 0.178 + 0.10, 0.74, z), Vector3(x0 + 0.10, 0.74, z)], Vector3.BACK, white if i % 2 == 0 else red)


static func _chassis(g: VehicleGeo, black: Color) -> void:
	g.box(Vector3(0, 0.36, 0.1), Vector3(1.1, 0.14, 4.4), VehicleGeo.mat(Color(0.04, 0.04, 0.045), VehicleGeo.K.PLASTIC))
	for zc in [FollowMeLogic.AXLE_F, FollowMeLogic.AXLE_R]:
		g.box(Vector3(0, FollowMeLogic.WHEEL_R, zc), Vector3(1.5, 0.08, 0.08), black)
