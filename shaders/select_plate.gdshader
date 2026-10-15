shader_type canvas_item;
// Character-select plate: white->pale-blue side gradient, the inverted teal trapezoid with its
// bevelled grey-blue edge strips, blurred teal skyline, translucent cyan grid with '+' marks and the thin
// vertical beam. One full-screen ColorRect in 1280x720 reference pixels.

uniform sampler2D sky : source_color, filter_linear, repeat_disable;
uniform vec2 sky_origin = vec2(0.0, -249.0);   // where the sky image's top-left lands (px)
uniform float sky_scale = 1.25;
uniform float blur_px = 3.2;
uniform float pulse = 0.0;                      // 0..1 beam shimmer
uniform float strip_w = 10.5;

varying vec2 p;

void vertex() {
	p = VERTEX;
}

float edge_x(float y) { return 258.0 + y * 0.18611; }

vec3 side_colour(float y) {
	float t = clamp((y - 118.0) / 600.0, 0.0, 1.0);
	return mix(vec3(1.0), vec3(0.684, 0.775, 0.805), t);
}

float line(float d, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 1.0, d);
}

void fragment() {
	vec3 col = side_colour(p.y);
	float xl = edge_x(p.y);
	float xr = 1280.0 - xl;
	float d = min(p.x - xl, xr - p.x);       // distance inside the outer edge of the strip
	float in_outer = smoothstep(-0.5, 0.8, d);
	float in_inner = smoothstep(strip_w - 0.5, strip_w + 0.8, d);

	// ---- teal body --------------------------------------------------------
	vec2 uv = (p - sky_origin) / (vec2(1024.0, 768.0) * sky_scale);
	vec2 px = vec2(1.0 / (1024.0 * sky_scale), 1.0 / (768.0 * sky_scale)) * blur_px;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 24; i++) {
		float fi = float(i);
		float a = fi * 2.39996323;
		float r = sqrt((fi + 0.5) / 24.0);
		acc += texture(sky, uv + vec2(cos(a), sin(a)) * r * px).rgb;
	}
	acc /= 24.0;
	float l = dot(acc, vec3(0.299, 0.587, 0.114));
	// luminance -> teal ramp (purple-navy shadows, teal mids, pale cyan highlights)
	float t = clamp((l - 0.56) * 1.55 + 0.46, 0.0, 1.0);
	vec3 c_sh = vec3(0.17, 0.20, 0.33);
	vec3 c_mid = vec3(0.37, 0.59, 0.64);
	vec3 c_hi = vec3(0.80, 0.96, 0.97);
	vec3 teal = t < 0.46 ? mix(c_sh, c_mid, t / 0.46) : mix(c_mid, c_hi, (t - 0.46) / 0.54);
	// a touch of the lower haze like the stills
	teal += vec3(0.04, 0.07, 0.07) * smoothstep(300.0, 720.0, p.y);

	// vignette next to the strips
	float vig = exp(-max(d - strip_w, 0.0) / 26.0);
	teal = mix(teal, teal * vec3(0.55, 0.66, 0.68), vig * 0.7);

	// ---- grid -------------------------------------------------------------
	const float PX = 117.0;
	const float PY = 115.0;
	vec2 g = vec2(p.x - 352.0, p.y - 70.0);
	vec2 cell = vec2(PX, PY);
	vec2 m = mod(g + cell * 0.5, cell) - cell * 0.5;          // offset to the nearest bright line
	vec2 m2 = mod(g, cell) - cell * 0.5;                       // offset to the nearest dim line
	vec3 grid_hi = vec3(0.80, 0.97, 0.98);
	vec3 grid_lo = vec3(0.12, 0.33, 0.42);
	float bright = max(line(abs(m.x), 1.6), line(abs(m.y), 1.6));
	float dim = max(line(abs(m2.x), 1.1), line(abs(m2.y), 1.1));
	teal = mix(teal, grid_lo, dim * 0.13);
	teal = mix(teal, grid_hi, bright * 0.26);
	// '+' marks: bright ones on bright crossings, dark ones on dim crossings
	float arm = 11.0;
	float plus_b = max(line(abs(m.x), 2.2) * step(abs(m.y), arm), line(abs(m.y), 2.2) * step(abs(m.x), arm));
	float plus_d = max(line(abs(m2.x), 1.8) * step(abs(m2.y), arm - 1.0), line(abs(m2.y), 1.8) * step(abs(m2.x), arm - 1.0));
	teal = mix(teal, vec3(0.14, 0.36, 0.55), plus_d * 0.34);
	teal = mix(teal, vec3(0.86, 0.99, 1.0), plus_b * (0.55 + 0.25 * pulse));

	// ---- beam ----------------------------------------------------------
	float bx = abs(p.x - 640.0);
	float by = 1.0 - smoothstep(236.0, 252.0, p.y);
	float core = (1.0 - smoothstep(0.6, 2.2, bx)) * by;
	float halo = exp(-bx / 7.0) * by * 0.20;
	float flare = exp(-length((p - vec2(640.0, 245.0)) * vec2(1.0, 1.6)) / 14.0) * (0.55 + 0.3 * pulse);
	teal = mix(teal, vec3(0.84, 1.0, 1.0), clamp(core * (0.62 + 0.18 * pulse) + halo + flare, 0.0, 1.0));

	// ---- strip (bevelled grey-blue) ------------------------------------
	float sd = clamp(d / strip_w, 0.0, 1.0);
	vec3 strip = mix(vec3(0.70, 0.76, 0.78), vec3(0.62, 0.69, 0.72), sd);
	strip = mix(vec3(0.80, 0.84, 0.85), strip, smoothstep(0.0, 0.16, sd));
	strip = mix(strip, vec3(0.44, 0.52, 0.55), smoothstep(0.84, 1.0, sd) * 0.55);

	col = mix(col, strip, in_outer);
	col = mix(col, teal, in_inner);
	COLOR = vec4(col, 1.0);
}
