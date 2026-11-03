// Terrain detail materials for terrain.gdshader (docs/GRAPHICS-PLAN.md G6), after hash / vnoise.
// Tiling CC0 PBR sets per WorldCover class (tools/26_terrain_textures.py -> world/textures/terrain/), blended
// UNDER the satellite colour: det_mod holds a high-passed albedo *modulation* (0.5 = unchanged), det_nrm the
// normal (xy), roughness offset and AO. Two scales per layer at unrelated sizes and angles (no visible tiling),
// the two strongest classes around the fragment, rock projected on the vertical planes on steep slopes (Ghats
// cliffs), everything fading out by DET_FAR. Textures are bound once as shader defaults (TerrainDetail).
// Needs hash / vnoise, wc_tex and sd_tex (terrain_water.gdshaderinc) declared before it.

uniform sampler2DArray det_mod : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray det_nrm : filter_linear_mipmap_anisotropic, repeat_enable;

// layers (tools/26_terrain_textures.py LAYERS)
const int L_SOIL = 0, L_GRASS = 1, L_SCRUB = 2, L_LATERITE = 3, L_ROCK = 4, L_FOREST = 5, L_URBAN = 6,
	L_SAND = 7, L_MUD = 8, L_CONCRETE = 9, L_ASPHALT = 10;
const int DET_LAYERS = 11;
const float DET_NEAR = 650.0, DET_FAR = 1200.0;
// WorldCover class (terrain_landcover.gdshaderinc) -> layer, -1 = none (class 0, no data: scrub)
const int CLS_LAYER[12] = int[12](L_SCRUB, L_FOREST, L_SCRUB, L_GRASS, L_SOIL, L_URBAN, L_LATERITE, L_ROCK, -1, L_MUD, L_MUD, L_GRASS);
// per layer: x albedo strength, y normal strength, z size of the fine tile (m)
const vec3 DET_P[11] = vec3[11](
	vec3(0.9, 0.8, 3.1), vec3(0.8, 0.6, 2.3), vec3(1.0, 0.9, 3.3), vec3(0.9, 0.8, 2.7), vec3(1.0, 1.2, 6.5),
	vec3(0.8, 0.8, 3.0), vec3(0.9, 0.8, 3.4), vec3(0.8, 0.7, 4.1), vec3(0.8, 0.7, 3.2), vec3(0.9, 0.5, 2.9),
	vec3(0.8, 0.5, 2.1));

// WorldCover classes of the 4 texels around the fragment and their bilinear weights (sampling point warped by
// noise so the 10 m class borders are neither blocky nor straight). false when there is no class tile.
bool cls_corners(vec2 lc_uv, vec2 en, out ivec4 cc, out vec4 w) {
	cc = ivec4(0);
	w = vec4(1.0, 0.0, 0.0, 0.0);
	ivec2 wsz = textureSize(wc_tex, 0);
	if (wsz.x <= 1) {
		return false;
	}
	vec2 tc = lc_uv * vec2(wsz) - 0.5 + (vec2(vnoise(en * 0.045), vnoise(en * 0.045 + 31.7)) - 0.5) * 1.4;
	ivec2 i0 = ivec2(floor(tc));
	vec2 f = fract(tc);
	f = f * f * (3.0 - 2.0 * f);
	ivec2 hi = wsz - 1;
	cc = ivec4(int(texelFetch(wc_tex, clamp(i0, ivec2(0), hi), 0).r * 255.0 + 0.5),
		int(texelFetch(wc_tex, clamp(i0 + ivec2(1, 0), ivec2(0), hi), 0).r * 255.0 + 0.5),
		int(texelFetch(wc_tex, clamp(i0 + ivec2(0, 1), ivec2(0), hi), 0).r * 255.0 + 0.5),
		int(texelFetch(wc_tex, clamp(i0 + ivec2(1, 1), ivec2(0), hi), 0).r * 255.0 + 0.5));
	w = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	return true;
}

