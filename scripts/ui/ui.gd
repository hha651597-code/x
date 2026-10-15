class_name UI
extends RefCounted
## Shared look: palette, fonts, labels and texture access. Everything is authored in the
## 1280×720 coordinates of the reference stills (the project stretches it to any window size).

const SKY_TOP := Color("7ec4f2")
const SKY := Color("2d7fd0")
const SKY_DEEP := Color("1f5aa6")
const TEAL := Color("3b8f9b")
const TEAL_LIGHT := Color("8cc9cf")
const WHITE := Color("ffffff")
const ICE := Color("e8f3fa")
const YELLOW := Color("f6d44a")
const P1 := Color("e0314b")
const P2 := Color("2f6bff")
const INK := Color("1b2a3a")
const SHADOW := Color("0b1624")

const BA := "res://assets/ba/"
const NOTO := "res://assets/fonts/NotoSans-Variable.ttf"
const BARLOW_XB := "res://assets/fonts/BarlowCondensed-ExtraBold.ttf"
const BARLOW_SB := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"
const CHAKRA_BI := "res://assets/fonts/ChakraPetch-BoldItalic.ttf"
const WGHT_TAG := 2003265652  # OpenType 'wght'

static var _fonts := {}
static var _tex := {}

## Noto Sans at a given weight (menu titles, captions, stage names).
static func font_ui(weight := 800) -> Font:
	var key := "ui%d" % weight
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = load(NOTO)
		f.variation_opentype = {WGHT_TAG: weight}
		_fonts[key] = f
	return _fonts[key]

## Barlow Condensed ExtraBold (fighter names, big labels).
static func font_name() -> Font:
	if not _fonts.has("name"):
		_fonts["name"] = load(BARLOW_XB)
	return _fonts["name"]

## Barlow Condensed SemiBold (small caps labels).
static func font_label() -> Font:
	if not _fonts.has("label"):
		_fonts["label"] = load(BARLOW_SB)
	return _fonts["label"]

## Chakra Petch Bold Italic: the display face for headlines, numerals and buttons. A real italic, because Godot 4.7 ignores
## synthetic slant on Labels (FontVariation.variation_transform does nothing here).
static func font_display() -> Font:
	if not _fonts.has("display"):
		_fonts["display"] = load(CHAKRA_BI)
	return _fonts["display"]

## An official-art texture by path relative to assets/ba/ ("icon/10005.webp"). Cached; null if missing.
static func tex(rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	var path := BA + rel
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	else:
		push_warning("missing texture " + path)
	_tex[rel] = t
	return t

static func icon(id: int) -> Texture2D:
	return tex("icon/%d.webp" % id)

static func portrait(id: int) -> Texture2D:
	return tex("portrait/%d.webp" % id)

static func collection(id: int) -> Texture2D:
	return tex("collection/%d.webp" % id)

## A Label with the house text styling. kind: "ui" | "name" | "label".
static func label(text: String, size: int, kind := "ui", color := INK, weight := 800,
		outline := 0, outline_color := WHITE, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font
	match kind:
		"name":
			font = font_name()
		"label":
			font = font_label()
		_:
			font = font_ui(weight)
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", outline_color)
	l.add_theme_constant_override("line_spacing", 0)
	return l

## Add soft glow/shadow behind a label (the white halo on card titles).
static func label_shadow(l: Label, color := Color(0, 0, 0, 0.5), offset := Vector2(0, 2)) -> Label:
	l.add_theme_color_override("font_shadow_color", color)
	l.add_theme_constant_override("shadow_offset_x", int(offset.x))
	l.add_theme_constant_override("shadow_offset_y", int(offset.y))
	return l

## Place a control by its top-left and size in reference pixels.
static func place(c: Control, x: float, y: float, w := -1.0, h := -1.0) -> Control:
	c.position = Vector2(x, y)
	if w >= 0.0 and h >= 0.0:
		c.size = Vector2(w, h)
	return c

## A rect in the reference stills, given as pixel corners.
static func rect(x0: float, y0: float, x1: float, y1: float) -> Rect2:
	return Rect2(x0, y0, x1 - x0, y1 - y0)

## Under-damped spring 0 → 1 (overshoots): the bouncy settle used by every entrance.
static func spring(t: float, k := 6.5, w := 10.5) -> float:
	if t <= 0.0:
		return 0.0
	return 1.0 - exp(-k * t) * cos(w * t)
