shader_type spatial;
render_mode cull_disabled, fog_disabled, alpha_to_coverage_and_one;
// Tree impostor on two crossed quads (origin at the trunk base, unit size scaled to the tree).
// The sprite comes from the atlas TreeAtlas bakes at startup (albedo + cover, normal). Columns are
// yaw (atlas_grid.x, TreeLook.yaw_column: camera on local +Z is column 0), rows are species.
// INSTANCE_CUSTOM: r = hue seed, g = species * variant_n + variant, b = value seed, a = mesh seed.
// The sprite normal is lit by the sun and sky (lit side, shade side, backlit leaves); canopy undersides
// are darkened from that normal and from a vertical gradient. The cover is alpha-tested
// (ALPHA_SCISSOR_THRESHOLD; soft edges by alpha to coverage under MSAA), so the trees are opaque-pass
// geometry: they write depth, cast clean cut-out shadows and get the volumetric fog from VfogComposite
// (a blended ALPHA put them in the transparent pass, after the composite: unfogged speckles in mist).
// Trees closer than lod_r are drawn as meshes by TreeLod: this impostor dithers away over lod_band
// metres (discard), the mesh dithers in with the opposite pattern.

global uniform vec3 fog_color;
global uniform float haze_density;
#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4)
#include "res://world/haze_sky.gdshaderinc"  // view-dependent haze colour (G4)
#include "res://world/tree_tint.gdshaderinc"
global uniform float wetness;

uniform sampler2D atlas_albedo : filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_normal : filter_linear_mipmap, repeat_disable;
uniform vec2 atlas_grid = vec2(8.0, 4.0);  // yaw columns, species rows (TreeAtlas)
uniform float variant_n = 4.0;  // species is floor(custom.g / variant_n); TreeSpecies.VARIANTS
uniform float sway_crown_m = 0.045;  // TreeLook.SWAY_CROWN_M, world metres at the crown
uniform float sway_omega = 1.3962634;  // TAU / TreeLook.SWAY_PERIOD_S
uniform float lod_r = 0.0;
uniform float lod_band = 8.0;

varying vec4 v_cust;
varying float v_yaw_col;
varying float v_dist;
varying float v_od;
varying vec3 v_t;
varying vec3 v_nq;

void vertex() {
	v_cust = INSTANCE_CUSTOM;
	// TreeLook.sway_m: 0 at the trunk base (UV.y = 1), sway_crown_m at the crown, period a few seconds.
	// VERTEX is in unit tree space, so divide by the crown scale to get world metres. No quality flag
	// on Trees, so this small sway runs on every preset.
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float crown = clamp(1.0 - UV.y, 0.0, 1.0);
	float xz = max(length(MODEL_MATRIX[0].xyz), 0.5);
	float phase = wp.x * 0.05 + wp.z * 0.07;
	VERTEX.xz += TANGENT.xz * sin(TIME * sway_omega + phase) * (sway_crown_m / xz) * crown;
	// TreeLook.yaw_column: atan(local x, local z), nearest of atlas_grid.x views.
	vec3 to_cam = CAMERA_POSITION_WORLD - wp;
	float yaw = atan(dot(to_cam, MODEL_MATRIX[0].xyz), dot(to_cam, MODEL_MATRIX[2].xyz));
	v_yaw_col = mod(floor(yaw * atlas_grid.x / 6.2831853 + 0.5), atlas_grid.x);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_od = distance(terrain_eye, MODEL_MATRIX[3].xyz);  // the camera's, also in the shadow pass (as tree_mesh)
	v_t = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
	v_nq = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX += curve_local(MODEL_MATRIX, curve_drop(wp));  // whole tree, from its base
}

void fragment() {
	// dither the impostor out where the LOD0 mesh takes over
	float dn = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (dn >= smoothstep(lod_r - lod_band, lod_r, v_od)) {
		discard;
	}
	float species = floor(floor(v_cust.g + 0.5) / variant_n);
	vec2 cell = vec2(v_yaw_col, species);
	vec2 uv = clamp(UV, vec2(0.004), vec2(0.996));
	vec2 auv = (cell + uv) / atlas_grid;
	vec4 a = texture(atlas_albedo, auv);
	vec4 nm = texture(atlas_normal, auv);
	// leaf cover thins in the mips: grow it with distance so far forests keep their density
	ALPHA = clamp(a.a * (1.3 + v_dist / 900.0), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 tn = nm.xyz * 2.0 - 1.0;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(v_t * tn.x + up * tn.y + v_nq * tn.z * (FRONT_FACING ? 1.0 : -1.0));
	float leafy = clamp((a.g - a.r) * 14.0, 0.0, 1.0);  // tint and shade the foliage, not bark
	vec3 col = mix(a.rgb, tree_tint(a.rgb, v_cust.r, v_cust.b), leafy);
	float under = clamp(-tn.y, 0.0, 1.0);
	float low_crown = smoothstep(0.22, 0.78, UV.y);  // UV.y is 0 at the crown, 1 at the trunk base
	col *= 1.0 - leafy * (0.22 * under + 0.12 * low_crown);
	col *= mix(1.0, 0.8, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = mix(0.9, 0.55, wetness);
	SPECULAR = mix(0.05, 0.25, wetness) * (1.0 - haze);
	BACKLIGHT = col * 0.45;
}
