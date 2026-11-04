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
uniform float max_dist = 25000.0;  // m: the march ends here; beyond it the layer goes on as a uniform veil
uniform float air_haze = 1.8e-5;  // clear-air extinction (1/m): not haze_density, which is the in-cloud fog inside cloud
uniform vec3 mean_density = vec3(0.0);  // mean density at 20 / 50 / 80 % of the layer (CloudLayer._update_mean)
uniform float in_cloud = 0.0;  // 0..1: flying inside cloud (CloudInside)
uniform float clear_r = 0.0;  // m: outside views keep this pocket around the camera free of cloud, so the aircraft stays readable
uniform float vert_grad = 0.3;  // interior light: brighter looking up, darker looking down (CloudLook.VERT)
uniform float subject_w = 0.0;  // 0..1: outside view of the aircraft: bright interior is darkened and cooled (CloudLook.interior_dim)
uniform vec3 glow_color : source_color = vec3(0.0);  // soft glow towards the sun inside cloud
// Sun lighting (G3). With light_steps = 1, phase_w = 0, powder_w = 0 and ms_octaves = 1 this is exactly the
// old look (one sample 300 m up the sun ray, one Beer term). The defaults keep the mean brightness of a side
// view within ~10 % of it (numeric check: thin edges ~15 % darker, thick cores ~2x brighter, silver lining).
uniform int light_steps = 1;  // samples along the sun ray per march step (graphics preset: 1..4)
uniform float light_dist = 300.0;  // m: the single sample (light_steps = 1)
uniform float light_first = 120.0;  // m: first of several samples, each next one light_grow further:
uniform float light_grow = 2.2;  // 120, 264, 581, 1278 m
uniform float light_absorb = 2.2;  // optical depth per unit of mean density along the sun ray
uniform float phase_g_fwd = 0.8;  // two-lobe Henyey-Greenstein: forward lobe (silver lining) ...
uniform float phase_g_back = -0.3;  // ... back lobe ...
uniform float phase_mix = 0.7;  // ... share of the forward lobe
uniform float phase_w = 0.3;  // 0 = isotropic (old look) .. 1 = full phase function
uniform float phase_max = 6.0;  // cap on the normalised phase (mean 1), so the lining does not blow out
uniform float powder_w = 0.2;  // dark-edge (powder) strength, sun behind the viewer; 0 = off
uniform float powder_k = 1.0;  // powder = 1 - exp(-2 * od * powder_k)
uniform int ms_octaves = 3;  // multiple-scattering octaves (1 = single scattering only), max 4
uniform float ms_a = 0.5;  // per octave: phase anisotropy x a,
uniform float ms_b = 0.5;  // optical depth x b,
uniform float ms_c = 0.5;  // energy x c (the octaves are normalised by their summed energy)
uniform float sun_gain = 1.0;  // overall scale of the sun term
global uniform vec3 fog_color;
global uniform float haze_density;
#include "res://world/haze_sky.gdshaderinc"

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

// Henyey-Greenstein phase times 4 pi (mean 1 over the sphere); c = cos(view ray, sun).
float hg4pi(float g, float c) {
	float gg = g * g;
	return (1.0 - gg) / pow(max(1.0 + gg - 2.0 * g * c, 1e-4), 1.5);
}

// Phase weight of octave k (anisotropy scaled by s = ms_a^k), blended towards 1 by phase_w and capped.
float phase_k(float c, float s) {
	float p = mix(hg4pi(phase_g_back * s, c), hg4pi(phase_g_fwd * s, c), phase_mix);
	return 1.0 + phase_w * (min(p, phase_max) - 1.0);
}

// Optical depth towards the sun from p: one sample (old look) or the mean of light_steps growing samples,
// each at a mip matching its spacing (so the far ones are cheap and smooth).
float sun_od(vec3 p, vec3 sun_enu, float dt) {
	if (light_steps <= 1) return density(p + sun_enu * light_dist, max(dt, 150.0)) * light_absorb;
	int n = min(light_steps, 4);
	float sum = 0.0;
	float dj = light_first;
	for (int j = 0; j < n; j++) {
		sum += density(p + sun_enu * dj, max(dt, 0.5 * dj));
		dj *= light_grow;
	}
	return sum / float(n) * light_absorb;
}

