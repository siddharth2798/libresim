shader_type sky;
// Sky: scattering-style gradient with sunset tint, sun disk + Mie glow.
// (Clouds are a depth-aware full-screen pass: world/volumetric_clouds.gdshader.)

uniform vec3 zenith_color : source_color = vec3(0.25, 0.45, 0.85);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.8, 0.9);
uniform vec3 ground_color : source_color = vec3(0.25, 0.27, 0.27);
uniform float day = 1.0;          // 0 night .. 1 day
uniform float dusk = 0.0;         // sunset tint amount

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = LIGHT0_DIRECTION;  // towards the sun, render frame (x east, y up, z south)
	{
		float up = max(d.y, 0.0);
		vec3 hor = mix(horizon_color, vec3(1.0, 0.62, 0.42), dusk * pow(1.0 - up, 6.0) * max(dot(normalize(d.xz), normalize(sun.xz)), 0.0));
		vec3 col = mix(hor, zenith_color, pow(up, 0.5));
		if (d.y < 0.0) col = mix(hor, ground_color, smoothstep(0.0, 0.2, -d.y));
		float mu = max(dot(d, sun), 0.0);
		col += LIGHT0_COLOR * (pow(mu, 2000.0) * 40.0 + pow(mu, 12.0) * 0.18 + pow(mu, 3.0) * 0.06) * LIGHT0_ENERGY * day;
		COLOR = col;
	}
}
