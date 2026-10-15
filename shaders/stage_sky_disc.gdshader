// Sky_Sun_Prop_01 and Sky_Moon_Prop_01 are BA's own meshes, drawn flat.
// not fully functional. BA's materials for these props were not found in the game files, so colour and blending here are ours.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec3 color = vec3(1.0);
// not fully functional. kind 0 is the flat sun disc, kind 1 the crescent moon with the black part of its vertex colour dropped.
uniform int kind = 0;

void fragment() {
	ALBEDO = color;
	ALPHA = kind == 1 ? dot(COLOR.rgb, vec3(0.3333)) : 1.0;
}
