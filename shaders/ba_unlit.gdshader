// ba_unlit.gdshader: eyes, mouth, eyebrows and halo. Port of MX/C-EyesMouth, MX/C-Eyebrow and MX/C-Halo/UnlitTextured.
// Provenance: our rewrite from the disassembled Blue Archive shader MX/C-EyesMouth, MX/C-Eyebrow and MX/C-Halo (pixel shader
// bytecode from the Steam install, constants from the Hina and Hoshino material files). Not for redistribution.
//
// None of these are shaded in BA: texture * tint and nothing else. Eyebrows are pushed toward the camera (BA _ZCorrection) so they
// show through the fringe; z_push does the same in view space. Eyes, mouth and eyebrows take the colour hooks so a hit flash
// covers the face too.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, skip_vertex_transform;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool alpha_mask = true;
uniform float alpha_cutoff = 0.5;
uniform float z_push = 0.0;                   // view-space units toward the camera; eyebrows 0.03, mouth 0.01
uniform vec3 code_add = vec3(0.0);
uniform vec3 code_mul = vec3(1.0);
uniform float code_gray : hint_range(0.0, 1.0) = 0.0;   // grayscale amount (KO)

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz + vec3(0.0, 0.0, z_push);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 base = texture(albedo_tex, UV) * tint;
	if (alpha_mask && base.a < alpha_cutoff) {
		discard;
	}
	vec3 col = base.rgb * code_mul + code_add;
	ALBEDO = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), code_gray);
}
