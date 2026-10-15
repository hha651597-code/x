// Skybox/MX Gradient 2 is the base, everything else is added on top.
// not fully functional. EYEDIR.y standing in for the skybox mesh's texcoord.y is inferred, not checked against the game.
// the stars read stage_time, never the engine clock (stage_time replaces it).
shader_type sky;

uniform vec3 _SkyColor = vec3(0.0);
uniform vec3 _EquatorColor = vec3(0.0);
uniform float _SkyGradient = 2.0;
uniform float _EquatorOffset = 0.0;

uniform vec3 haze_color = vec3(0.0);
uniform float haze_height = 0.16;
uniform float haze_strength = 0.0;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 glow_color = vec3(0.0);
uniform float glow_strength = 0.0;
uniform float glow_size = 0.4;
uniform float horizon_glow_strength = 0.0;

uniform float stars_amount = 0.0;
uniform vec3 star_color = vec3(1.0);
uniform float star_density = 0.1;
uniform float stage_time = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n + 17.0));
}

// not fully functional. the soft glow and haze bands are our invention, BA's gradient has neither.
float bands(float g, float n, float soft) {
	float x = g * n;
	float f = floor(x);
	float s = smoothstep(0.5 - soft, 0.5 + soft, fract(x));
	return (f + s) / n;
}

// not fully functional. cube-face projection, stars pinch slightly at face corners.
float star_layer(vec3 d, float scale, float dens, float size, float tw_speed) {
	vec3 a = abs(d);
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) { uv = d.yz / a.x; face = d.x > 0.0 ? 0.0 : 1.0; }
	else if (a.y >= a.z) { uv = d.xz / a.y; face = d.y > 0.0 ? 2.0 : 3.0; }
	else { uv = d.xy / a.z; face = d.z > 0.0 ? 4.0 : 5.0; }
	vec2 g = uv * scale + face * 31.7;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float on = step(1.0 - dens, hash21(id));
	vec2 off = (hash22(id + 3.1) - 0.5) * 0.6;
	float r = size * (0.45 + hash21(id + 9.7));
	float dist = length(f - off);
	float tw = 0.65 + 0.35 * sin(stage_time * tw_speed * (0.6 + hash21(id + 5.5)) + hash21(id + 1.3) * 6.2831);
	return on * smoothstep(r, r * 0.35, dist) * tw * (0.45 + 0.55 * hash21(id + 2.2));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float t = clamp(1.0 - d.y + _EquatorOffset, 0.0, 1.0);
	vec3 col = mix(_SkyColor, _EquatorColor, pow(t, _SkyGradient));

	float hz = exp(-pow(abs(d.y) / haze_height, 1.3));
	col = mix(col, haze_color, haze_strength * bands(hz, 3.0, 0.25));

	float ang = acos(clamp(dot(d, sun_dir), -1.0, 1.0));
	float g = 1.0 - smoothstep(0.0, glow_size, ang);
	col += glow_color * glow_strength * bands(g * g, 3.0, 0.45);

	vec3 sh = normalize(vec3(sun_dir.x, 0.0, sun_dir.z) + vec3(1e-5));
	vec3 dh = normalize(vec3(d.x, 0.0, d.z) + vec3(1e-5));
	float along = pow(max(dot(sh, dh), 0.0), 3.0);
	float strip = exp(-pow(abs(d.y - sun_dir.y * 0.15) / 0.12, 2.0));
	col += glow_color * horizon_glow_strength * along * bands(strip, 2.0, 0.3);

	if (stars_amount > 0.0 && d.y > 0.0) {
		float fade = smoothstep(0.03, 0.3, d.y);
		float s = star_layer(d, 70.0, star_density, 0.11, 2.3) + star_layer(d, 34.0, star_density * 0.6, 0.1, 1.5);
		col += star_color * clamp(s, 0.0, 1.0) * fade * stars_amount;
	}
	COLOR = col;
}
