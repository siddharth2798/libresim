shader_type spatial;
// Vehicle window glass (follow-me car and the other ground vehicles): nearly clear head-on (the dark
// interior shows), mirror-like at grazing angles (Fresnel, as aircraft/c172/glass.gdshader). The
// reflection is a cheap environment: sky gradient above the horizon, a soft bright horizon band,
// dark apron below, so a window reads as glass from any side. Haze as the other world shaders.
render_mode cull_disabled, fog_disabled, depth_draw_opaque;

global uniform vec3 fog_color;
global uniform float haze_density;
global uniform vec3 sky_top_color;
global uniform float night_level;

varying float v_dist;

void vertex() {
	v_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	float nv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float f = 0.04 + 0.96 * pow(1.0 - nv, 4.0);
	vec3 n = NORMAL * sign(dot(NORMAL, VIEW));
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, n), 0.0)).xyz;
	float day = 1.0 - night_level;
	vec3 sky = mix(fog_color, sky_top_color, smoothstep(0.0, 0.6, r.y)) * day + vec3(0.01, 0.012, 0.02) * night_level;
	vec3 ground = vec3(0.09, 0.085, 0.08) * (fog_color * day + vec3(0.02));
	vec3 env = r.y > 0.0 ? sky : mix(fog_color * 0.6 * day, ground, smoothstep(0.0, 0.12, -r.y));
	env += fog_color * day * 0.35 * exp(-abs(r.y) * 30.0);  // bright horizon line
	float haze = 1.0 - exp(-v_dist * haze_density);
	ALBEDO = COLOR.rgb * (1.0 - haze);
	EMISSION = env * (0.15 + 0.85 * f) * 0.9 * (1.0 - haze) + fog_color * haze;
	ALPHA = clamp(mix(0.30, 0.92, f) + haze * 0.5, 0.0, 1.0);
	ROUGHNESS = 0.04;
	SPECULAR = 1.0;
}
