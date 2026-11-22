#ifndef TERRAIN_CANOPY_INC
#define TERRAIN_CANOPY_INC
// Forest floor and canopy shade (docs/GRAPHICS-PLAN.md G8), included by terrain.gdshader after its uniforms, vnoise and
// the cloud globals. Far forests have no tree shadows (impostors cast none: they cost +9-10 ms at Ultra), and above
// Trees.HIDE_AGL no trees are drawn at all, so the ground shows the canopy itself:
//  - dense tree cover (land class 1..200) darkens and greens the imagery (the WorldCover tree tint does most of this),
//    and within ~300 m gets brown leaf-litter patches and damp hollows (2-3 noise lookups);
//  - open ground beside a forest lies in its shadow on the side away from the sun (the density a canopy height's shadow
//    length towards the sun, two taps of the land-class mask);
//  - inside the forest, crown-sized bumps of a noise height field are lit on their sun side and shaded on the other.
// Fades in beyond 120-300 m, where the near trees' real shadows end (and impostors begin), and out with distance where
// the 10 m mask and 9 m noise would shimmer. Cost: 3 texture taps per forest pixel, plus 2 noise lookups on High+
// (canopy_detail); canopy_start follows the preset's real tree shadows (TreeQuality).

const float CANOPY_H = 12.0;  // m, typical canopy height for the shadow length
global uniform float canopy_detail;  // TreeQuality: 0 Low (edge shadows only), 0.5 Medium (+ leaf litter), 1 High+ (+ crown relief)
global uniform float canopy_start;  // m: where real tree shadows end (near meshes, or the shadow proxies on High+)

vec3 canopy_floor(vec3 col, vec2 lc_uv, float lc_scale_, float tile_size_, float land, vec2 en, float dist, bool has_wc) {
	float forest = smoothstep(0.1, 0.6, texture(lc_tex, lc_uv).r * 1.275) * land;
	col = mix(col, col * vec3(0.8, 0.95, 0.72) * 0.85, forest * (has_wc ? 0.3 : 0.6));
	// forest floor up close: brown leaf-litter patches and darker damp hollows break up the flat green under trees
	float lk = forest * (1.0 - smoothstep(150.0, 320.0, dist)) * step(0.25, canopy_detail);
	if (lk > 0.0) {
		float patch = smoothstep(0.35, 0.75, vnoise(en / 3.5) * 0.7 + vnoise(en / 0.9) * 0.3);
		float hollow = smoothstep(0.55, 0.85, vnoise(en / 7.0 + 31.0));
		vec3 litter = vec3(dot(col, vec3(0.33))) * vec3(1.35, 1.0, 0.62);
		col = mix(col, litter, patch * 0.5 * lk) * (1.0 - 0.22 * hollow * lk);
	}
	float k = smoothstep(canopy_start, canopy_start * 1.6 + 100.0, dist) * (1.0 - smoothstep(9000.0, 16000.0, dist)) * land;
	if (k <= 0.0 || cloud_sun.y < 0.02) {
		return col;
	}
	k *= smoothstep(0.02, 0.12, cloud_sun.y) * (1.0 - 0.7 * cloud_shadow.y);  // no shadows at night or under overcast
	vec2 sun_h = vec2(cloud_sun.x, -cloud_sun.z);  // towards the sun, (east, north)
	float sl = length(sun_h);
	vec2 dir = sl > 1e-3 ? sun_h / sl : vec2(0.0);
	float reach = min(CANOPY_H * sl / max(cloud_sun.y, 0.08), 90.0);  // shadow length (m)
	vec2 m2uv = vec2(1.0, -1.0) * lc_scale_ / tile_size_;  // metres -> land-class UV (v measured from north)
	float up = max(texture(lc_tex, lc_uv + dir * reach * 0.5 * m2uv).r, texture(lc_tex, lc_uv + dir * reach * m2uv).r);
	float edge = clamp(smoothstep(0.1, 0.6, up * 1.275) - forest, 0.0, 1.0);  // open ground in a forest's shadow
	col *= 1.0 - 0.42 * edge * k;
	// crown relief: bumps ~9 m across, lit towards the sun; gone where a 9 m bump is under a pixel or two
	float rk = forest * k * (1.0 - smoothstep(1200.0, 3500.0, dist)) * step(0.75, canopy_detail);
	if (rk > 0.0) {
		vec2 q = en / 9.0;
		float h0 = vnoise(q);
		float h1 = vnoise(q + dir * (0.35 + 0.4 * sl));
		col *= 1.0 + clamp((h1 - h0) * -2.2, -0.45, 0.25) * rk - 0.1 * rk;
	}
	return col;
}
#endif
