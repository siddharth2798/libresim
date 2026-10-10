class_name Terminals
extends Node3D
## Landmark terminal buildings (tools/16_terminal_models.py):
## data/processed/terminals/<ICAO>.glb + <ICAO>_model.json {origin [e, n, h], signs [...]}.
## Loaded when the camera is within LOAD_RADIUS, materials swapped by name for
## world/terminal.gdshader (glass curtain walls, cladding, metal / clay-tile roofs,
## lit coffered soffits), plus the big airport-name lettering as Label3D signs.

const LOAD_RADIUS := 20000.0
const KINDS := {"glass": 0, "panel": 1, "gable": 1, "roof_metal": 2, "roof_white": 2, "roof_tile": 3,
	"concrete": 4, "column": 4, "soffit": 5}

var _dir := ""
var _sites := {}  # icao -> {"origin": Vector3 ENU, "node": Node3D or null, "meta": Dictionary}
var _mats: Array[ShaderMaterial] = []
var _shader := preload("res://world/terminal.gdshader")
var _timer := 0.0


func _ready() -> void:
	_dir = Paths.data("terminals")
	var d := DirAccess.open(_dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with("_model.json"):
			var meta = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join(f)))
			if meta is Dictionary and FileAccess.file_exists(_dir.path_join(meta.icao + ".glb")):
				var o: Array = meta.origin
				_sites[meta.icao] = {"origin": Vector3(o[0], o[1], o[2]), "node": null, "meta": meta}
	FloatingOrigin.shifted.connect(func(_d): _reposition())


func _process(dt: float) -> void:
	var night := clampf((2.0 - Props.get_f("environment/sun_elev_deg", 30.0)) / 8.0, 0.0, 1.0)
	for m in _mats:
		m.set_shader_parameter("night", night)
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 1.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := FloatingOrigin.to_world(cam.global_position)
	for icao in _sites:
		var s: Dictionary = _sites[icao]
		var near := Vector2(w.x, w.y).distance_to(Vector2(s.origin.x, s.origin.y)) < LOAD_RADIUS
		if near and s.node == null:
			s.node = _load(icao, s.meta)
			_reposition()
		elif not near and s.node != null:
			for m in s.node.get_meta("mats", []):
				_mats.erase(m)
			s.node.queue_free()
			s.node = null


func _load(icao: String, meta: Dictionary) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(_dir.path_join(icao + ".glb"), state) != OK:
		push_error("terminals: cannot load %s.glb" % icao)
		return Node3D.new()
	var root: Node3D = doc.generate_scene(state)
	var before := _mats.size()
	_swap_materials(root)
	root.set_meta("mats", _mats.slice(before))
	for s in meta.get("signs", []):
		var l := Label3D.new()
		l.text = s.text
		l.font_size = 256
		l.pixel_size = float(s.get("height", 4.0)) / 256.0
		l.outline_size = 0
		var c: Array = s.get("color", [1, 1, 1])
		l.modulate = Color(c[0], c[1], c[2])
		l.double_sided = false
		l.shaded = false
		l.position = Vector3(s.pos[0], s.pos[2], -s.pos[1])
		l.rotation.y = deg_to_rad(-float(s.heading_deg))  # sign faces this compass heading
		root.add_child(l)
	add_child(root)
	return root


func _swap_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var src := mesh.surface_get_material(i)
			var name := src.resource_name if src else ""
			var kind := 1
			for k in KINDS:
				if name.begins_with(k):
					kind = KINDS[k]
			var m := ShaderMaterial.new()
			m.shader = _shader
			m.set_shader_parameter("kind", kind)
			m.set_shader_parameter("base_color", (src as BaseMaterial3D).albedo_color if src is BaseMaterial3D else Color(0.8, 0.8, 0.8))
			if name.contains("@"):  # e.g. "glass@2.4" -> 2.4 m between mullions
				m.set_shader_parameter("mullion", float(name.get_slice("@", 1).get_slice("#", 0)))
			(n as MeshInstance3D).set_surface_override_material(i, m)
			_mats.append(m)
	for c in n.get_children():
		_swap_materials(c)


func _reposition() -> void:
	for icao in _sites:
		var s: Dictionary = _sites[icao]
		if s.node:
			(s.node as Node3D).position = FloatingOrigin.to_render(s.origin)
