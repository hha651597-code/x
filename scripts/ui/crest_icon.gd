class_name CrestIcon
extends RefCounted
## A school crest cut for a small chip (22 px on the select and VS plates, the HUD's name item): BaArt.school_crest is padded
## and 128 px wide, and the GPU aliases it when it shrinks it 4x or more. This crops it to its ink and resamples it once to
## twice its draw size, so wide logotypes (Hyakkiyako, Shanhaijing) stay as long as the box allows and square emblems fill
## the height.

const BOX := Vector2(44.0, 22.0)

static var _cache := {}

## The crest texture for a roster school key ("Millennium") fitted into box (the 22 px chip by default), or null.
static func get_icon(school: String, box := BOX) -> Texture2D:
	var key := "%s%s" % [school.to_lower(), box]
	if not _cache.has(key):
		var src := BaArt.school_crest(school)
		var t: Texture2D = null
		if src != null:
			var img := src.get_image()
			img = img.get_region(img.get_used_rect())
			var k := minf(box.x * 2.0 / float(img.get_width()), box.y * 2.0 / float(img.get_height()))
			img.resize(maxi(1, roundi(float(img.get_width()) * k)), maxi(1, roundi(float(img.get_height()) * k)), Image.INTERPOLATE_LANCZOS)
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
		_cache[key] = t
	return _cache[key]

## Its size on screen in px, or ZERO without a crest.
static func fit(school: String, box := BOX) -> Vector2:
	var t := get_icon(school, box)
	return Vector2.ZERO if t == null else Vector2(t.get_size()) * 0.5
