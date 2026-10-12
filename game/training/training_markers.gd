class_name TrainingMarkers
extends Node3D
## Assistive 3D markers for training lessons (like MSFS landing challenge / X-Plane training
## hoops): a chevron ribbon down the runway centreline, glide-path rings on the 3° approach
## (upcoming = cyan, next = yellow, flown = green, missed = red), an aim-point box on the
## runway, and a beacon column to turn toward. Everything is positioned in ENU and
## re-placed whenever the floating origin shifts.

const RING_R := 22.0
const RING_SPACING := 300.0
const RING_FIRST := 3600.0   # m before the threshold
const RING_LAST := 450.0
const PATH_DEG := 3.0
const TCH := 15.0            # m above the threshold on the glide path
const LIFT := 0.6            # keeps ground markers above the runway strip

var thr := Vector2.ZERO      # threshold (east, north)
var hdg := 0.0               # runway heading, rad true
var elev := 0.0              # threshold elevation, m
var length := 1500.0
var rings: Array = []        # [MeshInstance3D, along m, centre height m, state]
var _items: Array = []       # [Node3D, Vector3 enu]
var _beacon: Node3D
var _mats := {}
var _height: Callable


func setup(threshold: Vector2, heading_deg: float, elevation_m: float, runway_length: float, height_fn := Callable()) -> void:
	_height = height_fn
	thr = threshold
	hdg = deg_to_rad(heading_deg)
	elev = elevation_m
	length = runway_length
	for k in ["cyan", "yellow", "green", "red", "white"]:
		_mats[k] = _material({"cyan": Color(0.2, 0.9, 1.0, 0.55), "yellow": Color(1.0, 0.85, 0.15, 0.8),
			"green": Color(0.25, 1.0, 0.4, 0.35), "red": Color(1.0, 0.25, 0.2, 0.4), "white": Color(1, 1, 1, 0.5)}[k])
	FloatingOrigin.shifted.connect(func(_d): _place_all())


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


## ENU point at `along` metres from the threshold along the runway (negative = before it).
func point(along: float, across := 0.0) -> Vector2:
	var u := Vector2(sin(hdg), cos(hdg))
	var r := Vector2(cos(hdg), -sin(hdg))
	return thr + u * along + r * across


func _add(n: Node3D, enu: Vector3) -> void:
	add_child(n)
	_items.append([n, enu])
	n.global_position = FloatingOrigin.to_render_d(enu.x, enu.y, enu.z)


func _place_all() -> void:
	for it in _items:
		(it[0] as Node3D).global_position = FloatingOrigin.to_render_d(it[1].x, it[1].y, it[1].z)


## Dashes down the centreline (8 m every 20 m, first 1.8 km): "stay on this line".
func add_centreline() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.05, 8.0)
	var n := int(minf(length - 40.0, 1800.0) / 20.0)
	for i in n:
		var p := point(25.0 + i * 20.0)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = _mats.white
		mi.rotation.y = -hdg
		_add(mi, Vector3(p.x, p.y, _ground(p) + LIFT))


func _ground(p: Vector2) -> float:
	return _height.call(p.x, p.y) if _height.is_valid() else elev


func add_aimpoint() -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 0.05, 45.0)
	m.mesh = box
	m.material_override = _mats.yellow
	var p := point(300.0)
	m.rotation.y = -hdg
	_add(m, Vector3(p.x, p.y, _ground(p) + LIFT))


func add_rings() -> void:
	var d := RING_FIRST
	while d >= RING_LAST:
		var along := -d
		var h := elev + TCH + d * tan(deg_to_rad(PATH_DEG))
		var t := TorusMesh.new()
		t.inner_radius = RING_R - 1.2
		t.outer_radius = RING_R + 1.2
		t.rings = 24
		t.ring_segments = 8
		var m := MeshInstance3D.new()
		m.mesh = t
		m.material_override = _mats.cyan
		var p := point(along)
		m.rotation = Vector3(PI / 2.0, 0, 0)  # ring plane perpendicular to the approach
		var holder := Node3D.new()
		holder.rotation.y = -hdg
		holder.add_child(m)
		_add(holder, Vector3(p.x, p.y, h))
		rings.append([m, along, h, "up"])
		d -= RING_SPACING
	_highlight_next(-1.0e9)


## Mark a ring flown (hit) or missed, and light the next one.
func ring_done(i: int, hit: bool) -> void:
	rings[i][3] = "hit" if hit else "miss"
	(rings[i][0] as MeshInstance3D).material_override = _mats.green if hit else _mats.red
	_highlight_next(rings[i][1])


func _highlight_next(after_along: float) -> void:
	for r in rings:
		if r[3] == "up" and r[1] > after_along:
			(r[0] as MeshInstance3D).material_override = _mats.yellow
			return


func set_beacon(from_enu: Vector3, heading_deg: float, dist := 4000.0) -> void:
	if _beacon:
		_items = _items.filter(func(it): return it[0] != _beacon)
		_beacon.queue_free()
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 12.0
	cyl.bottom_radius = 12.0
	cyl.height = 2500.0
	col.mesh = cyl
	col.material_override = _mats.cyan
	_beacon = Node3D.new()
	_beacon.add_child(col)
	var a := deg_to_rad(heading_deg)
	var e := from_enu.x + sin(a) * dist
	var n := from_enu.y + cos(a) * dist
	_add(_beacon, Vector3(e, n, from_enu.z))


func clear_beacon() -> void:
	if _beacon:
		_items = _items.filter(func(it): return it[0] != _beacon)
		_beacon.queue_free()
		_beacon = null
