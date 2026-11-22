// Unshaded cockpit surface with alpha: overlay quads such as the FCU LCD strip (cockpit_surface.gdshaderinc).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;
#define CKPT_ALPHA
#include "res://aircraft/common/cockpit_surface.gdshaderinc"
