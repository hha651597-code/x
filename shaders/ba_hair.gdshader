// ba_hair.gdshader: Port of MX/C-Hair (ForwardLit pass).
// Provenance: our rewrite from the disassembled Blue Archive shader MX/C-Hair (pixel shader
// bytecode from the Steam install, constants from the Hina and Hoshino material files). Not for redistribution.
//
// Differences from the body shader:
//  * one material layer, and a much harder shade edge (width 0.05 instead of 0.1).
//  * the "angel ring": spec_tex stores a per-texel object-space strand direction in RGB and a mask in A. The highlight is a linear
//    fall-off on the lit side and a squared ramp on the other, gated to well-lit areas and multiplied by the HAIR COLOUR, not white.
//  * mask_tex.g is the painted shade bias.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://shaders/ba_light.gdshaderinc"

group_uniforms textures;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear, repeat_enable;
uniform sampler2D spec_tex : filter_linear, repeat_enable;     // BA _HairSpecTex, import Lossless, not sRGB
uniform bool use_mask = true;
uniform bool use_spec = true;
uniform vec4 tint : source_color = vec4(1.0);

group_uniforms shadow;
uniform vec3 shadow_tint : source_color = vec3(0.7366, 0.7164, 0.8679);   // BA _ShadowTint (Color, so source_color)
uniform float shadow_threshold = 0.43;
uniform float mask_g_sensitivity : hint_range(0.0, 3.0) = 1.0;
uniform float mask_r_apply : hint_range(0.0, 1.0) = 0.0;                 // BA _AdjustiveHairShadow

group_uniforms specular;
uniform vec3 spec_dir_mul = vec3(0.45, -0.01, 0.0);                     // BA _SpecDirMultiplier
uniform float spec_top_mul = 4.5;
uniform float spec_top_level = 3.5;
uniform float spec_bot_area = 0.295;
uniform float spec_bot_mul = 11.491;
uniform float spec_strength = 0.73;

group_uniforms rim_and_glow;
uniform float rim_area = 5.0;
uniform float rim_level = 4.0;
uniform float rim_strength = 1.0;
uniform vec3 glow_tint = vec3(2.0, 0.0, 1.8115);
uniform float glow_strength = 0.6;
uniform vec3 two_side_tint : source_color = vec3(1.0);

group_uniforms code_colours;
uniform vec3 code_add = vec3(0.0);
uniform vec3 code_mul = vec3(1.0);
uniform vec3 code_rim = vec3(0.0);
uniform float code_gray : hint_range(0.0, 1.0) = 0.0;   // grayscale amount (KO)

void fragment() {
	vec4 base = texture(albedo_tex, UV) * tint;
	vec4 m = use_mask ? texture(mask_tex, UV) : vec4(0.0, 0.5, 0.0, 1.0);
	vec3 N = normalize(NORMAL);
	if (!FRONT_FACING && dot(N, VIEW) < 0.0) {
		N = -N;
	}
	vec3 L = normalize(ba_light_dir);
	vec3 V = normalize(VIEW);
	vec3 H = normalize(V + L);
	float nl = dot(N, L);
	float nv = dot(N, V);
	float fres = clamp(1.0 - nv, 0.0, 1.0);

	// strand highlight
	float spec = 0.0;
	if (use_spec) {
		vec4 st = texture(spec_tex, UV);
		vec3 d = st.rgb * 2.0 - 1.0;
		vec3 strand = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * d) + vec3(1e-6));
		float x = dot(d, spec_dir_mul) + dot(strand, H);
		float bot = max(x, -spec_bot_area) + spec_bot_area;
		bot = bot * bot * spec_bot_mul;
		float top = (1.0 - x) * spec_top_mul - spec_top_level;
		spec = max((x >= 0.0 ? top : bot) - (1.0 - st.a), 0.0) * spec_strength;
	}

	float g = (use_mask ? m.g : 0.5) * 2.0 - 1.0;
	g = g - m.r * mask_r_apply;
	float term = nl + 0.77 * nv - g * mask_g_sensitivity;
	float thr = shadow_threshold + ba_thr_bias();
	float shade = clamp((thr - term) * 20.0, 0.0, 1.0);
	spec *= clamp((term - thr) * 5.0 - 0.5, 0.0, 1.0);

	float rim = clamp(fres * rim_area - rim_level, 0.0, 1.0) * rim_strength;
	vec3 shadow_colour = shadow_tint * ba_shadow_tone;
	vec3 tone = ba_tone(shadow_colour, shade);
	vec3 lit = tone + (rim + spec) * ba_light_data.x * ba_rim_light(nl);

	vec3 glow = glow_tint * (m.b * glow_strength);
	vec3 front = lit * base.rgb + glow;
	vec3 back = base.rgb * two_side_tint * (nl * 0.33 + 0.5) * shadow_colour;
	vec3 col = FRONT_FACING ? front : back;
	col = col * code_mul + code_add + code_rim * fres * fres;
	ALBEDO = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), code_gray);
}
