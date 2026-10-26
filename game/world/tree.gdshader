shader_type spatial;
render_mode cull_disabled, fog_disabled;
// Tree impostor on two crossed quads (origin at the trunk base, unit size).
// INSTANCE_CUSTOM: r,g,b colour variation, a = shape seed. Canopy is drawn
// procedurally (alpha scissor) with a fake spherical normal for soft lighting.

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;

varying vec3 v_tint;
varying float v_seed;
varying float v_dist;

void vertex() {
	v_tint = INSTANCE_CUSTOM.rgb;
	v_seed = INSTANCE_CUSTOM.a;
	// gentle wind sway, more at the top
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.3 + wp.x * 0.05 + wp.z * 0.07) * 0.025 * UV.y;
	VERTEX.x += sway * (1.0 - UV.y);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);  // x -1..1, y 0 (ground) .. 1 (top)
	float n = vnoise(UV * 9.0 + v_seed * 31.0) * 0.5 + vnoise(UV * 23.0 + v_seed * 7.0) * 0.25;
	// canopy: blob between y=0.28 and 1.0; trunk: thin strip below
	vec2 c = (p - vec2(0.0, 0.64)) / vec2(0.95, 0.38);
	float canopy = 1.0 - length(c) + (n - 0.35) * 0.6;
	float trunk = step(abs(p.x), 0.07) * step(p.y, 0.4);
	if (canopy < 0.0 && trunk < 0.5) {
		discard;
	}
	vec3 leaf = vec3(0.12, 0.22, 0.08) * (0.75 + v_tint * 0.6) * (0.7 + n * 0.6);
	vec3 bark = vec3(0.18, 0.13, 0.09);
	leaf *= mix(0.55, 1.1, smoothstep(0.25, 1.0, p.y));  // darker under the crown, lighter on top
	vec3 col = canopy >= 0.0 ? leaf : bark;
	// fake round normal for the canopy (view space)
	vec3 nrm = normalize(vec3(c.x, c.y * 0.8 + 0.4, 0.6));
	NORMAL = canopy >= 0.0 ? normalize(mix(NORMAL, (VIEW_MATRIX * vec4(nrm.x, nrm.y, nrm.z, 0.0)).xyz, 0.6)) : NORMAL;
	col *= mix(1.0, 0.8, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = fog_color * haze;
	ROUGHNESS = mix(0.9, 0.55, wetness);
	SPECULAR = mix(0.05, 0.25, wetness) * (1.0 - haze);
	BACKLIGHT = vec3(0.15, 0.2, 0.05);
}
