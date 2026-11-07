class_name LiveryPreviewPaint
extends RefCounted
## The turntable's copy of an atlas: small enough to update while a slider moves, with mipmaps so the
## fuselage does not alias into stripes when the whole aircraft is on screen.


const MAX_SIDE := 2048


static func for_screen(full: Image) -> Image:
	var img := full.duplicate()
	var long := maxi(img.get_width(), img.get_height())
	if long > MAX_SIDE:
		img.resize(maxi(1, img.get_width() * MAX_SIDE / long), maxi(1, img.get_height() * MAX_SIDE / long), Image.INTERPOLATE_BILINEAR)
	if img.has_mipmaps():
		img.clear_mipmaps()
	img.generate_mipmaps()
	return img


## Point every surface that uses this atlas at `tex`. A second call updates the material already overridden,
## because that material no longer has the atlas file path.
static func assign(root: Node, path: String, tex: Texture2D) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var over := m.get_surface_override_material(i) as BaseMaterial3D
			if over != null and str(over.get_meta("livery_atlas", "")) == path:
				over.albedo_texture = tex
				continue
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat == null or mat.albedo_texture == null or mat.albedo_texture.resource_path != path:
				continue
			var d := mat.duplicate() as BaseMaterial3D
			d.set_meta("livery_atlas", path)
			d.albedo_texture = tex
			d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			d.next_pass = mat.next_pass
			MaterialFinish.restamp(d)
			m.set_surface_override_material(i, d)
