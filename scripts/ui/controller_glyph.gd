class_name ControllerGlyph
extends Control
## The claimable controller picture of the assign screen: the pad's own silhouette in BA ink, or the claimed keyboard cluster as
## key caps, with BA's cost-tag disc carrying the player number. The pictures are Kenney's Input Prompts (assets/glyphs).
## Unclaimed it is pale, for the dark scrim; claimed it is ink, for the white panel. The claim flash is `lit`. The Control is 252x156.

const SIZE := Vector2(252, 156)
const DISC := 38.0                    # the number disc
const BODY_BOX := Vector2(220, 148)   # the silhouette is fitted into this, top-centred
const KEY_H := 38.0
const KEY_GAP := 4.0
const CLUSTER_GAP := 26.0
const KEYS_TOP := 8.0
## Per device: clusters left to right, each a list of rows of key files in assets/glyphs/keyboard.
const CLUSTERS := {
	"kb1": [[["w"], ["a", "s", "d"]], [["r", "t"], ["f", "g"]]],
	"kb2": [[["up"], ["left", "down", "right"]], [["semicolon", "apostrophe"], ["enter", "backspace"]]],
	"shared": [[["space"]]],
}

## "" before a claim (the first pad's silhouette), "kb1", "kb2" or "shared" for a key picture, "padN" for that pad's family.
var device := "":
	set(v):
		device = v
		queue_redraw()
var number := 1:
	set(v):
		number = v
		queue_redraw()
var lit := 0.0   # claim pulse, 0..1: the picture flashes to the cost blue
var shown := true

func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_number(n: int) -> ControllerGlyph:
	number = n
	return self

## What is drawn: a pad family, or the keyboard device.
func picture() -> String:
	if CLUSTERS.has(device):
		return device
	return ControllerGlyphs.family(int(device.substr(3)) if device.begins_with("pad") else 0)

func _draw() -> void:
	if not shown:
		return
	var tint := (BaTokens.INK if device != "" else BaTokens.FACET_C).lerp(BaTokens.COST, lit)
	var pic := picture()
	if CLUSTERS.has(pic):
		_draw_keys(CLUSTERS[pic], tint)
	else:
		var tex := ControllerGlyphs.body(pic)
		var k := minf(BODY_BOX.x / tex.get_width(), BODY_BOX.y / tex.get_height())
		var sz := tex.get_size() * k
		draw_texture_rect(tex, Rect2(Vector2((SIZE.x - sz.x) * 0.5, 0.0), sz), false, tint)
	_draw_number()

func _draw_keys(clusters: Array, tint: Color) -> void:
	var widths := []
	var total := CLUSTER_GAP * float(clusters.size() - 1)
	for cl in clusters:
		var w := 0.0
		for row in cl:
			w = maxf(w, _row_width(row))
		widths.append(w)
		total += w
	var x := (SIZE.x - total) * 0.5
	for c in clusters.size():
		for r in clusters[c].size():
			var row: Array = clusters[c][r]
			var rx: float = x + (float(widths[c]) - _row_width(row)) * 0.5
			for name in row:
				var tex := ControllerGlyphs.key(name)
				var w := KEY_H * tex.get_width() / tex.get_height()
				draw_texture_rect(tex, Rect2(rx, KEYS_TOP + (KEY_H + KEY_GAP) * r, w, KEY_H), false, tint)
				rx += w + KEY_GAP
		x += float(widths[c]) + CLUSTER_GAP

func _row_width(row: Array) -> float:
	var w := KEY_GAP * float(row.size() - 1)
	for name in row:
		var tex := ControllerGlyphs.key(name)
		w += KEY_H * tex.get_width() / tex.get_height()
	return w

func _draw_number() -> void:
	var disc := Rect2(Vector2((SIZE.x - DISC) * 0.5, 100.0), Vector2(DISC, DISC))
	BaArt.blit(self, "Combat__Combat_CardBg_EX_CostTag", disc)
	BaNumerals.draw(self, str(number), Vector2(disc.get_center().x, disc.position.y + DISC * 0.2), DISC * 0.56, BaNumerals.Tier.NORMAL, Color.WHITE, 1)
