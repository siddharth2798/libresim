class_name VehicleLamps
extends RefCounted
## Light points (world/light_point.gdshader, the aerodrome lights' glow) for the working ground vehicles of
## one airport: rotating amber beacons (day and night) and head / tail lamps (night only). Two
## MultiMeshes per airport, whatever the number of vehicles. Lamp positions come from the vehicle builders
## (GroundVehicles.lamps); add() takes a placed vehicle's transform in the frame the lights are drawn in.

const WHITE := Color(1.0, 0.93, 0.8)
const RED := Color(1.0, 0.05, 0.03)
const AMBER := Color(1.0, 0.5, 0.06)

static var _beacon_mat: ShaderMaterial
static var _lamp_mat: ShaderMaterial

var beacons := LightSet.new()
var lamps := LightSet.new()


static func _material(gain: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://world/light_point.gdshader")
	m.set_shader_parameter("gain", gain)
	m.set_shader_parameter("base_m", 0.22)
	m.set_shader_parameter("min_px", 1.8)
	m.set_shader_parameter("max_m", 4.0)
	m.set_shader_parameter("halo", 0.35)
	m.render_priority = 1
	return m


static func materials() -> void:
	if _beacon_mat == null:
		_beacon_mat = _material(2.4)
		_lamp_mat = _material(2.0)
		set_night(0.0)


static func set_night(night: float) -> void:
	if _beacon_mat == null:
		return
	_beacon_mat.set_shader_parameter("level", lerpf(0.35, 1.0, night))
	_lamp_mat.set_shader_parameter("level", night)


static func release() -> void:
	_beacon_mat = null
	_lamp_mat = null


## The lamps of a vehicle of `kind` placed with transform t (model -> drawing frame, scale included);
## seed sets the beacon phase. directional: head / tail lamps beam along the vehicle (a parked one);
## false = omnidirectional (a vehicle that moves, its MultiMesh does not turn with it).
func add(kind: String, t: Transform3D, seed: float, directional := true) -> void:
	var f := t.basis * Vector3.FORWARD
	var fwd := Vector2(f.x, -f.z).normalized() if directional else Vector2.ZERO
	for l in GroundVehicles.lamps(kind):
		var p: Vector3 = t * (l[1] as Vector3)
		match l[0]:
			"beacon":
				beacons.add(p.x, -p.z, p.y, AMBER, Vector2.ZERO, 0.0, 0.0, false, 3.0 + fposmod(seed + l[2] * 0.5, 1.0) * 0.999, 1.2)
			"head":
				lamps.add(p.x, -p.z, p.y, WHITE, fwd, 6.0, 0.05, false, 0.0, 1.0)
			"tail":
				lamps.add(p.x, -p.z, p.y, RED, -fwd, 4.0, 0.06, false, 0.0, 0.7)


## Add the MultiMesh instances under `parent` (nothing for an empty set).
func attach(parent: Node3D) -> void:
	materials()
	for pair in [[beacons, _beacon_mat, "VehicleBeacons"], [lamps, _lamp_mat, "VehicleLamps"]]:
		var mi: MultiMeshInstance3D = (pair[0] as LightSet).make_instance(pair[1], pair[2])
		if mi != null:
			mi.set_meta("no_solid", true)
			parent.add_child(mi)
