// Runway wear for runway_v2.gdshader: rubber in each touchdown zone (tyre streaks over a broad stain, heaviest just
// past the aiming point, in the two main-gear bands), wheel tracks the whole length, the broken oil / fuel drip line
// along the centre, paint scuffed in the wheel tracks and grimy elsewhere, and the pilot's own touchdown marks.
// Streaks: lanes RW_LANE wide across (gently wandering), cells RW_CELL long; a cell may start one streak 5-30 m long
// that begins abruptly (tyre spin-up) and tapers, slightly yawed. Far away (pixel wider than a streak) the streaks
// fade into their expected darkness, so nothing shimmers. Needs rw_* helpers, aim (runway_marks), seed, gear_hw.

uniform vec2 rubber = vec2(1.0, 0.7);  // rubber build-up landing over ends[0] / ends[1], 0..1
uniform vec4 marks[32];   // own touchdowns: along (m from ends[0]), across (m), yaw (rad, 0 = toward ends[1]),
                          // w = half-track in decimetres (integer part) + strength 0..0.99 (fraction)
uniform int mark_count = 0;

const vec3 RW_RUBBER = vec3(0.012, 0.0115, 0.011);
const vec3 RW_OIL = vec3(0.03, 0.026, 0.022);
const float RW_LANE = 0.45, RW_CELL = 6.0;  // streak lanes across, cells along (one streak start each at most)

// rubber along the runway (s from the threshold): from ~0.4 x the aiming distance, peak just past it, tail ~650 m on
float rw_rub_profile(float s) {
	float a = aim.x;
	float rise = smoothstep(a * 0.38, a * 0.9, s);
	float fall = 1.0 - smoothstep(a + 220.0, a + 620.0, s);
	return rise * fall * (0.55 + 0.45 * rw_g((s - a - 70.0) / 170.0));
}

// the two main-gear bands across (narrow- and wide-body tracks and their lateral scatter)
float rw_rub_band(float x, float widen) {
	return rw_g((abs(x) - gear_hw) / ((0.33 * gear_hw + 1.3) * widen));
}

// Streaks crossing (s, x): this lane and the nearer neighbour, cells up to 4 x RW_CELL back (streaks are at most 24 m).
// p: the spawn probability at s (amount x along-profile; the band across is per lane).
float rw_streaks(float s, float x, float p, float hx) {
	float warp = sin(s * 0.011 + seed) * 0.5 + sin(s * 0.047 + seed * 1.7) * 0.18;  // lanes wander gently
	float xw = x + warp;
	float j0 = floor(xw / RW_LANE);
	float jn = j0 + (fract(xw / RW_LANE) < 0.5 ? -1.0 : 1.0);
	float i0 = floor(s / RW_CELL);
	float acc = 0.0;
	float tread = 1.0 - smoothstep(0.004, 0.015, hx);
	int lanes = runway_detail >= 3 ? 2 : 1;  // High: this lane only (its streaks are kept inside it)
	for (int k = 0; k < lanes; k++) {
		float j = k == 0 ? j0 : jn;
		float lane_c = (j + 0.5) * RW_LANE;
		float pj = rw_rub_band(lane_c - warp, 1.0) * p;
		if (pj < 0.02) {
			continue;
		}
		for (int di = 0; di < 4; di++) {
			float i = i0 - float(di);
			vec2 id = vec2(i, j) + seed;
			float h0 = rw_hash(id);
			if (h0 > pj) {
				continue;
			}
			float h1 = fract(h0 * 37.13 + 0.31), h2 = fract(h0 * 91.71 + 0.57), h3 = fract(h0 * 53.37 + 0.19);
			float ds = s - (i + h3) * RW_CELL;
			float len = 5.0 + 19.0 * h1 * h1;
			if (ds < 0.0 || ds > len) {
				continue;
			}
			float c = lane_c + (h2 - 0.5) * 0.2 + (h3 - 0.5) * 0.012 * ds;  // slight yaw (crab)
			float w = 0.05 + 0.12 * h2 * h2;  // half-width: single tyres to smeared dual pairs
			if (lanes == 1) {  // keep it inside its lane, so no other lane needs looking at
				c = clamp(c, lane_c - RW_LANE * 0.5 + w, lane_c + RW_LANE * 0.5 - w);
			}
			float t = ds / len;
			float a = (0.55 + 0.45 * h1) * smoothstep(0.0, 0.35, ds) * (1.0 - t) * (1.0 - 0.3 * t)
				* (0.62 + 0.38 * sin(ds * (1.1 + h2) + h1 * 20.0) * sin(ds * 0.23 + h3 * 9.0));  // patchy, not painted
			a *= 1.0 - tread * 0.35 * (0.5 + 0.5 * sin((xw - c) * 70.0 + h3 * 6.0));  // tread grooves up close
			acc += (1.0 - acc) * a * rw_box(xw, c - w, c + w, max(hx, 0.45 * w));  // smeared edges
		}
	}
	return acc;
}

