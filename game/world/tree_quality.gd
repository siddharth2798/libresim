class_name TreeQuality
extends RefCounted
## Per-preset tree settings (docs/GRAPHICS-PLAN.md G8), applied by Graphics.apply_to_scene. From PRESETS: trees (impostor
## radius, m), tree_density, tree_lod (near-mesh radius, m; 0 = none on Low). From TABLE: atlas_px (impostor frame size;
## the atlas is 40 x 8 frames, so 64 px = 2560 x 512, 96 px = 3840 x 768; frames are drawn at most ~100 px tall at
## the near-mesh radius on a 1080p screen), blend (three impostor frames blended, else
## the nearest one), detail (LOD0 detail radius as a fraction of tree_lod), cover / cover_step (ground cover radius and
## grid step, m: GroundCover; none on Low), shadow_r (impostor trees cast proxy shadows within this, m: TreeShadows;
## High and up, inside the sun's shadow distance). The terrain canopy shade
## (terrain_canopy.gdshaderinc) costs the same on every preset and needs no setting.
## Costs rise with the preset; nothing here depends on the machine.

const TABLE := {
	"low": {"atlas_px": 64, "blend": false, "detail": 0.0, "cover": 0.0, "cover_step": 2.4, "shadow_r": 0.0},
	"medium": {"atlas_px": 72, "blend": false, "detail": 0.4, "cover": 18.0, "cover_step": 2.4, "shadow_r": 0.0},
	"high": {"atlas_px": 96, "blend": true, "detail": 0.4, "cover": 40.0, "cover_step": 1.6, "shadow_r": 500.0},
	"ultra": {"atlas_px": 96, "blend": true, "detail": 0.4, "cover": 50.0, "cover_step": 1.6, "shadow_r": 800.0},
	"max": {"atlas_px": 96, "blend": true, "detail": 0.4, "cover": 65.0, "cover_step": 1.5, "shadow_r": 1200.0},
}


static func of(preset: String) -> Dictionary:
	return TABLE.get(preset, TABLE.high)


## s: the Graphics.PRESETS entry of `preset`.
static func apply(tr: Node, s: Dictionary, preset: String) -> void:
	var q := of(preset)
	tr.radius = s.trees
	tr.density_scale = s.tree_density
	tr.lod_radius = s.tree_lod  # real tree meshes within this radius (0 = none)
	if "atlas_px" in tr:
		tr.atlas_px = q.atlas_px
		tr.blend_frames = q.blend
		tr.detail_radius = s.tree_lod * q.detail
		tr.cover_radius = q.cover
		tr.cover_step = q.cover_step
		tr.shadow_radius = minf(q.shadow_r, s.shadow)
	RenderingServer.global_shader_parameter_set("canopy_detail", 1.0 if q.blend else (0.5 if q.cover > 0.0 else 0.0))
	RenderingServer.global_shader_parameter_set("canopy_start", maxf(120.0, maxf(s.tree_lod, minf(q.shadow_r, s.shadow))))


## Impostor atlas memory (bytes) for a preset when nothing can be compressed: RGBA8 albedo + RG8 normal with mipmaps.
## Block compression (TreeAtlas.compress, where available) brings it to a third of that.
static func atlas_bytes(preset: String) -> int:
	return int(TreeAtlas.pixel_count(of(preset).atlas_px) * (4 + 2) * 4.0 / 3.0)


## Worst case in a full forest (land class 200, one tree per 10 m cell at most): impostors within the radius, near-mesh
## trees and their triangles (LOD0 within the detail radius, LOD1 out to the near radius), atlas MB.
static func budget(preset: String) -> Dictionary:
	var s: Dictionary = Graphics.PRESETS[preset]
	var q := of(preset)
	var per_m2: float = 0.8 * float(s.tree_density) / 100.0
	var lod: float = s.tree_lod
	var det: float = lod * float(q.detail)
	var near0 := PI * det * det * per_m2
	var near1 := PI * (lod * lod - det * det) * per_m2
	var tris0 := 0
	var tris1 := 0
	for sp in TreeSpecies.COUNT:
		tris0 = maxi(tris0, TreeMeshes.triangle_count(TreeMeshes.get_mesh(sp, 0)))
		tris1 = maxi(tris1, TreeMeshes.triangle_count(TreeMeshes.get_mesh(sp, 1)))
	var cover := cover_budget(preset)
	return {"impostors": int(PI * float(s.trees) * float(s.trees) * per_m2), "near_trees": int(near0 + near1),
		"near_tris": int(near0 * tris0 + near1 * tris1), "atlas_mb": atlas_bytes(preset) / 1048576.0,
		"cover_plants": cover.x, "cover_tris": cover.y}


## Worst-case ground cover: [plants, triangles] if every grid point within the radius carries a bush (16 triangles;
## grassland fills 60 % of points with 6-triangle tufts).
static func cover_budget(preset: String) -> Vector2i:
	var q := of(preset)
	if q.cover <= 0.0:
		return Vector2i.ZERO
	var plants := int(PI * q.cover * q.cover / (q.cover_step * q.cover_step))
	return Vector2i(plants, plants * GroundCoverMeshes.triangle_count(GroundCoverMeshes.get_mesh(GroundCoverRules.SHRUB)))