// one layer at three scales, each rotated and offset differently: fine (DET_P.z, the ground at your feet),
// mid (x 4.37) and coarse (x 19.3: clumps and patches seen from a few hundred metres). The fine scale is
// skipped beyond 160 m and the coarse one inside 40 m. Returns modulation (rgb, 1 = unchanged) in .rgb and AO
// in .a; n: tangent normal offset (east, north), r: roughness offset.
vec4 det_layer(int l, vec2 en, float dist, out vec2 n, out float r) {
	float s = DET_P[l].z, fl = float(l);
	float wf = 1.0 - smoothstep(25.0, 160.0, dist), wc = smoothstep(40.0, 350.0, dist);
	float wm = 1.0 - 0.5 * wc;
	mat2 r2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)), r3 = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28));
	vec4 m = texture(det_mod, vec3(r2 * en / (s * 4.37) + vec2(0.37, 0.71), fl)) * wm;
	vec4 o = texture(det_nrm, vec3(r2 * en / (s * 4.37) + vec2(0.37, 0.71), fl));
	vec2 nn = transpose(r2) * (o.xy * 2.0 - 1.0) * wm;
	vec2 ra = vec2(o.z - 0.5, o.w) * wm;
	if (wf > 0.0) {
		vec4 mf = texture(det_mod, vec3(en / s, fl)), of = texture(det_nrm, vec3(en / s, fl));
		m += mf * wf; nn += (of.xy * 2.0 - 1.0) * wf; ra += vec2(of.z - 0.5, of.w) * wf;
	}
	if (wc > 0.0) {
		vec2 uc = r3 * en / (s * 19.3) + vec2(0.13, 0.52);
		vec4 mc = texture(det_mod, vec3(uc, fl)), oc = texture(det_nrm, vec3(uc, fl));
		m += mc * wc; nn += transpose(r3) * (oc.xy * 2.0 - 1.0) * wc; ra += vec2(oc.z - 0.5, oc.w) * wc;
	}
	float tw = wm + wf + wc;
	n = nn / tw;
	r = ra.x / tw;
	return vec4(m.rgb / tw * 2.0, ra.y / tw);
}

// rock on the two vertical planes (and the ground plane) of a steep slope; wn: render-frame normal
vec4 det_rock_triplanar(vec3 wp, vec3 wn, out vec3 dn, out float r) {
	vec3 b = pow(abs(wn), vec3(4.0));
	b /= b.x + b.y + b.z;
	float s = DET_P[L_ROCK].z;
	float lr = float(L_ROCK);
	vec2 ux = vec2(wp.z, wp.y) / s, uz = vec2(wp.x, wp.y) / s + 0.5, uy = vec2(wp.x, -wp.z) / s;
	vec4 mx = vec4(texture(det_mod, vec3(ux, lr)).rgb, 0.0), mz = vec4(texture(det_mod, vec3(uz, lr)).rgb, 0.0);
	vec4 my = vec4(texture(det_mod, vec3(uy, lr)).rgb, 0.0);
	vec4 ox = texture(det_nrm, vec3(ux, lr)), oz = texture(det_nrm, vec3(uz, lr)), oy = texture(det_nrm, vec3(uy, lr));
	vec2 nx = ox.xy * 2.0 - 1.0, nz = oz.xy * 2.0 - 1.0, ny = oy.xy * 2.0 - 1.0;
	// tangent offsets in the render frame (x east, y up, z south) for each projection
	dn = vec3(0.0, nx.y, nx.x) * b.x + vec3(nz.x, nz.y, 0.0) * b.z + vec3(ny.x, 0.0, -ny.y) * b.y;
	r = (ox.z * b.x + oz.z * b.z + oy.z * b.y) - 0.5;
	vec3 m = (mx.rgb * b.x + mz.rgb * b.z + my.rgb * b.y) * 2.0;
	return vec4(m, ox.w * b.x + oz.w * b.z + oy.w * b.y);
}

