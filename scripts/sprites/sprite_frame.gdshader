shader_type canvas_item;
// One baked sprite frame (SpriteActor / ghosts / smear / the pixel halo). NO warping: the drawing is shown as drawn.
//  * thin white sticker outline like the portrait fighters (readability on busy stages)          [hi-res frames only]
//  * hit flash (mix to flash_color), dim (EX freeze), desaturation (KO), opacity (ghosts / invuln blink)
//  * energy rim + soft outer glow (EX ready / super / buff / shield), from a high mip level (frames are mipmapped + padded)
// PIXEL ART (`pixel_art` = true): every texel is read with texelFetch (nearest, no
// filtering, no mipmaps) and all looks are computed per ART PIXEL: flash / dim / desat recolour whole pixels, the glow is
// a stepped ring of whole pixels (1 bright ring + 1 dim ring outside the silhouette, the silhouette's own outline pixels
// tinted), no sticker outline. When the screen shows an art pixel as a WHOLE number of device pixels (the fight camera
// keeps it so, see SpritePixel) this is exact nearest sampling; only at a fractional size (camera zoom transition, odd
// window sizes) the seams between art pixels are anti-aliased over one device pixel ("sharp bilinear") so every art
// pixel still looks the same size instead of 1-2-1-2 device pixels wide.
// Uniform names match shaders/fighter.gdshader so FighterView / kits can drive both the same way.

uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dim = 1.0;
uniform float desat = 0.0;
uniform float opacity = 1.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform float outline_px = 3.0;      // outline radius in texels
uniform vec4 glow_color : source_color = vec4(0.55, 0.9, 1.0, 1.0);
uniform float glow = 0.0;
uniform bool pixel_art = false;      // pixel-art frame (see above)
uniform bool pixel_aa = true;        // pixel art at a fractional device scale: anti-alias the pixel seams (sharp bilinear)

// One art pixel, fully shaded (flash / dim / desat / stepped glow ring). t = texel, lim = last texel.
vec4 px_shade(sampler2D tex, ivec2 at, ivec2 lim) {
	ivec2 t = clamp(at, ivec2(0), lim);
	vec4 c = texelFetch(tex, t, 0);
	float ring = 0.0;     // outside the silhouette: 1 = bright ring (4-neighbour of the body), 0.45 = dim ring
	float edge = 0.0;     // inside: a body pixel on the silhouette edge (the art's own outline)
	if (glow > 0.001) {
		float n1 = 0.0;
		float n2 = 0.0;
		float hole = 0.0;
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				if (x == 0 && y == 0) {
					continue;
				}
				float s = texelFetch(tex, clamp(t + ivec2(x, y), ivec2(0), lim), 0).a;
				int md = abs(x) + abs(y);
				if (md == 1) {
					n1 = max(n1, s);
					hole = max(hole, 1.0 - s);
				} else {
					n2 = max(n2, s);
				}
			}
		}
		if (c.a < 0.5) {
			ring = n1 > 0.5 ? 1.0 : (n2 > 0.5 ? 0.45 : 0.0);
		} else {
			edge = hole > 0.5 ? 1.0 : 0.0;
		}
	}
	// stepped glow strength (a pulse moves in 4 visible steps, not a smooth fade)
	float g = ceil(clamp(glow, 0.0, 1.0) * 4.0) / 4.0;
	float f = clamp(flash, 0.0, 1.0);
	vec3 rgb = c.rgb * dim;
	float gray = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(gray), desat);
	rgb = mix(rgb, glow_color.rgb * dim, edge * g * 0.6);
	rgb = mix(rgb, flash_color.rgb, f);
	if (c.a < 0.5) {
		vec3 gc = mix(glow_color.rgb * dim, flash_color.rgb, f);
		return vec4(gc, ring * min(g * 1.25, 1.0));
	}
	return vec4(rgb, c.a);
}

void fragment() {
	vec4 vc = COLOR;
	if (pixel_art) {
		ivec2 sz = textureSize(TEXTURE, 0);
		ivec2 lim = sz - ivec2(1);
		vec2 p = UV * vec2(sz);
		// texels per device pixel along the texture's x / y (works flipped / rotated)
		vec2 d = vec2(length(vec2(dFdx(p.x), dFdy(p.x))), length(vec2(dFdx(p.y), dFdy(p.y))));
		vec2 k = 1.0 / max(d, vec2(0.00001));
		bool whole = abs(k.x - round(k.x)) < 0.04 && abs(k.y - round(k.y)) < 0.04;
		vec4 res;
		if (!pixel_aa || whole || max(d.x, d.y) >= 1.0) {
			res = px_shade(TEXTURE, ivec2(floor(p)), lim);
		} else {
			vec2 q = p - 0.5;
			vec2 b = floor(q);
			vec2 w = clamp((q - b - 0.5) / d + 0.5, 0.0, 1.0);
			ivec2 bi = ivec2(b);
			vec4 c00 = px_shade(TEXTURE, bi, lim);
			vec4 c10 = px_shade(TEXTURE, bi + ivec2(1, 0), lim);
			vec4 c01 = px_shade(TEXTURE, bi + ivec2(0, 1), lim);
			vec4 c11 = px_shade(TEXTURE, bi + ivec2(1, 1), lim);
			vec4 m0 = mix(vec4(c00.rgb * c00.a, c00.a), vec4(c10.rgb * c10.a, c10.a), w.x);
			vec4 m1 = mix(vec4(c01.rgb * c01.a, c01.a), vec4(c11.rgb * c11.a, c11.a), w.x);
			vec4 m = mix(m0, m1, w.y);
			res = vec4(m.rgb / max(m.a, 0.0001), m.a);
		}
		COLOR = vec4(res.rgb, res.a * opacity) * vc;
	} else {
		vec4 c = texture(TEXTURE, UV);
		float edge = 0.0;
		if (outline_px > 0.01 && c.a < 0.985) {
			vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
			float n = 0.0;
			for (int i = 0; i < 12; i++) {
				float a = float(i) * 0.5235988;
				n = max(n, texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px).a);
			}
			edge = clamp(n - c.a, 0.0, 1.0) * outline_color.a;
		}
		float halo = 0.0;
		float rim = 0.0;
		if (glow > 0.001) {
			float b = textureLod(TEXTURE, UV, 4.6).a;
			halo = clamp(b * 1.7, 0.0, 1.0) * glow * 0.75;
			float b2 = textureLod(TEXTURE, UV, 3.0).a;
			rim = (1.0 - clamp(b2 * 1.25, 0.0, 1.0)) * c.a * glow;
		}
		float f = clamp(flash, 0.0, 1.0);
		vec3 rgb = c.rgb * dim;
		float gray = dot(rgb, vec3(0.299, 0.587, 0.114));
		rgb = mix(rgb, vec3(gray), desat);
		rgb += glow_color.rgb * rim * 0.9;
		rgb = mix(rgb, flash_color.rgb, f);
		vec3 ocol = mix(outline_color.rgb, glow_color.rgb, clamp(glow, 0.0, 1.0) * 0.55) * dim;
		ocol = mix(ocol, flash_color.rgb, f);
		float a_body = max(c.a, edge);
		vec3 col = mix(ocol, rgb, c.a / max(a_body, 0.0001));
		float ha = halo * (1.0 - a_body);
		float A = a_body + ha;
		col = (col * a_body + glow_color.rgb * ha) / max(A, 0.0001);
		COLOR = vec4(col, A * opacity) * vc;
	}
}
