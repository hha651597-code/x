
#ifndef BA_CULL
#define BA_CULL cull_back
#endif

#ifdef BA_BLEND
render_mode unshaded, fog_disabled, depth_draw_never, BA_BLEND, BA_CULL;
#else
#ifdef BA_TRANSPARENT
render_mode unshaded, fog_disabled, depth_draw_never, BA_CULL;
#else
render_mode unshaded, fog_disabled, depth_draw_opaque, BA_CULL;
#endif
#endif

uniform int ba_shader = 0;
uniform int env_mode = 0;

uniform vec4 _Color = vec4(1.0);
uniform sampler2D _MainTex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 _MainTex_ST = vec4(1.0, 1.0, 0.0, 0.0);
uniform float _Cutoff = 0.5;

uniform float stage_time = 0.0;

uniform bool use_lightmap = false;
uniform sampler2D lightmap : filter_linear_mipmap, repeat_disable;
uniform float _LightmapStrength = 1.0;

uniform sampler2D _ReflectTex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 _ReflectTex_ST = vec4(1.0, 1.0, 0.0, 0.0);
uniform float _ReflectBaseAmount = 0.0;
uniform float _ReflectAnglePower = 1.0;
uniform float _ShadowAttenRefl = 0.0;
uniform float _ReflectStrength = 0.0;

uniform sampler2D _EmissionTex : source_color, filter_linear_mipmap, repeat_enable;
uniform float _EmissionStrength = 0.0;

uniform sampler2D _SpecTex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 _SpecLightDir = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec4 _SpecLightColor = vec4(0.0);
uniform float _SpecPower = 1.0;
uniform float _ShadowAttenSpec = 0.0;

uniform vec4 sh_ar = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sh_ag = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sh_ab = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 sh_br = vec4(0.0);
uniform vec4 sh_bg = vec4(0.0);
uniform vec4 sh_bb = vec4(0.0);
uniform vec4 sh_c = vec4(0.0);

uniform vec3 subtractive_shadow_color = vec3(1.0);
uniform float main_light_shadow_strength = 0.0;
uniform vec4 shadow_blobs[2];

uniform float z_offset = 0.0;
uniform vec4 clip_plane = vec4(0.0);

#ifdef BA_FOLIAGE
// not fully functional. BA has no foliage motion in its battle maps (339 scene bundles checked), so the sway is ours and stays off while wind_amp is 0.
uniform float wind_amp = 0.0;
uniform float wind_speed = 1.6;
uniform vec2 wind_dir = vec2(1.0, 0.35);
instance uniform vec3 inst_light = vec3(-1.0);
instance uniform float inst_phase = 0.0;
instance uniform vec2 inst_sway = vec2(0.0, 1.0);
instance uniform float inst_wind = 1.0;
#endif

varying vec3 v_world;
varying vec3 v_sh;
varying vec2 v_ruv;
varying float v_term;

vec3 sh9(vec3 n) {
	vec4 p = vec4(n, 1.0);
	vec3 res = vec3(dot(sh_ar, p), dot(sh_ag, p), dot(sh_ab, p));
	vec4 vb = n.xyzz * n.yzzx;
	res += vec3(dot(sh_br, vb), dot(sh_bg, vb), dot(sh_bb, vb));
	res += sh_c.rgb * (n.x * n.x - n.y * n.y);
	return res;
}

// not fully functional. BA's shadow is the URP shadow map, this circle is a stand-in (xyz feet, w radius, w 0 is off).
float blob_mask(vec3 p) {
	float m = 0.0;
	for (int i = 0; i < 2; i++) {
		vec4 b = shadow_blobs[i];
		if (b.w > 0.0) {
			float d = length(p.xz - b.xz) / b.w;
			float dy = abs(p.y - b.y) / b.w;
			m = max(m, (1.0 - smoothstep(0.0, 1.0, d)) * (1.0 - smoothstep(0.0, 1.0, dy)));
		}
	}
	return m;
}

