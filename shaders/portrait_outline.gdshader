shader_type canvas_item;
// Sticker look for a full-body portrait: a clean white outline around the transparent art plus a soft dark
// drop shadow (VS splash). Offsets are in DISPLAYED pixels; px_scale = texture pixels per displayed pixel.

uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_px = 4.0;
uniform float px_scale = 1.1;
uniform vec2 shadow_off = vec2(10.0, 12.0);
uniform float shadow_amt = 0.4;
uniform float shadow_blur = 7.0;
uniform float tint_amount = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

varying vec4 mod_color;

void vertex() {
	mod_color = COLOR;
}

vec4 over(vec4 top, vec4 bot) {
	float a = top.a + bot.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + bot.rgb * bot.a * (1.0 - top.a)) / max(a, 0.00001);
	return vec4(rgb, a);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * px_scale;
	float edge = 0.0;
	for (int i = 0; i < 16; i++) {
		float ang = float(i) * 0.39269908;
		vec2 dir = vec2(cos(ang), sin(ang));
		edge = max(edge, texture(TEXTURE, UV + dir * px * outline_px).a);
		edge = max(edge, texture(TEXTURE, UV + dir * px * outline_px * 0.55).a);
	}
	float sh = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.78539816;
		vec2 dir = vec2(cos(ang), sin(ang));
		sh += texture(TEXTURE, UV - shadow_off * px + dir * px * shadow_blur).a;
	}
	sh = sh / 8.0;
	vec4 shadow = vec4(0.0, 0.02, 0.06, sh * shadow_amt);
	vec4 ring = vec4(outline_color.rgb, edge * outline_color.a);
	vec3 art_rgb = mix(t.rgb, tint.rgb * t.rgb * 1.4, tint_amount);
	vec4 art = vec4(art_rgb, t.a);
	vec4 res = over(art, over(ring, shadow));
	COLOR = vec4(res.rgb * mod_color.rgb, res.a * mod_color.a);
}
