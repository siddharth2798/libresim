class_name AirportBeacon
extends Node3D
## Rotating aerodrome beacons (white / green, 12 rpm: one flash of each colour every
## 2.5 s) on the control tower, or near the airport reference point when there is none.
## Built for every lit airport within RADIUS of the camera (they are seen from far away).

const RADIUS := 70000.0
const MAST := 32.0  # beacon height above ground

var _sites: Array = []  # [icao, Vector2 ENU]
var _built := {}  # icao -> MultiMeshInstance3D
var _mat: ShaderMaterial
var _timer := 0.0
var hf: Callable


## sites: [[icao, Vector2 ENU]]; mat: the shared additive light material for beacons.
func setup(sites: Array, height_fn: Callable, mat: ShaderMaterial) -> void:
	_sites = sites
	hf = height_fn
	_mat = mat
	FloatingOrigin.shifted.connect(func(d: Vector3):
		for k in _built:
			_built[k].position += d)


## The beacon's two lamps (beams 180 deg apart) at p into s.
static func add_beacon(p: Vector2, h: float, s: LightSet) -> void:
	s.add(p.x, p.y, h, Color(1.0, 0.95, 0.85), Vector2.ZERO, 0.0, 0.0, false, 3.0, 1.5)
	s.add(p.x, p.y, h, Color(0.1, 1.0, 0.4), Vector2.ZERO, 0.0, 0.0, false, 3.5, 1.5)


func _process(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 2.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := FloatingOrigin.to_world(cam.global_position)
	var c := Vector2(w.x, w.y)
	for site in _sites:
		var icao: String = site[0]
		var p: Vector2 = site[1]
		var near := c.distance_to(p) < RADIUS
		if near and not _built.has(icao):
			var s := LightSet.new(p)
			add_beacon(p, hf.call(p.x, p.y) + MAST, s)
			var mi := s.make_instance(_mat, "beacon_" + icao)
			mi.custom_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
			mi.position = FloatingOrigin.to_render_d(p.x, p.y, 0.0)
			add_child(mi)
			_built[icao] = mi
		elif not near and _built.has(icao):
			_built[icao].queue_free()
			_built.erase(icao)
