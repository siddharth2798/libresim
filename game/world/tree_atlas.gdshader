shader_type canvas_item;
render_mode blend_disabled;
// Impostor atlas of the tree billboards, drawn once at startup by TreeAtlas (nothing here runs per
// frame). 4 columns (variants) x 4 rows (species: broadleaf, palm, acacia, slim). Each sprite is a
// lit 2.5D drawing: crown lumps with ragged outlines and leaf mottling, a trunk behind them, palm
// fronds as combs along curves. pass_id 0 writes linear albedo (with baked occlusion), 1 writes the
// normal (sprite space, xy = right / up, z = towards the viewer) packed to 0..1; alpha is the cover.

uniform int pass_id = 0;

const float AR[4] = float[4](0.70, 0.66, 1.35, 0.27);  // width / height, as TreeSpecies.ASPECT

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

vec3 leaf_colour(int sp) {
	if (sp == 0) return vec3(0.11, 0.21, 0.07);
	if (sp == 1) return vec3(0.15, 0.25, 0.06);
	if (sp == 2) return vec3(0.17, 0.22, 0.08);
	return vec3(0.09, 0.17, 0.09);
}

// Crown of lumps (species 0, 2, 3). Returns coverage; alb / nrm for the front-most lump.
float crown(int sp, int var, vec2 P, float W, out vec3 alb, out vec3 nrm) {
	int n = sp == 0 ? 9 : (sp == 2 ? 7 : 6);
	vec2 c0 = sp == 2 ? vec2(0.0, 0.62) : (sp == 3 ? vec2(0.0, 0.55) : vec2(0.0, 0.64));
	vec2 spread = sp == 2 ? vec2(0.45 * W, 0.05) : (sp == 3 ? vec2(0.15 * W, 0.25) : vec2(0.34 * W, 0.14));
	vec2 rad = sp == 2 ? vec2(0.35 * W, 0.075) : (sp == 3 ? vec2(0.6 * W, 0.14) : vec2(0.48 * W, 0.19));
	float best = -10.0;
	float cover = 0.0;
	alb = leaf_colour(sp);
	nrm = vec3(0.0, 0.0, 1.0);
	for (int k = 0; k < n; k++) {
		vec2 s = vec2(float(k) * 1.37 + float(var) * 5.1, float(sp) * 9.0 + float(var));
		float h1 = hash(s), h2 = hash(s + 17.3), h3 = hash(s + 41.9);
		vec2 c = k == 0 ? c0 : c0 + spread * vec2(h1 * 2.0 - 1.0, h2 * 2.0 - 1.0);
		vec2 r = rad * (k == 0 ? 1.25 : 0.75 + 0.5 * h3);
		vec2 q = (P - c) / r;
		float d = length(q) + (noise(P * 38.0 + s) - 0.5) * 0.5 + (noise(P * 95.0 + s) - 0.5) * 0.18;
		float a = 1.0 - smoothstep(0.86, 1.0, d);
		if (a <= 0.0) continue;
		float z = sqrt(max(1.0 - dot(q, q), 0.0));
		float depth = (h3 - 0.5) * 0.3 + z * 0.25;
		cover = max(cover, a);
		if (depth > best) {
			best = depth;
			nrm = normalize(vec3(q.x / r.x, q.y / r.y, z / (0.5 * (r.x + r.y))));
			float mottle = 0.62 + 0.75 * noise(P * 85.0 + s) * noise(P * 31.0 + s * 2.0);
			float ao = mix(0.5, 1.0, smoothstep(0.30, 0.90, P.y)) * (0.78 + 0.22 * smoothstep(-0.1, 0.1, depth)) * mix(0.8, 1.0, z);
			alb = leaf_colour(sp) * (0.8 + 0.4 * h1) * mottle * ao;
		}
	}
	return cover;
}

// Trunk (species 0, 2, 3): a tapered strip, forked into two limbs for the acacia.
float trunk(int sp, vec2 P, float var, out vec3 alb, out vec3 nrm) {
	float x0 = (hash(vec2(var, 3.0)) - 0.5) * 0.02;
	float top = sp == 2 ? 0.42 : (sp == 3 ? 0.35 : 0.5);
	float hw = (sp == 3 ? 0.011 : 0.017) * (1.0 + 0.9 * smoothstep(0.1, 0.0, P.y));
	float dx = P.x - x0;
	float cov = (1.0 - smoothstep(hw * 0.8, hw, abs(dx))) * step(0.0, P.y) * step(P.y, top);
	if (sp == 2) {
		for (int k = 0; k < 2; k++) {
			float sgn = k == 0 ? -1.0 : 1.0;
			float t = clamp((P.y - top) / 0.18, 0.0, 1.0);
			float lx = x0 + sgn * 0.2 * t * t;
			float lc = (1.0 - smoothstep(0.012, 0.016, abs(P.x - lx))) * step(top, P.y) * step(P.y, top + 0.18);
			cov = max(cov, lc);
		}
	}
	float c = clamp(dx / hw, -1.0, 1.0);
	nrm = normalize(vec3(c, 0.0, sqrt(max(1.0 - c * c, 0.0))));
	alb = vec3(0.17, 0.12, 0.08) * (0.7 + 0.5 * noise(vec2(P.x * 120.0, P.y * 14.0))) * (0.6 + 0.4 * (c * 0.5 + 0.5));
	return cov;
}

