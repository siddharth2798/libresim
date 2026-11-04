shader_type spatial;
// Follow-me car body (world/follow_me_shell.gd, follow_me_wheel.gd). Surface model and material kinds:
// world/vehicle_surface.gdshaderinc (shared with the other ground vehicles, world/vehicle.gdshader); the
// pickup adds its door / hood panel gaps here. Haze is applied here (aerial perspective, as
// terminal.gdshader) so the car fades into the same horizon as the terrain and the sky.
render_mode fog_disabled;

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform float wetness;

#include "res://world/vehicle_surface.gdshaderinc"

uniform float panel_gaps = 1.0;  // door / hood gap lines (the pickup's)
uniform float seed = 0.31;

varying vec3 v_pos;
varying vec3 v_nl;
varying vec3 v_eye;
varying float v_dist;

void vertex() {
	v_pos = VERTEX;
	v_nl = NORMAL;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_eye = transpose(mat3(MODEL_MATRIX)) * (CAMERA_POSITION_WORLD - wp);
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

float gap_line(float d) { return 1.0 - smoothstep(0.0012, 0.0035, d); }

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
	vehicle_surface(kind, v_pos, v_nl, UV, vec4(0.0), v_eye, v_dist, seed, 1.0, col, emit, rough, metal, spec, cc, ccr, ao);
	if (kind == 0 && panel_gaps > 0.0) {  // doors on the sides, hood and tailgate on top / rear
		float gaps = 0.0;
		if (abs(v_nl.x) > 0.7 && v_pos.y > 0.42 && v_pos.y < 1.09) {
			gaps = max(gap_line(abs(v_pos.z + 0.98)), max(gap_line(abs(v_pos.z + 0.12)), gap_line(abs(v_pos.z - 0.80))));
		}
		if (v_nl.y > 0.6 && abs(v_pos.x) < 0.93) {
			gaps = max(gaps, max(gap_line(abs(v_pos.z + 1.02)), gap_line(abs(v_pos.z + 2.26))));
			gaps = max(gaps, gap_line(abs(v_pos.x)) * step(v_pos.z, -1.0));
		}
		gaps *= panel_gaps * (1.0 - smoothstep(30.0, 90.0, v_dist));
		col *= 1.0 - 0.8 * gaps;
		cc *= 1.0 - gaps;
	}
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
