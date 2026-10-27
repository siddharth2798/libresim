shader_type spatial;
render_mode cull_disabled, fog_disabled, alpha_to_coverage_and_one;
// Tree impostor on two crossed quads (origin at the trunk base, unit size scaled to the tree).
// The sprite comes from the atlas TreeAtlas bakes at startup (albedo + cover, normal), picked by
// INSTANCE_CUSTOM: r = tint, g = species * 4 + variant, b = tint 2 (yellower), a = seed. The sprite
// normal is lit by the sun and sky like any surface (lit side, shade side, backlit leaves), edges
// are soft (alpha to coverage under MSAA). Trees closer than lod_r are drawn as meshes by TreeLod:
// this impostor dithers away over lod_band metres, the mesh dithers in with the opposite pattern.

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;

uniform sampler2D atlas_albedo : filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_normal : filter_linear_mipmap, repeat_disable;
uniform float lod_r = 0.0;
uniform float lod_band = 8.0;

varying vec4 v_cust;
varying float v_dist;
varying float v_od;
varying vec3 v_t;
varying vec3 v_nq;

void vertex() {
	v_cust = INSTANCE_CUSTOM;
	// gentle wind sway, more at the top (palms more than the rest)
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float palm = step(3.5, INSTANCE_CUSTOM.g) * step(INSTANCE_CUSTOM.g, 7.5);
	float sway = sin(TIME * 1.3 + wp.x * 0.05 + wp.z * 0.07) * (0.025 + 0.02 * palm) * UV.y;
	VERTEX.x += sway * (1.0 - UV.y);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_od = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	v_t = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
	v_nq = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// dither the impostor out where the LOD0 mesh takes over
	float dn = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (dn >= smoothstep(lod_r - lod_band, lod_r, v_od)) {
		discard;
	}
	float idx = floor(v_cust.g + 0.5);
	vec2 cell = vec2(mod(idx, 4.0), floor(idx / 4.0));
	bool flip = v_cust.a > 0.5;
	vec2 uv = vec2(flip ? 1.0 - UV.x : UV.x, UV.y);
	vec2 auv = (cell + clamp(uv, vec2(0.004), vec2(0.996))) * 0.25;
	vec4 a = texture(atlas_albedo, auv);
	vec4 nm = texture(atlas_normal, auv);
	// leaf cover thins in the mips: grow it with distance so far forests keep their density
	ALPHA = clamp(a.a * (1.3 + v_dist / 900.0), 0.0, 1.0);
	vec3 tn = nm.xyz * 2.0 - 1.0;
	tn.x = flip ? -tn.x : tn.x;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(v_t * tn.x + up * tn.y + v_nq * tn.z * (FRONT_FACING ? 1.0 : -1.0));
	vec3 tint = mix(vec3(0.75 + v_cust.r * 0.6), vec3(1.0, 0.95, 0.55) * (0.8 + v_cust.r * 0.5), v_cust.b * 0.5);
	float leafy = clamp((a.g - a.r) * 14.0, 0.0, 1.0);  // tint the foliage, not bark
	vec3 col = a.rgb * mix(vec3(1.0), tint, leafy);
	col *= mix(1.0, 0.8, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = fog_color * haze;
	ROUGHNESS = mix(0.9, 0.55, wetness);
	SPECULAR = mix(0.05, 0.25, wetness) * (1.0 - haze);
	BACKLIGHT = col * 0.45;
}
