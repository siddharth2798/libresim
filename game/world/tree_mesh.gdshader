shader_type spatial;
render_mode cull_disabled, fog_disabled, alpha_to_coverage_and_one;
// Near tree mesh (TreeMeshes / TreeParts), instanced by TreeLod within lod_r metres of the camera; it casts and receives
// sun shadows (the leaf cards are alpha-tested in the shadow pass too, so the shadows are dappled).
// COLOR.rgb = base colour with baked occlusion, COLOR.a = part (0 bark, 0.5 leaf card, 1 frond); UV = leaf-card atlas;
// CUSTOM0.xyz = the point a part collapses to, CUSTOM0.w = 1 for LOD0-only detail, which shrinks away between 0.7 and
// 1.0 x detail_r (TreeLod switches a cell to LOD1 beyond detail_r, where nothing of it is left to pop).
// INSTANCE_CUSTOM: r = hue seed, g = species * variant_n + variant, b = value seed, a = seed (each tree's cards shift a
// little, so no two crowns are alike). Same tint and season as the impostor; dithers in with the opposite pattern.

global uniform vec3 fog_color;
global uniform float haze_density;
#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4)
#include "res://world/haze_sky.gdshaderinc"  // view-dependent haze colour (G4)
#include "res://world/tree_tint.gdshaderinc"
#include "res://world/tree_parts.gdshaderinc"
global uniform float wetness;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float lod_r = 0.0;
uniform float lod_band = 8.0;
uniform float detail_r = 60.0;
uniform float season_dry = 0.0;  // TreeLook.dryness
uniform float variant_n = 4.0;

varying vec4 v_col;
varying vec4 v_cust;
varying vec3 v_local;
varying float v_dist;
varying float v_od;

void vertex() {
	v_col = COLOR;
	v_cust = INSTANCE_CUSTOM;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_od = distance(terrain_eye, wp);  // the camera's, also in the shadow pass
	if (CUSTOM0.w > 0.5) {
		VERTEX = mix(CUSTOM0.xyz, VERTEX, 1.0 - smoothstep(detail_r * 0.7, detail_r, v_od));
	}
	float seed = INSTANCE_CUSTOM.a;
	if (COLOR.a > 0.25) {  // whole cards shift with a noise of their anchor: crowns differ per tree
		vec2 q = CUSTOM0.xz * 6.0 + CUSTOM0.y * 4.0 + seed * 31.0;
		VERTEX += (vec3(tree_vnoise(q), tree_vnoise(q + 17.0), tree_vnoise(q + 41.0)) - 0.5) * vec3(0.08, 0.05, 0.08);
	}
	v_local = VERTEX;
	float ph = TIME * 1.3 + seed * 6.2831853;  // seed phase, not the render position: no jump at an origin shift
	VERTEX.x += sin(ph) * 0.012 * VERTEX.y * VERTEX.y;
	if (COLOR.a > 0.25) {  // leaves flutter
		VERTEX += NORMAL * sin(TIME * 3.1 + dot(CUSTOM0.xyz, vec3(41.0, 23.0, 37.0)) + seed * 20.0) * 0.004 * VERTEX.y;
	}
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += curve_local(MODEL_MATRIX, curve_drop(wp));  // whole tree, from its base
}

void fragment() {
	float dn = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (dn < smoothstep(lod_r - lod_band, lod_r, v_od)) {
		discard;
	}
	vec4 leaf = texture(leaf_tex, UV);
	vec4 alb = tree_part_albedo(v_col, leaf, v_local, tree_leaf_boost(UV));
	vec3 col = alb.rgb;
	float bl = 0.0;
	ALPHA = alb.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (v_col.a > 0.25) {
		col = tree_season(tree_tint(col, v_cust.r, v_cust.b), tree_species_of(v_cust.g, variant_n), season_dry, v_cust.r);
		NORMAL = FRONT_FACING ? NORMAL : -NORMAL;  // crown normals point out of the crown on both faces of a card
		bl = 0.6;  // light through the leaves: the shade side of a card glows a little, not a flat paper back
	}
	col *= mix(1.0, 0.8, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = mix(0.85, 0.55, wetness);
	SPECULAR = mix(0.08, 0.25, wetness) * (1.0 - haze);
	BACKLIGHT = col * bl;
}
