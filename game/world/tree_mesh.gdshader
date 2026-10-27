shader_type spatial;
render_mode cull_disabled, fog_disabled;
// LOD0 tree mesh (TreeMeshes), instanced by TreeLod within lod_r metres of the camera; it casts and
// receives sun shadows. COLOR.rgb = base colour with baked occlusion, COLOR.a = part (0 bark, 0.5 leaf
// lumps, 1 palm frond). INSTANCE_CUSTOM: r = tint, b = tint 2, a = seed (shapes differ per tree through
// a noise displacement of the crown lumps). Dithers in with the opposite pattern to tree.gdshader.

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;
global uniform vec3 terrain_eye;  // camera, render space (same in shadow passes)

uniform float lod_r = 0.0;
uniform float lod_band = 8.0;

varying vec4 v_col;
varying vec4 v_cust;
varying vec3 v_local;
varying float v_dist;
varying float v_od;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	v_col = COLOR;
	v_cust = INSTANCE_CUSTOM;
	v_local = VERTEX;
	float seed = INSTANCE_CUSTOM.a;
	if (COLOR.a > 0.25 && COLOR.a < 0.75) {  // lumpy crowns: no two trees alike
		float d = vnoise(VERTEX.xz * 5.0 + VERTEX.y * 3.1 + seed * 37.0) - 0.5;
		VERTEX += NORMAL * (d * 0.2 + (vnoise(VERTEX.xz * 14.0 + VERTEX.y * 9.0 + seed * 5.0) - 0.5) * 0.06);
	}
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = TIME * 1.3 + wp.x * 0.05 + wp.z * 0.07;
	VERTEX.x += sin(ph) * 0.012 * VERTEX.y * VERTEX.y;
	if (COLOR.a > 0.75) {
		VERTEX.y += sin(TIME * 2.1 + VERTEX.x * 9.0 + seed * 20.0) * 0.006 * UV.y;
	}
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_od = distance(terrain_eye, MODEL_MATRIX[3].xyz);
}

void fragment() {
	float dn = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (dn < smoothstep(lod_r - lod_band, lod_r, v_od)) {
		discard;
	}
	float kind = v_col.a;
	vec3 col = v_col.rgb;
	float bl = 0.0;
	if (kind > 0.75) {
		float comb = 0.55 + 0.45 * abs(sin(UV.y * 34.0));
		float edge = abs(UV.x * 2.0 - 1.0);
		if (edge > comb * (1.0 - 0.35 * UV.y) && edge > 0.07) {
			discard;
		}
		col *= 0.85 + 0.3 * vnoise(vec2(UV.y * 40.0, UV.x * 6.0));
		bl = 0.4;
	} else if (kind > 0.25) {
		// leaf clumps: mottle fading to its mean with distance, tinted per tree
		float m = vnoise(v_local.xz * 24.0 + v_local.y * 17.0 + v_cust.a * 9.0) * vnoise(v_local.xy * 11.0 + v_cust.a * 3.0);
		m = mix(0.55 + 0.9 * m, 0.85, smoothstep(40.0, 130.0, v_dist));
		// ragged silhouette: leaf gaps eat into the rim of a lump (also in the shadow, so shadows are dappled)
		float rim = 1.0 - abs(dot(NORMAL, normalize(VIEW)));
		if (vnoise(v_local.xz * 34.0 + v_local.y * 29.0 + v_cust.a * 7.0) < smoothstep(0.5, 1.0, rim) * 0.85 * (1.0 - smoothstep(60.0, 140.0, v_dist))) {
			discard;
		}
		vec3 tint = mix(vec3(0.75 + v_cust.r * 0.6), vec3(1.0, 0.95, 0.55) * (0.8 + v_cust.r * 0.5), v_cust.b * 0.5);
		col *= tint * m;
		bl = 0.45;
	} else {
		col *= 0.75 + 0.5 * vnoise(v_local.xy * vec2(160.0, 18.0) + v_local.z * 100.0);
	}
	col *= mix(1.0, 0.8, wetness);
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = fog_color * haze;
	ROUGHNESS = mix(0.9, 0.55, wetness);
	SPECULAR = mix(0.05, 0.25, wetness) * (1.0 - haze);
	BACKLIGHT = col * bl;
}