void vertex() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y) * _MainTex_ST.xy + _MainTex_ST.zw;
	UV = vec2(uv.x, 1.0 - uv.y);

#ifdef BA_FOLIAGE
	{
		float span = inst_sway.y - inst_sway.x;
		float w = clamp((VERTEX.y - inst_sway.x) / (abs(span) > 1e-4 ? span : 1e-4), 0.0, 1.5);
		w *= w;
		float t = stage_time * wind_speed + inst_phase + dot(NODE_POSITION_WORLD.xz, vec2(0.37, 0.21));
		float sw = sin(t) + 0.45 * sin(t * 2.3 + 1.7);
		VERTEX += inverse(mat3(MODEL_MATRIX)) * (vec3(wind_dir.x, 0.0, wind_dir.y) * (wind_amp * inst_wind * w * sw));
	}
#endif
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	v_sh = vec3(1.0);
	v_ruv = vec2(0.0);
	v_term = 0.0;
	if (ba_shader == 0) {
		if (!use_lightmap) {
			v_sh = max(sh9(vec3(-n.x, n.y, n.z)), vec3(0.0));
		}
		if (env_mode == 3) {
			vec2 r = -v.zy * _ReflectTex_ST.xy + _ReflectTex_ST.zw;
			v_ruv = vec2(r.x, 1.0 - r.y);
			v_term = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), _ReflectAnglePower);
		} else if (env_mode == 5) {
			v_term = pow(clamp(dot(n, normalize(v + _SpecLightDir.xyz)), 0.0, 1.0), _SpecPower);
		}
	}

	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z -= z_offset * 2e-5 * POSITION.w;
}

void fragment() {
	if (dot(clip_plane.xyz, v_world) + clip_plane.w > 0.0) {
		discard;
	}

	vec4 tex = texture(_MainTex, UV);
	vec3 col;
	float a;
	if (ba_shader == 1) {
		col = tex.rgb * _Color.rgb;
		a = tex.a * _Color.a;
	} else if (ba_shader == 2) {
		col = COLOR.rgb * _Color.rgb;
		a = COLOR.a * _Color.a;
	} else {
		vec3 lm = v_sh;
		if (use_lightmap) {
			lm = mix(vec3(1.0), texture(lightmap, vec2(UV2.x, 1.0 - UV2.y)).rgb, _LightmapStrength);
		}
#ifdef BA_FOLIAGE
		if (inst_light.x >= 0.0) {
			lm = inst_light;
		}
#endif
		lm = min(lm, mix(subtractive_shadow_color, lm, 1.0 - main_light_shadow_strength * blob_mask(v_world)));
		col = lm * tex.rgb * _Color.rgb;
		a = _Color.a;
		if (env_mode == 1) {
			if (tex.a < _Cutoff) {
				discard;
			}
			a = tex.a * _Color.a;
		} else if (env_mode == 2) {
			a = tex.a * _Color.a;
		} else if (env_mode == 3) {
			float k = clamp(lm.r + lm.g + lm.b - _ShadowAttenRefl, 0.0, 1.0) * tex.a * _ReflectStrength * (v_term + _ReflectBaseAmount);
			col += texture(_ReflectTex, v_ruv).rgb * k;
		} else if (env_mode == 4) {
			col += texture(_EmissionTex, UV).rgb * tex.a * _EmissionStrength;
		} else if (env_mode == 5) {
			float k = clamp((lm.r + lm.g + lm.b) * 0.333 - _ShadowAttenSpec, 0.0, 1.0) * tex.a * v_term;
			col += k * _SpecLightColor.rgb * texture(_SpecTex, UV).rgb;
		}
	}

#ifdef BA_MUL2X
	col *= 2.0;
#endif
	ALBEDO = col;
#ifdef BA_TRANSPARENT
	ALPHA = a;
#endif
}
