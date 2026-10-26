shader_type spatial;
render_mode fog_disabled;
// Terrain node: displaces the shared TerrainMesh grid from a 16-bit heightmap
// (RG8 = little-endian uint16) and colours it with satellite imagery.
// A node may cover a sub-rectangle of its source tile (virtual levels below L0).

uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform sampler2D img_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform ivec2 texel_off;       // first heightmap texel of this node
uniform int texel_step;        // heightmap texels per grid cell
uniform float tile_size;       // metres covered by this node
uniform vec2 img_off;          // imagery UV of this node's SW corner (v measured from north)
uniform float img_scale;       // imagery UV span of this node
// land class may come from a different (ancestor) tile than imagery
uniform vec2 lc_off = vec2(0.0, 1.0);
uniform float lc_scale = 1.0;
uniform float h_scale = 0.1;
uniform float h_offset = -100.0;
uniform float tile_n = 256.0;
uniform float skirt_depth = 30.0;
// geomorph: vertices blend toward the parent node's (2x coarser) surface between
// these camera distances, so LOD splits/merges don't pop (TerrainQuadtree)
uniform vec2 morph_range = vec2(1e12, 2e12);
global uniform vec3 terrain_eye;    // camera, render space (same in shadow passes)
global uniform vec3 fog_color;      // set by SkyTime (visibility / time of day)
global uniform float haze_density;
global uniform vec2 pattern_origin; // FloatingOrigin.pattern_origin(): origin mod ~50 km (float32-safe)
global uniform vec3 sky_top_color;
global uniform float wetness;       // WeatherFx: wet ground after rain
global uniform float precip;        // WeatherFx: local rain rate
uniform sampler2D lc_tex : filter_linear, repeat_disable;  // land class: 255 = water

varying float v_dist;
varying vec2 v_en;  // world east/north (m) relative to the pattern wrap base

float h_at(ivec2 t) {
	vec2 rg = texelFetch(height_tex, clamp(t, ivec2(0), ivec2(int(tile_n))), 0).rg;
	return (round(rg.r * 255.0) + round(rg.g * 255.0) * 256.0) * h_scale + h_offset;
}

void vertex() {
	ivec2 g = ivec2(round(UV * 64.0));
	ivec2 t = texel_off + g * texel_step;
	float h = h_at(t);
	vec3 wp0 = (MODEL_MATRIX * vec4(UV.x * tile_size, h, -UV.y * tile_size, 1.0)).xyz;
	float morph = clamp((distance(wp0, terrain_eye) - morph_range.x) / (morph_range.y - morph_range.x), 0.0, 1.0);
	ivec2 odd = g % 2;
	if (morph > 0.0 && odd != ivec2(0)) {
		// parent surface: midpoint of the parent edge (or of its triangle diagonal,
		// which runs from (i+1, j) to (i, j+1) in TerrainMesh) through this vertex
		int s = texel_step;
		ivec2 a = odd.x * odd.y == 1 ? ivec2(s, -s) : (odd.x == 1 ? ivec2(s, 0) : ivec2(0, s));
		h = mix(h, 0.5 * (h_at(t + a) + h_at(t - a)), morph);
	}
	float sp = tile_size / (64.0 * float(texel_step)); // metres per texel
	float dx = (h_at(t + ivec2(1, 0)) - h_at(t - ivec2(1, 0))) / (2.0 * sp);
	float dn = (h_at(t + ivec2(0, 1)) - h_at(t - ivec2(0, 1))) / (2.0 * sp);
	NORMAL = normalize(vec3(-dx, 1.0, dn));
	VERTEX = vec3(UV.x * tile_size, h - UV2.x * skirt_depth, -UV.y * tile_size);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	vec3 wr = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_en = vec2(wr.x + pattern_origin.x, -wr.z + pattern_origin.y);
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// Ground detail the 10 m imagery lacks: tonal variation at field / hill scale far away, grain and a
// micro-relief normal close up. Both fade by distance so nothing shimmers at the horizon.
float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int i = 0; i < 3; i++) { s += a * vnoise(p); p = p * 2.03 + vec2(17.3, 9.1); a *= 0.5; }
	return s;
}
// small wind waves: height field gradient from scrolling noise octaves
vec2 wave_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	float a = 1.0, f = 0.08;
	for (int i = 0; i < 4; i++) {
		vec2 q = p * f + vec2(t * 0.6, t * 0.35) * f * 3.0;
		float e = 0.05;
		g += a * vec2(vnoise(q + vec2(e, 0)) - vnoise(q - vec2(e, 0)), vnoise(q + vec2(0, e)) - vnoise(q - vec2(0, e))) / (2.0 * e) * f;
		a *= 0.5; f *= 2.1;
	}
	return g;
}

