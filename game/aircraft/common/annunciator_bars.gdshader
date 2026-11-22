shader_type spatial;
// The three green bars of an Airbus FCU / EFIS pushbutton (CockpitBarLamps). The face is the button atlas, where the
// lit bars sit `dim_offset` above the unlit ones. Off: the unlit art, plain shaded paint. On: the lit art as the base
// and a soft green emission only inside the bars (their shape comes from the lit art's green channel), so the gaps
// between the bars and the window around them stay dark and nothing blooms into a blob.
render_mode cull_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 dim_offset = vec2(0.0, 0.0283203);
uniform float lit = 0.0;      // 0 off, 1 on
uniform float energy = 0.0;   // emission strength (CockpitLamps.bar_energy: day, night, dimmer, bus)
uniform vec3 glow : source_color = vec3(0.32, 1.0, 0.42);

void fragment() {
	vec3 on_c = texture(tex, UV).rgb;
	vec3 off_c = texture(tex, UV + dim_offset).rgb;
	float bars = smoothstep(0.07, 0.18, on_c.g);
	ALBEDO = mix(off_c, on_c * 0.5, lit);
	ROUGHNESS = 0.4;
	SPECULAR = 0.3;
	EMISSION = glow * bars * energy * lit;
}
