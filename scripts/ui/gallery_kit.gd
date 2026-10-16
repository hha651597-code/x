class_name GalleryKit
extends RefCounted
## Shared pieces of the Extras screen and its three pages, all built from BA's sprites (assets/ba/hud through BaArt and
## ba_menu.gd, assets/ba/gallery for the few the HUD does not use): the facet tile, the tab, the info chip, rarity stars, dotted
## dividers and numerals that keep their commas. Everything is 1280x720 reference px, leaned 10 degrees like BA's plates.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const ART := "res://assets/ba/gallery/"
const CARD := "Common__Card_Item_Bg_N"
const SHEAR := BaTokens.SHEAR
const DIM := 0.85

## Facet tint per school (roster "school", lower case). roster.json carries no school colour, so these are read by eye from each crest.
const SCHOOL_TINT := {
	"abydos": Color("A6E4F7"), "arius": Color("C9CFDF"), "gehenna": Color("FFA9B4"), "hyakkiyako": Color("FFC9DD"),
	"millennium": Color("A9BBFF"), "redwinter": Color("F2B8AE"), "shanhaijing": Color("A9EBD0"), "srt": Color("BCE3A8"),
	"trinity": Color("D3BBF5"), "valkyrie": Color("9DB4E8"),
}
const ROLE_NAMES := {"DamageDealer": "Attacker", "Tanker": "Tanker", "Healer": "Healer", "Supporter": "Support", "Vehicle": "Tactical"}
## roster armour name -> the attack type it is coloured as (BA colours armour like the bullet that beats it)
const ARMOR_AS_BULLET := {"LightArmor": "Explosion", "HeavyArmor": "Pierce", "ElasticArmor": "Sonic", "Unarmed": "Mystic"}
const ARMOR_NAMES := {"LightArmor": "Light", "HeavyArmor": "Heavy", "ElasticArmor": "Elastic", "Unarmed": "Unarmed"}
const WEAPON_NAMES := {
	"AR": "Assault Rifle", "HG": "Handgun", "SR": "Sniper Rifle", "SMG": "Submachine Gun", "SG": "Shotgun",
	"MG": "Machine Gun", "GL": "Grenade Launcher", "RL": "Rocket Launcher", "RG": "Railgun", "MT": "Mortar", "FT": "Flamethrower",
}
const POSITION_NAMES := {"Front": "Front line", "Middle": "Mid line", "Back": "Back line"}

static var _art := {}

# art
## A sprite or texture under assets/ba/gallery by its stem ("Common__...", "UIs__..."). null with one warning when missing.
static func art(stem: String) -> Texture2D:
	if _art.has(stem):
		return _art[stem]
	var path := ART + ("tex/" if stem.begins_with("UIs__") else "sprites/") + stem + ".png"
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	else:
		BaArt.warn("gallery" + stem, "missing " + path)
	_art[stem] = t
	return t

static func lean(ci: CanvasItem, rect: Rect2, shear := SHEAR) -> void:
	ci.draw_set_transform_matrix(BaArt.lean_xform(shear, rect.get_center().y))

