shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;
// Impostor bake (TreeAtlas, once at startup or on a preset change; nothing here runs per frame): the LOD1 tree meshes,
// each instance turned so the orthographic bake camera sees it from one hemi-octahedral frame direction (TreeOcta).
// pass_id 0 writes the albedo (same colour path as tree_mesh.gdshader, no per-tree tint or season: the impostor adds
// those); the cover is the alpha of the viewport (opaque cut-out on a transparent background).
// pass_id 1 writes the normal in the frame's image axes (x right, y up) packed to 0..1 in RG and the foliage flag in B.
// Forward+ / Mobile store the viewport as sRGB, so there the normal pass writes the inverse sRGB curve of what it wants
// stored; Compatibility keeps both passes as written (srgb_target false), so there the albedo is encoded here.
// Normals go through the instance matrix as a MultiMesh does at run time (TreeParts.mesh squeezes them to match).

#include "res://world/tree_parts.gdshaderinc"

uniform int pass_id = 0;
uniform bool srgb_target = true;  // false on Compatibility, which stores what an unshaded pass writes as it is
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;

varying vec3 v_n;
varying vec4 v_col;
varying vec3 v_local;

vec3 to_srgb(vec3 l) {
	return mix(l * 12.92, 1.055 * pow(l, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), l));
}

vec3 to_linear(vec3 s) {
	return mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), s));
}

void vertex() {
	v_col = COLOR;
	v_local = VERTEX;
	v_n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 alb = tree_part_albedo(v_col, texture(leaf_tex, UV), v_local, 1.0);
	if (alb.a < 0.5) {
		discard;
	}
	if (pass_id == 0) {
		ALBEDO = srgb_target ? alb.rgb : to_srgb(alb.rgb);  // stored as sRGB either way (sampled as source_color)
	} else {
		vec3 n = normalize(v_n);
		vec3 packed = vec3(n.xy * 0.5 + 0.5, v_col.a > 0.25 ? 1.0 : 0.0);
		ALBEDO = srgb_target ? to_linear(packed) : packed;
	}
}
