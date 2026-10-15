shader_type canvas_item;
// Fighter portrait "soft-body puppet".
//  * The quad is padded with transparent space; every pixel is mapped back to the portrait through a vertical-dependent
//    warp (lean from the hips, S-bend, feet swing, per-segment squash/stretch, chest breathing, jelly wobble) so the torso
//    leans/whips while the feet stay planted.
//  * White sticker outline (hides the low-res edge, keeps the silhouette readable), hit flash, tint/desaturation,
//    dim (super-freeze darkens everything but the caster), energy rim + soft outer glow (EX ready / super / buff / shield).
// Units: all warp amounts are fractions of the portrait HEIGHT (x offsets are divided by `aspect` into UV).

uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dim = 1.0;
uniform float desat = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform float outline_px = 5.0;      // outline radius in texture pixels
uniform float opacity = 1.0;
uniform vec4 glow_color : source_color = vec4(0.55, 0.9, 1.0, 1.0);
uniform float glow = 0.0;            // 0..1 energy rim + halo strength
uniform float lod = 1.2;             // mip level used for the main sample (keeps minification smooth)

uniform float aspect = 0.66;         // texture width / height
uniform float hip = 0.42;            // height (from the feet) of the hip joint
uniform float neck = 0.80;           // height of the neck
uniform float syl = 1.0;             // vertical scale: legs (feet..hip)
uniform float syt = 1.0;             // torso (hip..neck)
uniform float syh = 1.0;             // head (neck..top)
uniform float sx = 1.0;              // horizontal scale about the centre line
uniform float puff = 0.0;            // chest breathing bulge
uniform float lean = 0.0;            // x offset of the head relative to the hips (bend)
uniform float twist = 0.0;           // S-curve bulge of the upper body
uniform float legs = 0.0;            // x offset of the feet (walk step / kick)
uniform float sway = 0.0;            // whole-body shear
uniform float wob = 0.0;             // jelly wobble amplitude
uniform float wob_ph = 0.0;          // jelly wobble phase

// output uv (texture space, may lie outside 0..1 in the padding) -> source uv
vec2 warp(vec2 uv) {
	float x = (uv.x - 0.5) * aspect;
	float t = 1.0 - uv.y;
	float ls = hip * syl;
	float ts_ = (neck - hip) * syt;
	float s;
	if (t < ls) {
		s = t / syl;
	} else if (t < ls + ts_) {
		s = hip + (t - ls) / syt;
	} else {
		s = neck + (t - ls - ts_) / syh;
	}
	float up = clamp((s - hip) / (1.0 - hip), 0.0, 1.0);
	float off = lean * pow(up, 1.8) + twist * sin(3.14159265 * up) + sway * s;
	off += legs * pow(clamp(1.0 - s / hip, 0.0, 1.0), 1.5);
	off += wob * sin(s * 9.0 - wob_ph) * s;
	float bulge = (s - 0.62) / 0.13;
	float w = sx * (1.0 + puff * exp(-bulge * bulge));
	float xs = (x - off) / w;
	return vec2(0.5 + xs / aspect, 1.0 - s);
}

bool in_box(vec2 q, float m) {
	return q.x >= -m && q.x <= 1.0 + m && q.y >= -m && q.y <= 1.0 + m;
}

void fragment() {
	vec2 q = warp(UV);
	bool inside = in_box(q, 0.0);
	bool near = in_box(q, 0.12);
	vec4 c = vec4(0.0);
	if (inside) {
		c = textureLod(TEXTURE, q, lod);
	}
	float halo = 0.0;
	float rim = 0.0;
	if (glow > 0.001 && near) {
		float b = textureLod(TEXTURE, clamp(q, vec2(0.0), vec2(1.0)), 4.6).a;
		halo = clamp(b * 1.7, 0.0, 1.0) * glow * (1.0 - c.a) * 0.75;
		float b2 = textureLod(TEXTURE, q, 3.0).a;
		rim = (1.0 - clamp(b2 * 1.25, 0.0, 1.0)) * c.a * glow;
	}
	float edge = 0.0;
	if (inside && c.a < 0.985) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
		float n = 0.0;
		for (int i = 0; i < 10; i++) {
			float a = float(i) * 0.6283185;
			vec2 qt = warp(UV + vec2(cos(a), sin(a)) * px);
			n = max(n, textureLod(TEXTURE, clamp(qt, vec2(0.0), vec2(1.0)), lod).a);
		}
		edge = clamp(n - c.a, 0.0, 1.0) * outline_color.a;
	}
	if (!inside && halo <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		float f = clamp(flash, 0.0, 1.0);
		vec3 rgb = c.rgb * tint.rgb * dim;
		float gray = dot(rgb, vec3(0.299, 0.587, 0.114));
		rgb = mix(rgb, vec3(gray), desat);
		rgb += glow_color.rgb * rim * 0.9;
		rgb = mix(rgb, flash_color.rgb, f * c.a);
		vec3 ocol = mix(outline_color.rgb, glow_color.rgb, clamp(glow, 0.0, 1.0) * 0.55) * dim;
		vec3 col = mix(ocol, rgb, c.a);
		col = mix(col, flash_color.rgb, f * edge);
		float a_body = max(c.a, edge);
		float ha = halo * (1.0 - a_body);
		float A = a_body + ha;
		col = (col * a_body + glow_color.rgb * ha) / max(A, 0.0001);
		COLOR = vec4(col, A * opacity);
	}
}