static func unlean(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

static func blit(ci: CanvasItem, t: Texture2D, rect: Rect2, tint := Color.WHITE, shear := 0.0) -> void:
	if t == null:
		return
	if shear != 0.0:
		lean(ci, rect, shear)
	ci.draw_texture_rect(t, rect, false, tint)
	if shear != 0.0:
		unlean(ci)

static func tint_of(s: Dictionary) -> Color:
	var c: Color = SCHOOL_TINT.get(String(s.get("school", "")).to_lower(), SCHOOL_TINT["abydos"])
	return c.lerp(Color.WHITE, 0.4)

# tiles
## The collection tile: BA's facet card (Card_Item_Bg_N, rim and all) in the school's tint, BA's baked portrait over it (its hair breaks the card's top edge),
## and a role chip coloured by attack type on the lower right, as on the fight HUD's portrait card.
static func draw_tile(ci: CanvasItem, size: Vector2, s: Dictionary, dim := 1.0, origin := Vector2.ZERO, foot := 0.0) -> void:
	var mul := Color(dim, dim, dim, 1.0)
	var card := Rect2(origin + Vector2(4.0, 6.0), size - Vector2(8.0, 8.0 + foot))
	blit(ci, art(CARD), card, tint_of(s) * mul)
	var pt: Texture2D = BaArt.portrait(int(s["id"]))
	if pt != null:
		var pw := card.size.x * 0.94
		ci.draw_texture_rect(pt, Rect2(card.position + Vector2(card.size.x * 0.025, -card.size.y * 0.04), Vector2(pw, pw * float(pt.get_height()) / float(pt.get_width()))), false, mul)
	var crest := BaArt.school_crest(String(s["school"]))
	if crest != null:
		var cw := card.size.x * 0.2
		var cr := Rect2(card.position + Vector2(card.size.x * 0.07, card.size.y - cw * 0.9 - 5.0), Vector2(cw, cw * 0.9))
		ci.draw_texture_rect(crest, Rect2(cr.position + Vector2(0.8, 0.8), cr.size), false, Color(BaTokens.INK, 0.7))
		ci.draw_texture_rect(crest, cr, false, mul)
	var glyph: Texture2D = BaArt.role_icon(String(s["role"]))
	if glyph != null:
		var chip := Rect2(card.end.x - card.size.x * 0.2, card.end.y - card.size.y * 0.42, card.size.x * 0.27, card.size.y * 0.3)
		BaArt.blit(ci, "Common__Card_Role_Bg", chip, BaArt.attack_color(String(s["bullet"])) * mul, SHEAR)
		ci.draw_texture_rect(glyph, chip.grow(-chip.size.y * 0.2), false, mul)

## The yellow notched bracket around a selected tile or tab, leaned 10 degrees (Card_Select_Line leans on BA's cards).
static func draw_bracket(ci: CanvasItem, rect: Rect2, pulse: float, a := 1.0) -> void:
	Menu.nine(ci, "Common__Card_Select_Line", rect, 0.55, Color(1, 1, 1, pulse * a), SHEAR, 0.4)

# plates and chips
static func plate(ci: CanvasItem, rect: Rect2, tint := Color.WHITE) -> void:
	Menu.nine(ci, "Combat__Common_Btn_BG", rect, Menu.K, tint, SHEAR)

## A white plate for a fact: a small coloured tile on the left (glyph texture or text), the value after it, a caption above it.
static func draw_chip(ci: CanvasItem, rect: Rect2, value: String, color: Color, glyph: Texture2D, tile_text := "", caption := "") -> void:
	plate(ci, rect)
	# the sprite's lower 7 px are its drop shadow: everything sits inside the white body above it
	var body := rect.size.y - 8.0
	var tile := Rect2(rect.position + Vector2(9.0, 3.5), Vector2(rect.size.y - 6.0, body - 6.0))
	BaArt.blit(ci, "Common__Card_Role_Bg", tile, color, SHEAR)
	if glyph != null:
		ci.draw_texture_rect(glyph, tile.grow(-5.0), false)
	elif tile_text != "":
		var fs := Menu.fit(tile_text, 14, tile.size.x - 4.0, 9, 800)
		Menu.label(ci, tile_text, Vector2(tile.get_center().x, tile.get_center().y + fs * 0.36), fs, Color.WHITE, Color(0, 0, 0, 0), 0, 1, 800)
	var x := tile.end.x + 12.0
	var room := rect.end.x - x - 12.0
	var size := Menu.fit(value, 15, room, 10, 800)
	if caption == "":
		Menu.label(ci, Menu.clip(value, size, room, 800), Vector2(x, rect.position.y + 0.5 * body + 0.5 + size * 0.36), size, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)
		return
	Menu.label(ci, caption, Vector2(x, rect.position.y + 13.0), 9, Color(BaTokens.INK, 0.7), Color(0, 0, 0, 0), 0, 0, 800)
	Menu.label(ci, Menu.clip(value, size, room, 800), Vector2(x, rect.end.y - 11.0), size, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)

## Rarity stars, lit then unlit, `total` of them, size px each.
static func draw_stars(ci: CanvasItem, pos: Vector2, lit: int, size: float, total := 3) -> void:
	var on := art("Common__Common_Icon_Formation_Star")
	var off := art("Common__Common_Icon_Formation_Star_Disable")
	for i in total:
		blit(ci, on if i < lit else off, Rect2(pos + Vector2(float(i) * size * 0.92, 0.0), Vector2(size, size * 0.955)))

## The dotted divider of BA's option rows (Common_Deco_DotLine, one dash every 9 px).
static func draw_dots(ci: CanvasItem, x0: float, x1: float, y: float, tint := Color(BaTokens.INK, 0.35)) -> void:
	var t := art("Common__Common_Deco_DotLine")
	if t == null:
		return
	var x := x0
	while x + 4.5 <= x1:
		ci.draw_texture_rect(t, Rect2(x, y, 4.5, 2.0), false, tint)
		x += 9.0

## A navy ribbon with a left-aligned white label: the footer hint and section titles.
static func ribbon_left(ci: CanvasItem, rect: Rect2, text: String, ink := Color.WHITE, size := 14, a := 1.0) -> void:
	Menu.nine(ci, "Combat__Combat_Title_Bg", rect, Menu.K, Color(1, 1, 1, a), SHEAR)
	var room := rect.size.x - 28.0
	var fs := Menu.fit(text, size, room, 9, 700)
	Menu.label(ci, Menu.clip(text, fs, room, 700), Vector2(rect.position.x + 16.0, rect.get_center().y + fs * 0.36), fs, Color(ink, ink.a * a), Color(0, 0, 0, 0), 0, 0, 700)

## A row title the way BA's option popup writes one: bold italic ink with a dotted rule under it.
static func draw_row_title(ci: CanvasItem, pos: Vector2, width: float, text: String) -> void:
	Menu.label(ci, text, pos, 15, BaTokens.INK, Color(0, 0, 0, 0), 0, 0, 800)
	draw_dots(ci, pos.x, pos.x + width, pos.y + 9.0)

## A white plate with a left-aligned navy label: the footer hint.
static func hint_plate(ci: CanvasItem, rect: Rect2, parts: Array, size := 14, a := 1.0) -> void:
	plate(ci, rect, Color(1, 1, 1, a))
	var room := rect.size.x - 32.0
	var gh := rect.size.y * 0.8
	var fs := size
	while fs > 9 and Menu.parts_width(parts, fs, gh) > room:
		fs -= 1
	Menu.draw_parts(ci, parts, Vector2(rect.position.x + 18.0, rect.get_center().y + fs * 0.36), fs, gh, Color(BaTokens.LABEL_INK, a))

## The popup of BA's system windows: white body, facet header of head_h px.
static func popup(ci: CanvasItem, rect: Rect2, head_h := 54.0) -> void:
	Menu.nine(ci, "Common__Common_Popup_Bg", rect, Menu.K, Color.WHITE, 0.0, head_h / 145.0)
	var th := float(BaArt.info("Common__Common_Top_Menu_Bg")["h"])
	Menu.nine(ci, "Common__Common_Top_Menu_Bg", Rect2(rect.position, Vector2(rect.size.x, head_h)), head_h / th)

# numbers
## [[text, is_digits]]: BaNumerals draws digits only and silently skips everything else, so commas, percent signs, colons and
## the multiplication sign are cut out and drawn as live text between the digit runs.
static func runs(text: String) -> Array:
	var out := []
	for ch in text:
		var d := "0123456789".contains(ch)
		if not out.is_empty() and out[-1][1] == d:
			out[-1][0] += ch
		else:
			out.append([ch, d])
	return out

static func live_size(h: float) -> int:
	return int(round(h * 1.1))

static func number_width(text: String, h: float, tier: int = BaNumerals.Tier.MINI) -> float:
	var w := 0.0
	var rs := runs(text)
	for r in rs:
		w += BaNumerals.width(r[0], h, tier) if r[1] else Menu.text_width(r[0], live_size(h), 800) - (h * 0.27 if r[0] in [",", "."] else 0.0)
	return w + float(maxi(rs.size() - 1, 0))

## Draws text with D_Font numerals for the digit runs and live bold text for the rest. pos is the top-left (align 0), top-centre
## (1) or top-right (2) of the line; returns its width. ink colours the live characters, tint the digits.
static func draw_number(ci: CanvasItem, text: String, pos: Vector2, h: float, tier: int = BaNumerals.Tier.MINI, tint := Color.WHITE, align := 0, ink := BaTokens.INK) -> float:
	var total := number_width(text, h, tier)
	var x := pos.x - total * (0.0 if align == 0 else (0.5 if align == 1 else 1.0))
	for r in runs(text):
		if r[1]:
			BaNumerals.draw(ci, r[0], Vector2(x, pos.y), h, tier, tint, 0)
			x += BaNumerals.width(r[0], h, tier) + 1.0
		else:
			var size := live_size(h)
			var tuck := h * 0.18 if r[0] in [",", "."] else 0.0
			Menu.label(ci, r[0], Vector2(x - tuck, pos.y + h * 0.92), size, ink, Color(0, 0, 0, 0), 0, 0, 800)
			x += Menu.text_width(r[0], size, 800) + 1.0 - tuck * 1.5
	return total

## 1234567 -> "1,234,567".
static func group(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if n < 0 else "") + out

## The largest height in [min_h, h] at which `text` is at most max_w wide in numerals.
static func fit_number(text: String, h: float, max_w: float, tier: int = BaNumerals.Tier.MINI, min_h := 12.0) -> float:
	var s := h
	while s > min_h and number_width(text, s, tier) > max_w:
		s -= 1.0
	return s

## A flat leaned gauge in BA's HP frame: `track` behind a flat `fill` that ends in a thumb sliver, like the fight bars.
static func draw_gauge(ci: CanvasItem, r: Rect2, frac: float, fill: Color, track := BaTokens.GAUGE_EMPTY) -> void:
	Menu.nine(ci, "Combat__Combat_Bg_Hp", r, Menu.K, Color.WHITE, SHEAR)
	var inner := r.grow_individual(-5.0, -4.0, -5.0, -5.0)
	var lean := SHEAR * inner.size.y * 0.5
	ci.draw_colored_polygon(PackedVector2Array([Vector2(inner.position.x + lean, inner.position.y), Vector2(inner.end.x + lean, inner.position.y),
			Vector2(inner.end.x - lean, inner.end.y), Vector2(inner.position.x - lean, inner.end.y)]), track)
	if frac <= 0.0:
		return
	var x := inner.position.x + maxf(inner.size.x * clampf(frac, 0.0, 1.0), 2.0)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(inner.position.x + lean, inner.position.y), Vector2(x + lean, inner.position.y),
			Vector2(x - lean, inner.end.y), Vector2(inner.position.x - lean, inner.end.y)]), fill)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x + lean - 2.5, inner.position.y), Vector2(x + lean, inner.position.y),
			Vector2(x - lean, inner.end.y), Vector2(x - lean - 2.5, inner.end.y)]), Color(BaTokens.THUMB_A, 0.85))

