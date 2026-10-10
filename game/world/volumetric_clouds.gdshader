shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled, blend_mix;
// Full-screen raymarched cumulus layer, depth-aware: marches from the camera to the
// first of (scene depth, layer exit), so clouds sit correctly in front of or behind
// terrain and the aircraft, from below, inside or above the layer.
// Density = coverage map (domes, taller where coverage is stronger) eroded by detail
// noise; both from tiling noise textures (cheap on integrated GPUs).

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D noise_lo : filter_linear_mipmap, repeat_enable;  // coverage (seamless)
uniform sampler2D noise_hi : filter_linear_mipmap, repeat_enable;  // detail (seamless)
uniform vec3 cam_world = vec3(0.0);   // camera ENU (east, north, up) m
uniform float cloud_base = 1400.0;
uniform float cloud_thick = 900.0;
uniform float coverage = 0.4;
uniform vec2 wind_offset = vec2(0.0);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);  // render frame, towards the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 ambient : source_color = vec3(0.5, 0.56, 0.66);
uniform int steps = 24;
uniform float max_dist = 25000.0;
global uniform vec3 fog_color;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);  // QuadMesh 1x1 -> full screen
}

float density(vec3 p) {
	float h = (p.z - cloud_base) / cloud_thick;
	if (h < 0.0 || h > 1.0) return 0.0;
	vec2 q = (p.xy + wind_offset) / 9000.0;
	float cov = textureLod(noise_lo, q, 0.0).r - (1.0 - coverage) * 0.82;
	float dome = cov * 2.6 - h * h * 1.1 - (1.0 - smoothstep(0.0, 0.1, h)) * 0.4;
	if (dome < -0.3) return 0.0;
	float detail = textureLod(noise_hi, q * 6.0 + vec2(h * 0.35, -h * 0.27), 0.0).r;
	return clamp((dome - (1.0 - detail) * 0.32) * 2.2, 0.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	float scene_dist = length(vpos.xyz);
	vec3 rd_view = normalize(vpos.xyz);
	vec3 rd_r = (INV_VIEW_MATRIX * vec4(rd_view, 0.0)).xyz;  // render frame
	vec3 rd = vec3(rd_r.x, -rd_r.z, rd_r.y);  // ENU
	vec3 ro = cam_world;
	float zb = cloud_base, zt = cloud_base + cloud_thick;
	float t0 = 0.0, t1 = max_dist;
	if (abs(rd.z) > 1e-5) {
		float ta = (zb - ro.z) / rd.z, tb = (zt - ro.z) / rd.z;
		t0 = max(min(ta, tb), 0.0);
		t1 = min(max(ta, tb), max_dist);
	} else if (ro.z < zb || ro.z > zt) {
		discard;
	}
	t1 = min(t1, scene_dist);
	if (t1 <= t0) discard;
	float dt = (t1 - t0) / float(steps);
	float t = t0 + dt * fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);
	float trans = 1.0;
	vec3 light = vec3(0.0);
	vec3 sun_enu = vec3(sun_dir.x, -sun_dir.z, sun_dir.y);
	for (int i = 0; i < steps; i++) {
		vec3 p = ro + rd * t;
		float d = density(p);
		if (d > 0.01) {
			float h = (p.z - cloud_base) / cloud_thick;
			float occl = density(p + sun_enu * 300.0);
			float lit = exp(-occl * 2.2) * (0.4 + 0.6 * h);
			vec3 c = mix(ambient, sun_color, lit);
			float a = 1.0 - exp(-d * dt * 0.006);
			light += trans * a * c;
			trans *= 1.0 - a;
			if (trans < 0.03) break;
		}
		t += dt;
	}
	float haze = 1.0 - exp(-t0 / 22000.0);
	ALBEDO = mix(light / max(1.0 - trans, 1e-3), fog_color, haze * 0.7);
	ALPHA = (1.0 - trans) * (1.0 - haze * 0.5);
}
