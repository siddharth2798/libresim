shader_type fog;
// A rain curtain under a storm cell (world/volumetric_fog.gd, cells from CloudStorm): a cylinder FogVolume from the
// ground to the cloud base. Densest at the core, ragged edges, falling streaks, a darker grey than the clear air.

uniform float density = 0.004;  // 1/m at the core
uniform float seed = 0.0;
uniform vec2 drift = vec2(0.0);  // m/s render x / z: the shafts lean and slide with the wind

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

void fog() {
	vec3 c = UVW * 2.0 - 1.0;  // -1..1 inside the cylinder's box
	float lean = 1.0 - UVW.y;  // the shafts trail behind the cell lower down
	vec2 xz = c.xz - drift * 0.004 * lean;
	float r = length(xz);
	vec3 p = vec3(xz.x * 6.0 + seed, UVW.y * 1.5 + TIME * 0.35, xz.y * 6.0 - seed);
	float sheets = vnoise(p) * 0.6 + vnoise(p * vec3(2.3, 0.5, 2.3)) * 0.4;
	float edge = 1.0 - smoothstep(0.35 + 0.35 * sheets, 1.0, r);
	float vert = smoothstep(0.0, 0.06, UVW.y) * (1.0 - 0.5 * smoothstep(0.5, 1.0, UVW.y));  // merges into the base
	DENSITY = density * edge * vert * mix(0.45, 1.0, sheets);
	ALBEDO = vec3(0.7, 0.72, 0.76);
}
