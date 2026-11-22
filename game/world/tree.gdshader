shader_type spatial;
render_mode cull_disabled, fog_disabled, alpha_to_coverage_and_one;
// Hemi-octahedral tree impostor (docs/GRAPHICS-PLAN.md G8). One quad per tree (UV 0..1, origin at the trunk foot,
// unit size scaled to the tree), turned here to face the camera over the species' bounding sphere. The atlas
// (TreeAtlas, baked at startup from the LOD1 meshes) holds every species from TreeOcta.N x N directions over the upper
// hemisphere: side views on the outer ring, the top view in the middle, so trees look right from the air too.
// The three frames around the view direction are blended (blend_frames, High and up; Low / Medium take the nearest),
// each sampled where the view ray through the quad meets that frame's image plane (tree_octa.gdshaderinc).
// Albedo and normal are cut-out on a transparent background, so their mip levels are premultiplied by the cover:
// dividing by it gives the true colour. The normal (frame axes, RG) is lit by the sun and sky.
// INSTANCE_CUSTOM: r = hue seed, g = species * variant_n + variant, b = value seed, a = mesh seed.
// Alpha-tested (ALPHA_SCISSOR_THRESHOLD; soft edges by alpha to coverage under MSAA): opaque-pass geometry that writes
// depth and gets the volumetric fog. Trees closer than lod_r are drawn as meshes by TreeLod: this impostor dithers
// away over lod_band metres (discard), the mesh dithers in with the opposite pattern (works on every renderer;
// visibility-range fades would act per 480 m chunk, not per tree).

global uniform vec3 fog_color;
global uniform float haze_density;
#include "res://world/curvature.gdshaderinc"  // Earth curvature (G4)
#include "res://world/haze_sky.gdshaderinc"  // view-dependent haze colour (G4)
#include "res://world/tree_tint.gdshaderinc"
#include "res://world/tree_octa.gdshaderinc"
global uniform float wetness;

uniform sampler2D atlas_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_normal : filter_linear_mipmap, repeat_disable;
uniform vec4 sp_sphere[5];  // TreeAtlas.sphere: canonical crown centre xyz, radius w
uniform vec4 sp_half[5];  // TreeAtlas.half: half extents of the canonical box around that centre
uniform float sp_aspect[5];  // TreeSpecies.ASPECT
uniform float species_n = 5.0;  // TreeSpecies.COUNT
uniform float variant_n = 4.0;  // TreeSpecies.VARIANTS
uniform float frame_px = 128.0;
uniform bool blend_frames = true;
uniform float sway_crown_m = 0.045;  // TreeLook.SWAY_CROWN_M, world metres at the crown
uniform float sway_omega = 1.3962634;  // TAU / TreeLook.SWAY_PERIOD_S
uniform float lod_r = 0.0;
uniform float lod_band = 8.0;
uniform float season_dry = 0.0;  // TreeLook.dryness

varying vec4 v_cust;
varying vec4 v_uv01;  // frame-local UVs of frames 0 and 1
varying vec4 v_misc;  // xy frame-local UV of frame 2, z species, w view distance
varying vec4 v_frames;  // xyz frame ids (i + j * N), w distance of the tree from the camera
varying vec3 v_w;  // frame weights
varying vec3 v_br;  // billboard right / up in view space
varying vec3 v_bu;

vec4 atlas_at(sampler2D tex, float id, vec2 uv, float sp) {
	vec2 f = vec2(mod(id, OCTA_N), floor(id / OCTA_N + 0.01));
	vec2 e = vec2(0.5 / frame_px);
	return texture(tex, (vec2(sp * OCTA_N, 0.0) + f + clamp(uv, e, 1.0 - e)) / vec2(species_n * OCTA_N, OCTA_N));
}