float palm(int var, vec2 P, float W, out vec3 alb, out vec3 nrm) {
	vec2 C = vec2(0.025, 0.86);
	float cover = 0.0;
	alb = vec3(0.14, 0.24, 0.05);
	nrm = vec3(0.0, 0.0, 1.0);
	// trunk: slight curve, flared foot, scar rings
	float ty = clamp(P.y / C.y, 0.0, 1.0);
	float tx = C.x * pow(ty, 1.5) + (hash(vec2(float(var), 7.0)) - 0.5) * 0.02 * ty;
	float hw = mix(0.016, 0.0095, ty) + 0.012 * smoothstep(0.08, 0.0, P.y);
	float tc = (1.0 - smoothstep(hw * 0.75, hw, abs(P.x - tx))) * step(0.0, P.y) * step(P.y, C.y);
	float rings = 0.75 + 0.25 * smoothstep(0.3, 0.7, abs(fract(P.y * 36.0) - 0.5) * 2.0);
	float cc = clamp((P.x - tx) / hw, -1.0, 1.0);
	vec3 tn = normalize(vec3(cc, 0.0, sqrt(max(1.0 - cc * cc, 0.0))));
	vec3 ta = vec3(0.12, 0.10, 0.075) * rings * (0.7 + 0.5 * noise(vec2(P.x * 90.0, P.y * 20.0)));
	// fronds: combs along drooping curves, front ones lighter
	float fcov = 0.0;
	vec3 fn = vec3(0.0, 0.5, 0.8);
	float fshade = 1.0;
	for (int k = 0; k < 12; k++) {
		float h1 = hash(vec2(float(k) * 3.7 + float(var) * 9.1, 5.0));
		float h2 = hash(vec2(float(k) * 1.9 + float(var) * 2.3, 8.0));
		float a = -0.25 + 3.4 * (float(k) + h1 * 0.6) / 12.0;  // fan over the upper half and a little below
		float L = 0.98 * W * (0.85 + 0.25 * h2);
		vec2 dir = vec2(cos(a), sin(a) * 0.5);
		float droop = 0.35 + 0.35 * h1;
		float best_d = 1.0;
		float best_t = 0.0;
		vec2 prev = C;
		for (int i = 1; i <= 12; i++) {  // distance to the polyline, continuous along each segment
			float t = float(i) / 12.0;
			vec2 pt = C + dir * L * t + vec2(0.0, -droop * L * t * t);
			vec2 seg = pt - prev;
			float hh = clamp(dot(P - prev, seg) / max(dot(seg, seg), 1e-6), 0.0, 1.0);
			float d = length(P - (prev + seg * hh));
			if (d < best_d) {
				best_d = d;
				best_t = (float(i) - 1.0 + hh) / 12.0;
			}
			prev = pt;
		}
		float w = (0.008 + 0.04 * sin(3.14159 * (0.12 + 0.88 * best_t)) * (0.6 + 0.4 * h2)) * L / W / 3.0;
		float comb = 0.68 + 0.32 * abs(sin(best_t * 31.0));
		float m = 1.0 - smoothstep(w * comb * 0.8, w * comb, best_d);
		m = max(m, 1.0 - smoothstep(0.003, 0.0045, best_d));
		if (m > fcov * 0.99) {
			fcov = max(fcov, m);
			fshade = 0.6 + 0.5 * best_t * (0.7 + 0.5 * h1);
			fn = normalize(vec3(dir.x * 0.6, 0.55, 0.7));
		}
	}
	float nut = 1.0 - smoothstep(0.018, 0.026, length(P - C - vec2(-0.004, -0.02)));
	cover = max(max(tc, fcov), nut);
	if (nut > 0.5) {
		alb = vec3(0.12, 0.09, 0.04);
		nrm = vec3(0.0, 0.2, 0.95);
	} else if (fcov > 0.4) {
		alb = vec3(0.11, 0.21, 0.05) * fshade * (0.8 + 0.4 * noise(P * 60.0));
		nrm = fn;
	} else {
		alb = ta;
		nrm = tn;
	}
	return cover;
}

void fragment() {
	vec2 g = UV * 4.0;
	ivec2 cell = ivec2(min(floor(g), vec2(3.0)));
	vec2 loc = fract(g);
	int sp = cell.y;
	int var = cell.x;
	float W = AR[sp] * 0.5;
	vec2 P = vec2((loc.x * 2.0 - 1.0) * W, 1.0 - loc.y);
	vec3 alb;
	vec3 nrm;
	float a;
	if (sp == 1) {
		a = palm(var, P, W, alb, nrm);
	} else {
		vec3 ta;
		vec3 tn;
		float tc = trunk(sp, P, float(var), ta, tn);
		float cc = crown(sp, var, P, W, alb, nrm);
		if (cc < 0.5 && tc > 0.0) {
			alb = ta;
			nrm = tn;
			cc = max(cc, tc);
		}
		a = cc;
	}
	if (a < 0.02) {
		alb = leaf_colour(sp) * 0.7;  // colour under transparent pixels, so mip levels do not bleed black
		nrm = vec3(0.0, 0.0, 1.0);
	}
	COLOR = pass_id == 0 ? vec4(alb, a) : vec4(nrm * 0.5 + 0.5, a);
}
