// Pavement distress for runway_v2.gdshader, in runway metres (across, along from ends[0]) and the runway's seed, so
// each runway keeps its own pattern: glossy black crack sealant ("tar snakes": wiggly transverse cracks every 5-20 m,
// sealed longitudinal seams between paving lanes, block-crack networks in a few old areas), rectangular patches
// (fresh dark or old light), paving-lane tone, and concrete slabs with sealed joints and spalled corners.
// Sealant and joints are box-filtered lines (fade to their average tone when thinner than a pixel).
// Needs rw_* helpers (runway_surface), width_m, seed, runway_detail.

uniform int surface = 0;              // 0 asphalt, 1 concrete
uniform float concrete_ends_m = 0.0;  // concrete for this many metres past each threshold (0 = none)
uniform float lane_w = 4.5;           // paving lane width (m)

const vec3 RW_SEAL = vec3(0.012, 0.012, 0.013);
const vec2 RW_SLAB = vec2(5.0, 6.25);  // concrete slab (across, along)

// tone of the paving lane under (across, along): lanes laid on different days, re-laid in ~300 m sections
float rw_lane_tone(float across, float along) {
	float k = floor((across + width_m * 0.5) / lane_w);
	float sec = floor(along / 300.0 + rw_hash(vec2(k, seed)));
	return 1.0 + (rw_hash(vec2(k, seed + 1.0)) - 0.5) * 0.08 + (rw_hash(vec2(k, sec) + seed) - 0.5) * 0.05;
}

// lateral offset (m) of a crack line at position u along it: a few sines of hashed phase, smooth bends to jagged
// centimetres (cheaper than noise, and cracks are this kind of sum anyway)
float rw_wiggle(float u, float ph) {
	vec4 p = fract(vec4(ph * 0.137, ph * 0.291, ph * 0.533, ph * 0.719)) * 6.2832;
	return sin(u * 0.23 + p.x) * 0.4 + sin(u * 0.83 + p.y) * 0.2 + sin(u * 3.7 + p.z) * 0.06 + sin(u * 23.0 + p.w) * 0.012;
}

// sealant coverage 0..1
float rw_sealant(float across, float along, float hx, float hs) {
	if (hx > 0.6 || hs > 12.0) {
		return 0.012;  // far: every line is far thinner than a pixel; their average share
	}
	float m = 0.0;
	float hw = 0.045;
	float half_w = width_m * 0.5;
	// transverse cracks: one per ~11 m cell (some cells none), wiggly, full width or across a few lanes
	// (a crack stays within its cell: placed 1.65 m or more from the cell's ends, it wiggles at most 0.7 m)
	{
		float i = floor(along / 11.0);
		float h = rw_hash(vec2(i, seed + 21.0));
		float c = (i + 0.15 + 0.7 * rw_hash(vec2(i, seed + 22.0))) * 11.0
			+ rw_wiggle(across, h * 61.0 + i);
		float xa = -half_w, xb = half_w;
		if (h > 0.35) {  // a partial crack across one to three lanes
			float l0 = floor(rw_hash(vec2(i, seed + 23.0)) * width_m / lane_w);
			xa = l0 * lane_w - half_w;
			xb = min(xa + lane_w * (1.0 + floor(rw_hash(vec2(i, seed + 24.0)) * 3.0)), half_w);
		}
		float wob = 0.7 + 0.3 * sin(across * 2.7 + i * 1.3) + 0.2 * sin(across * 9.1 + i);  // uneven bead
		float span = rw_box(across, xa, xb, hx + 0.2);
		float d = along - c;
		m = max(m, (rw_box(d, -hw * wob, hw * wob, hs + 0.3 * hx) * 0.85 + rw_box(d, -2.6 * hw * wob, 2.6 * hw * wob, hs + 0.3 * hx) * 0.25)
			* span * step(h, 0.78));
	}
	// longitudinal seams between paving lanes, sealed over most of their length
	float kl = floor((across + half_w) / lane_w + 0.5);
	if (kl > 0.5 && kl * lane_w < width_m - 0.5) {
		float xs = kl * lane_w - half_w + sin(along * 0.05 + kl * 3.7 + seed) * 0.08 + sin(along * 0.37 + kl) * 0.03;
		float on = smoothstep(0.5, 0.6, rw_noise(vec2(along * 0.008, kl * 5.0 + seed))) * 0.75;
		m = max(m, rw_box(across, xs - hw * 0.8, xs + hw * 0.8, hx) * on);
	}
	// block cracking (~2.5-3 m blocks) in a few old areas (Ultra and up near the camera; always in the bake)
	if (runway_detail >= 3) {
		float area = smoothstep(0.68, 0.76, rw_noise(vec2(across * 0.035, along * 0.005) + seed * 0.3));
		if (area > 0.0) {
			vec2 p = vec2(across, along);
			p += vec2(rw_wiggle(p.y, 3.0 + floor(p.x / 2.6)), rw_wiggle(p.x, 7.0 + floor(p.y / 3.1))) * 0.6;
			float row = floor(p.y / 3.1);
			p.x += rw_hash(vec2(row, seed)) * 2.6;
			vec2 f = abs(fract(p / vec2(2.6, 3.1)) - 0.5) * vec2(2.6, 3.1);
			vec2 e = vec2(1.3, 1.55) - f;  // metres to the block's edges
			float line = max(rw_box(e.x, -0.03, 0.03, hx * 1.4), rw_box(e.y, -0.03, 0.03, hs * 1.4));
			m = max(m, area * line);
		}
	}
	return m;
}

