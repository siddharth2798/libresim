// Runway surface for runway_v2.gdshader: hash / noise / box-filter helpers and the bare pavement, asphalt or concrete,
// in the terrain's apron colours (terrain_pavement.gdshaderinc PV_ASPHALT / PV_CONCRETE) so runway and shoulders
// match. Large-scale tone in runway metres (no tiling at any angle), a darker trafficked centre band, lighter oxidised
// and dusty outer metres, and up close the aggregate of the terrain detail arrays (layers 9 / 10, bound once by
// TerrainDetail.apply) at three unrelated scales with its normal and roughness. Wetness is the shader's last step.
// Needs width_m, seed, gear_hw and runway_detail declared before it.

uniform sampler2DArray det_mod : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray det_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rw_noise_tex : filter_linear, repeat_enable;  // RunwayNoise

const vec3 RW_ASPHALT = vec3(0.085, 0.085, 0.088);  // = PV_ASPHALT
const vec3 RW_CONCRETE = vec3(0.37, 0.365, 0.35);   // = PV_CONCRETE
const vec3 RW_OXIDE = vec3(0.05, 0.047, 0.042);      // added on the untrafficked edges: grey-brown dust and oxidised binder
const float RW_DET_FAR = 320.0;  // the aggregate is gone by here (the bake carries the far look)

float rw_hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

// value noise 0..1 from the RunwayNoise lattice: one bilinear fetch at a smoothstep-warped position (the same curve
// as an ALU value noise, a quarter of the cost)
float rw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	return textureLod(rw_noise_tex, (i + f * f * (3.0 - 2.0 * f) + 0.5) / 256.0, 0.0).r;
}

float rw_g(float a) {  // gaussian bump exp(-a^2)
	return exp(-a * a);
}

// Share of a pixel footprint x +- h covered by the interval [a, b] (a box filter: a stripe narrower than the pixel
// becomes its average tone instead of crawling).
float rw_box(float x, float a, float b, float h) {
	return (clamp(x + h, a, b) - clamp(x - h, a, b)) / (2.0 * h);
}

// Detail layer l at en (world east / north, m): the mid scale (tile x 4.37, turned) plus fine (tile) near or coarse
// (x 19.3, turned) farther, as terrain_detail.gdshaderinc det_layer but two fetches per array instead of three. Returns modulation (1 = unchanged);
// n: tangent normal offset (east, north), r: roughness offset.
vec3 rw_detail(int l, vec2 en, float dist, float tile, out vec2 n, out float r) {
	float fl = float(l);
	mat2 r2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)), r3 = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28));
	vec2 um = r2 * en / (tile * 4.37) + vec2(0.37, 0.71);
	vec4 m = vec4(texture(det_mod, vec3(um, fl)).rgb, 1.0);
	vec4 o = texture(det_nrm, vec3(um, fl));
	vec2 nn = transpose(r2) * (o.xy * 2.0 - 1.0);
	float ra = o.z - 0.5;
	// a second scale: fine near (the ground at your feet), coarse farther (clumps seen from a few hundred metres)
	bool near = dist < 120.0;
	float w2 = near ? 1.0 - smoothstep(20.0, 120.0, dist) : smoothstep(120.0, 350.0, dist);
	if (w2 > 0.0) {
		vec2 u2 = near ? en / tile : r3 * en / (tile * 19.3) + vec2(0.13, 0.52);
		vec4 o2 = texture(det_nrm, vec3(u2, fl));
		m += vec4(texture(det_mod, vec3(u2, fl)).rgb, 1.0) * w2;
		nn += (near ? o2.xy * 2.0 - 1.0 : transpose(r3) * (o2.xy * 2.0 - 1.0)) * w2;
		ra += (o2.z - 0.5) * w2;
	}
	n = nn / m.a;
	r = ra / m.a;
	return m.rgb / m.a * 2.0;
}

// Bare pavement colour at runway metres (across, along), without the aggregate: large-scale tone, darker trafficked
// centre, oxidised edges (baked per runway by RunwayBake).
vec3 rw_base(bool concrete, float across, float along) {
	float half_w = width_m * 0.5;
	float ax = abs(across);
	vec3 col = concrete ? RW_CONCRETE * 0.92 : RW_ASPHALT * 1.3;
	vec2 q = vec2(across, along) + seed * 37.0;
	float macro = (rw_noise(q * vec2(0.025, 0.004)) - 0.5) * 0.16 + (rw_noise(q * vec2(0.11, 0.025)) - 0.5) * 0.08;
	col *= 1.0 + macro;
	float centre = 1.0 - smoothstep(gear_hw + 2.0, gear_hw + 7.0, ax);
	float edge = smoothstep(max(half_w - 14.0, half_w * 0.45), half_w - 1.0, ax);
	edge *= 0.65 + 0.7 * rw_noise(vec2(across * 0.15, along * 0.02) + seed);
	if (concrete) {
		return col * (1.0 - 0.12 * centre) * (1.0 + 0.06 * edge);
	}
	return col * (1.0 - 0.12 * centre) + RW_OXIDE * (edge + 0.25);
}

// Aggregate near the camera (Ultra / Max only: on High it cost more than the near-field budget; gone by RW_DET_FAR): colour modulation; dn: normal offset (render frame),
// dr: roughness offset, agg: modulation luminance (1 = average; paint wears through on the high stones).
vec3 rw_aggregate(bool concrete, vec2 en, float dist, out vec3 dn, out float dr, out float agg) {
	dn = vec3(0.0);
	dr = 0.0;
	agg = 1.0;
	if (runway_detail < 3 || dist >= RW_DET_FAR) {
		return vec3(1.0);
	}
	float k = 1.0 - smoothstep(RW_DET_FAR * 0.65, RW_DET_FAR, dist);
	vec2 n2;
	float r2;
	vec3 m = mix(vec3(1.0), rw_detail(concrete ? 9 : 10, en, dist, concrete ? 2.9 : 2.1, n2, r2), (concrete ? 1.1 : 1.6) * k);
	agg = dot(m, vec3(0.333));
	dn = vec3(n2.x, 0.0, -n2.y) * 0.9 * k;
	dr = r2 * 0.5 * k;
	return m;
}
