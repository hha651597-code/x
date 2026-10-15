shader_type canvas_item;
// Blurs + darkens whatever is already on screen (the menu under the controller-assign overlay).
// Mip-chain blur of the screen texture plus a small golden-angle disc so it stays smooth.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 1.0;   // 0 = untouched, 1 = fully blurred + darkened
uniform float lod = 3.2;
uniform float spread = 0.012;
uniform float darken = 0.45;
uniform vec4 dark_color : source_color = vec4(0.012, 0.025, 0.05, 1.0);

void fragment() {
	vec3 acc = vec3(0.0);
	const int N = 14;
	for (int i = 0; i < N; i++) {
		float fi = float(i);
		float a = fi * 2.39996323;
		float r = sqrt((fi + 0.5) / float(N));
		vec2 o = vec2(cos(a), sin(a) * 1.7778) * r * spread * amount;
		acc += textureLod(screen_tex, SCREEN_UV + o, lod * amount).rgb;
	}
	vec3 blurred = acc / float(N);
	vec3 sharp = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 c = mix(sharp, blurred, amount);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 0.85);
	c = mix(c, dark_color.rgb, darken * amount);
	COLOR = vec4(c, 1.0);
}
