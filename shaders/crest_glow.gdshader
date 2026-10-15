shader_type canvas_item;
// Bloom for the crest emblem: the emblem SubViewport texture + two soft disc blurs added on top
// (a tight rim light and a wide halo). Radii are in 1280x720 reference pixels.

uniform float glow_near = 0.85;
uniform float glow_far = 0.55;
uniform float r_near = 5.0;
uniform float r_far = 28.0;
uniform vec4 tint : source_color = vec4(1.0);

vec4 disc(sampler2D tex, vec2 uv, float r) {
	vec3 acc = vec3(0.0);
	float a_acc = 0.0;
	const int N = 22;
	for (int i = 0; i < N; i++) {
		float fi = float(i);
		float ang = fi * 2.39996323;
		float rr = sqrt((fi + 0.5) / float(N));
		vec2 o = vec2(cos(ang), sin(ang)) * rr * r / vec2(1280.0, 720.0);
		vec4 c = texture(tex, uv + o);
		acc += c.rgb * c.a;
		a_acc += c.a;
	}
	return vec4(acc / max(a_acc, 0.0001), a_acc / float(N));
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec4 n = disc(TEXTURE, UV, r_near);
	vec4 f = disc(TEXTURE, UV, r_far);
	vec3 glow_rgb = (n.rgb * n.a * glow_near + f.rgb * f.a * glow_far) * tint.rgb;
	float glow_a = n.a * glow_near + f.a * glow_far;
	vec3 prem = base.rgb * base.a + glow_rgb * (1.0 - base.a);
	float a = clamp(base.a + glow_a * (1.0 - base.a), 0.0, 1.0);
	COLOR = vec4(prem / max(a, 0.0001), a);   // (COLOR.a at entry is the texture alpha, so it must not scale the halo)
}
