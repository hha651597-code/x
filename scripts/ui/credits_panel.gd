class_name CreditsPanel
extends Control
## The title screen's Credits popup: BA's system window over a dimmed screen, a scrolling list of sections with their text and link rows.
## Up / down move between the links (the list scrolls to keep the focused one in view), confirm opens it in the browser, back or the X
## closes the window; the wheel scrolls and a click on a link opens it. Only https links are ever opened.
## The same credits are written out in CREDITS.md (a test keeps every link of this list in that file).

const Menu := preload("res://scripts/ui/ba_menu.gd")
const PainterScript := preload("res://scripts/ui/painter.gd")

signal closed

const BOX := Rect2(170, 48, 940, 624)
const HEAD_H := 54.0
const BODY := Rect2(26, 70, 878, 496)       # the scrolling area, in the box's own pixels
const HINT_Y := 600.0                       # baseline of the hint line
const TEXT_W := 840.0
const LINK_H := 40.0
const CLOSE := Rect2(880, 8, 38, 38)
const SCROLL_STEP := 64.0

## {title, text: [paragraphs], links: [[label, https url]]}
const SECTIONS := [
	{"title": "The game",
		"text": ["Blue Archive Fighting Game (Tentative) is a fan project made by mattsumi. It is unofficial and has no connection with NEXON Games or Yostar."],
		"links": [["mattsumi on GitHub", "https://github.com/mattsumi"]]},
	{"title": "Blue Archive",
		"text": ["Blue Archive is the property of NEXON Games Co., Ltd. and Yostar, Inc. Its characters, artwork, interface, 3D models, voice lines, sound effects and title films are theirs. They are used here without any claim of ownership."],
		"links": [["Official website", "https://bluearchive.nexon.com/"], ["Blue Archive on X", "https://x.com/en_BlueArchive"],
			["Blue Archive on YouTube", "https://www.youtube.com/channel/UCsrnDYrkovQhCCE8kwKcvKQ"], ["Blue Archive on Discord", "https://discord.com/invite/bluearchiveglobal"],
			["Blue Archive on Facebook", "https://www.facebook.com/EN.BlueArchive"], ["Official forum", "https://forum.nexon.com/bluearchive-en/"]]},
	{"title": "Music",
		"text": ["Every track is from the Blue Archive Original Soundtrack, composed by Mitsukiyo, Nor and KARUT. The album covers in the jukebox are from its releases."],
		"links": [["Blue Archive Wiki: Soundtrack", "https://bluearchive.wiki/wiki/Soundtrack"],
			["Blue Archive Wiki: Original Soundtrack albums", "https://bluearchive.wiki/wiki/Blue_Archive_Original_Soundtrack"]]},
	{"title": "Fonts",
		"text": ["Noto Sans by The Noto Project Authors, Chakra Petch by The Chakra Petch Project Authors, Barlow Condensed by The Barlow Project Authors and Orbitron by The Orbitron Project Authors, under the SIL Open Font License 1.1."],
		"links": [["Noto Fonts", "https://github.com/notofonts"], ["Chakra Petch", "https://github.com/m4rc1e/Chakra-Petch"],
			["Barlow", "https://github.com/jpt/barlow"], ["Orbitron", "https://github.com/theleagueof/orbitron"]]},
	{"title": "Controller and key pictures",
		"text": ["Input Prompts by Kenney, released under CC0."],
		"links": [["Kenney: Input Prompts", "https://kenney.nl/assets/input-prompts"], ["Kenney", "https://kenney.nl"]]},
	{"title": "Engine",
		"text": ["Made with Godot Engine, under the MIT licence."],
		"links": [["Godot Engine", "https://godotengine.org"]]},
	{"title": "Tools",
		"text": ["Used to unpack and prepare the game's assets: BA-AX by Deathemonic, UnityPy by K0lb3, SkelToJson by Bastien Gimbert, the Blue Archive data tables by arisu-archive, the English voice subtitles from SchaleDB, FFmpeg and Xiph.Org's Theora for the title films, and Blender for animation."],
		"links": [["BA-AX", "https://github.com/Deathemonic/BA-AX"], ["UnityPy", "https://github.com/K0lb3/UnityPy"],
			["SkelToJson", "https://github.com/BastienGimbert/SkelToJson"], ["Blue Archive data tables", "https://github.com/arisu-archive/bluearchive-data"], ["SchaleDB", "https://schaledb.com"],
			["FFmpeg", "https://ffmpeg.org"], ["Theora", "https://xiph.org/theora/"], ["Blender", "https://www.blender.org"]]},
]

