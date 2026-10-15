shader_type canvas_item;
// Black curtain of the crest wipe: staggered slanted slabs drop in (`cover` 0..1), later an iris hole
// opens around the emblem (`iris` = radius in px) with a glowing accent rim.

uniform float cover = 0.0;
uniform float iris = 0.0;
uniform vec2 iris_center = vec2(640.0, 360.0);
uniform vec4 accent : source_color = vec4(1.0, 0.4, 0.5, 1.0);
uniform float ring_amt = 0.0;
uniform vec4 curtain : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 px = UV * vec2(1280.0, 720.0);
	const float COL_W = 124.0;
	const float N = 13.0;
	float sx = px.x - px.y * 0.22 + 2.0 * COL_W;
	float k = floor(sx / COL_W);
	float d = 0.05;
	float p = clamp((cover - k * d) / (1.0 - (N - 1.0) * d), 0.0, 1.0);
	p = 1.0 - pow(1.0 - p, 3.0);
	float fy = px.y / 720.0;
	bool from_top = mod(k, 2.0) < 1.0;
	float front = from_top ? p : 1.0 - p;
	float covered = from_top ? step(fy, p) : step(1.0 - fy, p);
	float edge_d = abs(fy - front) * 720.0;
	float line = exp(-pow(edge_d / 5.0, 2.0)) * step(0.001, p) * (1.0 - step(0.999, p));
	float a = covered * step(0.0005, p);
	if (iris > 0.5) {
		float dist = length(px - iris_center);
		a *= smoothstep(iris - 1.5, iris + 1.5, dist);
		float ring = exp(-pow((dist - iris) / 18.0, 2.0)) * ring_amt;
		vec3 col = mix(curtain.rgb, accent.rgb * 1.2, clamp(ring, 0.0, 1.0));
		COLOR = vec4(col, clamp(a + ring * 0.85, 0.0, 1.0));
	} else {
		vec3 col = mix(curtain.rgb, accent.rgb * 1.2, line * 0.9);
		COLOR = vec4(col, max(a, line * 0.9));
	}
}
