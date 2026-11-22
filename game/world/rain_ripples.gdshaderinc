// Rain ripples on wet pavement and puddles (graphics Phase 3): rings that open and fade where drops land, drawn as a
// normal tweak only (no texture, no extra pass). Near the camera only (RR_FAR) and only while it rains: one uniform
// branch on `precip` skips it all when dry, so every preset (Low included) can afford it. A grid of RR_CELL cells,
// one drop ring per cell per cycle; a ring never leaves its cell's 2 x 2 neighbourhood, so each pixel reads 4 cells.
// world/rain_splash.gd adds the splash flecks above these rings.
// Needs `global uniform float precip;` declared before the include. rr_grad(p, t, dist, aa): p a horizontal world
// position (m, any right-handed frame), aa its size of a pixel (m); returns the slope (d/dx, d/dy) in that frame.

const float RR_FAR = 45.0;  // m from the camera
const float RR_CELL = 0.6;  // m

vec2 rr_hash(vec2 p) {  // sin-free (exact on mobile GPUs); cells wrap every 1024 so the inputs stay small
	vec3 p3 = fract(vec3(mod(p, 1024.0).xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

vec2 rr_grad(vec2 p, float t, float dist, float aa) {
	if (precip < 0.01 || dist > RR_FAR) {
		return vec2(0.0);
	}
	float fade = (1.0 - smoothstep(RR_FAR * 0.5, RR_FAR, dist)) * (1.0 - smoothstep(0.02, 0.06, aa));  // no shimmer
	if (fade <= 0.0) {
		return vec2(0.0);
	}
	vec2 g = p / RR_CELL;
	vec2 gi = floor(g);
	vec2 side = step(0.5, fract(g)) * 2.0 - 1.0;  // the neighbours on this pixel's side of the cell
	vec2 d = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 c = gi + vec2(float(i & 1), float(i >> 1)) * side;
		vec2 h = rr_hash(c);
		vec2 h2 = rr_hash(c + 19.19);
		if (h2.y > 0.15 + 0.85 * precip) {
			continue;  // lighter rain: fewer drops
		}
		float age = fract(t * (0.8 + 0.5 * h2.x) + h.x);  // each ring lives about a second
		vec2 v = g - (c + 0.25 + 0.5 * h);
		float r = length(v);
		float w = (r - age * 0.45) * 30.0;  // ring front opening to 0.45 cell
		float amp = (1.0 - age) * (1.0 - age) * exp(-w * w * 0.15);
		d += v / max(r, 1e-3) * cos(w) * amp;
	}
	return d * 0.6 * fade * min(precip * 2.0, 1.0);
}

// The ripple normal offset in the render frame (x east, y up, z south) for p in ENU metres (east, north).
vec3 rr_enu(vec2 p, float t, float dist, float aa) {
	vec2 g = rr_grad(p, t, dist, aa);
	return vec3(g.x, 0.0, -g.y);
}
