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
uniform sampler2D lc_tex : filter_linear, repeat_disable;  // land class: 255 = water, 1..200 tree density
// ESA WorldCover class per texel (tools/19_worldcover.py), same source tile / lc_off / lc_scale as lc_tex;
// 1x1 when absent. Read with texelFetch and blended per class parameter, never filtered as classes.
uniform sampler2D wc_tex : filter_nearest, repeat_disable;
#include "res://world/terrain_landcover.gdshaderinc"
global uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;  // CloudLayer coverage noise
global uniform vec4 cloud_shadow;   // x cloud base (m), y coverage, z shadow strength
global uniform vec2 cloud_uv_off;   // noise phase of the pattern frame (wrap base + wind drift)
global uniform vec3 cloud_sun;      // towards the sun, render frame

varying float v_dist;
varying float v_alt;  // absolute altitude of the vertex (render y)
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
	v_alt = wr.y;
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

// Class-driven ground detail: 30 m tonal blobs, crop parcels with furrows, built-up speckle and
// slope-following streaks. Each layer fades out before it would alias or shimmer.
vec3 ground_detail(vec3 col, vec3 wn, vec4 amp, float streak, float k) {
	if (k <= 0.0) { return col; }
	float d = v_dist;
	float blob_k = (1.0 - smoothstep(500.0, 2800.0, d)) * k;
	if (blob_k > 0.0 && amp.y > 0.0) {
		float p = fbm(v_en * 0.031 + 5.3) - 0.5;
		col *= (1.0 + p * 0.24 * amp.y * blob_k) * vec3(1.0 + p * 0.1 * blob_k, 1.0, 1.0 - p * 0.1 * blob_k);
	}
	float parcel_k = (1.0 - smoothstep(700.0, 3200.0, d)) * amp.z * k;
	if (parcel_k > 0.0) {
		// rectangular field parcels, warped so they are not a grid; each has its own tone and furrows
		vec2 pp = mat2(vec2(0.94, -0.34), vec2(0.34, 0.94)) * v_en + (vec2(vnoise(v_en * 0.012), vnoise(v_en * 0.012 + 9.1)) - 0.5) * 36.0;
		vec2 ps = vec2(78.0, 49.0);
		vec2 cell = floor(pp / ps);
		float h1 = hash(cell), h2 = hash(cell + 7.7), h3 = hash(cell + 19.1);
		vec3 tone = mix(vec3(0.82, 1.08, 0.78), vec3(1.18, 1.0, 0.82), smoothstep(0.2, 0.8, h1));  // green crop vs ploughed / dry
		col *= mix(vec3(1.0), tone * (0.82 + 0.36 * h2), parcel_k);
		float fk = (1.0 - smoothstep(110.0, 420.0, d)) * amp.z * k;
		if (fk > 0.0) {
			vec2 e = min(fract(pp / ps), 1.0 - fract(pp / ps)) * ps;
			col *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 1.8, min(e.x, e.y))) * fk;  // bunds between parcels
			float a = h3 * 3.14159;
			float fur = sin(dot(v_en, vec2(cos(a), sin(a))) * 6.2832 / (1.8 + 1.6 * h1) + vnoise(v_en * 0.15) * 3.0);
			col *= 1.0 + fur * 0.085 * fk * step(0.3, h2);
		}
	}
	float block_k = (1.0 - smoothstep(450.0, 1500.0, d)) * amp.w * k;
	if (block_k > 0.0) {
		float hb = hash(floor(v_en / 6.5 + vnoise(v_en * 0.08) * 0.6));
		col *= (1.0 + (hb - 0.5) * 0.26 * block_k + (hash(floor(v_en / 23.0)) - 0.5) * 0.12 * block_k)
			* mix(vec3(1.0), mix(vec3(0.97, 0.98, 1.03), vec3(1.04, 1.0, 0.95), hb), block_k * 0.8);
	}
	float slope = smoothstep(0.04, 0.3, 1.0 - wn.y);
	if (slope > 0.0 && streak > 0.0) {
		vec2 dn = normalize(vec2(wn.x, -wn.z) + vec2(1e-4));  // downhill, (east, north)
		vec2 u = vec2(dot(v_en, vec2(-dn.y, dn.x)), dot(v_en, dn));
		float sv = vnoise(u * vec2(0.3, 0.03) + 11.0) * 0.55 + mix(0.5, vnoise(u * vec2(1.1, 0.09)), 1.0 - smoothstep(250.0, 900.0, d)) * 0.45;
		col *= 1.0 + (sv - 0.5) * 0.7 * streak * slope * k * (1.0 - smoothstep(600.0, 3000.0, d));
	}
	return col;
}

