class_name BaArt
extends RefCounted
## Blue Archive HUD art from assets/ba/hud (index.json): sprites, textures, portraits, crests, role icons, and the two
## draw helpers every HUD piece uses, nine() and blit().
## Names are "<Atlas>__<Name>" for sprites ("Combat__Combat_Bg_Hp") and the asset export's file stem for textures
## ("UIs__00_Images__Ingame_Start_Light"), without extension. Fighter ids are roster ids (assets/ba/roster.json), fighters and
## specials alike. A missing name gives null (or {}), plus one warning per name; warnings() lists them for tests.
## Lean: nine() and blit() skew around the rect's centre, "/" like every BA plate. shear is px of x per px of height, LEAN
## is BA's 10 degrees. A leaned call ends with draw_set_transform_matrix(IDENTITY), so call it before draws that set their own.

const Mood := preload("res://scripts/ui/portrait_mood.gd")
const DIR := "res://assets/ba/hud/"
const LEAN := 0.1763
const CREST_PX := 128
# roster "bullet" -> BaTokens' measured attack-type colour; the cut-in accent reads this table too
const ATTACK := {"Explosion": BaTokens.ATK_EXPLOSIVE, "Pierce": BaTokens.ATK_PIERCING, "Mystic": BaTokens.ATK_MYSTIC, "Sonic": BaTokens.ATK_SONIC}
const ATTACK_OTHER := BaTokens.ATK_OTHER

static var _data := {}
static var _tex := {}
static var _crests := {}
static var _expr := {}
static var _faces := {}
static var _grays := {}
static var _warned := {}
static var _additive: CanvasItemMaterial

## index.json: sprites, tex, portraits, words, crests.
static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DIR + "index.json", FileAccess.READ)
		if f == null:
			warn("index", "missing " + DIR + "index.json")
			return {}
		_data = JSON.parse_string(f.get_as_text())
	return _data

## Every name warned about so far (a name warns once).
static func warnings() -> Array:
	return _warned.keys()

static func warn(key: String, msg: String) -> void:
	if not _warned.has(key):
		_warned[key] = msg
		push_warning("BaArt: " + msg)

## A PNG under assets/ba/hud by its relative path ("words/ko.png"), cached. null with a warning when it is not there.
static func file(rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	var t: Texture2D = null
	if ResourceLoader.exists(DIR + rel):
		t = load(DIR + rel)
	else:
		warn(rel, "missing " + DIR + rel)
	_tex[rel] = t
	return t

static func has(name: String) -> bool:
	var d := data()
	return d.get("sprites", {}).has(name) or d.get("tex", {}).has(name)

## {w, h, borders: [l, r, t, b], padding, note, blend}. blend is "add" for the black-ground light textures (see additive()). Borders are the usable margins: they always leave one stretched pixel, so
## Combat_Bg_Hp reads 12/12/10/14 and not NGUI's 13/13/10/14. Textures have no borders. {} for an unknown name.
static func info(name: String) -> Dictionary:
	var d := data()
	var e: Dictionary = d.get("sprites", {}).get(name, {})
	if e.is_empty():
		e = d.get("tex", {}).get(name, {})
	if e.is_empty():
		warn(name, "unknown art " + name)
		return {}
	var b: Array = e.get("borders", [0, 0, 0, 0])
	return {"w": int(e["w"]), "h": int(e["h"]), "borders": [int(b[0]), int(b[1]), int(b[2]), int(b[3])],
		"padding": e.get("padding", [0, 0, 0, 0]), "note": e.get("note", ""), "blend": e.get("blend", "mix")}

## BA draws its light flares (Ingame_Start_Light, UITex_BGBlueLight) additive: set this on the node that draws them.
static func additive() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive

static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var d := data()
	var rel := ""
	if d.get("sprites", {}).has(name):
		rel = "sprites/" + name + ".png"
	elif d.get("tex", {}).has(name):
		rel = "tex/" + name + ".png"
	else:
		warn(name, "unknown art " + name)
		_tex[name] = null
		return null
	var t := file(rel)
	_tex[name] = t
	return t

## The "/" lean every plate and label has: shear px of x per px of height, pivoting on height y (a rect's centre or a
## text baseline).
static func lean_xform(shear: float, y: float) -> Transform2D:
	return Transform2D(Vector2(1.0, 0.0), Vector2(-shear, 1.0), Vector2(shear * y, 0.0))

static func _lean(ci: CanvasItem, rect: Rect2, shear: float) -> void:
	ci.draw_set_transform_matrix(lean_xform(shear, rect.get_center().y))

## 9-slice a sprite into rect. A rect smaller than the borders shrinks them together, so the corners meet instead of tearing.
## k draws the corners at k times their cut size, ky the top and bottom ones when it differs (ba_menu.gd's plates and popups).
static func nine(ci: CanvasItem, name: String, rect: Rect2, tint := Color.WHITE, shear := 0.0, k := 1.0, ky := -1.0) -> void:
	var t := tex(name)
	if t != null:
		nine_tex(ci, t, info(name)["borders"], rect, tint, shear, k, ky)

## nine() for a texture the caller made itself, with that sprite's borders [l, r, top, bottom].
static func nine_tex(ci: CanvasItem, t: Texture2D, b: Array, rect: Rect2, tint := Color.WHITE, shear := 0.0, k := 1.0, ky := -1.0) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var sw := float(t.get_width())
	var sh := float(t.get_height())
	var l := float(b[0])
	var r := float(b[1])
	var top := float(b[2])
	var bot := float(b[3])
	var kx := minf(k, rect.size.x / maxf(l + r, 0.001))
	var kyy := minf(k if ky < 0.0 else ky, rect.size.y / maxf(top + bot, 0.001))
	var sx := [0.0, l, sw - r, sw]
	var sy := [0.0, top, sh - bot, sh]
	var dx := [rect.position.x, rect.position.x + l * kx, rect.end.x - r * kx, rect.end.x]
	var dy := [rect.position.y, rect.position.y + top * kyy, rect.end.y - bot * kyy, rect.end.y]
	if shear != 0.0:
		_lean(ci, rect, shear)
	for j in 3:
		for i in 3:
			var src := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
			var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			if src.size.x > 0.0 and src.size.y > 0.0 and dst.size.x > 0.0 and dst.size.y > 0.0:
				ci.draw_texture_rect_region(t, dst, src, tint)
	if shear != 0.0:
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## The whole sprite or texture stretched into rect.
static func blit(ci: CanvasItem, name: String, rect: Rect2, tint := Color.WHITE, shear := 0.0) -> void:
	var t := tex(name)
	if t == null:
		return
	if shear != 0.0:
		_lean(ci, rect, shear)
	ci.draw_texture_rect(t, rect, false, tint)
	if shear != 0.0:
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)

