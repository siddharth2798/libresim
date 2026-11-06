class_name FanBlur
extends Node
## Opacity of the static A320 fan-blur discs (detail_fan_blur_l / detail_fan_blur_r).
## N1 is percent. The blade meshes are not touched. Alpha is 0 at idle and rises with rpm.


const _CLEAR := 25.0
const _FULL := 58.0
const _PEAK := 0.8

var _drive: Array = []  # [BaseMaterial3D, property path], one copy per engine


## 0 at or below 25, smoothstep to 0.8 at 58, clamped. No property reads.
static func disc_alpha(n1_pct: float) -> float:
	return smoothstep(_CLEAR, _FULL, n1_pct) * _PEAK


## Bind the two discs. Missing names are ignored. Each material is duplicated once.
func follow(glb: Node) -> void:
	_drive.clear()
	if glb == null:
		set_process(false)
		return
	_bind(glb, "detail_fan_blur_l", "engines/1/n1")
	_bind(glb, "detail_fan_blur_r", "engines/2/n1")
	set_process(not _drive.is_empty())
	_apply()


func _bind(glb: Node, node_name: String, n1_path: String) -> void:
	var mi := glb.find_child(node_name, true, false) as MeshInstance3D
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() < 1:
		return
	var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
	if src == null:
		src = mi.get_active_material(0) as BaseMaterial3D
	if src == null:
		return
	var d := src.duplicate() as BaseMaterial3D
	d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.set_surface_override_material(0, d)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drive.append([d, n1_path])


func _process(_dt: float) -> void:
	_apply()


func _apply() -> void:
	for row in _drive:
		var mat := row[0] as BaseMaterial3D
		var c := mat.albedo_color
		c.a = disc_alpha(Props.get_f(row[1]))
		mat.albedo_color = c
