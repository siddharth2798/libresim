// Night window lighting for building.gdshader (included after hash / vnoise).
// Real Indian city at night: roughly 15-35 % of windows lit, varying a lot per building (some almost dark,
// offices mostly dark, homes warmer) and per floor, lit windows in clusters (a flat, a family on one floor)
// rather than salt-and-pepper; light colours from warm tungsten / sodium-ish through warm and cool LED to
// TV blue; curtains soften and tint many of them. Windows switch on progressively with dusk.
// Far away (a window under ~3 px) each facade becomes its expected average glow: no squares, no moire.

const float WIN_EMIT = 0.42;      // emission of a fully lit, uncurtained window (linear)
const float WIN_OCC_HOME = 0.24;  // mean lit fraction of a residential building
const float WIN_OCC_OFFICE = 0.12;  // towers / offices at night
const float WIN_DARK = 0.14;      // share of buildings that are almost dark (empty, under construction)

// integer hash (stable for large world coordinates, unlike sin-based hashes at 1e4+)
float ihash3(ivec3 p) {
	uvec3 v = uvec3(p) * 1664525u + 1013904223u;
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	v ^= v >> uvec3(16u);
	v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
	return float(v.x >> 8u) * (1.0 / 16777216.0);
}

// lamp colour for a window: mostly warm at home, cool white in offices, a few TV-blue rooms
vec3 win_lamp(float r, bool office) {
	if (office) {
		return r < 0.75 ? vec3(0.80, 0.88, 1.0) : vec3(1.0, 0.86, 0.66);
	}
	if (r < 0.40) return vec3(1.0, 0.60, 0.30);   // tungsten / warm CFL
	if (r < 0.74) return vec3(1.0, 0.78, 0.52);   // warm white LED
	if (r < 0.92) return vec3(0.86, 0.90, 1.0);   // cool white tube light
	return vec3(0.42, 0.55, 1.0) * 0.7;           // TV-lit room
}

// Mean lit fraction of building `id` at this night level (0 when it is day).
float win_occupancy(float id, bool office, float nl) {
	float r = fract(id * 7.31 + 0.17);
	float occ = (office ? WIN_OCC_OFFICE : WIN_OCC_HOME) * mix(0.35, 1.65, r);
	occ *= step(WIN_DARK, fract(id * 13.7 + 0.41)) * 0.9 + 0.1;  // nearly dark buildings
	return occ * smoothstep(0.0, 0.8, nl);  // more windows come on as dusk deepens
}

// Far facades: windows are sub-pixel, so lit windows become sparse points (one candidate per block of 4 x 3
// window cells), at least ~1 px wide and energy-conserving (dimmer as they grow), so the city reads as a carpet
// of points; once a block is under ~2 px the points give way to their average. pm: facade metres (along, up),
// aa: pixel footprint (m). Returns the glow with the same mean as the near window pattern (times FAR_BOOST).
const float FAR_BOOST = 1.6;  // bright points bloom in the eye: a far facade reads brighter than its mean
vec3 far_points(float id, vec2 pm, vec2 csize, float aa, vec3 far_glow, float occ, bool office) {
	vec2 bs = csize * vec2(4.0, 3.0);
	vec3 avg = far_glow * FAR_BOOST;
	float avg_k = smoothstep(0.3, 0.6, aa / min(bs.x, bs.y));
	if (avg_k >= 1.0) {
		return avg;
	}
	int bid = int(id * 65521.0);
	ivec2 b = ivec2(floor(pm / bs));
	float p = clamp(occ * 3.0, 0.05, 0.9);  // share of blocks showing a point
	vec3 pts = vec3(0.0);
	if (ihash3(ivec3(b, bid + 17)) < p) {
		const float R0 = 0.9;  // m, a window
		vec2 lp = (vec2(b) + 0.2 + 0.6 * vec2(ihash3(ivec3(b, bid + 5)), ihash3(ivec3(b, bid + 9)))) * bs;
		float r = max(R0, aa * 0.75);
		float d = length(pm - lp) / r;
		float disc = max(1.0 - d * d, 0.0);
		// peak so that the block mean equals the average glow: mean = p * I0 * (pi R0^2 / 2) / block area
		float lum = dot(avg, vec3(0.333));
		float i0 = lum * bs.x * bs.y / (p * 1.5708 * R0 * R0);
		float r1 = ihash3(ivec3(b, bid + 23));
		pts = win_lamp(r1, office) * disc * i0 * mix(0.5, 1.5, fract(r1 * 7.3)) * (R0 * R0) / (r * r);
	}
	return mix(pts, avg, avg_k);
}

// Emission of the facade at a window cell. cell: (column, floor) cell coords, f: fract(cell), wmask: 0..1 window
// opening, cov: window area fraction of a cell, detail: 1 near .. 0 far (from the cell pixel footprint),
// csize: cell size (m), fw: fwidth(cell).
vec3 window_glow(float id, vec2 cell, vec2 f, float wmask, float cov, float detail, bool office, float nl, vec2 csize, vec2 fw) {
	if (nl <= 0.0) {
		return vec3(0.0);
	}
	float occ = win_occupancy(id, office, nl);
	// expected average: what a facade far away shows (same mean as the per-window pattern)
	vec3 avg = (office ? vec3(0.84, 0.88, 0.96) : vec3(0.95, 0.74, 0.52)) * 0.6;
	vec3 far_glow = avg * occ * cov * WIN_EMIT;
	// lit windows only resolve while a cell spans a few pixels (detail from the window footprint)
	float k = smoothstep(0.35, 0.85, detail);
	vec3 fp = k < 1.0 ? far_points(id, cell * csize, csize, max(fw.x * csize.x, fw.y * csize.y), far_glow, occ, office) : vec3(0.0);
	if (k <= 0.0) {
		return fp;
	}
	int bid = int(id * 65521.0);
	ivec2 c = ivec2(floor(cell));
	// clustering: floors and runs of neighbouring windows share a bias
	float floor_b = ihash3(ivec3(bid, c.y, 3));
	float run = ihash3(ivec3(bid, c.y, int(floor(cell.x / 3.0)) + 101));
	float bias = mix(0.2, 1.8, floor_b) * mix(0.4, 1.6, run);
	float p = clamp(occ * bias, 0.0, 0.92);
	float on = step(ihash3(ivec3(c.x, c.y, bid)), p);
	float r1 = ihash3(ivec3(c.x + 7, c.y, bid));
	float r2 = ihash3(ivec3(c.x, c.y + 11, bid));
	vec3 lamp = win_lamp(r1, office);
	// curtains: about half the lit windows glow dimmer through fabric (warmer, softer)
	float curtain = step(0.5, r2);
	lamp = mix(lamp, lamp * vec3(1.0, 0.82, 0.62) * 0.45, curtain);
	float bright = mix(0.45, 1.0, fract(r1 * 9.7 + r2 * 3.1));
	// soft interior falloff: brighter towards the ceiling lamp, darker at the sill and frame
	float inner = mix(0.7, 1.0, smoothstep(0.1, 0.9, f.y));
	vec3 near_glow = lamp * on * bright * inner * wmask * WIN_EMIT;
	return mix(fp, near_glow, k);
}
