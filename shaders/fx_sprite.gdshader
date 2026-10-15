shader_type canvas_item;
render_mode blend_premul_alpha;
// BA effect sprite: draws one flipbook frame of a curated FX sheet.
// add_amount 0: normal alpha blend; 1: pure additive (the premultiplied output keeps its colour and drops its alpha).
// lum_alpha 1: the sheet is white-on-black with no real alpha (the game's DXT1 sheets). Its colour is already premultiplied
//   against black and its alpha is the brightest channel.
// gray 1: keep only the sheet's brightness, so a sheet with baked colour (Hit_06 is yellow) takes any tint cleanly.
// erode 1: the sprite's modulate alpha is not opacity but "how much of the shape is left". Pixels whose mask value is
//   below (1 - modulate.a) drop out with a hard edge, so the shape shrinks instead of fading. The mask is mask_tex when
//   use_mask is 1, else the sheet's own luminance. It only bites on sheets that have a gradient.
// solid 1: whatever survives the erode is drawn flat in the tint, so a soft glow sheet (the hexagon) becomes a hard line
//   whose width is the erode power.
// ring_w > 0: the mask is also floored by a radial ramp that is 1 on the circle's rim (0.89 of the half width) and falls to 0
//   ring_w further in, so an eroded ring keeps a continuous band whose thickness is (1 - power) * ring_w, with the mask
//   still ragging its inner edge (half of the mask above 0.3 pushes the band inward). Single-frame circle sheets only.
// Nothing here reads the shader clock: the EX freeze stops world nodes, and effects are driven by their own age.

uniform sampler2D mask_tex : hint_default_white, filter_linear, repeat_disable;
uniform float lum_alpha = 1.0;
uniform float add_amount = 0.0;
uniform float erode = 0.0;
uniform float use_mask = 0.0;
uniform float soft = 0.06;
uniform float gray = 0.0;
uniform float ring_w = 0.0;
uniform float solid = 0.0;

varying vec4 vtint;

void vertex() {
	vtint = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float lum = max(t.r, max(t.g, t.b));
	float a = mix(t.a, lum, lum_alpha);
	vec3 base = mix(t.rgb, vec3(dot(t.rgb, vec3(0.299, 0.587, 0.114))), gray) * vtint.rgb;
	if (solid > 0.5) {
		a = 1.0;
		base = vtint.rgb;
	}
	float k = vtint.a;
	if (erode > 0.5) {
		float m = mix(lum, texture(mask_tex, UV).r, use_mask);
		if (ring_w > 0.0) {
			m = 1.0 - (0.89 - length(UV - 0.5) * 2.0) / ring_w + 0.5 * (m - 0.3);
		}
		float power = 1.0 - vtint.a;
		k = smoothstep(power, power + soft, m);
	}
	vec3 prem = mix(base * a, base, lum_alpha) * k;
	COLOR = vec4(prem, a * k * (1.0 - add_amount));
}
