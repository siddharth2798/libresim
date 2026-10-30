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
uniform float base_dark = 0.0;  // thick decks: darker, greyer undersides (light used up above)
uniform float max_dist = 25000.0;
uniform float in_cloud = 0.0;  // 0..1: flying inside cloud (CloudInside)
uniform float clear_r = 0.0;  // m: outside views keep this pocket around the camera free of cloud, so the aircraft stays readable
uniform float vert_grad = 0.3;  // interior light: brighter looking up, darker looking down (CloudLook.VERT)
uniform vec3 glow_color : source_color = vec3(0.0);  // soft glow towards the sun inside cloud
global uniform vec3 fog_color;
global uniform float haze_density;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);  // QuadMesh 1x1 -> full screen
}

// Texel sizes in metres (256 px tiling over 9000 m, detail at 6x): the noise is sampled at the mip
// that matches the march step, so detail finer than the step is averaged away instead of aliasing
// into salt-and-pepper speckle along the cloud edges (a point sample per step on 5 m texels).
const float LO_TEXEL = 35.0;
const float HI_TEXEL = 5.9;

float density(vec3 p, float step_m) {
	float h = (p.z - cloud_base) / cloud_thick;
	if (h < 0.0 || h > 1.0) return 0.0;
	vec2 q = (p.xy + wind_offset) / 9000.0;
	float cov = textureLod(noise_lo, q, max(log2(step_m / LO_TEXEL), 0.0)).r - (1.0 - coverage) * 0.82;
	float dome = cov * 2.6 - h * h * 1.1 - (1.0 - smoothstep(0.0, 0.1, h)) * 0.4;
	if (dome < -0.3) return 0.0;
	float detail = textureLod(noise_hi, q * 6.0 + vec2(h * 0.35, -h * 0.27), max(log2(step_m / HI_TEXEL) - 2.5, 0.0)).r;
	return clamp((dome - (1.0 - detail) * 0.32) * 2.2, 0.0, 1.0);
}

// Interleaved gradient noise (Jimenez): well-distributed per-pixel values, far less clumpy than a sin hash.
float ign(vec2 px) {
	return fract(52.9829189 * fract(dot(px, vec2(0.06711056, 0.00583715))));
}

// Mean of the 2x2 pixel quad via fine derivatives (the neighbours' march offsets differ, so this halves
// the remaining step noise for free). The derivative signs are measured from FRAGCOORD itself.
vec4 quad_mean(vec4 v, vec2 fc) {
	vec2 par = mod(floor(fc), 2.0);
	vec2 sg = vec2(dFdxFine(fc.x), dFdyFine(fc.y));  // +-1: direction of rising pixel index
	v += 0.5 * (1.0 - 2.0 * par.x) * sg.x * dFdxFine(v);
	v += 0.5 * (1.0 - 2.0 * par.y) * sg.y * dFdyFine(v);
	return v;
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
		t1 = -1.0;  // parallel to the layer and outside it: nothing to march
	}
	t1 = min(t1, scene_dist);
	float dt = max(t1 - t0, 0.0) / float(steps);
	float t = t0 + dt * ign(FRAGCOORD.xy);
	float trans = 1.0;
	vec3 light = vec3(0.0);
	vec3 sun_enu = vec3(sun_dir.x, -sun_dir.z, sun_dir.y);
	for (int i = 0; i < (t1 > t0 ? steps : 0); i++) {
		vec3 p = ro + rd * t;
		float d = density(p, dt);
		if (clear_r > 0.0) d *= smoothstep(0.5 * clear_r, clear_r, t);
		if (d > 0.01) {
			float h = (p.z - cloud_base) / cloud_thick;
			float occl = density(p + sun_enu * 300.0, max(dt, 150.0));
			float lit = exp(-occl * 2.2) * (0.4 + 0.6 * h);
			vec3 c = mix(ambient, sun_color, lit) * (1.0 - base_dark * (1.0 - h) * (1.0 - h));
			float a = 1.0 - exp(-d * dt * 0.006);
			light += trans * a * c;
			trans *= 1.0 - a;
			if (trans < 0.03) break;
		}
		t += dt;
	}
	// aerial perspective to the cloud entry point, from the visibility (at least a faint blue haze)
	float haze = 1.0 - exp(-t0 * max(haze_density, 1.0 / 22000.0));
	float alpha = (1.0 - trans) * (1.0 - haze * 0.35);
	vec3 col = mix(light / max(1.0 - trans, 1e-3), fog_color, haze);
	// inside cloud the interior is not one flat grey: lighter overhead and towards the sun, darker below
	col = col * (1.0 + vert_grad * rd.z * in_cloud) + glow_color * (in_cloud * pow(max(dot(rd, sun_enu), 0.0), 3.0));
	vec4 m = quad_mean(vec4(col * alpha, alpha), FRAGCOORD.xy);  // premultiplied, so empty pixels do not darken the edge
	if (m.a < 1e-4) discard;
	ALBEDO = m.rgb / m.a;
	ALPHA = m.a;
}
