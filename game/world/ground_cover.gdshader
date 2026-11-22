shader_type spatial;
render_mode cull_disabled, fog_disabled, alpha_to_coverage_and_one;
// Ground cover (GroundCover / GroundCoverMeshes): grass tufts, ferns and bushes within cover_r of the camera, cut out
// of the leaf-card atlas. INSTANCE_CUSTOM: r = tint seed, g = kind (0 grass, 1 fern, 2 shrub), b = dry (1 = straw grass),
// a = seed. Plants shrink away between 0.45 and 1.0 x cover_r (no pop at the edge of the layer, no specks far out), sway with a phase from
// their seed (no jump at an origin shift), darken towards their base, light like the ground (normals lean up) and dry
// out with the season (TreeLook.dryness). Lit, so they go dark at night; no shadows cast.

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;
#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4)
#include "res://world/haze_sky.gdshaderinc"
#include "res://world/tree_parts.gdshaderinc"

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float cover_r = 40.0;
uniform float season_dry = 0.0;

varying vec4 v_cust;
varying float v_h;
varying float v_dist;

void vertex() {
	v_cust = INSTANCE_CUSTOM;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = 1.0 - smoothstep(cover_r * 0.45, cover_r, distance(terrain_eye, wp));
	v_h = VERTEX.y;
	VERTEX *= s;
	float ph = TIME * 1.9 + INSTANCE_CUSTOM.a * 6.2831853;
	VERTEX.xz += vec2(sin(ph), cos(ph * 0.73)) * 0.05 * VERTEX.y * VERTEX.y;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	VERTEX += curve_local(MODEL_MATRIX, curve_drop(wp));
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALPHA = clamp(t.a * (1.0 + (tree_leaf_boost(UV) - 1.0) * 0.35), 0.0, 1.0);  // gentle: blades must not fill into squares
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	int kind = int(v_cust.g + 0.5);
	vec3 base = kind == 1 ? vec3(0.055, 0.12, 0.035) : (kind == 2 ? vec3(0.07, 0.11, 0.045) : vec3(0.075, 0.14, 0.04));
	vec3 col = base * t.rgb * 1.7 * mix(0.85, 1.15, v_cust.r);
	float dry = clamp(v_cust.b * 0.8 + season_dry * (kind == 0 ? 0.4 : 0.2), 0.0, 1.0);
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, l * vec3(1.8, 1.4, 0.65), dry * 0.65);
	col *= mix(0.7, 1.0, clamp(v_h, 0.0, 1.0));  // a little darker at the base, in the plant's own shade
	col *= mix(1.0, 0.8, wetness);
	NORMAL = normalize(mix(FRONT_FACING ? NORMAL : -NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, 0.6));
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = 0.9;
	SPECULAR = 0.05 * (1.0 - haze);
	BACKLIGHT = col * 0.5;
}
