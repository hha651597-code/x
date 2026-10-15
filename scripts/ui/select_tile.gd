class_name SelectTile
extends Control
## One roster tile as a BA student card: Student_Portrait over a Combat_CardBg_EX facet card, the hair and ears breaking out
## of the top edge, and the attack-type chip (role glyph on the attack colour) on the lower left corner. Drawn around the
## node's centre; the node is the 80 px hit area. id -1 is the random tile: a cyan facet card with a "?".

const CARD := Rect2(-42.0, -31.0, 84.0, 69.3)
const FACE := Rect2(-39.0, -43.0, 80.0, 64.8)
const CHIP := Vector2(23.0, 22.0)
const CARD_TINT := Color(1.22, 1.3, 1.36)       # the sprite is grey: over-1 tints brighten the facets
const RANDOM_TINT := Color(0.55, 1.05, 1.5)

var id := -1

func setup(roster_id: int) -> SelectTile:
	id = roster_id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

func _draw() -> void:
	var o := size * 0.5
	BaArt.blit(self, "Combat__Combat_CardBg_EX", Rect2(o + CARD.position, CARD.size), CARD_TINT if id >= 0 else RANDOM_TINT)
	if id < 0:
		var f := UI.font_display()
		var w := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 58).x
		var at := Vector2(o.x - w * 0.5 + 3.0, o.y + 18.0)
		draw_string_outline(f, at, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, 7, BaTokens.HEAD_OUTLINE)
		draw_string(f, at, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color.WHITE)
		return
	var face := BaArt.portrait(id)
	if face != null:
		draw_texture_rect(face, Rect2(o + FACE.position, FACE.size), false)
	var d: Dictionary = Game.by_id.get(id, {})
	var glyph := BaArt.role_icon(str(d.get("role", "")))
	var bg := BaArt.tex("Common__Card_Role_Bg")
	if glyph == null or bg == null:
		return
	var chip := Rect2(o + Vector2(CARD.position.x - 3.0, CARD.end.y - CHIP.y + 3.0), CHIP)
	draw_texture_rect(bg, chip, false, BaArt.attack_color(str(d.get("bullet", ""))))
	draw_texture_rect(glyph, chip.grow(-4.0), false)
