// MX/VertexColor: vertex colour * _TintColor, alpha blend 5/10, ZWrite off.
// not fully functional. the toon bands are our invention, BA draws the tint flat.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform float tint_alpha = 0.63137;
uniform vec3 lit_color = vec3(0.6);
uniform vec3 mid_color = vec3(0.4);
uniform vec3 shade_color = vec3(0.25);
uniform vec3 sun_color = vec3(1.0, 0.7, 0.4);
uniform vec3 haze_color = vec3(0.3, 0.15, 0.15);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float layer_alpha = 1.0;
uniform float haze_amount = 0.0;
uniform float haze_height = 0.16;
// not fully functional. baked 1 posterises the Muk clouds' own vertex shading, which reads as flat lilac bands at telephoto.
uniform int baked = 0;
instance uniform float up_half_world = 10.0;
uniform float band_soft = 0.035;
uniform float alpha_gain = 1.4;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 tone(float k) {
	float lo = smoothstep(0.35 - band_soft, 0.35 + band_soft, k);
	float hi = smoothstep(0.62 - band_soft, 0.62 + band_soft, k);
	return mix(mix(shade_color, mid_color, lo), lit_color, hi);
}

void fragment() {
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to = normalize(v_world - cam);
	float a = COLOR.a;
	float k;
	if (baked == 1) {
		float lum = dot(COLOR.rgb, vec3(0.3333));
		k = clamp(lum * 1.4, 0.0, 1.0);
	} else {
		float v = clamp(0.5 + 0.5 * (v_world.y - MODEL_MATRIX[3].y) / max(up_half_world, 0.001), 0.0, 1.0);
		k = clamp(0.75 * v + 0.25 * (1.0 - a) + 0.08, 0.0, 1.0);
	}
	vec3 col = tone(k);
	float prox = pow(max(dot(to, sun_dir), 0.0), 10.0);
	col = mix(col, col + sun_color * 0.5, prox * smoothstep(0.3, 0.7, k));
	float hz = exp(-pow(abs(to.y) / haze_height, 1.3));
	col = mix(col, haze_color, haze_amount * hz);
	ALBEDO = col;
	ALPHA = clamp(smoothstep(0.06, 0.55, a) * tint_alpha * alpha_gain * layer_alpha, 0.0, 1.0);
}
