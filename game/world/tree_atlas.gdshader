shader_type canvas_item;
render_mode blend_disabled;
// Impostor atlas of the tree billboards, drawn once at startup by TreeAtlas (nothing here runs per
// frame). Columns are yaw angles (TreeAtlas.YAWS, uniform grid.x), rows are species (broadleaf,
// palm, acacia, slim). Each column is the same tree seen from yaw = column * TAU / grid.x, with the
// camera on local (sin yaw, 0, cos yaw) — column 0 is the view from local +Z, matching TreeLook.yaw_column.
// pass_id 0 writes linear albedo (with baked occlusion), 1 writes the normal (sprite space, xy = right /
// up, z = towards the viewer) packed to 0..1; alpha is the cover.

uniform int pass_id = 0;
uniform vec2 grid = vec2(8.0, 4.0);

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

// Camera on (sn, 0, co) looking at the origin. Column 0 (co = 1, sn = 0) leaves the tree as drawn.
vec3 view_of(vec3 p, float co, float sn) {
	return vec3(co * p.x - sn * p.z, p.y, sn * p.x + co * p.z);
}

// Crown of lumps (species 0, 2, 3). Returns coverage; alb / nrm for the front-most lump.
float crown(int sp, vec2 P, float W, float co, float sn, out vec3 alb, out vec3 nrm) {
	int n = sp == 0 ? 9 : (sp == 2 ? 7 : 6);
	vec2 c0 = sp == 2 ? vec2(0.0, 0.62) : (sp == 3 ? vec2(0.0, 0.55) : vec2(0.0, 0.64));
	vec2 spread = sp == 2 ? vec2(0.45 * W, 0.05) : (sp == 3 ? vec2(0.15 * W, 0.25) : vec2(0.34 * W, 0.14));
	vec2 rad = sp == 2 ? vec2(0.35 * W, 0.075) : (sp == 3 ? vec2(0.6 * W, 0.14) : vec2(0.48 * W, 0.19));
	float best = -10.0;
	float cover = 0.0;
	alb = leaf_colour(sp);
	nrm = vec3(0.0, 0.0, 1.0);
	for (int k = 0; k < n; k++) {
		vec2 s = vec2(float(k) * 1.37, float(sp) * 9.0);
		float h1 = hash(s), h2 = hash(s + 17.3), h3 = hash(s + 41.9);
		vec2 c = k == 0 ? c0 : c0 + spread * vec2(h1 * 2.0 - 1.0, h2 * 2.0 - 1.0);
		float zc = k == 0 ? 0.0 : (hash(s + 9.2) - 0.5) * spread.x;
		vec3 cv = view_of(vec3(c.x, c.y, zc), co, sn);
		vec2 r = rad * (k == 0 ? 1.25 : 0.75 + 0.5 * h3);
		vec2 q = (P - cv.xy) / r;
		float d = length(q) + (noise(P * 38.0 + s) - 0.5) * 0.5 + (noise(P * 95.0 + s) - 0.5) * 0.18;
		float a = 1.0 - smoothstep(0.86, 1.0, d);
		if (a <= 0.0) continue;
		float z = sqrt(max(1.0 - dot(q, q), 0.0));
		float depth = cv.z + (h3 - 0.5) * 0.3 + z * 0.25;
		cover = max(cover, a);
		if (depth > best) {
			best = depth;
			nrm = normalize(vec3(q.x / r.x, q.y / r.y, z / (0.5 * (r.x + r.y))));
			float mottle = 0.62 + 0.75 * noise(cv.xy * 85.0 + s) * noise(cv.xy * 31.0 + s * 2.0);
			float ao = mix(0.5, 1.0, smoothstep(0.30, 0.90, P.y)) * (0.78 + 0.22 * smoothstep(-0.1, 0.1, depth)) * mix(0.8, 1.0, z);
			alb = leaf_colour(sp) * (0.8 + 0.4 * h1) * mottle * ao;
		}
	}
	return cover;
}

// Trunk (species 0, 2, 3): a tapered strip, forked into two limbs for the acacia.
float trunk(int sp, vec2 P, float co, float sn, out vec3 alb, out vec3 nrm) {
	float x0 = (hash(vec2(1.0, 3.0)) - 0.5) * 0.02;
	float top = sp == 2 ? 0.42 : (sp == 3 ? 0.35 : 0.5);
	float hw = (sp == 3 ? 0.011 : 0.017) * (1.0 + 0.9 * smoothstep(0.1, 0.0, P.y));
	float dx = P.x - view_of(vec3(x0, 0.0, 0.0), co, sn).x;
	float cov = (1.0 - smoothstep(hw * 0.8, hw, abs(dx))) * step(0.0, P.y) * step(P.y, top);
	if (sp == 2) {
		for (int k = 0; k < 2; k++) {
			float sgn = k == 0 ? -1.0 : 1.0;
			float t = clamp((P.y - top) / 0.18, 0.0, 1.0);
			vec3 limb = view_of(vec3(x0 + sgn * 0.16 * t * t, 0.0, sgn * 0.12 * t), co, sn);
			float lc = (1.0 - smoothstep(0.012, 0.016, abs(P.x - limb.x))) * step(top, P.y) * step(P.y, top + 0.18);
			cov = max(cov, lc);
		}
	}
	float c = clamp(dx / hw, -1.0, 1.0);
	nrm = normalize(vec3(c, 0.0, sqrt(max(1.0 - c * c, 0.0))));
	alb = vec3(0.17, 0.12, 0.08) * (0.7 + 0.5 * noise(vec2(P.x * 120.0, P.y * 14.0))) * (0.6 + 0.4 * (c * 0.5 + 0.5));
	return cov;
}

