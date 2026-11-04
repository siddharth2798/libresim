shader_type spatial;
// Procedural ground vehicles (world/ground_vehicles.gd): one material for every opaque part of every
// kind; the surface model is world/vehicle_surface.gdshaderinc. Per vehicle (instance uniforms):
// seed (fleet number, dirt, beacon phase), lamps (working: beacon turning, headlamps at night),
// wheel_turn (metres rolled) and steer (rad, right positive) for a vehicle that drives
// (world/vehicle_motion.gd): wheel vertices carry their hub in CUSTOM0 and turn about it here.
render_mode fog_disabled;

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;

#include "res://world/vehicle_surface.gdshaderinc"

instance uniform float seed = 0.0;
instance uniform float lamps = 0.0;
instance uniform float wheel_turn = 0.0;
instance uniform float steer = 0.0;

varying vec3 v_pos;
varying vec3 v_nl;
varying vec3 v_eye;
varying vec4 v_piv;
varying float v_dist;

void vertex() {
	v_pos = VERTEX;
	v_nl = NORMAL;
	v_piv = CUSTOM0;
	if (CUSTOM0.w > 0.0 && CUSTOM0.w < 50.0) {  // a wheel: roll about its hub, steer the front ones
		float r = CUSTOM0.w;
		float st = 0.0;
		if (r > 20.0) {
			r -= 20.0;
			st = -steer;
		}
		float a = -wheel_turn / r;
		mat3 roll = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(a), sin(a)), vec3(0.0, -sin(a), cos(a)));
		mat3 yaw = mat3(vec3(cos(st), 0.0, -sin(st)), vec3(0.0, 1.0, 0.0), vec3(sin(st), 0.0, cos(st)));
		VERTEX = CUSTOM0.xyz + yaw * (roll * (VERTEX - CUSTOM0.xyz));
		NORMAL = yaw * (roll * NORMAL);
	}
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_eye = transpose(mat3(MODEL_MATRIX)) * (CAMERA_POSITION_WORLD - wp);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	int kind = int(COLOR.a * 10.0 + 0.5);
	vec3 col = COLOR.rgb;
	vec3 emit;
	float rough;
	float metal;
	float spec;
	float cc;
	float ccr;
	float ao;
	float lit = lamps * night;
	vehicle_surface(kind, v_pos, v_nl, UV, v_piv, v_eye, v_dist, seed, lamps, col, emit, rough, metal, spec, cc, ccr, ao);
	if (kind == 8) emit *= lit;  // headlamps: only a working vehicle, only at night
	if (kind == 9) emit *= mix(0.15, 1.0, lit);
	float haze = 1.0 - exp(-v_dist * haze_density);
	col *= mix(1.0, 0.8, wetness);
	ALBEDO = col * (1.0 - haze);
	EMISSION = emit * (1.0 - haze * 0.5) + fog_color * haze;
	ROUGHNESS = mix(rough, rough * 0.5, wetness * 0.6);
	SPECULAR = spec * (1.0 - haze);
	METALLIC = metal;
	CLEARCOAT = cc * (1.0 - haze);
	CLEARCOAT_ROUGHNESS = ccr;
	AO = ao;
	AO_LIGHT_AFFECT = 0.25;
}
