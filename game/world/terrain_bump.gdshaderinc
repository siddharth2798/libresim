// Visual ground bump for terrain.gdshader (GRAPHICS-PLAN G9). Fractal value noise, at most PEAK metres,
// full within 1 km of the camera and gone at 2 km. Added along world up (curve_local of a negative drop).
// Not a height sample: TerrainQuadtree.height_at / the height tiles never see it.
// Keep the distances in sync with TerrainBump (FULL_M 1000, FAR_M 2000, peak 2 / 1 / 0).
// terrain_bump_amp is that peak in metres (TerrainQuadtree sets it from Graphics.preset).
#ifndef TERRAIN_BUMP_INC
#define TERRAIN_BUMP_INC
global uniform float terrain_bump_amp;

const float BUMP_FULL = 1000.0;
const float BUMP_FAR = 2000.0;
const float BUMP_STEP = 8.0;   // neighbourhood step (m); pavement SDF reaches 8 m, roads 4 m
const float BUMP_CELL = 32.0;  // metres per grid edge above which a ribbon can hide between vertices

// Three octaves, weights 0.5+0.25+0.125 = 0.875, so the signed result stays in [-1, 1]
// and the displacement stays within terrain_bump_amp (at most 2 m).
float bump_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bump_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(bump_hash(i), bump_hash(i + vec2(1.0, 0.0)), f.x);
	float b = mix(bump_hash(i + vec2(0.0, 1.0)), bump_hash(i + vec2(1.0, 1.0)), f.x);
	return mix(a, b, f.y);
}

float bump_signed(vec2 en) {
	float a = 0.5;
	float s = 0.0;
	vec2 p = en * (1.0 / 160.0);
	for (int i = 0; i < 3; i++) {
		s += a * bump_vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return (s / 0.875 - 0.5) * 2.0;
}

float bump_fade(float dist) {
	if (dist >= BUMP_FAR) {
		return 0.0;
	}
	return 1.0 - smoothstep(BUMP_FULL, BUMP_FAR, dist);
}

// Pavement (pv mask or the apron mask), a road / river ribbon, or land-class water.
bool bump_hit(vec2 uv, vec2 en) {
	if (apron_mask_box.z > 0.0 && apron_mask_box.w > 0.0) {
		vec2 q = (en - apron_mask_box.xy) / apron_mask_box.zw * vec2(1.0, -1.0) + vec2(0.0, 1.0);
		if (q.x >= 0.0 && q.y >= 0.0 && q.x <= 1.0 && q.y <= 1.0 && texture(apron_mask, q).r > 0.15) {
			return true;
		}
	}
	vec2 ruv = ro_rect.xy + vec2(uv.x, -uv.y) * ro_rect.z;
	if (pv_on > 0.5) {
		float e = texture(pv_tex, ruv).r * 16.0 - 8.0;  // negative inside the apron / runway
		if (e < 6.0) {
			return true;
		}
	}
	if (ro_on > 0.5) {
		float re = texture(ro_tex, ruv).r * 40.8 - 6.0;
		ivec2 sz = textureSize(ro_tex, 0);
		ivec2 tc = clamp(ivec2(ruv * vec2(sz)), ivec2(0), sz - 1);
		int cls = int(texelFetch(ro_tex, tc, 0).a * 255.0 + 0.5);
		if (cls > 0 && re < 4.0) {
			return true;  // road (1..9) or river (10+): the SDF is only stored out to +4 m
		}
	}
	vec2 lcu = lc_off + vec2(uv.x, -uv.y) * lc_scale;
	return texture(lc_tex, lcu).r >= 0.88;  // same start as the fragment water blend; 255 = water
}

// True when this vertex's triangles might cover pavement, a road or water, or we cannot tell.
bool bump_blocked(vec2 uv, vec2 en) {
	if (pv_on < 0.5 && ro_on < 0.5) {
		return true;  // pavement mask is not bound on this node: do not guess
	}
	if (tile_size / 64.0 > BUMP_CELL) {
		return true;  // coarser than the near ring: a runway can sit between vertices
	}
	for (int j = -3; j <= 3; j++) {
		for (int i = -3; i <= 3; i++) {
			vec2 o = vec2(float(i), float(j)) * BUMP_STEP;
			if (bump_hit(uv + vec2(o.x, o.y) / tile_size, en + o)) {
				return true;
			}
		}
	}
	return false;
}

// (metres up, dh/deast, dh/dnorth). Zero on skirts and wherever bump_blocked says so.
vec3 terrain_bump(vec2 uv, float skirt, vec3 wp) {
	if (skirt > 0.5 || terrain_bump_amp <= 0.0) {
		return vec3(0.0);
	}
	float amp = terrain_bump_amp * bump_fade(distance(wp, terrain_eye));
	if (amp <= 0.0) {
		return vec3(0.0);
	}
	vec2 en = vec2(wp.x + pattern_origin.x, -wp.z + pattern_origin.y);
	if (bump_blocked(uv, en)) {
		return vec3(0.0);
	}
	float y = bump_signed(en) * amp;
	float de = (bump_signed(en + vec2(4.0, 0.0)) - bump_signed(en - vec2(4.0, 0.0))) / 8.0 * amp;
	float dn = (bump_signed(en + vec2(0.0, 4.0)) - bump_signed(en - vec2(0.0, 4.0))) / 8.0 * amp;
	return vec3(y, de, dn);
}
#endif
