// Airport pavement for terrain.gdshader (after terrain_detail.gdshaderinc). Aprons are terrain, not a mesh:
// tools/27_pavement.py writes a 4 m mask per level-0 tile (terrain/pv/0, same lattice as the road tiles, so it
// uses ro_rect; layout in tools/pavement_raster.py). On pavement the field / town ground detail is replaced by
// concrete slabs (joint grid along the apron's edges, per-slab tone, sealed joints fading with distance) or
// asphalt, with tyre marks along the stand lead-in lines, oil stains where aircraft stand and rubber / grime
// streaks. The satellite colour stays only as a very low-frequency tint, so the apron matches its surroundings.

uniform sampler2D pv_tex : filter_linear, repeat_disable;
uniform float pv_on = 0.0;

const float PV_FAR = 3300.0;   // the tile is bound within ~3.6 km (TerrainQuadtree.ROADS_NEAR_M)
const vec2 PV_SLAB = vec2(5.0, 6.25);  // m, concrete slab size (across, along the joint direction)
const vec3 PV_CONCRETE = vec3(0.37, 0.365, 0.35);  // linear albedo of weathered apron concrete
const vec3 PV_ASPHALT = vec3(0.085, 0.085, 0.088);

struct Pave {
	float k;     // coverage 0..1 (edge anti-aliased, distance faded)
	int surf;    // 1 concrete, 2 asphalt
	float ang;   // slab joint direction (rad)
	float d;     // signed lateral offset from the nearest lead-in line (m), > 9 = none
	float wear;  // 0..1: 1 where aircraft stand, lower along the lead-in
};

Pave pv_fetch(vec2 uv, float dist, float aa) {
	Pave p = Pave(0.0, 0, 0.0, 99.0, 0.0);
	if (pv_on < 0.5 || dist > PV_FAR) {
		return p;
	}
	vec4 f = texture(pv_tex, uv);
	float e = f.r * 16.0 - 8.0;
	p.k = (1.0 - smoothstep(-aa, aa, e)) * (1.0 - smoothstep(PV_FAR - 1300.0, PV_FAR, dist));
	if (p.k <= 0.0) {
		return p;
	}
	ivec2 sz = textureSize(pv_tex, 0);
	vec2 tc = uv * vec2(sz) - 0.5;
	ivec2 i0 = ivec2(floor(tc));
	vec2 fr = fract(tc);
	vec4 n = texelFetch(pv_tex, clamp(ivec2(uv * vec2(sz)), ivec2(0), sz - 1), 0);
	int a = int(n.a * 255.0 + 0.5);
	p.surf = max(a & 3, 1);
	p.ang = n.b * 255.0 / 256.0 * 1.5707963;
	p.d = f.g > 0.955 ? 99.0 : f.g * 20.0 - 10.0;
	// wear is packed with the surface bits, so it is interpolated by hand
	float w[4];
	for (int i = 0; i < 4; i++) {
		ivec2 t = clamp(i0 + ivec2(i & 1, i >> 1), ivec2(0), sz - 1);
		w[i] = float(int(texelFetch(pv_tex, t, 0).a * 255.0 + 0.5) >> 2) / 63.0;
	}
	p.wear = mix(mix(w[0], w[1], fr.x), mix(w[2], w[3], fr.x), fr.y);
	return p;
}

// soft-edged stain blobs on a jittered grid of cell metres; dens: share of cells with one
float pv_stains(vec2 en, float cell, float dens, float seed) {
	vec2 c = floor(en / cell);
	float s = 0.0;
	for (int j = 0; j < 4; j++) {
		vec2 cc = c + vec2(float(j & 1), float(j >> 1)) - 0.5 + step(0.5, fract(en / cell)) - 0.5;
		float h = hash(cc + seed);
		if (h < dens) {
			vec2 ctr = (cc + 0.5 + (vec2(hash(cc + seed + 3.1), hash(cc + seed + 7.7)) - 0.5) * 0.8) * cell;
			float r = cell * (0.18 + 0.32 * hash(cc + seed + 11.3));
			float q = length((en - ctr) * vec2(1.0, 0.7 + 0.6 * h / dens)) / r + (vnoise(en * 2.3 + seed) - 0.5) * 0.6;
			s = max(s, (1.0 - smoothstep(0.55, 1.0, q)) * (0.5 + 0.5 * hash(cc + seed + 5.5)));
		}
	}
	return s;
}

