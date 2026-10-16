extends Screen
## Extras hub (opened from the menu's Extras card): three tabs on BA's facet header, CHARACTERS (the roster browser), JUKEBOX
## (the real OST tracks) and RECORDS (Records.load_all()). lb / rb switch tabs; left / right do too while the tab bar has focus
## (press up from the top of a page, down to return). Back -> Game.back().
## The pages live in scripts/ui/gallery_*.gd. Everything is 1280x720 reference pixels.
##   params: {"tab": "characters"|"jukebox"|"records", "records": {...}}  (the latter overrides the saved records, for tests)

const PainterScript := preload("res://scripts/ui/painter.gd")
const Menu := preload("res://scripts/ui/ba_menu.gd")
const PATTERN := "UIs__00_Images__Image_Triangle_Pattern_Deco_1"
const TABS := [
	{"id": "characters", "label": "Characters"},
	{"id": "jukebox", "label": "Jukebox"},
	{"id": "records", "label": "Records"},
]
const SUBS := ["Students and specials", "Blue Archive Original Soundtrack", "Your battle history"]
const HEAD_H := 58.0
const HEAD_FACE := 52.0                  # the bar's light face ends here (its lip and shadow follow): the header text stays above it
const HEAD_TEXT_X := 34.0
const HEAD_TITLE_Y := 29.0               # baselines
const HEAD_TITLE_SIZE := 30
const HEAD_SUB_Y := 44.0
const HEAD_SUB_SIZE := 12
const TAB_SIZE := Vector2(196, 40)
const TAB_X0 := 392.0
const TAB_PITCH := 208.0
const TAB_Y := 10.0
const DISC := 30.0
const BACK_RECT := Rect2(1118, 11, 128, 36)
const FOOT_Y := 690.0
const INPUT_AT := 0.35
const SLIDE := 90.0
const SLIDE_T := 0.3

var _t := 0.0
var _tab := 0
var _prev := -1
var _tab_t := 1.0
var _tab_dir := 1.0
var _focus := "page"                     # "page" | "tabs"
var _leaving := false
var _last_dev := "kb1"
var _head: Control
var _foot: Control
var _tabs: Array = []
var _discs: Array = []
var _back: GalleryKit.Tab
var _hint: Array = []   # hint line parts: text and glyphs
var _pages: Array = [null, null, null]

func enter(p: Dictionary, info: Dictionary) -> void:
	_build()
	var want := String(p.get("tab", "characters"))
	for i in TABS.size():
		if TABS[i]["id"] == want:
			_tab = i
	var pg := _page(_tab)
	_show_page(_tab, true)
	pg.call("begin", true)
	if info.get("back", false):
		_t = 0.6
	_refresh_hint()
	Sfx.play("whoosh", 1.1, 0.6)

func exit() -> void:
	Game.session.bgm = "auto"
	Game.session.save_settings()     # the jukebox moves the shared volume without saving
	for pg in _pages:
		if pg != null:
			pg.call("exit")

# construction
func _build() -> void:
	add_child(PainterScript.new().setup(Vector2(1280, 720), _draw_backdrop))
	_head = PainterScript.new().setup(Vector2(1280, 80), _draw_head)
	add_child(_head)
	for i in TABS.size():
		var tb := GalleryKit.Tab.new().setup(TAB_SIZE, String(TABS[i]["label"]), 21)
		tb.position = Vector2(TAB_X0 + float(i) * TAB_PITCH, TAB_Y)
		tb.gui_input.connect(_on_tab_input.bind(i))
		add_child(tb)
		_tabs.append(tb)
	for i in 2:
		var d := PainterScript.new().setup(Vector2(DISC, DISC), _draw_disc.bind(i))
		d.position = Vector2(TAB_X0 - 46.0 if i == 0 else TAB_X0 + 2.0 * TAB_PITCH + TAB_SIZE.x + 16.0, TAB_Y + 5.0)
		add_child(d)
		_discs.append(d)
	_back = GalleryKit.Tab.new().setup(BACK_RECT.size, "Back", 19, 1)
	_back.position = BACK_RECT.position
	_back.gui_input.connect(_on_back_input)
	add_child(_back)
	_foot = PainterScript.new().setup(Vector2(1280, 30), _draw_foot)
	_foot.position = Vector2(0, FOOT_Y)
	add_child(_foot)

func _draw_backdrop(c: Control) -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)])
	c.draw_polygon(pts, PackedColorArray([BaTokens.SKY_TOP, BaTokens.SKY_TOP, BaTokens.SKY_BOT, BaTokens.SKY_BOT]))
	BaArt.blit(c, PATTERN, Rect2(-140, 40, 780, 780), Color(1, 1, 1, 0.38))
	BaArt.blit(c, PATTERN, Rect2(700, -260, 700, 700), Color(1, 1, 1, 0.22))

