shader_type spatial;
render_mode fog_disabled;  // haze is applied below (aerial perspective, as terrain.gdshader)
// OSM buildings (tools/10_buildings.py, tools/building_geom.py). Per vertex:
//   CUSTOM0 = roof colour from imagery (rgb) + style (a = pid << 2 | roof type, 0 flat / 1 hip roof)
//   CUSTOM1 = wall height in cm (rg, 16 bit), parapet band / rooftop kind (b), height fraction (a)
// Everything else is procedural and seeded by a hash of the building: wall colour, window shape and
// rhythm, balconies, shopfronts, glass towers, weathering and rain streaks, roof material, tile courses
// on hip roofs, parapet cap, stairwell boxes and water tanks. Fine detail fades to its average colour
// with distance (no shimmer); windows light up at night.

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;
global uniform vec2 pattern_origin;  // FloatingOrigin: origin mod ~50 km (float32-safe)
uniform float night = 0.0;  // 0 day .. 1 night (set by Buildings from the sun)

varying vec4 v_c0;
varying vec4 v_c1;
varying vec3 v_world;
varying float v_dist;

void vertex() {
	v_c0 = CUSTOM0;
	v_c1 = CUSTOM1;
	// world-stable facade coordinates (no window jump on a floating-origin shift)
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + vec3(pattern_origin.x, 0.0, -pattern_origin.y);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash1(float x) { return fract(sin(x * 91.3458) * 47453.5453); }
float rb(float id, float k) { return hash1(id * 127.1 + k * 17.31); }  // per-building random number k
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// antialiased box 0/1 of x in [a, b], edges softened by the pixel footprint w
float box1(float x, float a, float b, float w) {
	w = max(w, 0.001);
	return smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x);
}

vec3 wall_palette(float r) {  // Indian city facades: whitewash, cream, ochre, concrete, pastels, weathered brown
	if (r < 0.14) return vec3(0.60, 0.57, 0.50);
	if (r < 0.28) return vec3(0.58, 0.46, 0.27);
	if (r < 0.40) return vec3(0.54, 0.34, 0.10);
	if (r < 0.52) return vec3(0.32, 0.32, 0.30);
	if (r < 0.60) return vec3(0.44, 0.43, 0.41);
	if (r < 0.69) return vec3(0.24, 0.40, 0.56);
	if (r < 0.78) return vec3(0.28, 0.48, 0.28);
	if (r < 0.86) return vec3(0.58, 0.28, 0.30);
	if (r < 0.93) return vec3(0.26, 0.17, 0.11);
	return vec3(0.52, 0.22, 0.13);
}

vec3 sign_palette(float r) {
	if (r < 0.2) return vec3(0.65, 0.10, 0.08);
	if (r < 0.4) return vec3(0.10, 0.25, 0.60);
	if (r < 0.6) return vec3(0.75, 0.62, 0.10);
	if (r < 0.8) return vec3(0.12, 0.45, 0.20);
	return vec3(0.70, 0.70, 0.66);
}

vec3 roof_palette(float r, vec3 img) {  // flat roofs: imagery, bare concrete, white coating, brick, tarpaulin
	vec3 base = pow(img, vec3(0.8)) * 1.35;
	if (r < 0.30) return base;
	if (r < 0.55) return mix(base, vec3(0.45, 0.43, 0.40), 0.75);
	if (r < 0.70) return mix(base, vec3(0.70, 0.69, 0.64), 0.75);
	if (r < 0.82) return mix(base, vec3(0.50, 0.25, 0.17), 0.75);
	if (r < 0.92) return mix(base, vec3(0.16, 0.34, 0.52), 0.65);
	return mix(base, vec3(0.34, 0.42, 0.32), 0.65);
}

vec3 tile_palette(float r) {
	if (r < 0.45) return vec3(0.46, 0.20, 0.12);
	if (r < 0.75) return vec3(0.58, 0.28, 0.16);
	if (r < 0.90) return vec3(0.30, 0.16, 0.10);
	return vec3(0.24, 0.24, 0.25);
}

