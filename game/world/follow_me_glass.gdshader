shader_type spatial;
// Follow-me car window glass: nearly clear head-on (the dark interior shows), mirror-like at grazing
// angles (Fresnel, the aircraft glass idea in aircraft/c172/glass.gdshader) picking up the sky
// colour, with the same haze as the other world shaders.
render_mode cull_disabled, fog_disabled, depth_draw_opaque;

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform vec3 sky_top_color;

varying float v_dist;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	float haze = 1.0 - exp(-v_dist * haze_density);
	vec3 refl = mix(fog_color, sky_top_color, 0.45);
	ALBEDO = COLOR.rgb * (1.0 - haze);
	EMISSION = refl * (0.03 + 0.5 * f) * (1.0 - haze) + fog_color * haze;
	ALPHA = clamp(mix(0.16, 0.85, f) + haze * 0.5, 0.0, 1.0);
	ROUGHNESS = 0.04;
	SPECULAR = 1.0;
}