// Detail for natural ground. col: ground colour so far, wn: render-frame normal, wp: world position (east, up,
// -north), cc / cw: class corners, k: class fade (0 on water / pavement). Returns the new colour; dn: normal
// offset (render frame) for the caller to add, dr: roughness offset.
vec3 terrain_detail(vec3 col, vec3 wn, vec3 wp, ivec4 cc, vec4 cw, vec2 lc_uv, vec2 en, float dist, float k,
		out vec3 dn, out float dr) {
	dn = vec3(0.0);
	dr = 0.0;
	k *= 1.0 - smoothstep(DET_NEAR, DET_FAR, dist);
	if (k <= 0.001) {
		return col;
	}
	// layer weights over the 4 corners; land near the sea is sand (sd_tex: metres from the shore, terrain_water)
	float shore = textureSize(sd_tex, 0).x > 1 ? smoothstep(-70.0, -25.0, texture(sd_tex, lc_uv).r * 255.0 - 128.0) : 0.0;
	float lw[11] = float[11](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
	int cls4[4] = int[4](cc.x, cc.y, cc.z, cc.w);
	float w4[4] = float[4](cw.x, cw.y, cw.z, cw.w);
	for (int i = 0; i < 4; i++) {
		int cl = cls4[i];
		int l = CLS_LAYER[clamp(cl, 0, 11)];
		float sand = (cl == 1 || cl == 5) ? shore * 0.3 : shore;
		if (l >= 0) {
			lw[l] += w4[i] * (1.0 - sand);
		}
		lw[L_SAND] += w4[i] * sand;
	}
	// the two strongest layers; the third's weight is subtracted from both so a change of rank is seamless
	int a = 0, b = 1;
	float wa = -1.0, wb = -1.0, wc = 0.0;
	for (int l = 0; l < DET_LAYERS; l++) {
		float v = lw[l];
		if (v > wa) { wc = wb; b = a; wb = wa; a = l; wa = v; }
		else if (v > wb) { wc = wb; b = l; wb = v; }
		else if (v > wc) { wc = v; }
	}
	wc = max(wc, 0.0);
	wa = max(wa - wc, 0.0);
	wb = max(wb - wc, 0.0);
	vec2 n2 = vec2(0.0);
	float r = 0.0;
	vec4 m = vec4(1.0);
	float sa = 0.0, sn = 0.0;
	if (wa > 0.0) {
		vec2 na; float ra;
		vec4 ma = det_layer(a, en, dist, na, ra);
		float t = wa / max(wa + wb, 1e-4);
		m = ma; n2 = na; r = ra;
		sa = DET_P[a].x; sn = DET_P[a].y;
		if (wb > 0.02) {
			vec2 nb; float rb;
			vec4 mb = det_layer(b, en, dist, nb, rb);
			m = mix(mb, ma, t); n2 = mix(nb, na, t); r = mix(rb, ra, t);
			sa = mix(DET_P[b].x, sa, t); sn = mix(DET_P[b].y, sn, t);
		}
		m.rgb = mix(vec3(1.0), m.rgb, sa);
		dn = vec3(n2.x, 0.0, -n2.y) * sn;  // east, north -> render x, -z
	}
	// steep slopes: rock, projected so cliffs are not stretched
	float steep = smoothstep(0.2, 0.45, 1.0 - wn.y);
	if (steep > 0.0) {
		vec3 rn; float rr;
		vec4 mr = det_rock_triplanar(wp, wn, rn, rr);
		m = mix(m, vec4(mix(vec3(1.0), mr.rgb, DET_P[L_ROCK].x), mr.a), steep);
		dn = mix(dn, rn * DET_P[L_ROCK].y, steep);
		r = mix(r, rr, steep);
	}
	dn *= k;
	dr = r * 0.6 * k;
	return col * mix(vec3(1.0), m.rgb * mix(1.0, m.a, 0.45), k);
}
