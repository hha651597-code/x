shader_type canvas_item;
// Big fighter art on the select screen: soft drop shadow (the dark halo around the figures in the stills),
// optional blur (when a Special panel opens over this side) and a white wash for the fading ghost.

uniform float shadow_px = 10.0;                    // shadow blur radius in TEXTURE pixels
uniform float shadow_amt = 0.42;
uniform vec2 shadow_off = vec2(5.0, 9.0);          // texture px
uniform float blur_px = 0.0;                       // colour blur radius in TEXTURE pixels (0 = sharp)
uniform float wash = 0.0;                          // 0..1 mix towards white
uniform float dim = 1.0;
uniform float saturation = 1.0;

vec4 over(vec4 top, vec4 bot) {
	float a = top.a + bot.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + bot.rgb * bot.a * (1.0 - top.a)) / max(a, 0.00001);
	return vec4(rgb, a);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 base;
	if (blur_px > 0.5) {
		vec4 acc = vec4(0.0);
		for (int i = 0; i < 40; i++) {
			float fi = float(i);
			float a = fi * 2.39996323;
			float r = sqrt((fi + 0.5) / 40.0);
			vec4 t = texture(TEXTURE, UV + vec2(cos(a), sin(a)) * r * px * blur_px);
			acc += vec4(t.rgb * t.a, t.a);
		}
		acc /= 40.0;
		base = vec4(acc.rgb / max(acc.a, 0.0001), acc.a);
	} else {
		base = texture(TEXTURE, UV);
	}
	float sh = 0.0;
	for (int i = 0; i < 14; i++) {
		float fi = float(i);
		float a = fi * 2.39996323;
		float r = sqrt((fi + 0.5) / 14.0);
		sh += texture(TEXTURE, UV - shadow_off * px + vec2(cos(a), sin(a)) * r * px * shadow_px).a;
	}
	sh /= 14.0;
	vec4 shadow = vec4(0.04, 0.11, 0.17, sh * shadow_amt);
	vec3 rgb = base.rgb;
	float l = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(vec3(l), rgb, saturation) * dim;
	rgb = mix(rgb, vec3(1.0), wash);
	vec4 res = over(vec4(rgb, base.a), shadow);
	COLOR = vec4(res.rgb, res.a * COLOR.a);
}
