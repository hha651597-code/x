shader_type canvas_item;
// The white "Player N" panel of the controller-assign overlay: rounded card, thin grey rim,
// pale-blue triangle pattern that fades to white at the bottom, BA's below-only shadow. Drawn by AssignPanel
// over a rect `margin` px larger than the card. Triangles are authored for a 367x270 panel (ref pixels).

uniform vec2 card_size = vec2(367.0, 270.0);
uniform float radius = 13.0;
uniform float flash = 0.0;                  // white flash on claim
uniform float shadow_amt = 0.30;            // BA's one shadow: 30 percent, 7 px down, 3 px at the sides, none above

float sd_round_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float edge(vec2 p, vec2 a, vec2 b) {
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
}

float in_tri(vec2 p, vec2 a, vec2 b, vec2 c) {
	float e1 = edge(p, a, b);
	float e2 = edge(p, b, c);
	float e3 = edge(p, c, a);
	float inside = (e1 >= 0.0 && e2 >= 0.0 && e3 >= 0.0) || (e1 <= 0.0 && e2 <= 0.0 && e3 <= 0.0) ? 1.0 : 0.0;
	return inside;
}

vec4 over(vec4 top, vec4 bot) {
	float a = top.a + bot.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + bot.rgb * bot.a * (1.0 - top.a)) / max(a, 0.00001);
	return vec4(rgb, a);
}

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 half_size = card_size * 0.5;
	vec2 p = lp - half_size;                     // centred on the card (lp is card-local, may be negative)
	float d = sd_round_box(p, half_size, radius);
	float aa = max(fwidth(d), 0.001);
	float a_shape = clamp(0.5 - d / aa, 0.0, 1.0);

	// pattern in 367x270 reference space
	vec2 q = (p + half_size) * vec2(367.0, 270.0) / card_size;
	vec3 col = vec3(0.780, 0.855, 0.914);                     // outer left  #c7dae9
	if (q.x > 262.0 + (q.y - 3.0) * 0.594)
		col = vec3(0.859, 0.910, 0.941);                       // right of the light triangle
	col = mix(col, vec3(0.855, 0.910, 0.945), in_tri(q, vec2(71.7, 86.7), vec2(0.0, 206.7), vec2(140.0, 206.7)));
	col = mix(col, vec3(0.796, 0.882, 0.933), in_tri(q, vec2(22.3, 0.0), vec2(263.0, 0.0), vec2(140.0, 206.7)));
	col = mix(col, vec3(0.722, 0.820, 0.898), in_tri(q, vec2(23.3, 0.0), vec2(120.0, 0.0), vec2(71.7, 86.7)));
	float light = max(in_tri(q, vec2(263.0, 3.3), vec2(368.0, 180.0), vec2(101.7, 270.0)), in_tri(q, vec2(368.0, 180.0), vec2(368.0, 270.0), vec2(101.7, 270.0)));
	col = mix(col, vec3(0.914, 0.941, 0.965), light);
	// bottom fade to white
	col = mix(col, vec3(1.0), smoothstep(150.0, 232.0, q.y));
	col = mix(col, vec3(1.0), flash * 0.6);

	// rim: thin grey-blue line + 1px white inner edge
	float rim = clamp(0.5 - (d + 1.6) / aa, 0.0, 1.0);
	vec3 rim_col = vec3(0.70, 0.74, 0.78);
	vec3 inner = mix(rim_col, col, rim);
	float white_in = smoothstep(-3.4, -1.6, d) * (1.0 - smoothstep(-1.6, -0.2, d));
	inner = mix(inner, vec3(1.0), white_in * 0.5);
	vec4 card = vec4(inner, a_shape);

	float ds = sd_round_box(p - vec2(0.0, 4.0), half_size, radius);
	float sa = shadow_amt * (1.0 - smoothstep(-1.0, 3.0, ds));
	vec4 under = vec4(0.03, 0.12, 0.27, sa);
	vec4 outc = over(card, under);
	COLOR = vec4(outc.rgb, outc.a) * vec4(1.0, 1.0, 1.0, COLOR.a);
}
