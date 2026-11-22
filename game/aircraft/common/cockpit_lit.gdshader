// Lit opaque cockpit surface (cockpit_surface.gdshaderinc).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
#define CKPT_LIT
#include "res://aircraft/common/cockpit_surface.gdshaderinc"