# text
static var _white := {}

## A white copy of a coloured icon (its own alpha), for glyphs on a coloured tile. Cached by texture.
static func white_of(t: Texture2D) -> Texture2D:
	if t == null:
		return null
	if _white.has(t):
		return _white[t]
	var img := t.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, img.get_pixel(x, y).a))
	var w := ImageTexture.create_from_image(img)
	_white[t] = w
	return w

## Greedy word wrap of `text` in Noto Sans of `weight` at `size` into lines no wider than max_w (a single longer word keeps its line).
static func wrap_text(text: String, weight: int, size: int, max_w: float) -> Array:
	var lines := []
	var cur := ""
	for word in text.split(" ", false):
		var cand: String = word if cur == "" else cur + " " + word
		if cur == "" or Menu.text_width(cand, size, weight) <= max_w:
			cur = cand
		else:
			lines.append(cur)
			cur = word
	if cur != "":
		lines.append(cur)
	return lines

## The largest size in [lo, hi] at which `text` wraps into at most max_lines lines of max_w: {size, lines, fits}.
static func fit_paragraph(text: String, weight: int, hi: int, lo: int, max_w: float, max_lines: int) -> Dictionary:
	var size := hi
	var lines := wrap_text(text, weight, size, max_w)
	while lines.size() > max_lines and size > lo:
		size -= 1
		lines = wrap_text(text, weight, size, max_w)
	return {"size": size, "lines": lines, "fits": lines.size() <= max_lines}

