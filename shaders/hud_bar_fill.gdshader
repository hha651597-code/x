shader_type canvas_item;
// Fill layer of HudBar: ghost, flat fill, quarter ticks and thumb inside the frame's inner rectangle, leaned like the frame.
// lp is in layer pixels. inner is the unleaned inner rectangle (x, y, w, h); shear is px of x per px of y, "/" when positive.

uniform vec4 inner = vec4(0.0, 0.0, 100.0, 10.0);
uniform float shear = 0.0;
uniform bool mirror = false;                 // anchored on the right edge, shrinking leftwards
uniform float fill = 1.0;
uniform float trail = 1.0;                   // the ghost: life lost a moment ago, drawn from fill up to trail
uniform float ticks = 0.0;                   // quarter ticks when above 0.5
uniform vec4 col_bot : source_color = vec4(1.0);
uniform vec4 ghost_col : source_color = vec4(0.949, 0.965, 1.0, 0.6);
uniform vec4 thumb_a : source_color = vec4(1.0, 0.953, 0.89, 0.85);
uniform vec4 thumb_b : source_color = vec4(1.0, 0.984, 0.929, 0.43);
uniform float radius = 2.0;

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

vec4 over(vec4 top, vec4 bot) {
	float a = top.a + bot.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + bot.rgb * bot.a * (1.0 - top.a)) / max(a, 0.00001);
	return vec4(rgb, a);
}

void fragment() {
	float cy = inner.y + inner.w * 0.5;
	vec2 q = vec2(lp.x + shear * (lp.y - cy), lp.y) - inner.xy;
	vec2 half_sz = inner.zw * 0.5;
	vec2 e = abs(q - half_sz) - half_sz + vec2(radius);
	float d = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0) - radius;
	float cover = clamp(0.5 - d / max(fwidth(d), 0.001), 0.0, 1.0);

	float u = q.x / inner.z;
	if (mirror) {
		u = 1.0 - u;
	}
	float m_trail = clamp((trail - u) * inner.z + 0.5, 0.0, 1.0);
	float m_fill = clamp((fill - u) * inner.z + 0.5, 0.0, 1.0);
	vec4 col = vec4(ghost_col.rgb, ghost_col.a * m_trail);
	col = over(vec4(col_bot.rgb, col_bot.a * m_fill), col);

	float s = u * 4.0;
	float tick = (1.0 - smoothstep(0.3, 0.9, abs(s - round(s)) * inner.z * 0.25)) * step(0.5, s) * step(s, 3.5) * step(0.5, ticks);
	col = over(vec4(0.02, 0.06, 0.15, 0.45 * tick), col);

	float dist = abs(u - fill) * inner.z;
	float edge = step(0.002, fill) * step(fill, 0.998);
	col = over(vec4(thumb_b.rgb, thumb_b.a * (1.0 - smoothstep(2.0, 3.4, dist)) * edge), col);
	col = over(vec4(thumb_a.rgb, thumb_a.a * (1.0 - smoothstep(0.8, 1.7, dist)) * edge), col);

	COLOR = vec4(col.rgb * COLOR.rgb, col.a * cover * COLOR.a);
}
