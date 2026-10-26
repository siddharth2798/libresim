shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, blend_add;
// Full-screen sun glare, drawn after everything else: a veil that lifts the blacks around the sun, a faint
// six-point starburst and a few lens ghosts along the line through the screen centre. The sun counts as
// visible where the depth buffer is empty (sky) around its screen position, so terrain, the cockpit frame
// and the aircraft cut the glare off (it leaks round their edges).

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);  // render frame, towards the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.88);
uniform float strength = 0.0;                // 0..1: sun up, not behind a deck, not too low

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);  // QuadMesh 1x1 -> full screen
}

float ghost(vec2 p, vec2 c, float r, float soft) {
	float d = length(p - c) / r;
	return smoothstep(1.0, 1.0 - soft, d) * (0.4 + 0.6 * smoothstep(0.55, 1.0, d));  // ring-heavy disc
}

void fragment() {
	vec3 sv = (VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz;
	if (strength <= 0.001 || sv.z >= -0.01) discard;
	vec4 clip = PROJECTION_MATRIX * vec4(sv * 1000.0, 1.0);
	vec2 ndc = clip.xy / clip.w;
	vec2 sun_uv = vec2(ndc.x * 0.5 + 0.5, ndc.y * 0.5 + 0.5);  // Godot flips y in the projection
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	// share of the sun's neighbourhood that is open sky
	float open = 0.0;
	for (int i = 0; i < 12; i++) {
		float a = float(i) * 0.5236;
		vec2 u = sun_uv + vec2(cos(a), sin(a) * aspect) * 0.012 * (i % 2 == 0 ? 1.0 : 0.5);
		bool in_view = u.x > 0.0 && u.x < 1.0 && u.y > 0.0 && u.y < 1.0;
		open += (!in_view || textureLod(depth_tex, u, 0.0).r < 0.000001) ? 1.0 : 0.0;
	}
	open /= 12.0;
	float edge = 1.0 - smoothstep(0.9, 1.6, max(abs(ndc.x), abs(ndc.y)));  // fades as the sun leaves the screen
	float k = strength * open * edge;
	if (k <= 0.001) discard;
	vec2 p = (SCREEN_UV - sun_uv) * vec2(aspect, 1.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float veil = 0.22 * exp(-r * 2.4) + 0.9 * exp(-r * 9.0);
	float star = pow(abs(cos(ang * 3.0)), 60.0) * exp(-r * 6.0) * 0.5;
	vec3 col = sun_color * (veil + star);
	// lens ghosts mirror the sun through the screen centre
	vec2 ctr = vec2(0.5, 0.5);
	for (int i = 0; i < 4; i++) {
		float t = float(i) * 0.55 + 0.45;
		vec2 gc = mix(sun_uv, 2.0 * ctr - sun_uv, t);
		float sz = 0.025 + 0.02 * float(i);
		vec3 tint = vec3(0.55 + 0.1 * float(i), 0.8, 1.0 - 0.12 * float(i));
		col += tint * ghost((SCREEN_UV - gc) * vec2(aspect, 1.0), vec2(0.0), sz, 0.5) * 0.05;
	}
	ALBEDO = col * k * 0.55;
}
