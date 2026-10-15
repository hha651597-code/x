// tint is a plain vec3 because Godot linearises source_color.
// not fully functional. the card is ours, BA's FX_MAT_Circle_Glow cards were not ported, this is a soft additive texture added over the map.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D glow_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0, 0.6, 0.3);
uniform float intensity = 1.0;
uniform float flicker = 0.0;
uniform float stage_time = 0.0;
uniform float seed = 0.0;

varying float wobble;

void vertex() {
	float t = stage_time + seed * 7.31;
	wobble = 1.0 + flicker * (0.6 * sin(t * 13.0) + 0.4 * sin(t * 5.3 + 1.7));
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz)) * wobble;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * mat4(vec4(scale.x, 0.0, 0.0, 0.0), vec4(0.0, scale.y, 0.0, 0.0), vec4(0.0, 0.0, scale.z, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	ALBEDO = tint * texture(glow_tex, UV).rgb * intensity * wobble;
	ALPHA = 1.0;
}
