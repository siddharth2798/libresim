shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, blend_mix;
// Heat shimmer (world/postfx/heat_shimmer.gd): a full-screen quad that redraws the screen texture with a small,
// moving refraction offset where hot air sits:
//  - over sunlit ground at grazing angles (the far runway / apron / fields seen from low down), between near_m
//    (beyond the aircraft) and far_m;
//  - behind running exhausts: up to 4 plumes, each a cone from the nozzle along its flow (aircraft.json "exhausts").
//    Only geometry behind the plume is distorted, so the airframe in front stays sharp.
// Sorted before the cloud quad (CloudLayer sorting_offset 1000), because the screen texture is captured before
// the transparent pass: clouds drawn later stay on top and are never overwritten.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform float ground = 0.0;     // 0..1
uniform float near_m = 120.0;
uniform float far_m = 4000.0;
uniform vec4 plume_a[4];        // nozzle: render-space position, radius m
uniform vec4 plume_b[4];        // plume end: render-space position, radius m
uniform float plume_k[4];       // 0..1 per plume (0 = off)
uniform float amp = 0.0025;     // max offset in UV

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);  // QuadMesh 1x1 -> full screen (as world/sun_glare.gdshader)
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, max(depth, 1e-7), 1.0);
	vec3 vp = v.xyz / v.w;
	float dist = depth <= 0.0 ? 1e9 : length(vp);
	vec3 dir = normalize(vp);
	float mask = 0.0;
	if (ground > 0.0 && depth > 0.0) {
		float wy = abs((INV_VIEW_MATRIX * vec4(dir, 0.0)).y);  // grazing rays only: hot air is a thin layer
		mask += ground * smoothstep(near_m, near_m * 2.0, dist) * (1.0 - smoothstep(far_m * 0.6, far_m, dist)) * (1.0 - smoothstep(0.015, 0.07, wy));
	}
	for (int i = 0; i < 4; i++) {
		if (plume_k[i] <= 0.0) {
			continue;
		}
		vec3 a = (VIEW_MATRIX * vec4(plume_a[i].xyz, 1.0)).xyz;
		vec3 b = (VIEW_MATRIX * vec4(plume_b[i].xyz, 1.0)).xyz;
		float best = 0.0;
		for (int j = 0; j <= 6; j++) {  // the plume as 7 discs along its axis
			float t = float(j) / 6.0;
			vec3 p = mix(a, b, t);
			float s = dot(p, dir);
			if (s <= 0.0 || dist < s - 0.5) {
				continue;  // behind the camera, or the pixel's surface is in front of the plume
			}
			float r = mix(plume_a[i].w, plume_b[i].w, t);
			float off = length(p - dir * s);
			best = max(best, (1.0 - smoothstep(0.4 * r, r, off)) * (1.0 - 0.8 * t));
		}
		mask += best * plume_k[i];
	}
	mask = clamp(mask, 0.0, 1.0);
	if (mask < 0.003) {
		discard;
	}
	vec2 q = SCREEN_UV * vec2(90.0, 40.0);
	vec2 n = vec2(vnoise(q + vec2(0.0, TIME * 2.5)), vnoise(q * 1.3 + vec2(7.0, TIME * 3.1))) - 0.5;
	vec3 c = textureLod(screen_tex, SCREEN_UV + n * amp * mask, 0.0).rgb;
	ALBEDO = c;
	ALPHA = smoothstep(0.0, 0.25, mask);
}
