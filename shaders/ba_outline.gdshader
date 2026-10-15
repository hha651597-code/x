// ba_outline.gdshader: Blue Archive's Outline pass (Cull Front inverted hull). Use as a next_pass material.
// Provenance: our rewrite from the disassembled Blue Archive shader Outline passes (Layer4, Hair, Face, Weapon: identical; pixel shader
// bytecode from the Steam install, constants from the Hina and Hoshino material files). Not for redistribution.
//
//  * the hull is moved in clip space along the projected 2D normal by a constant number of pixels, so the line has the SAME PIXEL
//    WIDTH at every distance (BA: 0.002 NDC, 0.1 % of the screen width, times the painted vertex alpha).
//  * the colour is texture * outline_tint * light tone, not black: BA's body tint is 0.13 grey, faces use a warm skin tone, hair a
//    dark version of its colour.
//  * the GLBs here have no COLOR_0 and no smoothed hull normals, so thickness is one uniform and the hull uses the shading
//    normals. Restoring both from BA's meshes (keyed by rest position) is the next step.
// width_px is in pixels of the viewport this mesh renders into (the actor's SubViewport, not screen pixels).

shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

#include "res://shaders/ba_light.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 outline_tint : source_color = vec3(0.1321);   // BA _OutlineTint, Hina body
uniform float width_px = 1.6;
uniform float depth_push = 0.02;                           // view-space units away from the camera
uniform vec3 code_mul = vec3(1.0);

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.z -= depth_push;
	vec4 clip = PROJECTION_MATRIX * vp;
	vec3 n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 dir = n.xy * vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]);
	dir = dir / max(length(dir), 1e-5);
	clip.xy += dir * (2.0 / VIEWPORT_SIZE) * width_px * clip.w;
	POSITION = clip;
}

void fragment() {
	vec4 base = texture(albedo_tex, UV) * tint;
	ALBEDO = base.rgb * outline_tint * ba_light_tone * ba_light_data.x * code_mul;
}
