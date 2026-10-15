shader_type canvas_item;
// The two white bands of the select screen outside the trapezoid: a faint triangle facet field and BA's halo ring behind each
// fighter's head. Draws nothing inside the trapezoid. One full-screen ColorRect in 1280x720 reference px.

uniform sampler2D field : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D ring : source_color, filter_linear, repeat_disable;
uniform vec2 head_l = vec2(238.0, 196.0);
uniform vec2 head_r = vec2(1058.0, 200.0);
uniform float field_px = 760.0;
uniform float ring_px = 500.0;
uniform float spin = 0.0;
uniform vec4 tint_l : source_color = vec4(0.93, 0.56, 0.56, 1.0);
uniform vec4 tint_r : source_color = vec4(0.5, 0.82, 1.0, 1.0);
uniform float field_a = 0.35;
uniform float ring_a = 0.5;

varying vec2 p;

void vertex() {
	p = VERTEX;
}

float edge_x(float y) { return 258.0 + y * 0.18611; }

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float inside(vec2 uv) {
	vec2 i = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return i.x * i.y;
}

void fragment() {
	float xl = edge_x(p.y);
	float edge = smoothstep(xl, xl - 3.0, p.x) + smoothstep(1280.0 - xl, 1280.0 - xl + 3.0, p.x);
	edge = clamp(edge, 0.0, 1.0);
	bool left = p.x < 640.0;
	vec2 head = left ? head_l : head_r;
	vec4 tint = left ? tint_l : tint_r;
	vec2 q = (p - head);
	vec2 fuv = vec2(left ? q.x : -q.x, q.y) / field_px + 0.5;
	vec2 ruv = rot(q, left ? spin : -spin) / ring_px + 0.5;
	float f = texture(field, fuv).a * inside(fuv) * field_a;
	float r = texture(ring, ruv).a * inside(ruv) * ring_a;
	float a = clamp(f + r, 0.0, 1.0) * edge;
	COLOR = vec4(tint.rgb, a);
}
