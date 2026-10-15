class_name FxArt
extends RefCounted
## BA effect textures: the registry of curated sheets in assets/ba/fx, flipbook frame sizes, and the shared sprite materials.
## lum: the sheet is white-on-black with no real alpha, so the shader takes alpha from luminance.
## gray: the sheet has baked colour; the shader keeps only its brightness so any tint works.
## solid: with erode, what is left is drawn flat in the tint (a hard line out of a soft glow sheet).
## ring_w: a mask sheet that also gives an eroding circle a radial floor (see the shader), so the ring stays one band.

const DIR := "res://assets/ba/fx/"
const SHADER := preload("res://shaders/fx_sprite.gdshader")

const SHEETS := {
	"hit_star": {"file": "spark/hit_star_burst_2x2.png", "cols": 2, "rows": 2, "lum": true, "gray": true},
	"hit_star_warm": {"file": "spark/hit_star_burst_2x2.png", "cols": 2, "rows": 2, "lum": true},
	"hit_cross": {"file": "spark/cross_blades_4.png", "cols": 1, "rows": 1, "lum": true},
	"streak": {"file": "spark/spark_streak_a.png", "cols": 1, "rows": 1, "lum": true},
	"capsule": {"file": "spark/spark_capsule_glow.png", "cols": 1, "rows": 1, "lum": true},
	"muzzle_a": {"file": "muzzle/muzzle_flash_a_2x2.png", "cols": 2, "rows": 2, "lum": true},
	"circle": {"file": "ring/circle_solid.png", "cols": 1, "rows": 1, "lum": true},
	"ring_wave": {"file": "ring/ring_wave_mask.png", "cols": 1, "rows": 1, "lum": true, "ring_w": 0.4},
	"glow_disc": {"file": "ring/glow_disc_soft.png", "cols": 1, "rows": 1, "lum": true},
	"shock": {"file": "ring/shockwave_spikes_2x2.png", "cols": 2, "rows": 2, "lum": true},
	"shock_mask": {"file": "ring/shockwave_spikes_2x2_mask.png", "cols": 2, "rows": 2, "lum": true},
	"shield": {"file": "block/block_card_shield_blue.png", "cols": 1, "rows": 1, "lum": true},
	"hex": {"file": "block/block_hexagon_outline.png", "cols": 1, "rows": 1, "lum": true, "solid": true},
	"puff": {"file": "dust/smoke_puff_white_2x2.png", "cols": 2, "rows": 2, "lum": false},
	"boom_puff": {"file": "boom/boom_puff_sheet_4x4.png", "cols": 4, "rows": 4, "lum": false},
	"boom_cloud": {"file": "boom/boom_spiky_cloud.png", "cols": 1, "rows": 1, "lum": false},
	"focus": {"file": "ko/focus_lines_spikes.png", "cols": 1, "rows": 1, "lum": false},
	"star8": {"file": "spark/hit_8point_star_glow.png", "cols": 1, "rows": 1, "lum": true},
	"star4": {"file": "sparkle/sparkle_4point.png", "cols": 1, "rows": 1, "lum": false},
	"star4_fat": {"file": "spark/hit_4point_star_fat.png", "cols": 1, "rows": 1, "lum": true},
	"plus": {"file": "heal/heal_plus_round.png", "cols": 1, "rows": 1, "lum": true},
	"blade": {"file": "slash/slash_blade_streaks.png", "cols": 1, "rows": 4, "lum": true},
	"tracer_comet": {"file": "bullet/tracer_comet.png", "cols": 1, "rows": 1, "lum": true},
	"tracer_head": {"file": "bullet/tracer_head.png", "cols": 1, "rows": 1, "lum": true},
	"tracer_capsule": {"file": "bullet/tracer_capsule.png", "cols": 1, "rows": 1, "lum": true},
	"beam_soft": {"file": "bullet/beam_soft.png", "cols": 1, "rows": 1, "lum": true},
	"energy_ball": {"file": "bullet/energy_ball.png", "cols": 1, "rows": 1, "lum": false},
	"fire_puff": {"file": "bullet/fire_puff_5x4.png", "cols": 5, "rows": 4, "lum": false, "gray": true},
	"digits_normal": {"file": "damage_text/damage_digits_normal.png", "cols": 1, "rows": 1, "lum": false},
	"digits_weak": {"file": "damage_text/damage_digits_weak.png", "cols": 1, "rows": 1, "lum": false},
}

static var _tex := {}
static var _mats := {}

static func tex(sheet: String) -> Texture2D:
	if _tex.has(sheet):
		return _tex[sheet]
	var t: Texture2D = null
	if SHEETS.has(sheet):
		var path: String = DIR + str(SHEETS[sheet]["file"])
		if ResourceLoader.exists(path):
			t = load(path)
		else:
			push_warning("missing fx texture " + path)
	_tex[sheet] = t
	return t

## One flipbook frame, in sheet pixels.
static func frame_size(sheet: String) -> Vector2:
	var t := tex(sheet)
	if t == null:
		return Vector2.ONE
	var info: Dictionary = SHEETS[sheet]
	return t.get_size() / Vector2(float(info["cols"]), float(info["rows"]))

## Shared material. blend: "mix" (alpha blend) or "add". mask: a sheet name to erode against ("" = the sheet's luminance).
static func material(blend: String, lum: bool, erode: bool, mask := "", gray := false, solid := false) -> ShaderMaterial:
	var key := "%s|%d|%d|%s|%d|%d" % [blend, int(lum), int(erode), mask, int(gray), int(solid)]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("lum_alpha", 1.0 if lum else 0.0)
	m.set_shader_parameter("add_amount", 1.0 if blend == "add" else 0.0)
	m.set_shader_parameter("erode", 1.0 if erode else 0.0)
	m.set_shader_parameter("gray", 1.0 if gray else 0.0)
	m.set_shader_parameter("solid", 1.0 if solid else 0.0)
	if mask != "":
		m.set_shader_parameter("mask_tex", tex(mask))
		m.set_shader_parameter("use_mask", 1.0)
		m.set_shader_parameter("ring_w", float(SHEETS[mask].get("ring_w", 0.0)))
	_mats[key] = m
	return m

## A centred Sprite2D showing sheet `sheet` (frames via hframes/vframes), with the matching shared material.
static func sprite(sheet: String, blend := "mix", erode := false, mask := "") -> Sprite2D:
	var info: Dictionary = SHEETS[sheet]
	var s := Sprite2D.new()
	s.texture = tex(sheet)
	s.hframes = int(info["cols"])
	s.vframes = int(info["rows"])
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.material = material(blend, bool(info["lum"]), erode, mask, bool(info.get("gray", false)), bool(info.get("solid", false)))
	return s