static func _portrait(fighter_id: int, field: String) -> Texture2D:
	var e: Dictionary = data().get("portraits", {}).get(str(fighter_id), {})
	if e.is_empty():
		warn("portrait%d" % fighter_id, "no portrait entry for roster id %d" % fighter_id)
		return null
	if e.get(field) == null:
		return null
	return file(str(e[field]))

## 252x204 baked parallelogram (Student_Portrait), or the baked fallback for an id the install lacks. A state other than "calm"
## ("scratched", "hurt", "critical", "flinch", "win", "lose", "ko") is that face from expressions.json; one the install lacks falls
## to the next calmer face (PortraitMood.CHAIN) and in the end to the calm one.
static func portrait(fighter_id: int, state := "calm") -> Texture2D:
	if state == "calm":
		return _portrait(fighter_id, "file")
	var key := "%d/%s" % [fighter_id, state]
	if not _faces.has(key):
		var e: Dictionary = expressions().get(str(fighter_id), {})
		var t: Texture2D = null
		for s in Mood.CHAIN.get(state, []):
			var f: String = e.get(s, "")
			if s != "calm" and f != "" and ResourceLoader.exists(DIR + "portraits/" + f):
				t = file("portraits/" + f)
				break
		_faces[key] = t if t != null else _portrait(fighter_id, "file")
	return _faces[key]

## portraits/expressions.json: roster id -> state -> file under portraits/ (the emotes and vignettes are baked into the tiles).
## {} when the install has none.
static func expressions() -> Dictionary:
	if _expr.is_empty() and FileAccess.file_exists(DIR + "portraits/expressions.json"):
		_expr = JSON.parse_string(FileAccess.get_file_as_string(DIR + "portraits/expressions.json"))
	return _expr

## t with its colour pulled down to sat (0 grey, 1 as drawn), cached.
static func gray(t: Texture2D, sat: float) -> Texture2D:
	var key := "%d/%.2f" % [t.get_instance_id(), sat]
	if not _grays.has(key):
		var img := t.get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.adjust_bcs(1.0, 1.0, sat)
		_grays[key] = ImageTexture.create_from_image(img)
	return _grays[key]

## 182x144 Student_Portrait_*_Small; the full portrait when the id has no small one (fallbacks).
static func portrait_small(fighter_id: int) -> Texture2D:
	var t := _portrait(fighter_id, "small")
	return t if t != null else portrait(fighter_id)

## The school's crest, white from the source's alpha (tint it with modulate), 128 px wide. school is roster's "school".
static func school_crest(school: String) -> Texture2D:
	var key := school.to_lower()
	if _crests.has(key):
		return _crests[key]
	var stem: String = data().get("crests", {}).get(key, "")
	var src := tex(stem) if stem != "" else null
	if src == null:
		warn("crest" + key, "no crest for school " + school)
		_crests[key] = null
		return null
	var img := src.get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(CREST_PX, maxi(1, roundi(float(CREST_PX) * img.get_height() / img.get_width())), Image.INTERPOLATE_LANCZOS)
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, img.get_pixel(x, y).a))
	var t := ImageTexture.create_from_image(img)
	_crests[key] = t
	return t

## White glyph for a roster role (DamageDealer, Tanker, Healer, Supporter, Vehicle).
static func role_icon(role: String) -> Texture2D:
	return tex("Common__Common_Icon_" + role)

## Chip colour for a roster attack type ("bullet": Explosion, Pierce, Mystic, Sonic).
static func attack_color(attack_type: String) -> Color:
	return ATTACK.get(attack_type, ATTACK_OTHER)
