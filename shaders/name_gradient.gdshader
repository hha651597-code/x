shader_type canvas_item;
// BA's headline gradient on white text: white at y_top, bottom at y_bottom (the node's local px). Outlines are dark, so only
// the bright fill is tinted.

uniform float y_top = 0.0;
uniform float y_bottom = 50.0;
uniform vec3 bottom : source_color = vec3(0.839, 0.929, 1.0);

varying float ly;

void vertex() {
	ly = VERTEX.y;
}

void fragment() {
	float t = clamp((ly - y_top) / max(y_bottom - y_top, 1.0), 0.0, 1.0);
	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(COLOR.rgb, COLOR.rgb * bottom, t * smoothstep(0.5, 0.9, lum));
}
