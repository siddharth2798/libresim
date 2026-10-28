shader_type spatial;
// Soft contact shadow under the follow-me car: a rounded-box falloff plus four darker patches under
// the tyres, on a plane just above the taxiway. Fades with distance and in haze.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float haze_density;

uniform vec2 quad_half = vec2(1.7, 3.5);   // metres, half size of the plane
uniform vec2 body_half = vec2(0.92, 2.45); // metres, half size of the footprint
uniform float strength = 0.55;

varying float v_dist;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float box_sd(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * quad_half;
	float body = 1.0 - smoothstep(-0.15, 1.0, box_sd(p, body_half, 0.4));
	float wheels = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 c = vec2(i % 2 == 0 ? -0.80 : 0.80, i < 2 ? -1.55 : 1.45);
		vec2 d = (p - c) / vec2(0.2, 0.42);
		wheels = max(wheels, exp(-dot(d, d)));
	}
	float a = clamp(body * 0.55 + wheels * 0.75, 0.0, 1.0) * strength;
	a *= 1.0 - smoothstep(60.0, 140.0, v_dist);
	a *= exp(-v_dist * haze_density * 2.0);
	ALBEDO = vec3(0.0);
	ALPHA = a;
}
