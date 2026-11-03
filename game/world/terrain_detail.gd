class_name TerrainDetail
extends RefCounted
## Terrain detail materials (docs/GRAPHICS-PLAN.md G6, terrain_detail.gdshaderinc): the two CC0 texture arrays
## made by tools/26_terrain_textures.py, bound once as defaults of the terrain shader so every node material
## shares them (one albedo-modulation array, one normal + roughness + AO array; 11 layers of 1024 px each).

const MOD := "res://world/textures/terrain/detail_mod.webp"
const NRM := "res://world/textures/terrain/detail_nrm.webp"
const SOURCES := "res://world/textures/terrain/SOURCES.md"


static func apply(shader: Shader) -> void:
	if shader.get_default_texture_parameter("det_mod") != null:
		return
	if not ResourceLoader.exists(MOD) or not ResourceLoader.exists(NRM):
		push_warning("terrain detail textures missing: run tools/26_terrain_textures.py")
		return
	shader.set_default_texture_parameter("det_mod", load(MOD))
	shader.set_default_texture_parameter("det_nrm", load(NRM))
