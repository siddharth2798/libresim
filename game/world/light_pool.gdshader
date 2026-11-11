shader_type spatial;
// Fake floodlight from one apron floodlight bank (world/apron_floodlights.gd), drawn as a light volume: a box
// around the cone's footprint; each pixel's surface is rebuilt from the depth buffer and gets what the real
// SpotLight of ApronLamps would give it, with Godot's own spot terms (so real and fake match and sum to one
// level across the cross-fade): inverse square from the lamp head with the range window, cos of incidence on
// the surface (normal from screen derivatives) and the cone 1 - rim^CONE_EXP, relative to the aim point on the
// ground. So the pool is brightest at and just short of the aim, dims between masts and toward the cone edge,
// lies on the ground whatever the terrain LOD (no quad edges, no z-fighting), and also lights vehicles and
// aircraft inside the volume. Additive, near-neutral colour. It fades out where ApronLamps lights the bank with
// a real SpotLight (real_in .. real_out from the camera).
// Per instance: COLOR.rgb lamp colour, COLOR.a gain; CUSTOM = (lamp height above the box centre, lamp offset
// behind the box centre, cos of the spot cone angle (ApronLamps.cone_deg), aim offset ahead of the box centre).
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_front, fog_disabled, shadows_disabled;

global uniform float haze_density;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float level = 1.0;
uniform float strength = 0.093;  // pool at the aim point; ApronLamps.ENERGY is the real lamp's
uniform vec3 real_eye = vec3(0.0);  // camera, render frame
uniform float real_in = -1.0;  // lamps nearer than this to real_eye: real light only (no pool); < 0: none
uniform float real_out = -1.0;  // full pool from here out
const float VOL_BELOW = 12.0;  // ApronFloodlights.VOL_BELOW / VOL_ABOVE
const float VOL_ABOVE = 20.0;
const float CONE_EXP = 1.0;  // ApronLamps.CONE_EXP (spot_angle_attenuation)
const float RANGE_K = 2.2;  // ApronLamps.RANGE_K: spot range = throw x RANGE_K

// Godot's spot light terms (scene_forward_lights_inc): range window x inverse square, and the cone.
float spot_dist(float d, float range) {
	float nd = d / range;
	nd *= nd;
	nd *= nd;
	nd = max(1.0 - nd, 0.0);
	return nd * nd / (d * d);
}
float spot_cone(float scos, float cone_cos) {
	float rim = max(1e-4, (1.0 - max(scos, cone_cos)) / (1.0 - cone_cos));
	return 1.0 - pow(rim, CONE_EXP);
}

varying vec3 v_c;
varying vec3 v_ax;
varying vec3 v_ay;
varying vec3 v_az;
varying vec3 v_lamp;
varying vec3 v_aim;
varying vec3 v_col;
varying float v_cos;

void vertex() {
	v_c = MODEL_MATRIX[3].xyz;
	v_ax = MODEL_MATRIX[0].xyz;
	v_ay = MODEL_MATRIX[1].xyz;
	v_az = MODEL_MATRIX[2].xyz;
	vec3 ax = normalize(v_az);
	v_lamp = v_c - ax * INSTANCE_CUSTOM.y + vec3(0.0, INSTANCE_CUSTOM.x, 0.0);
	v_aim = v_c + ax * INSTANCE_CUSTOM.w - vec3(0.0, (VOL_ABOVE - VOL_BELOW) * 0.5, 0.0);
	v_cos = INSTANCE_CUSTOM.z;
	float fake = real_out > 0.0 ? smoothstep(real_in, real_out, length(v_lamp - real_eye)) : 1.0;
	float trans = exp(-length(INV_VIEW_MATRIX[3].xyz - v_c) * haze_density * 1.6);
	v_col = COLOR.rgb * COLOR.a * fake * trans;
}

void fragment() {
	if (level <= 0.0) {
		discard;  // daylight: the pools add nothing (uniform for the whole quad: derivatives below stay valid)
	}
	// The surface position from the depth buffer, and its screen derivatives for the normal, are computed for
	// every lane BEFORE any lane may discard: a 2x2 quad with a discarded lane has undefined derivatives, and that
	// garbage differed from frame to frame, so every silhouette inside a pool flickered (docs/FLICKER-PLAN.md
	// phase 2). Sky pixels (reverse Z: depth 0, view.w 0) are given a finite far position for the same reason.
	float depth = texture(depth_tex, SCREEN_UV).r;
	bool sky = depth <= 1e-7;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, max(depth, 1e-7), 1.0);
	view.xyz /= view.w;
	vec3 wp = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec3 ddx = dFdx(wp);
	vec3 ddy = dFdy(wp);
	vec3 r = wp - v_c;
	vec3 q = vec3(dot(r, v_ax) / dot(v_ax, v_ax), dot(r, v_ay) / dot(v_ay, v_ay), dot(r, v_az) / dot(v_az, v_az));
	if (sky || max(abs(q.x), max(abs(q.y), abs(q.z))) > 1.0 || max(v_col.r, max(v_col.g, v_col.b)) < 1e-4) {
		discard;
	}
	// Across a depth discontinuity (a silhouette) the derivatives span metres and the cross product is meaningless;
	// the ground the pools light is flat, so an up normal is the right fallback there and where both vanish.
	vec3 c = cross(ddx, ddy);
	if (dot(c, c) < 1e-20 || dot(ddx, ddx) > 0.25 || dot(ddy, ddy) > 0.25) {
		c = vec3(0.0, 1.0, 0.0);
	}
	vec3 n = normalize(c);
	vec3 to_lamp = v_lamp - wp;
	float d = max(length(to_lamp), 0.5);
	vec3 l = to_lamp / d;
	if (dot(n, INV_VIEW_MATRIX[3].xyz - wp) < 0.0) {
		n = -n;  // the derivative order may flip it: a visible surface faces the camera
	}
	float ndl = max(dot(n, l), 0.0);  // faces turned away from the lamp stay dark
	vec3 axis = normalize(v_aim - v_lamp);
	vec3 ta = v_lamp - v_aim;
	float da = length(ta);
	float ndl_aim = max(ta.y / da, 0.05);  // flat ground at the aim point
	float range = da * RANGE_K;
	// irradiance relative to the aim point (what the real lamp gives there)
	float e = ndl * spot_dist(d, range) * spot_cone(dot(-l, axis), v_cos) / (ndl_aim * spot_dist(da, range));
	vec2 edge2 = smoothstep(vec2(1.0), vec2(0.7), abs(q.xz));
	ALBEDO = v_col * (e * edge2.x * edge2.y * strength * level);
	ALPHA = 1.0;
}
