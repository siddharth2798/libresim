shader_type spatial;
// The generic jetway (world/models/vehicles/jetway.glb) with a night look, driven by the global night_level (NightSky: 0 by
// day, 1 at night, the same level that switches the apron floodlights on). By day it is the glb's own material (albedo
// atlas, roughness 0.55, double sided) and nothing is added. At night it adds, as emission (no light sources, so it
// costs the same on every renderer, Compatibility included):
//   - the lit parts of the atlas's night skin (cab windows and door lamp; tools/bake_jetway_glow.gd made glow_tex),
//   - a row of lit windows along the tunnel sides (windows = true: tunnel sections; spaced in metres along the tunnel, the
//     sections telescope),
//   - the apron's floodlight spill: warm light on the skin, strongest on the underside (light bounced up from the lit
//     apron), then the sides, least on the roof.
// JetwayNight (world/jetway_night.gd) holds the constants and the same maths for the tests.

global uniform float night_level;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness = 0.55;
uniform bool windows = false;
uniform vec3 warm = vec3(1.0, 0.8, 0.52);  // sodium / warm LED, like the apron lamps (ApronLightLayout)
uniform float glow_gain = 1.6;
uniform float window_gain = 1.1;
uniform float spill_gain = 0.16;
const float WIN_Y0 = 4.95;  // window band, metres up the model (the tunnel's floor is at 3.8, its roof at 6.2)
const float WIN_Y1 = 5.65;
const float WIN_PITCH = 1.7;  // metres along the tunnel
const float WIN_ON = 0.62;  // lit share of each pitch

varying vec3 v_pos;
varying float v_sx;
varying float v_nz;

void vertex() {
	v_pos = VERTEX;
	v_sx = length(MODEL_MATRIX[0].xyz);  // tunnel sections are stretched along x: pitch is measured on the stretched length
	v_nz = abs(NORMAL.z);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	ALBEDO = a.rgb;
	ROUGHNESS = roughness;
	if (night_level > 0.0) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float spill = 0.9 * clamp(-wn.y, 0.0, 1.0) + 0.45 * (1.0 - abs(wn.y)) + 0.15 * clamp(wn.y, 0.0, 1.0);
		vec3 e = a.rgb * warm * (spill * spill_gain) + texture(glow_tex, UV).rgb * glow_gain;
		if (windows) {
			float along = fract(v_pos.x * v_sx / WIN_PITCH);
			float wx = smoothstep(0.0, 0.08, along) * (1.0 - smoothstep(WIN_ON - 0.08, WIN_ON, along));
			float wy = smoothstep(WIN_Y0, WIN_Y0 + 0.08, v_pos.y) * (1.0 - smoothstep(WIN_Y1 - 0.08, WIN_Y1, v_pos.y));
			e += warm * (wx * wy * smoothstep(0.7, 0.9, v_nz) * window_gain);
		}
		EMISSION = e * night_level;
	}
}
