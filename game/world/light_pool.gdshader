shader_type spatial;
// Fake pool of light on the ground under an apron floodlight mast: an additive warm
// radial gradient on a flat quad (no real light needed for distant masts).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

global uniform float haze_density;

uniform float level = 1.0;
uniform vec3 tint = vec3(1.0, 0.78, 0.5);
uniform float strength = 0.22;

varying float v_trans;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_trans = exp(-length(INV_VIEW_MATRIX[3].xyz - wp) * haze_density * 1.6);
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	float pool = exp(-r2 * 3.5) * (1.0 - smoothstep(0.8, 1.0, r2));
	ALBEDO = tint * pool * strength * level * v_trans;
	ALPHA = 1.0;
}