// broad rubber stain under the streaks, 0..1 (baked)
float rw_stain(float s, float x, int end_i) {
	float prof = (end_i == 0 ? rubber.x : rubber.y) * rw_rub_profile(s);
	if (prof < 0.004) {
		return 0.0;
	}
	float mott = rw_noise(vec2(x * 0.45, s * 0.05) + seed) * 0.6 + rw_noise(vec2(x * 1.4, s * 0.3) + seed + 50.0) * 0.4;
	return min(prof * (rw_rub_band(x, 1.4) * (0.68 + 0.32 * mott) + 0.38 * (1.0 - smoothstep(0.0, gear_hw + 4.0, abs(x)))), 0.97);
}

// spawn probability of streak cells at s (0 outside the touchdown-zone window)
float rw_streak_p(float s, int end_i) {
	return (end_i == 0 ? rubber.x : rubber.y) * rw_rub_profile(s) * 2.2;
}

// the streaks' expected opacity (what they average to once a pixel is wider than a streak)
float rw_streak_avg(float p, float x) {
	return 1.0 - exp(-0.65 * p * rw_rub_band(x, 1.0));
}

// rolling wear the whole length: main-gear and nose-wheel tracks (darkening factor)
float rw_tracks(float s, float x) {
	float ax = abs(x);
	float n = 0.6 + 0.4 * rw_noise(vec2(x * 1.5, s * 0.04) + seed);
	return (0.11 * rw_g((ax - gear_hw) / 1.3) + 0.06 * rw_g(x / 0.8)) * n;
}

// oil and fuel drips along the centreline, broken into blotches; heavier where aircraft line up and hold
float rw_oil(float along, float across, float s, float hx, float hs) {
	if (abs(across) > 3.0) {
		return 0.0;
	}
	float off = across - sin(along * 0.009 + seed) * 0.4;
	float g = rw_g(off / 0.75);
	if (g < 0.01) {
		return 0.0;
	}
	float n = rw_noise(vec2(along * 0.45, off * 1.3 + seed)) * 0.65 + rw_noise(vec2(along * 2.2, off * 3.0 + seed)) * 0.35;
	float lod = max(smoothstep(0.08, 0.4, hx), smoothstep(1.0, 5.0, hs));
	float zone = 0.45 + 0.55 * (1.0 - smoothstep(40.0, 350.0, s));
	return mix(smoothstep(0.56, 0.78, n), 0.22, lod) * g * zone * 0.6;
}

// how much paint is left: scuffed in the wheel tracks, worn through on the aggregate (agg: detail luminance, 1 =
// average) and grimy in patches (multiplies paint coverage)
float rw_paint_left(float s, float x, float hx, float hs, float agg) {
	float ax = abs(x);
	float scuff = 0.3 * rw_g((ax - gear_hw) / 1.1) + 0.35 * rw_g(x / 0.55);
	float near = 1.0 - max(smoothstep(0.01, 0.06, hx), smoothstep(0.1, 0.8, hs));
	float pits = 0.12;
	if (near > 0.0) {
		vec2 q = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * vec2(x, s);
		float n = rw_noise(q * 4.3 + seed) * 0.6 + rw_noise(q * 13.0) * 0.4;
		pits = mix(0.12, smoothstep(0.55, 0.8, n + (1.0 - agg) * 0.9), near);
	}
	float grime = rw_noise(vec2(x * 0.35, s * 0.08) + seed * 1.7);
	return clamp(0.95 - scuff * (0.6 + 0.4 * grime) - 0.4 * pits - 0.12 * grime, 0.15, 1.0);
}

// the pilot's own touchdowns: a fresh streak pair per mark
float rw_own_marks(float along, float across, float hx) {
	float acc = 0.0;
	for (int i = 0; i < mark_count && i < 32; i++) {
		vec4 m = marks[i];
		vec2 d = vec2(across - m.y, along - m.x);
		vec2 dir = vec2(sin(m.z), cos(m.z));
		float t = dot(d, dir);
		float strength = fract(m.w);
		float len = 8.0 + 22.0 * strength;
		if (t < 0.0 || t > len) {
			continue;
		}
		float ht = floor(m.w) * 0.1;
		float l = abs(dir.y * d.x - dir.x * d.y);
		float tw = 0.1 + 0.08 * strength;
		float a = (0.5 + 0.5 * strength) * smoothstep(0.0, 0.3, t) * pow(1.0 - t / len, 0.9)
			* (0.7 + 0.3 * rw_noise(vec2(t * 2.0, float(i) * 7.0)));
		acc += (1.0 - acc) * a * rw_box(l, ht - tw, ht + tw, hx);
	}
	return acc;
}
