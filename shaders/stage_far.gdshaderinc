// The haze mixes toward Skybox/MX Gradient 2 along the fragment's own view ray.

#ifdef FF_SMOKE
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled, blend_mix;
#elif defined(FF_GLOW) || defined(FF_CARD)
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled, blend_add;
#else
render_mode unshaded, fog_disabled, depth_draw_opaque, cull_back;
#endif

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 color_mul = vec3(1.0);
uniform float cutoff = 0.5;
uniform float color_scale = 1.0;
uniform float stage_time = 0.0;

uniform vec3 sky_color = vec3(0.0);
uniform vec3 equator_color = vec3(0.0);
uniform float sky_gradient = 2.0;
uniform float equator_offset = 0.0;
uniform float haze_density = 0.0045;
uniform float haze_power = 1.4;
uniform float haze_amount = 0.95;
uniform float haze_low = 0.0;
uniform float haze_low_scale = 40.0;
uniform vec3 haze_color = vec3(0.4, 0.3, 0.3);
uniform vec4 clip_plane = vec4(0.0);

#ifdef FF_EMIS
uniform sampler2D emis_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 emis_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float emis_gain = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
#endif

#ifdef FF_SMOKE
uniform float smoke_life = 14.0;
uniform vec2 smoke_drift = vec2(6.0, 2.0);
uniform vec3 smoke_lit = vec3(0.6);
uniform vec3 smoke_shade = vec3(0.3);
uniform float smoke_alpha = 0.7;
#endif

varying vec3 v_world;
varying float v_age;
varying float v_seed;

vec3 sky_at(float y) {
	float t = clamp(1.0 - y + equator_offset, 0.0, 1.0);
	return mix(sky_color, equator_color, pow(t, sky_gradient));
}

float haze_at(float dist) {
	return clamp(1.0 - exp(-pow(max(dist, 0.0) * haze_density, haze_power)), 0.0, 1.0);
}

void vertex() {
#ifdef FF_CARD
	v_age = 0.0;
	v_seed = 0.0;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 cv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	cv.xyz *= 0.997;
	POSITION = PROJECTION_MATRIX * cv;
#elif defined(FF_SMOKE) || defined(FF_GLOW)
	vec3 c = VERTEX;
	vec2 corner = UV2;
#ifdef FF_SMOKE
	vec3 prm = COLOR.rgb * color_scale;
	float age = fract(stage_time / smoke_life + prm.y);
	c += vec3(smoke_drift.x, prm.z, smoke_drift.y) * age;
	corner *= prm.x * (0.45 + 1.15 * age);
	v_age = age;
	v_seed = prm.y;
#else
	v_age = 0.0;
	v_seed = dot(VERTEX.xz, vec2(0.13, 0.31));
#endif
	v_world = (MODEL_MATRIX * vec4(c, 1.0)).xyz;
	vec4 vc = MODELVIEW_MATRIX * vec4(c, 1.0);
	vc.xy += corner;
	POSITION = PROJECTION_MATRIX * vc;
#else
	v_age = 0.0;
	v_seed = 0.0;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
#endif
}

void fragment() {
	if (dot(clip_plane.xyz, v_world) + clip_plane.w > 0.0) {
		discard;
	}
	vec3 vd = v_world - CAMERA_POSITION_WORLD;
	float dist = length(vd);
	float h = haze_at(dist);
	// lazy implementation. will fix later :) height term is a guess, tuned by eye
	float f = (h + (1.0 - h) * haze_low * exp(-max(v_world.y, 0.0) / haze_low_scale) * clamp(dist / 120.0, 0.0, 1.0)) * haze_amount;
	vec3 sky = sky_at(vd.y / dist);
#ifdef FF_SMOKE
	vec4 t = texture(albedo_tex, UV);
	float fade = smoothstep(0.0, 0.12, v_age) * (1.0 - smoothstep(0.5, 1.0, v_age));
	ALBEDO = mix(mix(smoke_shade, smoke_lit, t.g), mix(sky, haze_color, 0.5), f * 0.6);
	ALPHA = smoothstep(0.55, 0.8, t.r) * fade * smoke_alpha;
#elif defined(FF_CARD)
	vec4 cardtex = texture(albedo_tex, UV);
	ALBEDO = cardtex.rgb * cardtex.a * COLOR.rgb * color_scale * (1.0 - f * 0.75);
	ALPHA = 1.0;
#elif defined(FF_GLOW)
	float g = texture(albedo_tex, UV).r;
	float tw = 0.85 + 0.15 * sin(stage_time * 2.3 + v_seed * 40.0);
	ALBEDO = COLOR.rgb * color_scale * g * g * tw * (1.0 - f * 0.6);
	ALPHA = 1.0;
#else
	vec3 col;
#ifdef FF_FLAT
	col = COLOR.rgb * color_scale;
#else
	vec4 tex = texture(albedo_tex, UV);
#ifdef FF_CUTOUT
	if (tex.a < cutoff) {
		discard;
	}
#endif
	col = tex.rgb * color_mul * COLOR.rgb * color_scale;
#endif
	col = mix(col, sky, f);
#ifdef FF_EMIS
	vec2 eu = (UV - emis_rect.xy) / emis_rect.zw;
	if (eu.x >= 0.0 && eu.x <= 1.0 && eu.y >= 0.0 && eu.y <= 1.0) {
		vec4 e = texture(emis_tex, eu);
		float zone = hash12(floor(vec2(v_world.z * 0.04 + v_world.x * 0.01, v_world.y * 0.08)) + UV2.x * 17.0);
		float lit = UV2.y * (zone < 0.3 ? 0.0 : (zone < 0.7 ? 0.8 : 1.8));
		float on = step(fract(e.a * 173.7 + UV2.x * 91.3), lit) * step(0.02, e.a);
		col += e.rgb * on * emis_gain * (1.0 - h * 0.5);
	}
#endif
	ALBEDO = col;
#endif
}