// Sun energy reaching p (replaces the old exp(-od)): multiple-scattering octaves (Wrenninge / Hillaire), each
// with its own phase pk[k], then the powder term (Schneider), only when the sun is behind the viewer (away).
float sun_energy(float od, vec4 pk, int oct, float away) {
	float e = exp(-od) * pk.x;
	float den = 1.0;
	float c2 = ms_c * ms_c, b2 = ms_b * ms_b;
	if (oct > 1) { e += ms_c * exp(-od * ms_b) * pk.y; den += ms_c; }
	if (oct > 2) { e += c2 * exp(-od * b2) * pk.z; den += c2; }
	if (oct > 3) { e += c2 * ms_c * exp(-od * b2 * ms_b) * pk.w; den += c2 * ms_c; }
	float powder = 1.0 - exp(-2.0 * od * powder_k);
	return e / max(den, 1e-4) * (1.0 + powder_w * away * (powder - 1.0)) * sun_gain;
}

// Roots of k t^2 + b t + c = 0 (k >= 0, tiny: the curvature term), sorted; 1e30 where there is none.
vec2 qroots(float k, float b, float c) {
	if (k < 1e-14) {
		return vec2(abs(b) > 1e-9 ? -c / b : 1e30, 1e30);
	}
	float disc = b * b - 4.0 * k * c;
	if (disc < 0.0) return vec2(1e30);
	float q = -0.5 * (b + (b >= 0.0 ? 1.0 : -1.0) * sqrt(disc));  // stable form: no cancellation for small k
	float r0 = q / k;
	float r1 = abs(q) > 1e-20 ? c / q : 0.0;
	return vec2(min(r0, r1), max(r0, r1));
}
// The layer's mean density at relative height h (0 outside it): what far cloud averages to.
float mean_at(float h) {
	if (h < 0.0 || h > 1.0) return 0.0;
	return h < 0.5 ? mix(mean_density.x, mean_density.y, clamp((h - 0.2) / 0.3, 0.0, 1.0))
		: mix(mean_density.y, mean_density.z, clamp((h - 0.5) / 0.3, 0.0, 1.0));
}
float first_pos(vec2 r) { return r.x > 0.0 ? r.x : (r.y > 0.0 ? r.y : 1e30); }

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
	// The layer follows the Earth's curvature like the ground (curvature.gdshaderinc): along the ray the
	// height above it is z(t) = ro.z + rd.z t + k t^2. First stretch of the ray inside the slab [zb, zt]:
	float kc = (1.0 - rd.z * rd.z) * (0.5 / 6371000.0);
	vec2 rt = qroots(kc, rd.z, ro.z - zt), rbs = qroots(kc, rd.z, ro.z - zb);
	float t0 = 0.0, t1;
	if (ro.z >= zb && ro.z <= zt) {
		t1 = min(first_pos(rt), first_pos(rbs));
	} else if (ro.z < zb) {
		t0 = first_pos(rbs);  // up through the base, out through the top
		t1 = first_pos(rt);
	} else {
		t0 = first_pos(rt);  // down through the top, out through the base or back up through the top
		t1 = min(first_pos(rbs), rt.y > t0 ? rt.y : 1e30);
	}
	float tx = min(t1, scene_dist);  // where the ray really leaves the layer (or hits the scene)
	t1 = min(tx, max_dist);
	float dt = max(t1 - t0, 0.0) / float(steps);
	float t = t0 + dt * ign(FRAGCOORD.xy);
	float trans = 1.0;
	vec3 light = vec3(0.0);
	float tw = 0.0, ww = 0.0;  // weighted mean distance of what is seen (for the haze)
	vec3 sun_enu = vec3(sun_dir.x, -sun_dir.z, sun_dir.y);
	float cs = dot(rd, normalize(sun_enu));  // the phase is constant along the ray: once per pixel
	int oct = clamp(ms_octaves, 1, 4);
	float a2 = ms_a * ms_a;
	vec4 pk = vec4(phase_k(cs, 1.0), phase_k(cs, ms_a), phase_k(cs, a2), phase_k(cs, a2 * ms_a));
	float away = 0.5 - 0.5 * cs;
	for (int i = 0; i < (t1 > t0 ? steps : 0); i++) {
		vec3 p = ro + rd * t;
		p.z += kc * t * t;
		// far cloud blends into the layer's mean density, the veil that goes on beyond max_dist (no cut edge)
		float d = mix(density(p, dt), mean_at((p.z - cloud_base) / cloud_thick), smoothstep(0.55 * max_dist, max_dist, t));
		if (clear_r > 0.0) d *= smoothstep(0.5 * clear_r, clear_r, t);
		if (d > 0.01) {
			float h = (p.z - cloud_base) / cloud_thick;
			float od = sun_od(p, sun_enu, dt);
			float hl = 0.4 + 0.6 * h;
			float lit = exp(-od) * hl;  // the old sun share: the ambient keeps it, so only the sun term changes
			vec3 c = ambient * (1.0 - lit) + sun_color * (sun_energy(od, pk, oct, away) * hl);
			c *= 1.0 - base_dark * (1.0 - h) * (1.0 - h);
			float a = 1.0 - exp(-d * dt * 0.006);
			light += trans * a * c;
			tw += trans * a * t;
			ww += trans * a;
			trans *= 1.0 - a;
			if (trans < 0.03) break;
		}
		t += dt;
	}
	// Beyond max_dist the layer goes on to where the ray leaves it (curved slab, tx) as a veil of its mean
	// density: near-horizontal rays from in or near the layer pile up optical depth smoothly with elevation
	// instead of stopping at the end of the march. Lit like the average of what the march saw.
	float v0 = max(t0, max_dist), v1 = min(tx, 400000.0);
	if (v1 > v0 && trans > 0.03) {
		float vm = 0.5 * (v0 + v1);
		float dm = mean_at((ro.z + rd.z * vm + kc * vm * vm - cloud_base) / cloud_thick);
		dm = max(dm, 0.5 * (mean_at((ro.z + rd.z * v0 + kc * v0 * v0 - cloud_base) / cloud_thick)
			+ mean_at((ro.z + rd.z * v1 + kc * v1 * v1 - cloud_base) / cloud_thick)));
		float od = dm * (v1 - v0) * 0.006;
		if (od > 1e-3) {
			float a = 1.0 - exp(-od);
			vec3 cv = ww > 1e-3 ? light / max(1.0 - trans, 1e-3) : ambient * 0.75 + sun_color * 0.45;
			light += trans * a * cv;
			tw += trans * a * (v0 + min(v1 - v0, 1.0 / max(dm * 0.006, 1e-6)) * 0.5);  // mean depth seen into the veil
			ww += trans * a;
			trans *= 1.0 - a;
		}
	}
	// aerial perspective to the seen part of the cloud, from the visibility (at least a faint blue haze), in the
	// colour of the sky model along the ray (haze_sky.gdshaderinc), so far cloud melts into the sky behind it
	float th = ww > 1e-4 ? tw / ww : t0;
	float haze = 1.0 - exp(-th * max(air_haze, 1.0 / 22000.0));
	// the cloud only thins with the haze in front of where the layer starts (none from inside it: a cloud wall
	// at the horizon stays opaque, so the ground / sky edge behind it never shows through)
	float alpha = (1.0 - trans) * (1.0 - 0.35 * (1.0 - exp(-t0 * max(air_haze, 1.0 / 22000.0))));
	vec3 col = mix(light / max(1.0 - trans, 1e-3), haze_color(rd_r), haze);
	// inside cloud the interior is not one flat grey: lighter overhead and towards the sun, darker below
	float lm = dot(col, vec3(0.299, 0.587, 0.114));
	float bright = smoothstep(0.3, 0.9, lm) * subject_w * in_cloud;
	col *= (1.0 - 0.25 * bright) * mix(vec3(1.0), vec3(0.9, 0.95, 1.06), bright);  // CloudLook.DIM / BLUE
	col = col * (1.0 + vert_grad * rd.z * in_cloud) + glow_color * (in_cloud * pow(max(dot(rd, sun_enu), 0.0), 3.0));
	vec4 m = quad_mean(vec4(col * alpha, alpha), FRAGCOORD.xy);  // premultiplied, so empty pixels do not darken the edge
	if (m.a < 1e-4) discard;
	ALBEDO = m.rgb / m.a;
	ALPHA = m.a;
}
