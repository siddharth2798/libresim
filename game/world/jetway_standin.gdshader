shader_type spatial;
// Far stand-in box of a jetway (world/jetway_standin.gd): its average seen colour by day, and at night the same lit tunnel
// as world/jetway.gdshader on a plain box: a row of lit windows along the long sides, the floodlight spill on its underside
// and sides. night_level (NightSky) drives it, so it is the same look and the same fade as the full model: no pop at the
// switch between them.

global uniform float night_level;

uniform vec3 albedo : source_color = vec3(0.72, 0.74, 0.76);
uniform float roughness = 0.6;
uniform vec3 warm = vec3(1.0, 0.8, 0.52);
uniform float window_gain = 0.8;  // the box is seen small and far: a little less than the full model's windows, and softer
uniform float spill_gain = 0.16;
const float WIN_Y0 = 0.5;  // window band as a share of the box height (the full model: 4.95 .. 5.65 m of a 3.8 .. 6.3 m tube)
const float WIN_Y1 = 0.8;
const float WIN_PITCH = 1.7;
const float WIN_ON = 0.62;

varying vec3 v_pos;  // unit box: -0.5 .. 0.5
varying float v_nz;  // model-space |normal.z|: the long sides
varying vec2 v_size;  // the box's length along x and its height (m)

void vertex() {
	v_pos = VERTEX;
	v_nz = abs(NORMAL.z);
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	if (night_level > 0.0) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float spill = 0.9 * clamp(-wn.y, 0.0, 1.0) + 0.45 * (1.0 - abs(wn.y)) + 0.15 * clamp(wn.y, 0.0, 1.0);
		vec3 e = albedo * warm * (spill * spill_gain);
		float along = fract((v_pos.x + 0.5) * v_size.x / WIN_PITCH);
		float wx = smoothstep(0.0, 0.15, along) * (1.0 - smoothstep(WIN_ON - 0.15, WIN_ON, along));
		float h = v_pos.y + 0.5;
		float wy = smoothstep(WIN_Y0, WIN_Y0 + 0.05, h) * (1.0 - smoothstep(WIN_Y1 - 0.05, WIN_Y1, h));
		e += warm * (wx * wy * smoothstep(0.7, 0.9, v_nz) * window_gain);
		EMISSION = e * night_level;
	}
}
