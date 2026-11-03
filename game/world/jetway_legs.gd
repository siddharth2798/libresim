class_name JetwayLegs
extends RefCounted
## The wheel support of a jetway (the glb's "Support": a wheel bogie and two lift columns with a cross-head). In the
## glb the columns rise to 9.2 m, 2.5 m above the 6.67 m tunnel roof, and the part tilted with the tunnel, so with a
## pitched (docked) bridge the wheels left the ground. Here the bogie and the columns are separate meshes (the same
## vertex data, the triangles split by height), standing upright under the support girder with the wheels on the
## ground and the columns stretched or shrunk to end at the tunnel roof.

const BOGIE_TOP := 1.05  # triangles wholly below this (m above the ground) are the wheel bogie

static var _split := {}  # Support mesh instance id -> [bogie ArrayMesh, legs ArrayMesh, legs y0, legs y1]

var node := Node3D.new()  # in the rig's frame (turns with the tunnel, not tilted)
var _bogie := MeshInstance3D.new()
var _legs := MeshInstance3D.new()
var _y0 := 1.0
var _y1 := 9.2


## Replace the glb's Support (a MeshInstance3D at model x = SUPPORT_X) by the split meshes under `host`.
func take(support: MeshInstance3D, host: Node3D) -> void:
	var parts := split(support.mesh)
	_bogie.mesh = parts[0]
	_legs.mesh = parts[1]
	_y0 = parts[2]
	_y1 = parts[3]
	for m in [_bogie, _legs]:
		if support.material_override:
			m.material_override = support.material_override
		node.add_child(m)
	node.name = "Support"
	_bogie.name = "SupportBogie"
	_legs.name = "SupportLegs"
	host.add_child(node)
	support.get_parent().remove_child(support)
	support.queue_free()


## x: along the tunnel from the rig's origin to the girder; foot / top: ground and tunnel-roof heights (rig frame).
func place(x: float, foot: float, top: float) -> void:
	node.position = Vector3(x - JetwayPose.SUPPORT_X, 0.0, 0.0)
	_bogie.position = Vector3(0.0, foot, 0.0)
	var k := maxf((top - foot - _y0) / (_y1 - _y0), 0.05)
	_legs.scale = Vector3(1.0, k, 1.0)
	_legs.position = Vector3(0.0, foot + _y0 * (1.0 - k), 0.0)


static func split(mesh: Mesh) -> Array:
	var key := mesh.get_instance_id()
	if _split.has(key):
		return _split[key]
	var bogie := ArrayMesh.new()
	var legs := ArrayMesh.new()
	var y0 := INF
	var y1 := -INF
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		var lo := PackedInt32Array()
		var hi := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			var top := maxf(v[idx[t]].y, maxf(v[idx[t + 1]].y, v[idx[t + 2]].y))
			var dst := lo if top <= BOGIE_TOP else hi
			dst.append_array([idx[t], idx[t + 1], idx[t + 2]])
			if top > BOGIE_TOP:
				for i in 3:
					y0 = minf(y0, v[idx[t + i]].y)
					y1 = maxf(y1, v[idx[t + i]].y)
		for pair in [[bogie, lo], [legs, hi]]:
			if (pair[1] as PackedInt32Array).is_empty():
				continue
			var a := arr.duplicate()
			a[Mesh.ARRAY_INDEX] = pair[1]
			(pair[0] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			(pair[0] as ArrayMesh).surface_set_material((pair[0] as ArrayMesh).get_surface_count() - 1, mesh.surface_get_material(s))
	_split[key] = [bogie, legs, y0 if y0 < INF else 1.0, y1 if y1 > -INF else 9.2]
	return _split[key]
