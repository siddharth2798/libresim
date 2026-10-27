// Per-class ground parameters for terrain.gdshader (ESA WorldCover 2021, CC BY 4.0).
// Class codes (tools/19_worldcover.py): 0 none, 1 tree, 2 shrub, 3 grass, 4 crop, 5 built-up,
// 6 bare / sparse, 7 snow / ice, 8 water (drawn by the lc water mask), 9 herbaceous wetland,
// 10 mangrove, 11 moss / lichen. Class 0 is neutral: the ground looks exactly as without wc.
// Parameters are blended bilinearly over the 4 texels around the fragment, so class borders fade.

// multiplicative albedo tint (rgb), colour desaturation (a)
const vec4 CLS_TINT[12] = vec4[12](
	vec4(1.0, 1.0, 1.0, 0.0),
	vec4(0.86, 0.95, 0.80, 0.0),    // tree cover: dark forest floor
	vec4(1.06, 0.97, 0.78, 0.0),    // shrub: dry olive
	vec4(0.95, 1.07, 0.80, 0.0),    // grass: yellow-green
	vec4(1.03, 1.01, 0.90, 0.0),    // crop: parcels vary on top of this
	vec4(0.96, 0.96, 0.99, 0.45),   // built-up: grey
	vec4(1.18, 1.00, 0.80, 0.0),    // bare / sparse: pale dry soil
	vec4(1.20, 1.20, 1.25, 0.0),
	vec4(1.0, 1.0, 1.0, 0.0),
	vec4(0.86, 0.98, 0.90, 0.0),    // wetland
	vec4(0.72, 0.90, 0.74, 0.0),    // mangrove
	vec4(0.90, 1.00, 0.86, 0.0));
// x grain (existing micro noise), y patch (30 m tonal blobs), z crop parcels + furrows, w built-up speckle
const vec4 CLS_AMP[12] = vec4[12](
	vec4(1.0, 0.0, 0.0, 0.0),
	vec4(0.55, 0.9, 0.0, 0.0),
	vec4(1.2, 1.4, 0.0, 0.0),
	vec4(0.8, 1.3, 0.0, 0.0),
	vec4(0.55, 0.5, 1.0, 0.0),
	vec4(0.45, 0.4, 0.0, 1.0),
	vec4(1.6, 1.2, 0.0, 0.0),
	vec4(0.5, 0.5, 0.0, 0.0),
	vec4(1.0, 0.0, 0.0, 0.0),
	vec4(0.5, 0.6, 0.0, 0.0),
	vec4(0.5, 0.8, 0.0, 0.0),
	vec4(0.8, 0.8, 0.0, 0.0));
// slope-following streaks (rock, scree, runoff gullies)
const float CLS_STREAK[12] = float[12](0.15, 0.0, 0.45, 0.25, 0.0, 0.0, 1.0, 0.3, 0.0, 0.0, 0.0, 0.3);

void cls_blend(ivec4 c, vec4 w, out vec3 tint, out float desat, out vec4 amp, out float streak) {
	vec4 t = CLS_TINT[c.x] * w.x + CLS_TINT[c.y] * w.y + CLS_TINT[c.z] * w.z + CLS_TINT[c.w] * w.w;
	tint = t.rgb;
	desat = t.a;
	amp = CLS_AMP[c.x] * w.x + CLS_AMP[c.y] * w.y + CLS_AMP[c.z] * w.z + CLS_AMP[c.w] * w.w;
	streak = CLS_STREAK[c.x] * w.x + CLS_STREAK[c.y] * w.y + CLS_STREAK[c.z] * w.z + CLS_STREAK[c.w] * w.w;
}
