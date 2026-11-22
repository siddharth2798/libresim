// Lit cockpit surface with alpha and a depth pre-pass (cockpit_surface.gdshaderinc).
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;
#define CKPT_LIT
#define CKPT_ALPHA
#include "res://aircraft/common/cockpit_surface.gdshaderinc"