#include "res://world/terrain_roads.gdshaderinc"
#include "res://world/terrain_water.gdshaderinc"

void fragment() {
	vec2 uv = img_off + vec2(UV.x, -UV.y) * img_scale;
	vec2 lc_uv = lc_off + vec2(UV.x, -UV.y) * lc_scale;
	vec3 col = texture(img_tex, uv).rgb;
	// Sentinel-2 mosaics are dark and slightly blue-shifted; lift for daylight.
	col = pow(col, vec3(0.85)) * 1.15;
	float water = smoothstep(0.88, 0.97, texture(lc_tex, lc_uv).r);
	// road / river ribbons from the signed-distance tile (terrain_roads.gdshaderinc): crisp edges whatever the
	// imagery shows; rivers join the water branch below, roads are painted over the ground further down
	float ro_e = 8.0, road = 0.0, river = 0.0, bank = 0.0;
	int ro_cls = 0;
	float ro_aa = clamp(v_dist * 0.0011, 0.04, 1.6);  // ~ one pixel in metres
	if (ro_on > 0.5 && v_dist < 3400.0) {
		ro_fetch(ro_rect.xy + vec2(UV.x, -UV.y) * ro_rect.z, ro_e, ro_cls);
		float ro_k = 1.0 - smoothstep(1500.0, 3300.0, v_dist);
		float cover = ro_cls > 0 ? (1.0 - smoothstep(-ro_aa, ro_aa, ro_e)) * ro_k : 0.0;
		if (ro_cls >= 10) {
			river = cover * (1.0 - water);
			bank = (1.0 - smoothstep(0.0, 1.5, ro_e)) * ro_k * (1.0 - cover);
		} else {
			road = cover;
		}
		water = max(water, river);
	}
	float land = 1.0 - water;
	// forest floor: dense tree cover (land class 1..200) darkens and greens the imagery under the canopy;
	// with WorldCover the tree class tint does most of this, so the density term is only a hint
	float forest = smoothstep(0.1, 0.6, texture(lc_tex, lc_uv).r * 1.275) * land;
	col = mix(col, col * vec3(0.8, 0.95, 0.72) * 0.85, forest * (textureSize(wc_tex, 0).x > 1 ? 0.3 : 0.6));
	// land cover: class parameters from the 4 texels around the fragment, weights smoothed and the
	// sampling point warped by noise so 10 m class borders are neither blocky nor straight
	float cls_k = (1.0 - smoothstep(5000.0, 12000.0, v_dist)) * land;
	vec3 c_tint = vec3(1.0);
	float c_desat = 0.0, c_streak = 0.15;
	vec4 c_amp = vec4(1.0, 0.0, 0.0, 0.0);  // class 0 = the plain ground look
	ivec2 wsz = textureSize(wc_tex, 0);
	if (cls_k > 0.0 && wsz.x > 1) {
		vec2 tc = lc_uv * vec2(wsz) - 0.5 + (vec2(vnoise(v_en * 0.045), vnoise(v_en * 0.045 + 31.7)) - 0.5) * 1.4;
		ivec2 i0 = ivec2(floor(tc));
		vec2 f = fract(tc);
		f = f * f * (3.0 - 2.0 * f);
		ivec2 hi = wsz - 1;
		ivec4 cc = ivec4(int(texelFetch(wc_tex, clamp(i0, ivec2(0), hi), 0).r * 255.0 + 0.5),
			int(texelFetch(wc_tex, clamp(i0 + ivec2(1, 0), ivec2(0), hi), 0).r * 255.0 + 0.5),
			int(texelFetch(wc_tex, clamp(i0 + ivec2(0, 1), ivec2(0), hi), 0).r * 255.0 + 0.5),
			int(texelFetch(wc_tex, clamp(i0 + ivec2(1, 1), ivec2(0), hi), 0).r * 255.0 + 0.5));
		vec4 w = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
		cls_blend(min(cc, ivec4(11)), w, c_tint, c_desat, c_amp, c_streak);
	}
	col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), c_desat * cls_k);
	col *= mix(vec3(1.0), c_tint, cls_k);
	// macro: slow tonal drift (m-scale to km-scale) so far ground is not a flat smear
	float macro = fbm(v_en * 0.0011) - 0.5 + 0.6 * (fbm(v_en * 0.011) - 0.5);
	col *= 1.0 + macro * 0.5 * land * smoothstep(300.0, 2500.0, v_dist);
	// micro: soft grain and relief within a kilometre
	float near_k = 1.0 - smoothstep(250.0, 1400.0, v_dist);
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;  // ground normal, render frame (x east, y up)
	if (near_k > 0.0 && land * (1.0 - road) > 0.0) {
		vec2 q = v_en * 0.8;
		float grain = (fbm(q) - 0.5) * 0.5 + (fbm(v_en * 0.15) - 0.5) * 0.9;
		col *= 1.0 + grain * 0.22 * land * (1.0 - road) * near_k * c_amp.x;
		vec2 e = vec2(0.6, 0.0);
		vec2 mg = vec2(fbm(q + e.xy) - fbm(q - e.xy), fbm(q + e.yx) - fbm(q - e.yx));
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(-mg.x, 0.0, mg.y, 0.0)).xyz * 0.25 * land * (1.0 - 0.8 * road) * near_k * (0.5 + 0.5 * c_amp.x));
	}
	col = ground_detail(col, wn, c_amp, c_streak, cls_k);
	col *= 1.0 - 0.3 * bank;  // wet river bank
	float rough = 0.95;
	float spec = 0.1;
	if (road > 0.0) {
		col = mix(col, road_surface(ro_cls, ro_e + RO_HW[ro_cls], ro_aa, v_dist, v_en), road);
		rough = mix(rough, 0.72, road);
		spec = mix(spec, 0.2, road);
	}
	// cloud shadows: where the sun's ray to this ground point crosses the cloud layer's coverage noise
	if (cloud_shadow.z > 0.0 && cloud_sun.y > 0.08) {
		float t = (cloud_shadow.x + 360.0 - v_alt) / cloud_sun.y;
		if (t > 0.0 && t < 80000.0) {
			vec2 q = (v_en + vec2(cloud_sun.x, -cloud_sun.z) * t) / 9000.0 + cloud_uv_off;
			float cov = textureLod(cloud_noise, q, 0.0).r - (1.0 - cloud_shadow.y) * 0.82;
			float sh = smoothstep(0.0, 0.45, cov * 2.6 - 0.2) * cloud_shadow.z * smoothstep(0.08, 0.3, cloud_sun.y);
			col *= 1.0 - 0.55 * sh * (1.0 - 0.6 * water);
		}
	}
	if (water > 0.0) {
		vec4 sd4 = texture(sd_tex, lc_uv);
		float sea = 1.0 - river / max(water, 0.001);  // 0 on river ribbons, which have no shore data
		float sd_m = sd4.r * 255.0 - 128.0;
		float chop = mix(0.28, 1.0, smoothstep(0.08, 0.4, sd4.g));  // sheltered water is calmer
		vec2 g = wave_grad(v_en, TIME) * 1.4 * chop * (1.0 - smoothstep(150.0, 2500.0, v_dist));
		vec3 nw = normalize(vec3(-g.x, 1.0, g.y));  // render frame: x east, y up, z south
		vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(nv, VIEW), 0.0, 1.0), 4.0);
		vec3 deep = vec3(0.05, 0.13, 0.15);  // Arabian Sea: grey-green-blue
		vec3 sat = col * 0.75;  // keep the satellite tint near coasts and creeks
		vec3 base = mix(mix(deep, sat, 0.4), vec3(0.045, 0.085, 0.065), 1.0 - sea);  // green-brown ribbons
		// shoals: turquoise near the shore (blended with what the imagery shows), deep offshore
		float shoal = exp(-max(sd_m, 0.0) / 55.0) * sea;
		base = mix(base, mix(vec3(0.05, 0.26, 0.25), col * 0.9, 0.45), shoal * 0.8);
		vec3 sky = mix(sky_top_color, fog_color, 0.35);
		vec3 wcol = mix(base, sky, clamp(fres * 0.75 + 0.04, 0.0, 0.85));
		col = mix(col, wcol, water);
		float foam = shore_foam(sd_m, sd4.g, v_en, v_dist, TIME) * sea * water;
		col = mix(col, vec3(0.92, 0.95, 0.96), foam);
		NORMAL = normalize(mix(NORMAL, nv, water));
		rough = mix(rough, 0.06 + 0.14 * precip, water);  // rain roughens the surface
		rough = mix(rough, 0.75, foam);
		spec = mix(spec, 0.6, water);
		spec = mix(spec, 0.15, foam);
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