## A Callable taking the url; empty means OS.shell_open. Tests set it so no browser opens.
static var opener := Callable()

var _rows: Array = []           # {kind: "head" | "text" | "link", text, url, y, h}
var _links: Array = []          # indexes into _rows
var _focus := 0
var _scroll := 0.0
var _scroll_to := 0.0
var _content_h := 0.0
var _t := 0.0
var _box: Control
var _body: Control
var _closing := false
var _close_hover := false
var _x: TextureRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_scrim_input)
	_build_rows()
	_box = PainterScript.new().setup(BOX.size, _draw_box)
	_box.position = BOX.position
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_box)
	_body = PainterScript.new().setup(BODY.size, _draw_body)
	_body.position = BODY.position
	_body.clip_contents = true
	_body.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.gui_input.connect(_on_body_input)
	_box.add_child(_body)
	_x = TextureRect.new()
	_x.texture = load("res://assets/ba/ui/Common__Common_Icon_Close.png")
	_x.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_x.stretch_mode = TextureRect.STRETCH_SCALE
	_x.position = CLOSE.position
	_x.size = CLOSE.size
	_x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_x)
	var cl := Control.new()
	cl.position = CLOSE.position
	cl.size = CLOSE.size
	cl.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.gui_input.connect(_on_close_input)
	cl.mouse_entered.connect(func() -> void: _close_hover = true)
	cl.mouse_exited.connect(func() -> void: _close_hover = false)
	_box.add_child(cl)

## Every row of the list with its place: the wrapped paragraphs and the link rows, from SECTIONS.
func _build_rows() -> void:
	var y := 6.0
	for sec in SECTIONS:
		_rows.append({"kind": "head", "text": sec["title"], "y": y, "h": 44.0})
		y += 44.0
		for para in sec["text"]:
			for line in GalleryKit.wrap_text(para, 600, 16, TEXT_W):
				_rows.append({"kind": "text", "text": line, "y": y, "h": 24.0})
				y += 24.0
			y += 8.0
		for l in sec["links"]:
			_links.append(_rows.size())
			_rows.append({"kind": "link", "text": l[0], "url": l[1], "y": y, "h": LINK_H})
			y += LINK_H + 6.0
		y += 18.0
	_content_h = y

static func all_text() -> String:
	var out := ""
	for sec in SECTIONS:
		out += String(sec["title"]) + "\n" + "\n".join(sec["text"]) + "\n"
		for l in sec["links"]:
			out += "%s %s\n" % [l[0], l[1]]
	return out

static func all_urls() -> Array:
	var out := []
	for sec in SECTIONS:
		for l in sec["links"]:
			out.append(l[1])
	return out

# actions
## Returns true: the window takes every action while it is open.
func handle(act: String) -> bool:
	match act:
		"up": _move(_focus - 1)
		"down": _move(_focus + 1)
		"confirm": open_focused()
		"back": close()
	return true

func _move(i: int) -> void:
	i = clampi(i, 0, _links.size() - 1)
	if i != _focus:
		_focus = i
		Sfx.play("tick")
	_scroll_to = scroll_for(_rows[_links[_focus]], _scroll_to, BODY.size.y, _content_h, _focus == 0, _focus == _links.size() - 1)

## The scroll offset that keeps a row in view of `view` px, starting from `scroll`; the first link goes back to the very top and the last to the very end.
static func scroll_for(row: Dictionary, scroll: float, view: float, content: float, first: bool, last: bool) -> float:
	if first:
		return 0.0
	if last:
		return maxf(content - view, 0.0)
	var s := scroll
	if float(row["y"]) < s + 12.0:
		s = float(row["y"]) - 12.0
	elif float(row["y"]) + float(row["h"]) > s + view - 12.0:
		s = float(row["y"]) + float(row["h"]) - view + 12.0
	return clampf(s, 0.0, maxf(content - view, 0.0))

func open_focused() -> void:
	if _links.is_empty():
		return
	open_url(String(_rows[_links[_focus]]["url"]))

## Opens a https link (nothing else) through `opener`, or the system browser.
func open_url(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	Sfx.play("confirm")
	if opener.is_valid():
		opener.call(url)
	else:
		OS.shell_open(url)
	return true

func close() -> void:
	if _closing:
		return
	_closing = true
	Sfx.play("back")
	closed.emit()
	queue_free()

func probe() -> Dictionary:
	return {"focus": _focus, "links": _links.size(), "url": String(_rows[_links[_focus]]["url"]) if not _links.is_empty() else "",
			"scroll": snappedf(_scroll_to, 0.1), "content": _content_h, "box": BOX, "body": Rect2(BOX.position + BODY.position, BODY.size)}

# frame
func _process(delta: float) -> void:
	_t += delta
	_scroll = lerpf(_scroll, _scroll_to, 1.0 - exp(-delta * 14.0))
	if absf(_scroll - _scroll_to) < 0.05:
		_scroll = _scroll_to
	var e := clampf(_t / 0.2, 0.0, 1.0)
	modulate.a = e
	_box.scale = Vector2.ONE * lerpf(0.96, 1.0, e)
	_box.pivot_offset = BOX.size * 0.5
	_box.queue_redraw()
	_body.queue_redraw()
	queue_redraw()

# drawing
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(BaTokens.NAVY, 0.7))

