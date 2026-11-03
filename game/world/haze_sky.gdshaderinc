// View-dependent aerial perspective colour (docs/GRAPHICS-PLAN.md G4). SkyTime fills haze_lut from the analytic
// sky (world/haze_lut.gd, the CPU twin Atmosphere.sky + the sky shader's sun glow) over (angle to the sun's
// azimuth, view elevation above the dipped horizon) whenever the sun or the haze change, so the far haze is
// warmer towards the sun, bluer away from it and meets the sky behind it without a band. Overcast, night and
// lightning stay in fog_color: the result is fog_color + clear x (sky model here - sky model fog_color was
// taken from), exactly how sky_clouds.gdshader blends its analytic sky. Needs fog_color declared before.
// Unset (no SkyTime: haze_sun.w = 0) it is plain fog_color.
#ifndef HAZE_SKY_INC
#define HAZE_SKY_INC
global uniform sampler2D haze_lut : filter_linear, repeat_disable;
global uniform vec4 haze_sun;  // xy sun azimuth (unit render x, z), z sin(horizon dip), w clear-sky weight
global uniform vec3 haze_ref;  // linear model colour fog_color was built from

const vec2 HAZE_LUT_N = vec2(32.0, 8.0);  // HazeLut.W, HazeLut.H
const float HAZE_S_MAX = 0.5;  // HazeLut.S_MAX: sine of the top row's elevation

// Haze colour (linear) seen along dir (render frame, unit, from the camera).
vec3 haze_color(vec3 dir) {
	if (haze_sun.w <= 0.0) {
		return fog_color;
	}
	float hl = length(dir.xz);
	float ca = hl > 1e-4 ? dot(dir.xz / hl, haze_sun.xy) : 1.0;
	float a = acos(clamp(ca, -1.0, 1.0)) / PI;
	float v = sqrt(clamp((dir.y + haze_sun.z) / HAZE_S_MAX, 0.0, 1.0));
	vec2 uv = (vec2(a, v) * (HAZE_LUT_N - 1.0) + 0.5) / HAZE_LUT_N;
	vec3 l = textureLod(haze_lut, uv, 0.0).rgb;
	return max(fog_color + haze_sun.w * (l - haze_ref), vec3(0.0));
}
#endif
