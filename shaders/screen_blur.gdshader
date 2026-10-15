shader_type canvas_item;
// Blur + dim whatever is already on screen underneath (the stage-select overlay: the character
// select dissolves into a soft dark backdrop). `blur` is in 1280x720 reference pixels, so the
// look is the same at any window size. blur = 0, darken = 0 reproduces the screen unchanged.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur = 0.0;             // blur radius in reference pixels
uniform float darken = 0.0;           // 0..1 mix towards dark_color
uniform float dim = 1.0;              // brightness multiplier before the dark mix
uniform float desaturate = 0.0;       // 0..1 towards grey
uniform vec4 dark_color : source_color = vec4(0.02, 0.025, 0.035, 1.0);
uniform float vignette = 0.0;         // extra darkening towards the corners

void fragment() {
	float scale = float(textureSize(screen_tex, 0).x) / 1280.0;
	float px = blur * scale;                       // real pixels
	float lod = log2(max(px * 0.55, 1.0));
	vec2 r_uv = vec2(blur / 1280.0, blur / 1280.0 * 1280.0 / 720.0) * 0.5;
	vec3 acc = textureLod(screen_tex, SCREEN_UV, lod).rgb * 2.0;
	float wsum = 2.0;
	const int N = 14;
	for (int i = 0; i < N; i++) {
		float fi = float(i);
		float a = fi * 2.39996323;
		float r = sqrt((fi + 0.7) / float(N));
		vec2 o = vec2(cos(a), sin(a)) * r * r_uv;
		float w = 1.0 - r * 0.35;
		acc += textureLod(screen_tex, SCREEN_UV + o, lod).rgb * w;
		wsum += w;
	}
	vec3 c = acc / wsum;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate);
	c *= dim;
	vec2 q = SCREEN_UV - vec2(0.5);
	float v = smoothstep(0.25, 0.85, length(q * vec2(1.0, 0.8)) * 1.35);
	c = mix(c, dark_color.rgb, clamp(darken + vignette * v, 0.0, 1.0));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
