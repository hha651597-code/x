shader_type canvas_item;
// A fighter's mirror image on the glossy floor: strongest at the feet, fading towards the head.
uniform float strength = 0.3;
uniform vec4 tint : source_color = vec4(0.75, 0.88, 1.0, 1.0);
uniform float dim = 1.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float fade = pow(clamp(UV.y, 0.0, 1.0), 2.4);
	vec3 rgb = mix(t.rgb, tint.rgb * dot(t.rgb, vec3(0.34)) * 1.8 + tint.rgb * 0.12, 0.35) * dim;
	COLOR = vec4(rgb, t.a * strength * fade);
}
