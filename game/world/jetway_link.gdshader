shader_type spatial;
render_mode cull_disabled;
// The fixed walkways between the terminal and the jetway rotundas (world/jetway_links.gd): the cladding (a little floodlight
// spill at night) and the glazed band (lit from inside, warm). Same night_level and warm light as jetway.gdshader; by day it
// is the plain material it replaced and adds nothing.

global uniform float night_level;

uniform vec3 albedo : source_color = vec3(0.78, 0.79, 0.8);
uniform float roughness = 0.55;
uniform float metallic = 0.0;
uniform bool glass = false;
uniform vec3 warm = vec3(1.0, 0.8, 0.52);
uniform float glass_gain = 0.35;
uniform float spill_gain = 0.16;

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (night_level > 0.0) {
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float spill = 0.9 * clamp(-wn.y, 0.0, 1.0) + 0.45 * (1.0 - abs(wn.y)) + 0.15 * clamp(wn.y, 0.0, 1.0);
		vec3 e = albedo * warm * (spill * spill_gain);
		if (glass) {
			e += warm * glass_gain;
		}
		EMISSION = e * night_level;
	}
}
