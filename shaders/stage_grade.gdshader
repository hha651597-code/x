shader_type canvas_item;
// Full-screen grade over the blurred stage plate: gentle contrast / saturation, a soft glowing haze on the horizon,
// slow drifting light shafts from the upper left and a navy vignette. Reads the plate through the screen texture.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 tint : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform vec4 light_col : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float horizon_v = 0.86;
uniform float time = 0.0;
uniform float shaft_amt = 0.15;
uniform float vignette = 0.36;
uniform float contrast = 1.07;
uniform float saturation = 1.1;
uniform float haze_amt = 0.3;
uniform float shift = 0.0;            // parallax shift of the light source (uv)

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	c = (c - 0.5) * contrast + 0.5;
	// horizon haze (a glowing band that melts the plate into the floor)
	float dh = uv.y - horizon_v + 0.012;
	float haze = exp(-pow(dh / 0.085, 2.0)) * smoothstep(-0.02, 0.12, uv.y + 0.2);
	vec3 hz = mix(light_col.rgb, tint.rgb, 0.3);
	c = mix(c, hz, haze * haze_amt);
	// light shafts
	vec2 src = vec2(0.26 + shift, -0.32);
	vec2 d = vec2((uv.x - src.x) * 1.7778, uv.y - src.y);
	float ang = atan(d.x, d.y);
	float len = length(d);
	float b1 = 0.5 + 0.5 * sin(ang * 24.0 + 0.9 * sin(time * 0.17) + 1.0);
	float b2 = 0.5 + 0.5 * sin(ang * 9.0 - time * 0.11 + 1.3);
	float beams = smoothstep(0.38, 1.0, b1 * (0.45 + 0.55 * b2));
	float fall = exp(-len * 0.95) * (1.0 - smoothstep(horizon_v - 0.2, horizon_v + 0.02, uv.y) * 0.7);
	c += light_col.rgb * beams * fall * shaft_amt;
	// soft bloom wash from the source corner
	c += light_col.rgb * exp(-length(d) * 2.4) * 0.10;
	// vignette
	vec2 q = (uv - 0.5) * vec2(1.05, 1.25);
	float v = dot(q, q);
	c = mix(c, c * vec3(0.55, 0.66, 0.85), vignette * smoothstep(0.1, 0.5, v));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
