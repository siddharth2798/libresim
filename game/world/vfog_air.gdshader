shader_type fog;
// The near-field structure around the camera (world/volumetric_fog.gd): one box FogVolume covering the froxel range.
// Godot accumulates FogVolume density in fixed point (about 1/1024 per m: smaller values vanish, checked on 4.7),
// so the thin air itself (shafts, night glow) is the Environment's float volumetric_fog_density, and this volume
// only carries what is dense enough or cuts it away:
//   top:    above the haze top (base_m) the thin air is cut away, so looking up does not see 10 km of it.
//   shafts: in the cloud shadows (the same coverage noise and projection as the terrain's cloud shadows) the thin
//           air is cut away (negative density, the total is clamped at 0): only sunlit columns scatter -> shafts.
//   mist:   a patchy layer over the low ground on humid mornings (VfogRules.mist).
//   rain:   falling streaks near the camera in heavy rain.
//   cloud:  near-field puffs while inside cloud (adds structure to CloudInside's fog).
// The sun lights all of it through Godot (anisotropy, the shadow map).

// Copies of the global shader parameters of the same names (CloudLayer / FloatingOrigin), set by VolumetricFog:
// global uniforms read wrong values in fog shaders (Godot 4.7, seen as a yellow cast).
uniform vec4 cloud_shadow = vec4(0.0);  // x cloud base (m), y coverage, z shadow strength
uniform vec2 cloud_uv_off = vec2(0.0);
uniform vec3 cloud_sun = vec3(0.0, 1.0, 0.0);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 pattern_origin = vec2(0.0);

uniform float cut = 0.0;  // 1/m removed in the cloud shadows below the base (>= the thin air, >= 0.002)
uniform float base_m = 1400.0;  // haze top: the cloud base, or ~2 km over the ground in clear air
uniform float mist = 0.0;  // 1/m at the floor of the mist layer
uniform float mist_floor = 0.0;  // m AMSL
uniform float mist_top = 100.0;
uniform vec3 mist_glow = vec3(0.0);  // light the mist adds itself (skylight / haze colour), so shaded mist stays pale
uniform float rain = 0.0;  // 1/m
uniform float cloud = 0.0;  // 1/m
uniform vec3 cam = vec3(0.0);  // camera, render frame
uniform vec2 wind = vec2(0.0);  // m/s, render x / z: rain and puffs move with the air

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// 1 where the sun reaches this point, 0 under thick cloud (terrain.gdshader's cloud-shadow test).
float sun_through(vec2 en, float alt) {
	if (cloud_shadow.z <= 0.0 || cloud_sun.y <= 0.02 || alt > cloud_shadow.x + 600.0) {
		return 1.0;
	}
	float t = (cloud_shadow.x + 360.0 - alt) / max(cloud_sun.y, 0.05);
	vec2 q = (en + vec2(cloud_sun.x, -cloud_sun.z) * t) / 9000.0 + cloud_uv_off;
	float cov = textureLod(cloud_noise, q, 0.0).r - (1.0 - cloud_shadow.y) * 0.82;
	return 1.0 - smoothstep(0.0, 0.3, cov * 2.6 - 0.2) * clamp(cloud_shadow.z * 1.6, 0.0, 1.0);
}

void fog() {
	vec3 w = WORLD_POSITION;
	vec2 en = vec2(w.x + pattern_origin.x, -w.z + pattern_origin.y);
	float alt = w.y;
	float below = 1.0 - smoothstep(base_m - 250.0, base_m, alt);
	// the thin air lives below the haze top (cloud base, else ~2 km over the ground) and only where the sun reaches
	float d = cut > 0.0 ? -cut * max(smoothstep(0.25, 0.55, 1.0 - sun_through(en, alt)) * below, 1.0 - below) : 0.0;
	float m = 0.0;
	if (mist > 0.0) {
		// low frequencies only (km scale, blurred mips): the froxels are 50-150 m wide at a few km, finer detail aliases
		float p1 = textureLod(cloud_noise, en / 7000.0 + vec2(0.37, 0.61), 4.0).r;
		float p2 = textureLod(cloud_noise, en / 3000.0 + vec2(0.71, 0.13), 3.0).r;
		float patch = smoothstep(0.3, 0.75, 0.65 * p1 + 0.35 * p2 + 0.1);
		float h = (alt - mist_floor) / max(mist_top - mist_floor, 1.0);  // 0 at the valley floor, 1 at the mean top
		float prof = 1.0 - smoothstep(-0.2, 0.7 + 0.6 * patch, h);  // densest low down, soft top that rises and falls
		m = mist * mix(0.35, 1.0, patch) * prof;
		// FogVolume density is fixed point (~1/1024 per m): dither below one step, the froxel filter and temporal
		// reprojection average it into smooth density instead of terraced contours
		m = max(m + (hash3(w * 0.173 + vec3(fract(TIME * 7.13) * 97.0)) - 0.5) * 0.0012 * step(0.0003, m), 0.0);
		d += m;
	}
	float r = distance(w, cam);
	if (rain > 0.0) {
		vec3 p = vec3(en.x - wind.x * TIME, alt + 9.0 * TIME, en.y + wind.y * TIME);
		float streak = vnoise(p * vec3(1.0 / 35.0, 1.0 / 220.0, 1.0 / 35.0));
		d += rain * smoothstep(0.35, 0.85, streak) * exp(-r / 1800.0) * below;
	}
	if (cloud > 0.0) {
		vec3 p = vec3(en.x - wind.x * TIME, alt, en.y + wind.y * TIME) / 70.0;
		d += cloud * smoothstep(0.4, 0.8, vnoise(p) * 0.65 + vnoise(p * 2.7) * 0.35) * (1.0 - smoothstep(150.0, 450.0, r));
	}
	DENSITY = d;
	ALBEDO = vec3(1.0);
	EMISSION = mist_glow * (m / max(mist, 1e-6));
}
