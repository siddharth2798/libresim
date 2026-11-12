// Inside a door portal (stencil = CabinDoorModel.PORTAL_REF, written by the mask just before), push the depth to the far
// plane so the doorway behind the unbroken skin can draw there with normal depth testing. Reverse-Z: 0.0 is far. The depth
// test stays on but inverted (a disabled test also disables depth writes): the far value always passes against the skin.
shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_always, cull_back, shadows_disabled, fog_disabled;
stencil_mode read, compare_equal, 90;

void fragment() {
	ALBEDO = vec3(0.02, 0.02, 0.022);
	ALPHA = 1.0;
	DEPTH = 0.0;
}
