// Shore look for terrain.gdshader's water branch. sd_tex (tools/21_shore.py, same source tile and uv as the
// land-class mask): R = 128 + signed distance to the shore in metres (positive over water), G = openness
// (how far open water reaches: open sea 1, lakes and narrow backwaters low).

uniform sampler2D sd_tex : filter_linear, repeat_disable;

// Foam coverage 0..1 at shore distance d (m, > 0 on the water side): a swash line at the waterline and
// soft wave fronts running shoreward on open water. Fades out with distance so it never shimmers.
float shore_foam(float d, float open, vec2 en, float dist, float t) {
	float k = 1.0 - smoothstep(2500.0, 6000.0, dist);
	if (k <= 0.0 || d > 120.0) { return 0.0; }
	float n = vnoise(en * 0.09 + vec2(t * 0.03, 0.0)) * 0.6 + vnoise(en * 0.45 - vec2(0.0, t * 0.08)) * 0.4;
	float dw = d + (n - 0.5) * 7.0;
	float surf = smoothstep(0.2, 0.55, open);  // calm backwaters get only a thin swash line
	k *= smoothstep(0.22, 0.4, open);           // rivers, creeks and ponds: no foam at all
	float swash = (1.0 - smoothstep(0.2, 4.0 + 5.0 * n + 10.0 * surf, dw)) * (0.5 + 0.5 * surf);
	float ph = fract(dw / 22.0 + t * 0.08 + n * 0.25);  // fronts travel towards the shore
	float front = smoothstep(0.0, 0.05, ph) * (1.0 - smoothstep(0.05, 0.5, ph));
	float gate = smoothstep(0.3, 0.55, vnoise(en * vec2(0.035, 0.05) + 3.7 + vec2(t * 0.02, 0.0)));
	float lines = front * gate * (1.0 - smoothstep(25.0, 110.0, d)) * (0.55 + 0.45 * surf);
	return clamp(swash + lines, 0.0, 1.0) * k;
}