void vertex() {
	v_cust = INSTANCE_CUSTOM;
	int sp = clamp(tree_species_of(INSTANCE_CUSTOM.g, variant_n), 0, 4);
	vec4 s = sp_sphere[sp];
	vec3 asq = vec3(sp_aspect[sp], 1.0, sp_aspect[sp]);
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// camera in the canonical frame: the instance basis is yaw x scale (orthogonal columns), so no 4x4 inverse
	vec3 to_cam = CAMERA_POSITION_WORLD - wp;
	vec3 cx = MODEL_MATRIX[0].xyz, cy = MODEL_MATRIX[1].xyz, cz = MODEL_MATRIX[2].xyz;
	vec3 cam_c = vec3(dot(to_cam, cx) / dot(cx, cx), dot(to_cam, cy) / dot(cy, cy), dot(to_cam, cz) / dot(cz, cz)) * asq;
	vec3 d = cam_c - s.xyz;
	d = normalize(vec3(d.x, max(d.y, 0.0), d.z) + vec3(0.0, 1e-5, 0.0));
	vec3 br, bu;
	octa_basis(d, br, bu);
	// quad just covers the species' box seen along d (its support along each billboard axis), not the bounding circle:
	// a quarter to a half of the old area, most from above and for slim trees
	vec3 hb = sp_half[sp].xyz;
	vec2 q = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0 * vec2(dot(hb, abs(br)), dot(hb, abs(bu)));
	vec3 rel = br * q.x + bu * q.y + d * (0.5 * s.w);  // half a radius towards the camera: slopes do not cut the crown
	vec3 pc = s.xyz + rel;
	vec3 f0, f1, f2;
	octa_select(d, f0, f1, f2);
	if (blend_frames) {
		v_uv01 = vec4(octa_frame_uv(rel, d, f0.xy, s.w), octa_frame_uv(rel, d, f1.xy, s.w));
		v_misc.xy = octa_frame_uv(rel, d, f2.xy, s.w);
	} else {  // Low / Medium: the nearest frame only, one projection
		f0 = f0.z >= f1.z ? (f0.z >= f2.z ? f0 : f2) : (f1.z >= f2.z ? f1 : f2);
		f0.z = 1.0;
		f1 = vec3(f0.xy, 0.0);
		f2 = f1;
		v_uv01 = vec4(octa_frame_uv(rel, d, f0.xy, s.w), 0.0, 0.0);
		v_misc.xy = vec2(0.0);
	}
	v_frames.xyz = vec3(f0.x + f0.y * OCTA_N, f1.x + f1.y * OCTA_N, f2.x + f2.y * OCTA_N);
	v_w = vec3(f0.z, f1.z, f2.z);
	VERTEX = pc / asq;
	// TreeLook.sway_m: none at the trunk foot, sway_crown_m at the top (VERTEX is in unit tree space: divide by the scale)
	float xz = max(length(MODEL_MATRIX[0].xyz), 0.5);
	VERTEX.x += sin(TIME * sway_omega + INSTANCE_CUSTOM.a * 6.2831853) * (sway_crown_m / xz) * clamp(pc.y, 0.0, 1.0);  // seed phase: no jump at an origin shift
	mat3 to_view = mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX);
	v_br = normalize(to_view * (br / asq));
	v_bu = normalize(to_view * (bu / asq));
	v_misc.zw = vec2(float(sp), length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
	v_frames.w = distance(terrain_eye, wp);  // the camera's, also in the shadow pass (as tree_mesh)
	VERTEX += curve_local(MODEL_MATRIX, curve_drop(wp));  // whole tree, from its base
}

void fragment() {
	// dither the impostor out where the near mesh takes over
	float dn = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (dn >= smoothstep(lod_r - lod_band, lod_r, v_frames.w)) {
		discard;
	}
	float sp = v_misc.z;
	vec4 a = atlas_at(atlas_albedo, v_frames.x, v_uv01.xy, sp) * v_w.x;
	vec4 n = atlas_at(atlas_normal, v_frames.x, v_uv01.xy, sp) * v_w.x;
	if (blend_frames) {
		a += atlas_at(atlas_albedo, v_frames.y, v_uv01.zw, sp) * v_w.y + atlas_at(atlas_albedo, v_frames.z, v_misc.xy, sp) * v_w.z;
		n += atlas_at(atlas_normal, v_frames.y, v_uv01.zw, sp) * v_w.y + atlas_at(atlas_normal, v_frames.z, v_misc.xy, sp) * v_w.z;
	}
	float cov = a.a;
	float inv = 1.0 / max(cov, 0.004);
	// leaf cover thins in the mips: grow it with distance so far forests keep their density
	ALPHA = clamp(cov * (1.15 + v_misc.w / 1100.0), 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 col = a.rgb * inv;
	vec2 nxy = n.xy * inv * 2.0 - 1.0;
	float leafy = clamp((col.g - col.r) * 14.0, 0.0, 1.0);  // foliage is green, bark is not (the normal atlas is RG only)
	vec3 bd = normalize(cross(v_br, v_bu));
	NORMAL = normalize(v_br * nxy.x + v_bu * nxy.y + bd * sqrt(max(1.0 - dot(nxy, nxy), 0.0)));
	vec3 tinted = tree_season(tree_tint(col, v_cust.r, v_cust.b), int(sp + 0.5), season_dry, v_cust.r);
	col = mix(col, tinted, leafy);
	col *= mix(1.0, 0.8, wetness);
	float haze = 1.0 - exp(-v_misc.w * haze_density);
	ALBEDO = col * (1.0 - haze);
	EMISSION = haze_color(-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * haze;
	ROUGHNESS = mix(0.88, 0.55, wetness);
	SPECULAR = mix(0.06, 0.25, wetness) * (1.0 - haze);
	BACKLIGHT = col * 0.45 * leafy;
}
