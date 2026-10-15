// Drawn on the Sprite2D that shows the fighter's SubViewport. Flash, dim and KO live in the character shaders (ba_*.gdshader), and the
// outline is the inverted hull of ba_outline.gdshader.
shader_type canvas_item;

uniform float opacity = 1.0;
// The transparent MSAA viewport resolves an edge pixel as colour times coverage in linear space and then sRGB-encodes it, so
// straight-alpha blending darkens every edge (50 percent coverage reads about 0.70 of the interior). Un-premultiplying in linear
// space first gives back the interior colour.
uniform bool fix_fringe = true;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}

void fragment() {
	vec4 paint = COLOR;
	if (fix_fringe && paint.a > 0.02 && paint.a < 0.999) {
		paint.rgb = min(to_srgb(to_linear(max(paint.rgb, vec3(0.0))) / paint.a), vec3(1.0));
	}
	COLOR = vec4(paint.rgb, paint.a * opacity);
}
