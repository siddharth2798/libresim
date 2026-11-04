shader_type spatial;
// Ground decal of a procedural vehicle (world/vehicle_ground.gd): a soft contact shadow under the body,
// darker blobs under the tyres, and at night the pool of light in front of a working vehicle's
// headlamps. Premultiplied blend: shadow darkens (alpha), the light pool adds (albedo).
// Per quad: UV = metres from the quad centre (y forward), UV2 = half size of the shape, COLOR.r = shape
// (0 body, 0.5 tyre, 1 light pool), COLOR.g = strength.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float haze_density;
global uniform float night_level;

instance uniform float lamps = 0.0;

varying float v_dist;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float box_sd(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV;
	vec2 h = UV2;
	float shape = COLOR.r;
	float k = COLOR.g;
	float fade = exp(-v_dist * haze_density * 2.0);
	vec3 light = vec3(0.0);
	float a = 0.0;
	if (shape < 0.25) {
		float m = min(h.x, h.y) * 0.5;
		a = (1.0 - smoothstep(-m, 0.35, box_sd(p, h - vec2(0.15), 0.3))) * k;
		a *= 1.0 - smoothstep(70.0, 160.0, v_dist);
	} else if (shape < 0.75) {
		vec2 d = p / h;
		a = exp(-dot(d, d) * 2.2) * k;
		a *= 1.0 - smoothstep(50.0, 120.0, v_dist);
	} else {
		// y: 0 at the lamps .. h.y ahead; the beam widens and fades with distance
		float t = clamp(p.y / h.y, 0.0, 1.0);
		float w = mix(0.35, 1.0, t) * h.x;
		float across = exp(-pow(p.x / w, 2.0) * 2.5);
		float along = smoothstep(0.0, 0.12, t) * pow(1.0 - t, 1.6);
		light = vec3(1.0, 0.9, 0.72) * across * along * k * lamps * night_level * (p.y > 0.0 ? 1.0 : 0.0);
		light *= 1.0 - smoothstep(250.0, 450.0, v_dist);
	}
	ALBEDO = light * fade;
	ALPHA = a * fade;
}
