// ba_body.gdshader: body, clothes and weapons. Port of MX/C-General/Layer4 (ForwardLit pass).
// Provenance: our rewrite from the disassembled Blue Archive shader MX/C-General/Layer4 (pixel shader
// bytecode from the Steam install, constants from the Hina and Hoshino material files). Not for redistribution.
//
// How it works:
//  * mask_tex.a picks one of 4 material layers (skin, cloth, trim, ...): 0..0.25 / .25..0.5 / .5..0.75 / .75..1.
//    Every per-layer value below is a vec4 holding the 4 layers (x = layer 0 ... w = layer 3).
//  * mask_tex.g is a hand-painted light/shadow bias, 0.5 = neutral; mask_tex.b is a glow mask.
//  * shade term = N.L + 0.77 * N.V + bias. shade = saturate((threshold - term) * 10): a hard two-tone with a 0.1 wide edge.
//  * lit colour = light tone, shadow colour = per-layer tint * shadow tone, both multiplied with the albedo.
//  * view light, inverse view light and rim are added to the lit tone.
//  * code_add / code_mul / code_rim / code_gray are BA's _CodeAddColor / _CodeMultiplyColor / _CodeAddRimColor and its grayscale
//    mode: the hit flash, dim, super glow and KO go through them, so shading and outline survive.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://shaders/ba_light.gdshaderinc"

group_uniforms textures;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear, repeat_enable;   // import as Lossless, no mipmaps, not sRGB
uniform bool use_mask = true;                                 // false: no mask texture, whole surface is fallback_layer with neutral paint
uniform int fallback_layer : hint_range(0, 3) = 1;
uniform vec4 tint : source_color = vec4(1.0);

group_uniforms layer_shadow;
uniform vec4 shadow_threshold = vec4(0.15, 0.5, 0.91, 0.4);    // BA _ShadowThreshold4 (Hina body)
uniform vec3 shadow_tint_0 = vec3(1.0, 0.7882, 0.7216);        // from BA _ShadowTintR4/G4/B4, layer 0 (skin)
uniform vec3 shadow_tint_1 = vec3(0.3699, 0.2987, 0.4623);     // layer 1 (main cloth)
uniform vec3 shadow_tint_2 = vec3(0.4245, 0.3464, 0.2023);     // layer 2 (trim)
uniform vec3 shadow_tint_3 = vec3(0.6899, 0.6388, 0.8208);     // layer 3 (unused by the Hina mask)
uniform float mask_g_sensitivity : hint_range(0.0, 3.0) = 1.0; // how strongly the painted G channel moves the threshold

group_uniforms layer_view_light;
uniform vec4 view_offset = vec4(0.0, 0.1, 0.0, -0.5);          // BA _ViewOffset4: how far the light bends the view vector for the view-light term
uniform vec4 view_power = vec4(189.0, 9.0, 14.0, 256.0);       // _ViewPower4: sharpness
uniform vec4 view_strength = vec4(0.0, 0.2, 1.0, 0.1);         // _ViewStrength4
uniform vec4 view_edge = vec4(0.0, 1.0, 0.354, 0.44);          // _ViewLightEdge4: 0 soft, 1 hard step
uniform vec4 inv_view_power = vec4(1.0, 1.0, 2.6, 8.2);        // _InvViewPower4
uniform vec4 inv_view_strength = vec4(0.0, 0.0, 0.0, -0.4);    // _InvViewStrength4
uniform vec4 base_brightness = vec4(0.0);                      // _BaseBrightness4: flat lift per layer

group_uniforms layer_rim;
uniform vec4 rim_area = vec4(5.0);                             // _RimAreaMultiplier4: higher = thinner rim
uniform vec4 rim_strength = vec4(1.0);                         // _RimStrength4

group_uniforms glow_and_back;
uniform vec3 glow_tint = vec3(6.1199, 0.0, 8.397);             // BA _GlowTint (HDR). Cap with glow_cap if the bloom is too hot
uniform float glow_strength = 0.87;
uniform float glow_cap = 4.0;
uniform vec3 two_side_tint : source_color = vec3(1.0);

group_uniforms code_colours;
uniform vec3 code_add = vec3(0.0);       // BA _CodeAddColor
uniform vec3 code_mul = vec3(1.0);       // BA _CodeMultiplyColor
uniform vec3 code_rim = vec3(0.0);       // BA _CodeAddRimColor (added times (1 - N.V) squared)
uniform float code_gray : hint_range(0.0, 1.0) = 0.0;   // grayscale amount (KO)

void fragment() {
	vec4 base = texture(albedo_tex, UV) * tint;
	vec4 m = use_mask ? texture(mask_tex, UV) : vec4(0.0, 0.5, 0.0, (float(fallback_layer) + 0.5) * 0.25);
	int li = int(clamp(floor(m.a * 4.0), 0.0, 3.0));

	vec3 N = normalize(NORMAL);
	if (!FRONT_FACING && dot(N, VIEW) < 0.0) {
		N = -N;
	}
	vec3 L = normalize(ba_light_dir);
	vec3 V = normalize(VIEW);
	float nl = dot(N, L);
	float nv = dot(N, V);
	float fres = clamp(1.0 - nv, 0.0, 1.0);
	float gs = (1.0 - 2.0 * m.g) * mask_g_sensitivity;
	float edge = view_edge[li];

	// view light and inverse view light
	vec3 hv = normalize(V + L * view_offset[li]);
	float vl = clamp(gs + pow(clamp(dot(N, hv), 1e-5, 1.0), view_power[li]), 0.0, 1.0);
	vl = (1.0 - edge) * vl + edge * clamp((vl - 0.5) * 10.0, 0.0, 1.0);
	float ivl = clamp(gs + pow(max(fres, 1e-5), inv_view_power[li]), 0.0, 1.0);
	ivl = (1.0 - edge) * ivl + edge * min(ivl * 4000.0, 1.0);
	float boost = ivl * inv_view_strength[li] + vl * view_strength[li] + base_brightness[li];

	// two-tone shade
	float term = nl + 0.77 * nv + gs;
	float shade = clamp((shadow_threshold[li] + ba_thr_bias() - term) * 10.0, 0.0, 1.0);
	vec3 layer_tint = li == 0 ? shadow_tint_0 : (li == 1 ? shadow_tint_1 : (li == 2 ? shadow_tint_2 : shadow_tint_3));
	vec3 shadow_colour = layer_tint * ba_shadow_tone;
	vec3 tone = ba_tone(shadow_colour, shade);

	// rim
	float area = rim_area[li];
	float rim = clamp(fres * area - max(area - 1.0, 0.0), 0.0, 1.0);
	vec3 lit = tone + rim_strength[li] * rim * ba_light_data.x * ba_rim_light(nl) + boost * ba_light_tone;

	vec3 glow = min(glow_tint * (m.b * glow_strength), vec3(glow_cap));
	vec3 front = lit * base.rgb + glow;
	vec3 back = base.rgb * two_side_tint * (nl * 0.33 + 0.5) * shadow_colour;
	vec3 col = FRONT_FACING ? front : back;
	col = col * code_mul + code_add + code_rim * fres * fres;
	ALBEDO = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), code_gray);
}