// patches: colour factor (1 = none); border: the sealed outline's coverage
float rw_patch(float across, float along, float hx, float hs, out float border) {
	border = 0.0;
	float k = floor((across + width_m * 0.5) / lane_w);
	float i = floor(along / 55.0);
	vec2 id = vec2(k, i) + seed * 3.0;
	if (rw_hash(id) > 0.1) {
		return 1.0;
	}
	float len = 3.0 + 12.0 * rw_hash(id + 1.0);
	float s0 = i * 55.0 + rw_hash(id + 2.0) * (55.0 - len);
	float wid = mix(1.8, lane_w - 0.2, rw_hash(id + 3.0));
	float x0 = k * lane_w - width_m * 0.5 + rw_hash(id + 4.0) * (lane_w - wid);
	float cov = rw_box(across, x0, x0 + wid, hx) * rw_box(along, s0, s0 + len, hs);
	if (cov <= 0.0) {
		return 1.0;
	}
	float bw = 0.05;
	border = cov - rw_box(across, x0 + bw, x0 + wid - bw, hx) * rw_box(along, s0 + bw, s0 + len - bw, hs);
	float f = rw_hash(id + 5.0);
	return mix(1.0, f < 0.45 ? 0.62 + 0.15 * f : 1.15 + 0.15 * f, cov);
}

// concrete slabs: colour factor; joint: sealed joint coverage
float rw_slabs(float across, float along, float hx, float hs, out float joint) {
	vec2 q = vec2(across + width_m * 0.5, along);
	vec2 c = floor(q / RW_SLAB);
	vec2 f = q - c * RW_SLAB;
	float jw = 0.025;
	joint = max(rw_box(f.x, -jw, jw, hx) + rw_box(f.x, RW_SLAB.x - jw, RW_SLAB.x + jw, hx),
		rw_box(f.y, -jw, jw, hs) + rw_box(f.y, RW_SLAB.y - jw, RW_SLAB.y + jw, hs));
	float h = rw_hash(c + seed), h2 = rw_hash(c + seed + 4.0);
	float tone = 1.0 + (h - 0.5) * 0.1 + (h2 > 0.94 ? 0.08 : 0.0) - (h2 < 0.05 ? 0.08 : 0.0);
	// spalled corner: a small dark chip at one slab corner in a few slabs
	if (rw_hash(c + seed + 8.0) < 0.12) {
		vec2 corner = vec2(step(0.5, rw_hash(c + 1.0)), step(0.5, rw_hash(c + 2.0))) * RW_SLAB;
		float d = length((f - corner) * vec2(1.0, 1.3)) + (rw_noise(f * 6.0) - 0.5) * 0.12;
		tone *= 1.0 - 0.45 * rw_box(d, -1.0, 0.25, max(hx, 0.02));
	}
	// a diagonal crack in a few slabs
	if (rw_hash(c + seed + 9.0) < 0.06) {
		float d = abs(dot(f / RW_SLAB - 0.5, normalize(vec2(1.0, -0.8))) + (rw_noise(f * 1.5) - 0.5) * 0.06);
		joint = max(joint, rw_box(d * RW_SLAB.x, -0.02, 0.02, hx));
	}
	return tone;
}