void fragment() {
	vec2 uv = img_off + vec2(UV.x, -UV.y) * img_scale;
	vec2 lc_uv = lc_off + vec2(UV.x, -UV.y) * lc_scale;
	vec3 col = texture(img_tex, uv).rgb;
	// Sentinel-2 mosaics are dark and slightly blue-shifted; lift for daylight.
	col = pow(col, vec3(0.85)) * 1.15;
	float water = smoothstep(0.88, 0.97, texture(lc_tex, lc_uv).r);
	float land = 1.0 - water;
	// macro: slow tonal drift (m-scale to km-scale) so far ground is not a flat smear
	float macro = fbm(v_en * 0.0011) - 0.5 + 0.6 * (fbm(v_en * 0.011) - 0.5);
	col *= 1.0 + macro * 0.5 * land * smoothstep(300.0, 2500.0, v_dist);
	// micro: soft grain and relief within a kilometre
	float near_k = 1.0 - smoothstep(250.0, 1400.0, v_dist);
	if (near_k > 0.0 && land > 0.0) {
		vec2 q = v_en * 0.8;
		float grain = (fbm(q) - 0.5) * 0.5 + (fbm(v_en * 0.15) - 0.5) * 0.9;
		col *= 1.0 + grain * 0.22 * land * near_k;
		vec2 e = vec2(0.6, 0.0);
		vec2 mg = vec2(fbm(q + e.xy) - fbm(q - e.xy), fbm(q + e.yx) - fbm(q - e.yx));
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(-mg.x, 0.0, mg.y, 0.0)).xyz * 0.25 * land * near_k);
	}
	float rough = 0.95;
	float spec = 0.1;
	if (water > 0.0) {
		vec2 g = wave_grad(v_en, TIME) * 1.4 * (1.0 - smoothstep(150.0, 2500.0, v_dist));
		vec3 nw = normalize(vec3(-g.x, 1.0, g.y));  // render frame: x east, y up, z south
		vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(nv, VIEW), 0.0, 1.0), 4.0);
		vec3 deep = vec3(0.05, 0.13, 0.15);  // Arabian Sea: grey-green-blue
		vec3 shallow = col * 0.75;  // keep the satellite tint near coasts and creeks
		vec3 sky = mix(sky_top_color, fog_color, 0.35);
		vec3 wcol = mix(mix(deep, shallow, 0.4), sky, clamp(fres * 0.75 + 0.04, 0.0, 0.85));
		col = mix(col, wcol, water);
		NORMAL = normalize(mix(NORMAL, nv, water));
		rough = mix(rough, 0.06 + 0.14 * precip, water);  // rain roughens the surface
		spec = mix(spec, 0.6, water);
	}
	// wet ground: darker, glossier, with standing water on flat ground
	float wet = wetness * (1.0 - water);
	if (wet > 0.0) {
		float flat_ground = smoothstep(0.985, 0.998, dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz));
		float puddle = smoothstep(0.62, 0.8, vnoise(v_en * 0.05) * 0.7 + vnoise(v_en * 0.31) * 0.3) * flat_ground * wet;
		col *= mix(1.0, 0.6, wet);
		col = mix(col, col * 0.7, puddle);
		rough = mix(rough, 0.5, wet);
		rough = mix(rough, 0.08, puddle);
		spec = mix(spec, 0.35, wet);
	}
	// aerial perspective: surface light extinguished, horizon-coloured in-scatter added
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = fog_color * haze;
	ROUGHNESS = rough;
	SPECULAR = spec * (1.0 - haze);
}
