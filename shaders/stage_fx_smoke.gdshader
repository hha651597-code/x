shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;
// follows BA DSFX/FX_SHADER_Explosion_Smoke_Flowmap_0 (decompiled).

uniform float stage_time = 0.0;

uniform sampler2D flow_tex : filter_linear, repeat_enable;
uniform sampler2D main_tex : filter_linear, repeat_disable;
uniform sampler2D lut : filter_nearest, repeat_disable;
uniform int lut_w = 64;
uniform vec4 flow_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 r_color = vec4(1.0);
uniform float flow_speed = 0.5;
uniform float g_sharpness = 20.0;
uniform float shadow_value = -0.1;
uniform float shadow_mul = 0.5;
uniform float mutiply = 1.0;
uniform vec3 pivot = vec3(0.0, 0.0, 0.4);

varying vec2 v_uv;
varying vec2 v_off;
varying vec3 v_c2;
varying vec4 v_vc;

vec4 lut_row(int row, float t) {
	float x = clamp(t, 0.0, 1.0) * float(lut_w - 1);
	int i0 = int(floor(x));
	int i1 = min(i0 + 1, lut_w - 1);
	return mix(texelFetch(lut, ivec2(i0, row), 0), texelFetch(lut, ivec2(i1, row), 0), x - float(i0));
}

void vertex() {
	float phase = INSTANCE_CUSTOM.y;
	vec4 r0 = lut_row(0, phase);
	v_off = r0.xy;
	v_c2 = lut_row(1, phase).rgb;
	v_vc = lut_row(2, phase);
	v_uv = UV;
	float size = INSTANCE_CUSTOM.w * r0.z;
	float c = cos(INSTANCE_CUSTOM.x);
	float s = sin(INSTANCE_CUSTOM.x);
	vec2 q = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y) * size;
	vec3 centre = (VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX = centre + vec3(q, pivot.z * size);
	VERTEX.z += phase < 0.0 ? 1.0e6 : 0.0;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

vec4 main_at(vec2 uv_unity) {
	return texture(main_tex, vec2(uv_unity.x, 1.0 - uv_unity.y));
}

void fragment() {
	vec2 uv = vec2(v_uv.x, 1.0 - v_uv.y);
	vec2 fuv = uv * flow_st.xy + flow_st.zw;
	vec2 flow = (texture(flow_tex, vec2(fuv.x, 1.0 - fuv.y)).rg * 2.0 - 1.0) * flow_speed;
	float p1 = fract(stage_time * 0.5);
	float p2 = fract(stage_time * 0.5 + 0.5);
	vec4 sa = main_at(uv - flow * p1);
	vec4 sb = main_at(uv - flow * p2);
	vec4 s = mix(sb, sa, abs(1.0 - 2.0 * p2));

	float alpha = (s.b > v_off.y ? 1.0 : 0.0) * s.a * v_vc.a * r_color.a;
	float shade = (s.b + shadow_value >= v_off.y) ? s.r : shadow_mul;
	vec3 body = shade * v_vc.rgb * r_color.rgb;
	float core = clamp((s.g - v_off.x) * g_sharpness, 0.0, 1.0);
	ALBEDO = mix(body, v_c2, core) * mutiply;
	ALPHA = alpha * mutiply;
}