func _draw_head(c: Control) -> void:
	var th := float(BaArt.info("Common__Common_Top_Menu_Bg")["h"])
	Menu.nine(c, "Common__Common_Top_Menu_Bg", Rect2(0, 0, 1280, HEAD_H), HEAD_H / th)
	var x := HEAD_TEXT_X - (1.0 - Motion.whip(_t - 0.02)) * 240.0
	Menu.label(c, "Extras", Vector2(x, HEAD_TITLE_Y), HEAD_TITLE_SIZE, BaTokens.INK, Color.WHITE, 2, 0, 800)
	Menu.label(c, SUBS[_tab], Vector2(x + 2.0, HEAD_SUB_Y), HEAD_SUB_SIZE, Color(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 0, 700)

func _draw_disc(c: Control, i: int) -> void:
	BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", Rect2(0, 0, DISC, DISC))
	var act := "lb" if i == 0 else "rb"
	var glyph := _glyph(act)
	if glyph != null:
		c.draw_texture_rect(glyph, Rect2(Vector2.ONE * DISC * 0.125, Vector2.ONE * DISC * 0.75), false)
		return
	var label: String = Controls.label_for(_last_dev, act)
	var fs := Menu.fit(label, 15, DISC - 10.0, 9, 800)
	Menu.label(c, label, Vector2(DISC * 0.5, DISC * 0.5 + fs * 0.36), fs, Color.WHITE, Color(0, 0, 0, 0), 0, 1, 800)

func _draw_foot(c: Control) -> void:
	var w := minf(Menu.parts_width(_hint, 14, 22.0) + 60.0, 1232.0)
	GalleryKit.hint_plate(c, Rect2(24, 1, w, 28), _hint, 14, clampf((_t - 0.5) * 4.0, 0.0, 1.0))

func _page(i: int) -> Control:
	if _pages[i] == null:
		var pg: Control
		match i:
			0:
				pg = GalleryCharacters.new()
				pg.connect("wants_focus", _on_page_wants_focus)
			1:
				pg = GalleryJukebox.new()
				pg.connect("wants_focus", _on_page_wants_focus)
			_:
				pg = GalleryRecords.new()
				if params.has("records"):
					pg.set("override", params["records"])
		add_child(pg)
		pg.call("set_active", false)
		_pages[i] = pg
		for n in [_head, _back, _foot] + _tabs + _discs:
			move_child(n, get_child_count() - 1)
	return _pages[i]

func _show_page(i: int, on: bool) -> void:
	var pg: Control = _page(i)
	pg.call("set_active", on)
	if on:
		pg.call("set_page_focus", _focus == "page")

# frame
func _process(delta: float) -> void:
	_t += delta
	if _t < 0.9:
		_head.queue_redraw()
		_foot.queue_redraw()
	for i in _tabs.size():
		var tb: GalleryKit.Tab = _tabs[i]
		tb.position = Vector2(TAB_X0 + float(i) * TAB_PITCH, TAB_Y - (1.0 - Motion.whip(_t - 0.06 - Motion.stagger(i * 3))) * 70.0)
		tb.selected = i == _tab
		tb.focused = _focus == "tabs"
		tb.tick(delta)
	for d in _discs:
		(d as Control).position.y = TAB_Y + 5.0 - (1.0 - Motion.whip(_t - 0.2)) * 70.0
	_back.position = BACK_RECT.position + Vector2((1.0 - Motion.whip(_t - 0.15)) * 220.0, 0.0)
	_back.tick(delta)
	if _prev >= 0:
		_tab_t = minf(_tab_t + delta / SLIDE_T, 1.0)
		var cur: Control = _pages[_tab]
		cur.position.x = _tab_dir * (1.0 - Motion.whip(_tab_t * SLIDE_T, 0.1, 0.2)) * SLIDE
		if _tab_t >= 1.0:
			cur.position.x = 0.0
			_prev = -1

# tabs / focus
func _goto(i: int, sound := true) -> void:
	i = clampi(i, 0, TABS.size() - 1)
	if i == _tab:
		return
	var old: Control = _pages[_tab]
	old.call("set_active", false)
	old.position.x = 0.0
	_prev = _tab
	_tab_dir = 1.0 if i > _tab else -1.0
	_tab = i
	_tab_t = 0.0
	var pg := _page(i)
	_show_page(i, true)
	pg.call("begin", false)
	if sound:
		Sfx.play("tick", 1.15, 0.9)
	_refresh_hint()

func _set_focus(f: String) -> void:
	if f == _focus:
		return
	_focus = f
	(_page(_tab)).call("set_page_focus", f == "page")
	_refresh_hint()
	Sfx.play("tick", 0.85 if f == "tabs" else 1.1, 0.7)

func _on_page_wants_focus() -> void:
	if _focus != "page":
		_focus = "page"
		(_page(_tab)).call("set_page_focus", true)
		_refresh_hint()

func on_action(dev: String, act: String) -> void:
	if _t < INPUT_AT or _leaving:
		return
	if dev != _last_dev and dev != "shared":
		_last_dev = dev
		_refresh_hint()
	match act:
		"back":
			_leave()
			return
		"lb":
			_goto(_tab - 1)
			return
		"rb":
			_goto(_tab + 1)
			return
	if _focus == "tabs":
		match act:
			"left": _goto(_tab - 1)
			"right": _goto(_tab + 1)
			"down", "confirm": _set_focus("page")
	else:
		var consumed: bool = (_page(_tab)).call("handle", act)
		if not consumed and act == "up":
			_set_focus("tabs")

func _leave() -> void:
	if _leaving or Game.busy:
		return
	_leaving = true
	Sfx.play("back")
	Game.session.bgm = "auto"
	if Game.history.is_empty() or String(Game.history.back()["name"]) == "":
		Game.go("menu", {}, "fade")
	else:
		Game.back()

func _on_tab_input(ev: InputEvent, i: int) -> void:
	if covered or Game.busy or _t < INPUT_AT or _leaving:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_goto(i)

func _on_back_input(ev: InputEvent) -> void:
	if covered or Game.busy or _t < INPUT_AT:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_leave()

# footer hint
func _dir_label() -> Variant:
	if _last_dev == "kb1":
		return "WASD"
	if _last_dev.begins_with("pad"):
		var g := _glyph("dpad")
		return g if g != null else "D-pad"
	return "Arrows"

## A pad's glyph for an action; null on a keyboard, which shows its letters.
func _glyph(act: String) -> Texture2D:
	return Controls.glyph_for(_last_dev, act) if _last_dev.begins_with("pad") else null

## The key as a part of the hint line: its glyph, else its text.
func _key(act: String) -> Variant:
	var g := _glyph(act)
	return g if g != null else Controls.label_for(_last_dev, act)

func _refresh_hint() -> void:
	var gap := "        "
	var bk: Variant = _key("back")
	if _focus == "tabs":
		_hint = ["Left / Right  Switch tab", gap, "Down  Back to the page", gap, bk, "  Back"]
	else:
		match _tab:
			0:
				_hint = [_dir_label(), "  Browse", gap, _key("aux"), "  Fighters / Specials", gap, _key("lb"), " / ", _key("rb"), "  Switch tab", gap, bk, "  Back"]
			1:
				_hint = [_dir_label(), "  Choose", gap, _key("confirm"), "  Play", gap, "Up / Down  Player controls", gap, _key("lb"), " / ", _key("rb"), "  Switch tab", gap, bk, "  Back"]
			_:
				_hint = [_key("lb"), " / ", _key("rb"), "  Switch tab", gap, bk, "  Back"]
	if _foot != null:
		_foot.queue_redraw()
		_head.queue_redraw()
		for dsc in _discs:
			(dsc as Control).queue_redraw()

## What the header's title and subtitle ink covers (cap height above the baseline, a descender under the subtitle's), for the fit test.
static func head_text_rects(tab: int) -> Array:
	var tw := UI.font_ui(800).get_string_size("Extras", HORIZONTAL_ALIGNMENT_LEFT, -1, HEAD_TITLE_SIZE).x
	var sw := UI.font_ui(700).get_string_size(SUBS[tab], HORIZONTAL_ALIGNMENT_LEFT, -1, HEAD_SUB_SIZE).x
	return [Rect2(HEAD_TEXT_X, HEAD_TITLE_Y - 0.73 * HEAD_TITLE_SIZE, tw, 0.73 * HEAD_TITLE_SIZE),
			Rect2(HEAD_TEXT_X + 2.0, HEAD_SUB_Y - 0.73 * HEAD_SUB_SIZE, sw, 0.95 * HEAD_SUB_SIZE)]

func probe() -> Dictionary:
	var out := {"tab": TABS[_tab]["id"], "focus": _focus, "t": snappedf(_t, 0.01), "bgm": Game.session.bgm}
	var pg = _pages[_tab]
	if pg != null:
		out["page"] = pg.call("probe")
	return out
