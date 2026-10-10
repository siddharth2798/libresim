shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, fog_disabled, blend_mix;
// Soft cumulus puff impostor: camera-facing quad with procedural noise alpha.
// Per-instance: INSTANCE_CUSTOM.x = seed, .y = brightness (base darker).

global uniform vec3 fog_color;
global uniform float haze_density;
uniform vec3 sun_color : source_color = vec3(1.0, 0.98, 0.95);
uniform float daylight = 1.0;

varying float v_seed;
varying float v_shade;
varying float v_dist;

void vertex() {
	// spherical billboard: keep the instance's scale, face the camera
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= scale;
	v_seed = INSTANCE_CUSTOM.x;
	v_shade = INSTANCE_CUSTOM.y;
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float n = fbm(UV * 3.0 + v_seed * 17.0);
	float a = smoothstep(1.0, 0.35, r + (n - 0.5) * 0.7);
	// flat-ish bottoms: fade the lower part less, darken it
	float base = smoothstep(-0.2, -0.9, uv.y);
	vec3 col = mix(vec3(1.0), vec3(0.72, 0.74, 0.78), base * 0.7 + (1.0 - n) * 0.25) * v_shade;
	col *= mix(vec3(0.12, 0.13, 0.17), sun_color, daylight);
	float haze = 1.0 - exp(-v_dist * haze_density * 0.8);
	ALBEDO = mix(col, fog_color, haze);
	ALPHA = a * 0.92 * (1.0 - haze * 0.6);
}
