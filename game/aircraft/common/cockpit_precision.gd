class_name CockpitPrecision
extends Node
## Keeps the cockpit rigid to the pilot's eye at any altitude. Built by Cockpit after its lighting; the scan runs deferred,
## once every cockpit part (FCU bars, LCD strip) exists.
## Why: render space is ENU metres with y = altitude, so in cruise the camera and the cockpit sit ~11 km from the render
## origin, where float32 steps are ~1 mm. Godot's single-precision renderer forms VIEW * MODEL on the GPU from those
## numbers, and the cockpit, 0.6 m (overhead) to 0.9 m (displays) from the eye, jittered by a few pixels each frame
## (tests/debug_overhead_shake.tscn measures it). Here every cockpit StandardMaterial3D becomes its cockpit shader
## (CockpitSurface) and other cockpit ShaderMaterials get the same line patched in; each mesh gets its aircraft-local origin (instance uniform ckpt_origin, from local transforms only,
## refreshed when a lever moves it), and every frame the camera's aircraft-local pose goes to the globals ckpt_view /
## ckpt_cam / ckpt_on. The shader then builds the cockpit's view-space position from small numbers.
## aircraft.json cockpit.detail_textures {material name: path in the aircraft folder}: a higher-resolution copy of an
## atlas (same UV layout) used instead of the glb's on every graphics preset but "low" (memory on small GPUs).
## --cockpit-precision=off keeps the glb materials (A/B checks, or a GPU that cannot run the shader).

var _model: AircraftModel
var _meshes: Array = []  # [MeshInstance3D, ...] drawn with a cockpit shader
var _pivots: Array = []  # [[pivot Node3D, last Transform3D, [index into _meshes]]]
var _mats: Array = []  # [[StandardMaterial3D, ShaderMaterial, last key]]
var _on := false
var _root: Node3D
var scanned := false


## Remembers the cockpit under `root` (the Cockpit node) of `model` and scans it at the end of this frame.
func build(model: AircraftModel, root: Node3D) -> void:
	_model = model
	_root = root
	process_priority = 11  # after the camera rig (10): this frame's eye pose
	if "--cockpit-precision=off" in OS.get_cmdline_user_args():
		scanned = true  # scan() does nothing
		set_process(false)
		return
	scan.call_deferred()


## Converts the cockpit's materials; returns how many StandardMaterial3Ds became cockpit shaders. Runs once.
func scan() -> int:
	if scanned or _root == null or not is_instance_valid(_root):
		return 0
	scanned = true
	var root := _root
	var detail := _detail(_model.def)
	var made := {}  # StandardMaterial3D -> ShaderMaterial
	var by_pivot := {}  # pivot Node3D -> [mesh index]
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not _convert(mi, made, detail):
			continue
		_meshes.append(mi)
		var p := mi.get_parent()
		while p != null and p != root:
			if str(p.name).begins_with("pivot_"):
				if not by_pivot.has(p):
					by_pivot[p] = []
				by_pivot[p].append(_meshes.size() - 1)
			p = p.get_parent()
		_place(mi)
	for p in by_pivot:
		_pivots.append([p, (p as Node3D).transform, by_pivot[p]])
	for m in made:
		_mats.append([m, made[m], CockpitSurface.key(m)])
	return made.size()


## {material name: Texture2D} of cockpit.detail_textures, empty on the low preset.
static func _detail(def: AircraftDef) -> Dictionary:
	var out := {}
	if def == null or str(Graphics.preset) == "low":
		return out
	var cfg: Dictionary = def.section("cockpit").get("detail_textures", {})
	for k in cfg:
		if str(k).begins_with("_"):
			continue
		var path: String = def.dir + "/" + str(cfg[k])
		if ResourceLoader.exists(path):
			out[str(k)] = load(path)
	return out


func _convert(mi: MeshInstance3D, made: Dictionary, detail: Dictionary) -> bool:
	if mi.material_override != null:
		var s := _shader(mi.material_override, made, detail)
		if s == null:
			return false
		mi.material_override = s
		return true
	var any := false
	for i in mi.mesh.get_surface_count():
		var s := _shader(mi.get_active_material(i), made, detail)
		if s != null:
			mi.set_surface_override_material(i, s)
			any = true
	return any


func _shader(m: Material, made: Dictionary, detail: Dictionary) -> ShaderMaterial:
	if m is ShaderMaterial:
		var ok := CockpitSurface.patch(m)
		var nx := (m as ShaderMaterial).next_pass
		while ok and nx is ShaderMaterial:  # windshield rain over the glass
			ok = CockpitSurface.patch(nx)
			nx = (nx as ShaderMaterial).next_pass
		return m if ok and nx == null else null
	if not m is BaseMaterial3D:
		return null
	if not made.has(m):
		var s := CockpitSurface.make(m, detail.get(m.resource_name))
		if s == null:
			return null
		made[m] = s
	return made[m]


## The mesh origin in the aircraft frame, from local transforms only (no 11 km render-space numbers).
func _place(mi: MeshInstance3D) -> void:
	var t := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != _model:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	var o := t.origin
	mi.set_instance_shader_parameter("ckpt_origin", Vector4(o.x, o.y, o.z, 1.0))


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d() as CameraRig
	var on := cam != null and cam.aircraft == _model and cam.mode == CameraRig.Mode.COCKPIT
	if on:
		RenderingServer.global_shader_parameter_set("ckpt_view", Projection(cam.cockpit_local.affine_inverse()))
		RenderingServer.global_shader_parameter_set("ckpt_cam", cam.global_position)
	if on != _on:
		_on = on
		RenderingServer.global_shader_parameter_set("ckpt_on", 1.0 if on else 0.0)
	for p in _pivots:  # levers moved this frame (CockpitLevers runs before the camera)
		var t: Transform3D = (p[0] as Node3D).transform
		if t != p[1]:
			p[1] = t
			for i in p[2]:
				_place(_meshes[i])
	for row in _mats:
		var k := CockpitSurface.key(row[0])
		if k != row[2]:
			row[2] = k
			CockpitSurface.sync(row[0], row[1])


func _exit_tree() -> void:
	if _on:
		RenderingServer.global_shader_parameter_set("ckpt_on", 0.0)
