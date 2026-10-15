shader_type canvas_item;
// The menu's student fades out where the tile grid begins, so wide art never shows through a gutter.
uniform float fade_from = 520.0;
uniform float fade_to = 592.0;
varying float gx;

void vertex() {
	gx = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).x;
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.a *= 1.0 - smoothstep(fade_from, fade_to, gx);
}