## A fighter's name in Barlow Condensed ExtraBold, leaned, shrunk until it is at most max_w wide. pos is the baseline-left.
## Returns the size used.
static func draw_name(ci: CanvasItem, text: String, pos: Vector2, size: int, max_w: float, fill: Color, outline: Color, ow: int) -> int:
	var font := UI.font_name()
	var s := Menu.fit_font(font, text, size, max_w, 16)
	ci.draw_set_transform_matrix(BaArt.lean_xform(SHEAR, pos.y))
	if ow > 0:
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, ow, outline)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, fill)
	unlean(ci)
	return s

# a tab
## A leaned tab or button. Tabs: the selected one is a yellow plate with BA's facet overlay and a brown label, the others navy
## ribbons with a white label at 0.85. The notched bracket shows on the selected tab while `focused` (the tab bar holds the
## cursor). Buttons (variant 1) are white plates with a navy label that turn yellow under the pointer.
class Tab extends Control:
	var text := ""
	var font_px := 20
	var variant := 0
	var selected := false
	var focused := false
	var hover := false
	var _t := 0.0

	func setup(sz: Vector2, label: String, px := 20, kind := 0) -> Tab:
		size = sz
		custom_minimum_size = sz
		pivot_offset = sz * 0.5
		text = label
		font_px = px
		variant = kind
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			hover = true)
		mouse_exited.connect(func() -> void:
			hover = false)
		return self

	func tick(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var ink: Color
		if variant == 1:
			GalleryKit.plate(self, r, BaTokens.CONFIRM_PLATE if hover else Color.WHITE)
			ink = BaTokens.LABEL_INK
		elif selected:
			GalleryKit.plate(self, r, BaTokens.CONFIRM_PLATE)
			BaArt.blit(self, "Common__Common_Btn_Normal_Y_S_Pt", r.grow_individual(2.0, 1.0, 2.0, 0.0))
			ink = BaTokens.CONFIRM_INK
		else:
			var dim := 1.0 if hover else GalleryKit.DIM
			GalleryKit.Menu.nine(self, "Combat__Combat_Title_Bg", r, GalleryKit.Menu.K, Color(dim, dim, dim, 1.0), GalleryKit.SHEAR)
			ink = Color(1, 1, 1, dim)
		var fs: int = GalleryKit.Menu.fit(text, font_px, size.x - 28.0, 10, 800)
		GalleryKit.Menu.label(self, text, Vector2(r.get_center().x, r.get_center().y + fs * 0.36), fs, ink, Color(0, 0, 0, 0), 0, 1, 800)
		if selected and focused:
			GalleryKit.draw_bracket(self, r.grow_individual(12.0, 7.0, 12.0, 4.0), Motion.pulse(_t))

## One portrait tile of a grid: the card, a name plate in the `foot` px under it when foot > 0, and the pulsing bracket when selected.
class Tile extends Control:
	var s: Dictionary
	var foot := 0.0
	var sel := false
	var dim := 1.0
	var t := 0.0

	func _draw() -> void:
		GalleryKit.draw_tile(self, size, s, dim, Vector2.ZERO, foot)
		if foot > 0.0:
			var r := Rect2(Vector2(10.0, size.y - foot - 8.0), Vector2(size.x - 20.0, foot + 3.0))
			GalleryKit.Menu.nine(self, "Combat__Common_Bg_Raius5px", r, 0.5, Color(1, 1, 1, 0.94), GalleryKit.SHEAR)
			var nm := Fighters.display_name(s)
			var fs: int = GalleryKit.Menu.fit(nm, 12, r.size.x - 8.0, 8, 800)
			GalleryKit.Menu.label(self, nm, Vector2(r.get_center().x, r.get_center().y + fs * 0.36), fs, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 1, 800)
		if sel:
			GalleryKit.draw_bracket(self, Rect2(Vector2.ZERO, size).grow_individual(4.0, 0.0, 4.0, 0.0), Motion.pulse(t))
