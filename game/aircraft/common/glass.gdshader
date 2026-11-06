shader_type spatial;
render_mode cull_disabled;
// Cockpit glass: nearly clear head-on, increasingly mirror-like at grazing angles (Fresnel), so the
// canopy picks up the sky radiance (and its sun glint) from outside without hiding the panel.
// Defaults match the C172 canopy. MaterialFinish raises them slightly on the A320 windscreen.
uniform float pane_roughness : hint_range(0.0, 1.0) = 0.03;
uniform float pane_metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float f = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = vec3(0.55, 0.68, 0.72) * 0.45;  // faint green-blue tint
	ALPHA = mix(0.06, 0.75, f);
	ROUGHNESS = pane_roughness;
	METALLIC = pane_metallic;
	SPECULAR = 1.0;
}
