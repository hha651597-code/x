class_name SpriteActor
extends Node2D
## Draws one SpriteSet frame with its origin (feet / floor) on this node's origin, art facing RIGHT (the parent flips it
## with the fighter's facing), plus a 1-2 tick motion-smear copy behind it and the official halo above the head.
## The frame is shown exactly as drawn (no warping); FighterView adds only whole-body squash / breathing around the feet.
##
## Pixel art (SpriteSet.pixel): nearest texels, exactly SpriteSet.art_px world px per art pixel, every nudge / smear offset
## snapped to whole art pixels (origin on a pixel corner, so a flip keeps the grid), the smear is a flat pale copy that
## steps back in whole pixels (no stretch), the halo is the pixel halo (SpriteHalo pixel mode). FighterView keeps this
## node's parent on the same art-pixel grid in world space and never scales it (see _apply_sprite).

const SHADER := preload("res://scripts/sprites/sprite_frame.gdshader")

var sset: SpriteSet
var spr: Sprite2D                    # the frame (FighterView exposes it as `body`: floor reflection, kits, ghosts)
var mat: ShaderMaterial
var smear_spr: Sprite2D
var smear_mat: ShaderMaterial
var halo: SpriteHalo
var cur := ""                        # name of the frame on screen
var rec := {}                        # its SpriteSet frame record
var _opts := {}

func setup(s: SpriteSet, outline: Color, seed_ := 0.0) -> void:
	sset = s
	smear_spr = new_sprite(s.pixel)
	smear_mat = ShaderMaterial.new()
	smear_mat.shader = SHADER
	smear_mat.set_shader_parameter("pixel_art", s.pixel)
	smear_mat.set_shader_parameter("outline_px", 0.0)
	smear_mat.set_shader_parameter("flash", 0.5)
	smear_mat.set_shader_parameter("flash_color", Color(0.92, 0.97, 1.0))
	smear_spr.material = smear_mat
	smear_spr.visible = false
	add_child(smear_spr)
	spr = new_sprite(s.pixel)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("pixel_art", s.pixel)
	mat.set_shader_parameter("outline_color", outline)
	mat.set_shader_parameter("outline_px", s.outline_px / maxf(s.world_scale, 0.01))
	spr.material = mat
	add_child(spr)
	halo = SpriteHalo.new()
	halo.setup(s.halo, seed_, s)
	add_child(halo)

## A frame sprite with the right sampling: nearest texels for pixel art, trilinear for hi-res frames.
static func new_sprite(pixel := false) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = false
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if pixel else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return sp

## Show frame `fname` with nudges `o` ({dx, dy, scale, flip}); an unknown name keeps the current frame.
func show_frame(fname: String, o: Dictionary) -> void:
	var r: Dictionary = sset.frames.get(fname, {})
	if r.is_empty():
		return
	if fname != cur and _TRACE:
		_trace_seen(fname)
	cur = fname
	rec = r
	_opts = o
	place(spr, r, o, sset.world_scale, sset.pixel)

## Opt-in coverage trace (SPRITE_TRACE=1): prints "SPRITESEEN <char> <frame>" the first time a frame is shown anywhere.
static var _TRACE := OS.get_environment("SPRITE_TRACE") != ""
static var _TRACE2 := OS.get_environment("SPRITE_TRACE") == "2"
static var _seen := {}

func _trace_seen(fname: String) -> void:
	var key := "%s/%s" % [sset.key, fname]
	if not _seen.has(key):
		_seen[key] = true
		print("SPRITESEEN ", key)

## Put sprite `sp` so that frame record r's origin lands on (0, 0) (+ the frame's and `o`'s nudges, world px).
## Pixel art: one art pixel = `ws` world px and the nudge is snapped to whole art pixels. A per-frame / per-anim "scale"
## is still honoured (it is a size FIX for a frame drawn too big / small, e.g. Hina's 5L sheet) but it is not pixel-exact:
## SpriteSet.validate warns, the real fix is to redraw that frame at the right size.
static func place(sp: Sprite2D, r: Dictionary, o: Dictionary, ws: float, pixel := false) -> void:
	var s := ws * float(r["scale"]) * float(o.get("scale", 1.0))
	var fl := -1.0 if bool(o.get("flip", false)) else 1.0
	var origin: Vector2 = r["origin"]
	sp.texture = r["tex"]
	sp.offset = -(origin + Vector2(SpriteSet.PAD, SpriteSet.PAD))
	sp.scale = Vector2(s * fl, s)
	var p := Vector2(float(r["dx"]) + float(o.get("dx", 0.0)), float(r["dy"]) + float(o.get("dy", 0.0)))
	sp.position = p.snapped(Vector2(ws, ws)) if pixel else p

## A texel position of the current frame -> this node's local space (world px, art facing right).
func local_of(p: Vector2) -> Vector2:
	if rec.is_empty():
		return Vector2.ZERO
	return spr.position + (p - (rec["origin"] as Vector2)) * spr.scale

func has_fx() -> bool:
	return not rec.is_empty() and bool(rec["has_fx"])

## Effect / muzzle anchor of the current frame (local), when the frame has one (anims.json frames.<name>.fx or frames.json muzzle).
func fx_local() -> Vector2:
	return local_of(rec["fx"]) if has_fx() else Vector2.ZERO

## Head anchor (where the halo floats) of the current frame, local.
func head_local() -> Vector2:
	return local_of(rec["halo"]) if not rec.is_empty() else Vector2(0.0, -Arena.SPRITE_H)

## Per render frame: smear copy (0..1) and halo (fade 0..1, e.g. on KO).
func update_fx(delta: float, smear: float, halo_fade: float) -> void:
	if rec.is_empty():
		return
	if smear > 0.01:
		smear_spr.visible = true
		place(smear_spr, rec, _opts, sset.world_scale, sset.pixel)
		if sset.pixel:
			# a flat pale copy a few whole pixels behind, in 2 opacity steps (no stretch, no blur)
			smear_spr.position.x -= snappedf(26.0 * smear, sset.art_px)
			smear_mat.set_shader_parameter("opacity", 0.45 if smear > 0.5 else 0.25)
		else:
			smear_spr.position.x -= 26.0 * smear
			smear_spr.scale.x *= 1.0 + 0.1 * smear
			smear_mat.set_shader_parameter("opacity", 0.42 * smear)
	else:
		smear_spr.visible = false
	halo.fade = halo_fade
	var hrot := float(rec["halo_rot"])
	if bool(_opts.get("flip", false)):
		hrot = -hrot
	halo.track(local_of(rec["halo"]), hrot, bool(rec["halo_on"]), delta)

## Shader look of the frame (flash / dim / desat / opacity / glow).
func set_look(flash: float, flash_col: Color, dim: float, desat: float, opacity: float, glow: float, glow_col: Color) -> void:
	mat.set_shader_parameter("flash", flash)
	mat.set_shader_parameter("flash_color", flash_col)
	mat.set_shader_parameter("dim", dim)
	mat.set_shader_parameter("desat", desat)
	mat.set_shader_parameter("opacity", opacity)
	mat.set_shader_parameter("glow", glow)
	mat.set_shader_parameter("glow_color", glow_col)
	smear_mat.set_shader_parameter("dim", dim)
	halo.set_dim(dim)
