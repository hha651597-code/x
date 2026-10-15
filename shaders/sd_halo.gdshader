// Halo drawn after the opaque geometry, for models whose halo would otherwise be hidden (sd.json "halo_overlay").
// Same output as ba_unlit's halo: texture times BA's halo tint, nothing else.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 base = texture(albedo_tex, UV) * tint;
	ALBEDO = base.rgb;
	ALPHA = base.a;
}