void fragment() {
	vec3 n_world = normalize(cross(dFdx(v_world), dFdy(v_world)));
	NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	float s = floor(v_c0.a * 255.0 + 0.5);
	float rtype = mod(s, 4.0);
	float H = (floor(v_c1.r * 255.0 + 0.5) + 256.0 * floor(v_c1.g * 255.0 + 0.5)) * 0.01;  // 0 = old BLD1 tile
	float band = v_c1.b * 255.0;
	float id = hash1(floor(s / 4.0) * 1.618 + H * 0.0731);
	vec3 roof = v_c0.rgb;
	vec3 col;
	vec3 emit = vec3(0.0);
	float gloss = 0.0;
	if (abs(n_world.y) > 0.2) {
		// ---- roofs ----
		float cover = 0.0;
		vec3 cap = wall_palette(rb(id, 1.0)) * 1.2;
		if (band > 240.0) {  // stairwell box top or water tank lid
			col = band > 251.0 ? vec3(0.04, 0.045, 0.05) : cap * 0.85;
		} else if (rtype > 0.5) {  // hip roof: tile courses
			col = mix(tile_palette(rb(id, 12.0)), roof * 1.2, 0.12);
			float course = v_world.y / 0.17;
			float fc = fwidth(course);
			float lines = smoothstep(0.0, 0.25, fract(course));
			col *= mix(0.88, 0.8 + 0.2 * lines, 1.0 - smoothstep(0.3, 0.7, fc));
			col *= 0.88 + 0.24 * vnoise(v_world.xz * 0.9 + v_world.y * 1.3);
		} else {
			col = roof_palette(rb(id, 10.0), roof);
			col *= 0.86 + 0.28 * vnoise(v_world.xz * 0.33 + id * 40.0);  // stains and patches
			col *= 0.94 + 0.12 * vnoise(v_world.xz * 2.3);
			// parapet strip: light cap on the outer edge, shadow line inside it
			if (band <= 200.0) {
				float e = band / 200.0;
				float m = 1.0 - smoothstep(0.1, 0.3, fwidth(e));
				float capm = 1.0 - smoothstep(0.30, 0.38, e);
				vec3 pc = mix(col * mix(0.72, 1.0, smoothstep(0.35, 1.0, e)), cap, capm);
				col = mix(col, pc, m);
			}
		}
	} else {
		float hg = H > 0.5 ? v_c1.a * H : v_world.y;  // height above the ground
		float Hh = H > 0.5 ? H : 1000.0;
		float u = abs(n_world.x) > abs(n_world.z) ? v_world.z : v_world.x;
		float age = rb(id, 9.0);
		vec3 pal = wall_palette(rb(id, 1.0)) * (0.9 + 0.2 * rb(id, 2.0));
		bool tower = Hh > 32.0 && rb(id, 3.0) < 0.6;
		if (band > 240.0) {  // sides of a rooftop box / tank
			col = band > 251.0 ? vec3(0.05, 0.055, 0.06) : pal * 0.8 + 0.1;
			gloss = band > 251.0 ? 0.4 : 0.0;
		} else {
			float fh = 3.1;
			float floors = max(1.0, floor((Hh - 0.9) / fh + 0.5));
			bool plain_top = hg > floors * fh;  // the parapet wall above the last floor
			float ws = mix(2.3, 3.7, rb(id, 4.0));
			vec2 cell = vec2(u / ws, hg / fh);
			vec2 f = fract(cell);
			vec2 fw = fwidth(cell);
			float detail = 1.0 - smoothstep(0.2, 0.45, max(fw.x, fw.y));
			float sw = mix(0.46, 0.78, rb(id, 5.0));  // window width as a fraction of a cell
			float wx0 = 0.5 - sw * 0.5;
			float wx1 = 0.5 + sw * 0.5;
			float wy0 = 0.24;
			float wy1 = mix(0.74, 0.88, rb(id, 6.0));
			bool shop = Hh > 5.5 && rb(id, 7.0) < 0.6;
			bool balc = !tower && Hh > 8.0 && rb(id, 8.0) < 0.45;
			float wcol = floor(cell.x);
			bool bal_cell = balc && mod(wcol + floor(rb(id, 11.0) * 2.0), 2.0) < 0.5 && hash(vec2(wcol, floor(cell.y)) + id) > 0.2;
			float wm = box1(f.x, wx0, wx1, fw.x) * box1(f.y, wy0, wy1, fw.y);
			float cov = sw * (wy1 - wy0);
			col = pal;
			vec3 glass = vec3(0.03, 0.045, 0.06) + fog_color * 0.07 * (0.4 + rb(id, 13.0));
			// weathering: dirt toward the ground, soot under the roof edge, rain streaks from the top
			float sn = vnoise(vec2(u * 1.9 + id * 60.0, hg * 0.12));
			float fadeu = 1.0 - smoothstep(0.3, 0.8, fwidth(u) * 1.9);
			float dirt = (1.0 - smoothstep(0.0, 2.6, hg)) * (0.2 + 0.5 * age) + 0.1 * (1.0 - smoothstep(0.0, 9.0, hg));
			float streak = smoothstep(0.5, 0.85, sn) * exp(-(Hh - hg) / (2.0 + 9.0 * sn)) * (0.2 + 0.5 * age);
			float eave = (1.0 - smoothstep(0.0, 1.2, Hh - hg)) * 0.15;
			float stain = (dirt + streak * fadeu + eave) * 0.6 * mix(0.5, 1.0, fadeu);
			col *= 1.0 - stain;
			col *= 0.94 + 0.12 * vnoise(vec2(u * 0.6, hg * 0.35) + id * 20.0);
			float lit_win = 0.0;
			if (tower) {
				// glass curtain wall: dark spandrel band per floor, glazing with mullions, sky tint
				float mull = box1(fract(u / 1.6), 0.04, 0.96, fwidth(u / 1.6));
				float sp = box1(f.y, 0.30, 1.0, fw.y);
				float gm = mix(0.75, mull * sp, detail);
				vec3 gl = mix(vec3(0.10, 0.16, 0.20), fog_color * 0.5, 0.25 + 0.35 * smoothstep(0.0, 120.0, hg));
				gl *= 0.8 + 0.4 * hash(floor(cell) + id);
				col = mix(pal * 0.55, gl, gm * 0.9);
				gloss = gm * 0.7;
				lit_win = gm;
			} else if (plain_top) {
				col *= mix(1.0, 1.12, smoothstep(floors * fh + 0.5, Hh, hg));
			} else if (shop && hg < 3.3) {
				// shopfront: wide openings with shutters or glass, a signboard above
				vec2 sc = vec2(u / 4.2, hg);
				float op = box1(fract(sc.x), 0.07, 0.93, fwidth(sc.x)) * box1(sc.y, 0.0, 2.6, fwidth(sc.y));
				float slats = 0.8 + 0.2 * smoothstep(0.35, 0.65, abs(fract(hg * 7.0) - 0.5) * 2.0);
				vec3 shut = mix(vec3(0.30, 0.32, 0.33) * slats, glass * 2.0, step(0.5, hash(vec2(floor(sc.x), id))));
				float sgn = box1(hg, 2.7, 3.25, fwidth(hg)) * step(0.4, rb(id, 14.0));
				vec3 sc3 = sign_palette(hash(vec2(floor(sc.x), id * 3.0)));
				col = mix(col, shut, mix(0.7, op, detail) * 0.9);
				col = mix(col, sc3 * 0.8, mix(0.4, sgn, detail) * 0.8);
				lit_win = mix(0.6, op, detail) * 0.8;
			} else {
				float slab = box1(f.y, 0.0, 0.09, fw.y);  // floor slab edge, shadow under it
				float under = box1(f.y, 0.88, 1.0, fw.y);
				col = mix(col, col * 1.25 + 0.04, slab * detail * 0.9);
				col *= 1.0 - 0.3 * under * detail;
				float sill = box1(f.y, wy0 - 0.05, wy0, fw.y) * box1(f.x, wx0 - 0.05, wx1 + 0.05, fw.x);
				col = mix(col, col * 1.1 + 0.03, sill * detail * 0.7);
				float recess = smoothstep(0.0, 0.25, (wy1 - f.y) / (wy1 - wy0));  // dark under the lintel
				vec3 g = glass * mix(0.55, 1.0, recess) * (0.75 + 0.5 * hash(floor(cell) + id * 5.0));
				float curtain = step(0.78, hash(floor(cell) + id * 9.0));
				g = mix(g, vec3(0.45, 0.32, 0.28) * (0.6 + hash(floor(cell)) * 0.6), curtain * 0.7);
				float wmask = wm;
				if (bal_cell) {
					// balcony: slab, railing band, tall door glass
					float rail = box1(f.y, 0.0, 0.42, fw.y);
					float door = box1(f.x, 0.18, 0.82, fw.x) * box1(f.y, 0.42, 0.88, fw.y);
					col = mix(col, col * 0.78, rail * detail * 0.8);
					col = mix(col, col * 1.1, slab * detail);
					wmask = door;
				}
				float wmix = mix(cov, wmask, detail);
				col = mix(col, g, wmix * 0.97);
				lit_win = wmix;
			}
			// night: per-building occupancy (offices mostly dark, homes warmer), soft warm/cool lamps
			float occ = mix(0.06, 0.3, rb(id, 17.0));
			if (tower) {
				occ = 0.35;
			}
			float on = step(1.0 - occ, hash(floor(cell) + id * 31.0));
			vec3 lamp = mix(vec3(1.0, 0.76, 0.48), vec3(0.82, 0.88, 1.0), step(0.8, rb(id, 23.0)));
			float lit = mix(occ * cov, on * lit_win, detail) * night;
			if (tower) {
				lit = lit_win * on * night;
			} else if (shop && hg < 3.3) {
				lit = mix(lit_win * 0.5, lit_win * on, detail) * night * 1.2;
			}
			if (plain_top) {
				lit = 0.0;
			}
			emit = lamp * lit * 0.75;
			// far away: the facade pattern gives way to the building's average colour
			float far = smoothstep(800.0, 2500.0, v_dist);
			col = mix(col, mix(pal, roof, 0.2) * 0.9, far);
		}
	}
	col *= mix(1.0, 0.72, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = emit * (1.0 - haze * 0.5) + fog_color * haze;
	ROUGHNESS = mix(mix(0.85, 0.25, gloss), 0.4, wetness);
	SPECULAR = mix(0.4, 0.8, gloss) * (1.0 - haze);
}