float palm(vec2 P, float W, float co, float sn, out vec3 alb, out vec3 nrm) {
	vec3 C = vec3(0.025, 0.86, 0.0);
	float cover = 0.0;
	alb = vec3(0.14, 0.24, 0.05);
	nrm = vec3(0.0, 0.0, 1.0);
	float ty = clamp(P.y / C.y, 0.0, 1.0);
	float bend = (hash(vec2(1.0, 7.0)) - 0.5) * 0.02;
	vec3 trunk_p = view_of(vec3(C.x * pow(ty, 1.5) + bend * ty, 0.0, bend * ty * 0.5), co, sn);
	float hw = mix(0.016, 0.0095, ty) + 0.012 * smoothstep(0.08, 0.0, P.y);
	float tc = (1.0 - smoothstep(hw * 0.75, hw, abs(P.x - trunk_p.x))) * step(0.0, P.y) * step(P.y, C.y);
	float rings = 0.75 + 0.25 * smoothstep(0.3, 0.7, abs(fract(P.y * 36.0) - 0.5) * 2.0);
	float cc = clamp((P.x - trunk_p.x) / hw, -1.0, 1.0);
	vec3 tn = normalize(vec3(cc, 0.0, sqrt(max(1.0 - cc * cc, 0.0))));
	vec3 ta = vec3(0.12, 0.10, 0.075) * rings * (0.7 + 0.5 * noise(vec2(P.x * 90.0, P.y * 20.0)));
	float fcov = 0.0;
	float best_z = -10.0;
	vec3 fn = vec3(0.0, 0.35, 0.85);
	float fshade = 1.0;
	for (int k = 0; k < 12; k++) {
		float h1 = hash(vec2(float(k) * 3.7, 5.0));
		float h2 = hash(vec2(float(k) * 1.9, 8.0));
		float az = 6.2831853 * (float(k) + h1 * 0.35) / 12.0;
		float L = 0.98 * W * (0.85 + 0.25 * h2);
		float droop = 0.35 + 0.35 * h1;
		vec3 dir = vec3(cos(az), 0.12, sin(az));
		float best_d = 1.0;
		float best_t = 0.0;
		float pz = -10.0;
		vec3 prev = view_of(C, co, sn);
		for (int i = 1; i <= 12; i++) {
			float t = float(i) / 12.0;
			vec3 pv = view_of(C + dir * L * t + vec3(0.0, -droop * L * t * t, 0.0), co, sn);
			vec2 seg = pv.xy - prev.xy;
			float hh = clamp(dot(P - prev.xy, seg) / max(dot(seg, seg), 1e-6), 0.0, 1.0);
			float d = length(P - (prev.xy + seg * hh));
			if (d < best_d) {
				best_d = d;
				best_t = (float(i) - 1.0 + hh) / 12.0;
				pz = mix(prev.z, pv.z, hh);
			}
			prev = pv;
		}
		float w = (0.008 + 0.04 * sin(3.14159 * (0.12 + 0.88 * best_t)) * (0.6 + 0.4 * h2)) * L / W / 3.0;
		float comb = 0.68 + 0.32 * abs(sin(best_t * 31.0));
		float m = max(1.0 - smoothstep(w * comb * 0.8, w * comb, best_d), 1.0 - smoothstep(0.003, 0.0045, best_d));
		if (m > 0.02 && (pz > best_z + 0.01 || (abs(pz - best_z) <= 0.01 && m > fcov))) {
			best_z = pz;
			fcov = m;
			fshade = 0.55 + 0.5 * best_t * (0.7 + 0.5 * h1);
			fn = normalize(vec3(dir.x * co - dir.z * sn, -0.25 - droop * 0.4, 0.72));
		}
	}
	vec2 nut_p = view_of(C + vec3(-0.004, -0.02, 0.0), co, sn).xy;
	float nut = 1.0 - smoothstep(0.018, 0.026, length(P - nut_p));
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
	vec2 g = UV * grid;
	ivec2 cell = ivec2(min(floor(g), grid - vec2(1.0)));
	vec2 loc = fract(g);
	int sp = cell.y;
	float yaw = float(cell.x) * 6.2831853 / grid.x;
	float co = cos(yaw);
	float sn = sin(yaw);
	float W = AR[sp] * 0.5;
	vec2 P = vec2((loc.x * 2.0 - 1.0) * W, 1.0 - loc.y);
	vec3 alb;
	vec3 nrm;
	float a;
	if (sp == 1) {
		a = palm(P, W, co, sn, alb, nrm);
	} else {
		vec3 ta;
		vec3 tn;
		float tc = trunk(sp, P, co, sn, ta, tn);
		float cc = crown(sp, P, W, co, sn, alb, nrm);
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
