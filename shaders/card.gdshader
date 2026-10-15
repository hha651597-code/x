shader_type canvas_item;
// The house card: soft shadow, thick rounded white (or yellow) border, a cover-fit picture,
// optional parallelogram shear, glossy sheen and an outer glow for cursors.
// Drawn by Card (scripts/ui/card.gd) over a rect that is `margin` px larger than the card.

uniform vec2 card_size = vec2(200.0, 100.0);
uniform float radius = 18.0;
uniform float border = 5.0;
uniform vec4 border_color : source_color = vec4(1.0);
uniform vec4 fill_color : source_color = vec4(0.81, 0.9, 1.0, 1.0);
uniform sampler2D pic : source_color, filter_linear, repeat_disable;
uniform bool use_pic = true;
uniform vec2 focus = vec2(0.5, 0.5);
uniform float zoom = 1.0;
uniform float shear = 0.0;          // x offset per px of height; > 0 leans the top to the right
uniform float gloss = 0.45;
uniform float dim = 1.0;            // < 1 darkens the picture (unselected cards)
uniform float saturation = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0); // rgb tint, a = amount
uniform float shadow_amt = 0.42;
uniform float shadow_blur = 14.0;
uniform vec2 shadow_off = vec2(0.0, 6.0);
uniform vec4 shadow_color : source_color = vec4(0.03, 0.12, 0.27, 1.0);
uniform vec4 glow_color : source_color = vec4(0.3, 0.55, 1.0, 1.0);
uniform float glow_amt = 0.0;
uniform float glow_size = 10.0;
uniform float picture_alpha = 1.0;  // fade the picture towards fill_color (ghost crossfades)

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec4 over(vec4 top, vec4 bot) {
	float a = top.a + bot.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + bot.rgb * bot.a * (1.0 - top.a)) / max(a, 0.00001);
	return vec4(rgb, a);
}

void fragment() {
	vec4 mod_color = COLOR;
	vec2 half_size = card_size * 0.5;
	vec2 p = lp - half_size;
	vec2 ps = vec2(p.x + shear * p.y, p.y);
	float d = sd_round_box(ps, half_size, radius);
	float aa = max(fwidth(d), 0.001);
	float a_shape = clamp(0.5 - d / aa, 0.0, 1.0);
	float a_inner = clamp(0.5 - (d + border) / aa, 0.0, 1.0);

	vec2 inner_size = max(card_size - vec2(2.0 * border), vec2(1.0));
	vec2 uvbox = (p + half_size - vec2(border)) / inner_size;
	vec3 col = fill_color.rgb;
	if (use_pic) {
		vec2 ts = vec2(textureSize(pic, 0));
		float s = max(inner_size.x / ts.x, inner_size.y / ts.y) * zoom;
		vec2 vis = inner_size / (ts * s);
		vec2 uv0 = (vec2(1.0) - vis) * focus;
		vec4 t = texture(pic, uv0 + uvbox * vis);
		col = mix(col, t.rgb, t.a * picture_alpha);
	}
	col = mix(col, tint.rgb, tint.a);
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation) * dim;
	// glossy white wash from the top-left (the reference's bright plates)
	float g = clamp(dot(uvbox, vec2(0.55, 0.85)) / 1.1, 0.0, 1.0);
	col += vec3(1.0) * gloss * (1.0 - smoothstep(0.0, 0.85, g)) * 0.6;
	col = clamp(col, 0.0, 1.0);

	vec3 card_rgb = mix(border_color.rgb, col, a_inner);
	vec4 card = vec4(card_rgb, a_shape);

	float ds = sd_round_box(vec2(ps.x - shadow_off.x, ps.y - shadow_off.y), half_size, radius);
	float sa = shadow_amt * (1.0 - smoothstep(-shadow_blur * 0.35, shadow_blur, ds));
	vec4 under = vec4(shadow_color.rgb, sa);
	float ga = glow_amt * exp(-max(d, 0.0) / glow_size);
	under = over(vec4(glow_color.rgb, clamp(ga, 0.0, 1.0)), under);

	vec4 outc = over(card, under);
	COLOR = vec4(outc.rgb * mod_color.rgb, outc.a * mod_color.a);
}
