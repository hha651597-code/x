shader_type canvas_item;
// EX cut-in portrait: a coloured halo glow + crisp white rim around the transparent art, a white-out flash and a
// brightness push. Offsets are in TEXTURE pixels.

uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.6, 1.0);
uniform float glow_px = 22.0;
uniform float glow_amt = 1.0;
uniform float rim_px = 4.0;
uniform float flash = 0.0;
uniform float brighten = 0.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float g = 0.0;
	for (int i = 0; i < 24; i++) {
		float fi = float(i);
		float a = fi * 2.39996323;
		float r = sqrt((fi + 0.5) / 24.0);
		g += texture(TEXTURE, UV + vec2(cos(a), sin(a)) * r * px * glow_px).a;
	}
	g /= 24.0;
	float glow = clamp(g * 2.2, 0.0, 1.0) * glow_amt;
	float rim = 0.0;
	for (int j = 0; j < 12; j++) {
		float a2 = float(j) * 0.5235988;
		rim = max(rim, texture(TEXTURE, UV + vec2(cos(a2), sin(a2)) * px * rim_px).a);
	}
	vec3 art = t.rgb * (1.0 + brighten) + vec3(flash);
	vec3 col = mix(glow_color.rgb, vec3(1.0), clamp(rim, 0.0, 1.0));
	col = mix(col, art, t.a);
	float alpha = max(t.a, max(glow * (1.0 - t.a), rim));
	COLOR = vec4(col, alpha) * COLOR;
}