// Paved surface colour. uv: imagery uv (low-frequency tint), en: world east / north (m), aa: pixel footprint (m).
// rough / spec: replaced by the pavement's; dn: normal offset (render frame).
vec3 pave_surface(Pave p, vec2 uv, vec2 en, float dist, float aa, out float rough, out float spec, out vec3 dn) {
	dn = vec3(0.0);
	// satellite tint: ~150 m blur of the imagery, its hue and part of its brightness
	float px_m = tile_size / (img_scale * float(textureSize(img_tex, 0).x));
	vec3 sat = pow(textureLod(img_tex, uv, clamp(log2(150.0 / px_m), 0.0, 8.0)).rgb, vec3(0.85)) * 1.15;
	float sl = max(dot(sat, vec3(0.299, 0.587, 0.114)), 0.01);
	vec3 hue = clamp(sat / sl, vec3(0.88), vec3(1.12));
	bool asphalt = p.surf == 2;
	rough = asphalt ? 0.82 : 0.78;
	spec = 0.3;
	vec3 base = asphalt ? PV_ASPHALT : PV_CONCRETE;
	float bl = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 col = base * mix(vec3(1.0), hue, 0.3) * mix(1.0, clamp(sl / bl, 0.6, 1.5), asphalt ? 0.15 : 0.35);
	float near = 1.0 - smoothstep(30.0, 300.0, dist);
	float det_k = 1.0 - smoothstep(DET_NEAR, DET_FAR, dist);
	// slab frame: q.x across, q.y along the joint direction
	vec2 dir = vec2(cos(p.ang), sin(p.ang));
	vec2 q = vec2(dot(en, vec2(dir.y, -dir.x)), dot(en, dir));
	if (!asphalt) {
		vec2 cell = floor(q / PV_SLAB);
		float h = hash(cell + 0.37), h2 = hash(cell + 9.1);
		col *= 1.0 + (h - 0.5) * 0.12 + (h2 > 0.94 ? 0.08 : 0.0) - (h2 < 0.05 ? 0.1 : 0.0)  // tone, newer / older slabs
			+ (vnoise(q * 0.7 + h * 17.0) - 0.5) * 0.08 * near;  // mottling within a slab
		vec2 jd = abs(fract(q / PV_SLAB + 0.5) - 0.5) * PV_SLAB;  // metres to the nearest joint (x, y)
		float jm = min(jd.x, jd.y);
		float fk = 1.0 - smoothstep(60.0, 380.0, dist);
		float jw = 0.03;  // sealed joint half-width
		float line = (1.0 - smoothstep(jw, jw + aa, jm)) * clamp(2.5 * jw / max(aa, 1e-3), 0.0, 1.0);
		col *= 1.0 - (0.3 * line + 0.06 * (1.0 - smoothstep(0.0, 0.35, jm))) * fk;  // tar seal, dirt along it
		rough = mix(rough, 0.6, line * fk);
	} else {
		// asphalt: repaired patches on an 11 m grid
		vec2 pc = floor(en / 11.0);
		float h = hash(pc + 4.2);
		if (h > 0.92) {
			vec2 f = abs(fract(en / 11.0) - 0.5);
			col *= mix(1.0, 0.82 + 0.3 * hash(pc + 1.3), (1.0 - smoothstep(0.3, 0.34, max(f.x, f.y))) * near);
		}
	}
	// micro texture: concrete / asphalt layer of the detail arrays
	if (det_k > 0.0) {
		vec2 n2; float r2;
		vec4 m = det_layer(asphalt ? L_ASPHALT : L_CONCRETE, en, dist, n2, r2);
		col *= mix(vec3(1.0), m.rgb * mix(1.0, m.a, 0.4), DET_P[asphalt ? L_ASPHALT : L_CONCRETE].x * det_k);
		dn = vec3(n2.x, 0.0, -n2.y) * 0.4 * det_k;
		rough += r2 * 0.5 * det_k;
	}
	// rubber and grime: long streaks along the slab direction, darker toward the stands
	float g = vnoise(q * vec2(0.09, 0.018) + 3.7) * 0.65 + vnoise(q * vec2(0.3, 0.05)) * 0.35;
	col *= 1.0 - 0.2 * smoothstep(0.45, 0.85, g) * (0.4 + 0.6 * p.wear);
	// tyre marks along the lead-in: nose wheel on the line, main gears either side (narrow- and wide-body tracks)
	if (p.d < 9.0 && p.wear > 0.0) {
		float ad = abs(p.d);
		float streak = 0.6 + 0.4 * vnoise(vec2(p.d * 2.0, dot(en, vec2(0.71, 0.71)) * 0.15));
		float tyre = (1.0 - smoothstep(0.25, 0.9, ad)) * 0.8 + (1.0 - smoothstep(0.5, 1.3, abs(ad - 3.6)))
			+ 0.5 * (1.0 - smoothstep(0.4, 1.1, abs(ad - 5.5)));
		float tk = tyre * streak * smoothstep(0.0, 0.5, p.wear) * (1.0 - smoothstep(7.5, 9.0, ad));
		col *= 1.0 - (asphalt ? 0.18 : 0.32) * clamp(tk, 0.0, 1.0);
		// oil / hydraulic stains where aircraft stand: under the engines, the nose and the APU
		float sk = smoothstep(0.88, 0.98, p.wear) * (1.0 - smoothstep(120.0, 600.0, dist));
		if (sk > 0.0) {
			float zone = exp(-pow(ad - 5.7, 2.0) / 6.0) + 0.6 * exp(-ad * ad / 3.0);
			float st = max(pv_stains(en, 2.6, 0.22 * zone, 1.7), 0.6 * pv_stains(en, 1.1, 0.12 * zone, 8.3));
			col = mix(col, col * vec3(0.42, 0.4, 0.38), st * sk);
			rough = mix(rough, 0.35, st * sk);
			spec = mix(spec, 0.35, st * sk);
		}
	}
	rough = clamp(rough, 0.3, 1.0);
	return col;
}
