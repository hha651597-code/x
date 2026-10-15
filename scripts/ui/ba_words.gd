class_name BaWords
extends RefCounted
## BA's image-font words, and our baked stand-ins for the ones BA has no lettering for.
## BA's own: fight, start, win, lose, vs, warning, block, block_resist, miss, immune, combo, best_record.
## Ours (tools/hud_words.py, Chakra Petch, 2x size): round_1 to round_9, final, ko, super, ex_ready, just_guard, guard_crush.
## index.json "words" says which is which; BaArt.data()["words"].keys() lists them all.

static func tex(word: String) -> Texture2D:
	var w: Dictionary = BaArt.data().get("words", {}).get(word, {})
	if w.is_empty():
		BaArt.warn("word" + word, "unknown word " + word)
		return null
	if w["kind"] == "ba":
		return BaArt.tex(str(w["texture"]))
	return BaArt.file(str(w["file"]))

## The word centred on centre, width px wide, its own aspect.
static func draw(ci: CanvasItem, word: String, centre: Vector2, width: float, tint := Color.WHITE) -> void:
	var t := tex(word)
	if t == null:
		return
	var size := Vector2(width, width * float(t.get_height()) / float(t.get_width()))
	ci.draw_texture_rect(t, Rect2(centre - size * 0.5, size), false, tint)
