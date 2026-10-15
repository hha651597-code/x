// ba_face.gdshader: Port of MX/C-Face (ForwardLit, vertex and pixel).
// Provenance: our rewrite from the disassembled Blue Archive shader MX/C-Face (pixel shader
// bytecode from the Steam install, constants from the Hina and Hoshino material files). Not for redistribution.
//
//  * the face is lit by its own light, face_light_dir, in OBJECT space (BA default (-0.3419, 0.9397, 0)) and rotated with the mesh
//    node, so it follows the facing yaw and the tilt layer but not the head bone.
//  * the shade edge is soft: saturate((threshold - term) * 2), 0.5 wide, against 0.1 for the body and 0.05 for the hair.
//  * no spec, no view light. Only shade, rim and the colour hooks.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://shaders/ba_light.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : filter_linear, repeat_enable;
uniform bool use_mask = true;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 face_light_dir = vec3(-0.3419, 0.9397, 0.0);          // object space, toward the light
uniform vec3 shadow_tint : source_color = vec3(1.0, 0.7882, 0.7216);
uniform float shadow_threshold = 0.7;
uniform float mask_g_sensitivity : hint_range(0.0, 3.0) = 1.0;
uniform float mask_r_apply : hint_range(0.0, 1.0) = 0.0;
uniform float view_bias = 0.0;   // added to the shade term: the fighters are seen 65 degrees off BA's near-frontal camera
uniform float rim_area = 3.0;
uniform float rim_level = 2.0;
uniform float rim_strength = 1.0;
uniform vec3 code_add = vec3(0.0);
uniform vec3 code_mul = vec3(1.0);
uniform vec3 code_rim = vec3(0.0);
uniform float code_gray : hint_range(0.0, 1.0) = 0.0;   // grayscale amount (KO)

varying vec3 face_l_view;

void vertex() {
	face_l_view = normalize((MODELVIEW_MATRIX * vec4(face_light_dir, 0.0)).xyz);
}

void fragment() {
	vec4 base = texture(albedo_tex, UV) * tint;
	vec4 m = use_mask ? texture(mask_tex, UV) : vec4(0.0, 0.5, 0.0, 1.0);
	vec3 N = normalize(NORMAL);
	if (!FRONT_FACING && dot(N, VIEW) < 0.0) {
		N = -N;
	}
	vec3 V = normalize(VIEW);
	float nl = dot(N, normalize(face_l_view));
	float nv = dot(N, V);
	float fres = clamp(1.0 - nv, 0.0, 1.0);
	float g = m.g * 2.0 - 1.0 - m.r * mask_r_apply;
	float term = nv * 0.77 + nl + view_bias - g * mask_g_sensitivity;
	float thr = shadow_threshold + ba_thr_bias();
	float shade = clamp((thr - term) * 2.0, 0.0, 1.0);
	vec3 tone = ba_tone(shadow_tint * ba_shadow_tone, shade);
	float rim = clamp(fres * rim_area - rim_level, 0.0, 1.0) * rim_strength * ba_light_data.x;
	// the face rim uses the body-light N.L so the rim stays on the lit side of the head
	float n_dot_key = dot(N, normalize(ba_light_dir));
	vec3 col = (tone + rim * ba_rim_light(n_dot_key)) * base.rgb;
	col = col * code_mul + code_add + code_rim * fres * fres;
	ALBEDO = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), code_gray);
}