func _draw_box(c: Control) -> void:
	GalleryKit.popup(c, Rect2(Vector2.ZERO, BOX.size), HEAD_H)
	Menu.label(c, "Credits", Vector2(30.0, 40.0), 34, BaTokens.INK, Color.WHITE, 2, 0, 800)
	_x.modulate = BaTokens.BRACKET if _close_hover else BaTokens.INK
	Menu.label(c, "Up / Down  Choose a link        Confirm  Open it in the browser        Back  Close", Vector2(BOX.size.x * 0.5, HINT_Y), 14, Color(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 1, 700)
	# a scroll track beside the list
	if _content_h > BODY.size.y:
		var th := BODY.size.y
		Menu.nine(c, "Combat__Common_Bg_Raius5px", Rect2(BODY.end.x + 6.0, BODY.position.y, 5.0, th), Menu.K, Color(BaTokens.GAUGE_EMPTY, 0.45))
		var knob := th * BODY.size.y / _content_h
		var ky := (th - knob) * _scroll / maxf(_content_h - BODY.size.y, 1.0)
		Menu.nine(c, "Combat__Common_Bg_Raius5px", Rect2(BODY.end.x + 5.0, BODY.position.y + ky, 7.0, knob), Menu.K, BaTokens.COST)

func _draw_body(c: Control) -> void:
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var y := float(r["y"]) - _scroll
		if y > BODY.size.y or y + float(r["h"]) < 0.0:
			continue
		match String(r["kind"]):
			"head":
				GalleryKit.draw_row_title(c, Vector2(4.0, y + 30.0), BODY.size.x - 8.0, String(r["text"]).to_upper())
			"text":
				Menu.label(c, String(r["text"]), Vector2(6.0, y + 17.0), 16, Color(BaTokens.INK, 0.95), Color(0, 0, 0, 0), 0, 0, 600)
			"link":
				var sel: bool = _links[_focus] == i
				var rect := Rect2(0.0, y, BODY.size.x - 8.0, LINK_H)
				GalleryKit.plate(c, rect, BaTokens.CONFIRM_PLATE.lerp(Color.WHITE, 0.45) if sel else Color.WHITE)
				var room := rect.size.x - 40.0
				var url := String(r["url"]).trim_prefix("https://").trim_suffix("/")
				var uw := minf(Menu.text_width(url, 13, 600), room * 0.5)
				var ls := Menu.fit(String(r["text"]), 18, room - uw - 20.0, 12, 800)
				Menu.label(c, Menu.clip(String(r["text"]), ls, room - uw - 20.0, 800), Vector2(20.0, y + 26.0), ls, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)
				Menu.label(c, Menu.clip(url, 13, uw, 600), Vector2(rect.end.x - 20.0, y + 25.0), 13, Color(BaTokens.INK, 0.75), Color(0, 0, 0, 0), 0, 2, 600)
				if sel:
					GalleryKit.draw_bracket(c, rect.grow_individual(4.0, 1.0, 4.0, 1.0), Motion.pulse(_t))

# mouse
func _row_at(local_y: float) -> int:
	var y := local_y + _scroll
	for k in _links.size():
		var r: Dictionary = _rows[_links[k]]
		if y >= float(r["y"]) and y <= float(r["y"]) + LINK_H:
			return k
	return -1

func _on_body_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var k := _row_at((ev as InputEventMouseMotion).position.y)
		if k >= 0 and k != _focus and (ev as InputEventMouseMotion).relative != Vector2.ZERO:
			_focus = k
			Sfx.play("tick")
	elif ev is InputEventMouseButton and ev.pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var k := _row_at(mb.position.y)
			if k >= 0:
				_focus = k
				open_focused()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_to = clampf(_scroll_to + SCROLL_STEP, 0.0, maxf(_content_h - BODY.size.y, 0.0))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_to = clampf(_scroll_to - SCROLL_STEP, 0.0, maxf(_content_h - BODY.size.y, 0.0))

func _on_close_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		close()

func _on_scrim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		close()
