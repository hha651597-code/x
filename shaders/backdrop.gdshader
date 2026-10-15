shader_type canvas_item;
// Blurred, tinted scenic backdrop (menu, assign, select). Disc blur in UV space, then tint,
// saturation, brightness and a dark mix (used when an overlay covers the screen).

uniform float radius = 0.012;
uniform float aspect = 1.3333;
uniform vec4 tint : source_color = vec4(0.25, 0.55, 0.95, 1.0);
uniform float tint_amount = 0.35;
uniform float brightness = 1.0;
uniform float saturation = 1.1;
uniform float darken = 0.0;
uniform vec4 dark_color : source_color = vec4(0.02, 0.05, 0.12, 1.0);

void fragment() {
	const int N = 32;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < N; i++) {
		float fi = float(i);
		float a = fi * 2.39996323;
		float r = sqrt((fi + 0.5) / float(N));
		vec2 o = vec2(cos(a), sin(a) * aspect) * r * radius;
		acc += texture(TEXTURE, UV + o).rgb;
	}
	vec3 c = acc / float(N);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = mix(c, c * tint.rgb * 1.7, tint_amount);
	c *= brightness;
	c = mix(c, dark_color.rgb, darken);
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0) * COLOR.a;
}
