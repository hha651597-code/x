shader_type canvas_item;
// Glossy arena floor in WORLD coordinates (a big ColorRect starting at the horizon edge): a tinted gradient, perspective
// tile grid, soft tile tones, a lit lip at the horizon and a rippled reflection of the stage backdrop read from the
// screen texture (the backdrop is drawn before the floor, the fighters after it).

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 far_col : source_color = vec4(0.88, 0.94, 1.0, 1.0);
uniform vec4 near_col : source_color = vec4(0.45, 0.62, 0.86, 1.0);
uniform vec4 line_col : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.85, 0.3, 1.0);
uniform float horizon_v = 0.86;       // screen uv.y of the horizon edge
uniform float px_to_v = 0.0014;       // screen uv units per world pixel (zoom / 720)
uniform float refl_amt = 0.42;
uniform float time = 0.0;
uniform float half_w = 860.0;         // arena half width (world px)

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

float grid_line(float g, float w) {
	float f = abs(fract(g - 0.5) - 0.5);
	float fw = max(fwidth(g), 0.0001);
	return 1.0 - smoothstep(0.0, fw * w + 0.006, f);
}

void fragment() {
	float d = lp.y;                          // world px below the horizon edge
	float wx = lp.x - 2400.0;
	float h = d + 900.0;                     // distance below the vanishing line
	float t = clamp(d / 380.0, 0.0, 1.0);
	vec3 col = mix(far_col.rgb, near_col.rgb, pow(t, 0.55));

	// perspective tiles
	float u = wx / h * 900.0;
	float z = 810000.0 / h;
	vec2 g = vec2(u / 150.0, z / 80.0);
	float chk = mod(floor(g.x) + floor(g.y), 2.0);
	col *= 1.0 + (chk - 0.5) * 0.07;
	float lines = max(grid_line(g.x, 1.4), grid_line(g.y, 1.4));
	float lfade = smoothstep(0.0, 14.0, d);
	col = mix(col, line_col.rgb, lines * 0.45 * lfade);

	// arena lanes: a lit centre mark and a bright rail at the edges
	float edge = 1.0 - smoothstep(0.0, 8.0, abs(abs(wx) - half_w - 0.0) * (900.0 / h));
	col = mix(col, accent.rgb, edge * 0.55 * lfade);
	float mid = 1.0 - smoothstep(0.0, 3.0, abs(wx) * (900.0 / h));
	col = mix(col, line_col.rgb, mid * 0.28 * lfade);

	// reflection of the backdrop (mirrored about the horizon, smeared + rippled with distance)
	vec2 suv = SCREEN_UV;
	float dv = suv.y - horizon_v;
	float rip = sin(dv * 260.0 + time * 1.4 + wx * 0.02) * 0.0016 * (0.3 + t);
	vec3 refl = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		vec2 ruv = vec2(suv.x + rip, horizon_v - dv * 1.15 - fi * 0.006 * (0.4 + t));
		refl += texture(screen_tex, clamp(ruv, vec2(0.0), vec2(1.0))).rgb;
	}
	refl /= 6.0;
	float rf = refl_amt * (1.0 - smoothstep(0.0, 1.0, t * 1.15)) + refl_amt * 0.12;
	col = mix(col, refl * 0.96, clamp(rf, 0.0, 0.8));

	// glossy sheen sweeping the floor slowly
	float sheen = exp(-pow((wx * 0.0011 - 0.1 + sin(time * 0.1) * 0.35), 2.0) * 3.0) * (1.0 - smoothstep(0.0, 0.8, t));
	col += vec3(1.0) * sheen * 0.10;

	// the lit lip at the horizon edge
	float lip = 1.0 - smoothstep(0.0, 5.0, d);
	col = mix(col, vec3(1.0), lip * 0.55);
	float lip_glow = exp(-d / 20.0) * 0.10;
	col += vec3(1.0, 1.0, 1.0) * lip_glow;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
