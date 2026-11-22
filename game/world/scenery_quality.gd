class_name SceneryQuality
extends RefCounted
## Per-preset scenery settings that are not in the main preset table (core/graphics_settings.gd calls apply()).
## tile_cache: ground tiles (heights, images, composites) TerrainTileCache keeps per kind before it trims the ones
##   unused for 3 s. Each image entry is about 2.5 MB of video memory (768² imagery plus land-class, WorldCover and
##   shore maps), so 400 entries can reach about 1 GB after a long flight. The tiles the camera needs are never
##   trimmed, whatever the size: the selection is by distance, not view direction, so turning does not reload them.
## terrain_shadow: terrain nodes cast sun shadows. Medium draws one shadow split out to 700 m, where the ground's
##   own relief shadow adds little and costs a full terrain pass into the shadow map; High and up keep it.
## bld_shadow: OSM building tiles cast sun shadows.

const TABLE := {
	"low": {"tile_cache": 120, "terrain_shadow": false, "bld_shadow": true},
	"medium": {"tile_cache": 150, "terrain_shadow": false, "bld_shadow": true},
	"high": {"tile_cache": 400, "terrain_shadow": true, "bld_shadow": true},
	"ultra": {"tile_cache": 400, "terrain_shadow": true, "bld_shadow": true},
	"max": {"tile_cache": 400, "terrain_shadow": true, "bld_shadow": true},
}


static func for_preset(preset: String) -> Dictionary:
	return TABLE.get(preset, TABLE.high)


static func shadow_mode(on: bool) -> GeometryInstance3D.ShadowCastingSetting:
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Terrain (cache size, node shadows) and buildings (tile shadows) of a flight or viewer scene.
static func apply(root: Node, preset: String) -> void:
	var q := for_preset(preset)
	var t := root.get_node_or_null("Terrain")
	if t:
		if "cache" in t and t.cache != null:
			t.cache.max_entries = int(q.tile_cache)
		t.set_meta("cast_shadow", bool(q.terrain_shadow))
		for c in t.get_children():
			if c is MeshInstance3D:
				c.cast_shadow = shadow_mode(bool(q.terrain_shadow))
	var b := root.get_node_or_null("Buildings")
	if b:
		b.set_meta("cast_shadow", bool(q.bld_shadow))
		for c in b.get_children():
			if c is MeshInstance3D:
				c.cast_shadow = shadow_mode(bool(q.bld_shadow))


## The shadow setting for a new terrain node or building tile under `parent` (on until a preset says otherwise).
static func mode_for(parent: Node) -> GeometryInstance3D.ShadowCastingSetting:
	return shadow_mode(bool(parent.get_meta("cast_shadow", true)))
