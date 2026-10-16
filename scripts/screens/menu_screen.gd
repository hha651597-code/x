extends Screen
## Main Menu: a lightly blurred blue Kivotos backdrop, a random student on the left who greets you with a line, and a
## grid of art tiles on the right with a 12 px gutter, so no strip, ribbon or bracket reaches into a neighbour. Story and Single Play
## show a random chapter illustration each visit (assets/ba/menu_cg, tools/menu_cg_assets.py).
## Each tile carries its label on a facet strip tinted from its own picture; the selected tile gets BA's notched yellow bracket
## and the others sit at 0.85. The caption rides on a navy ribbon. Versus 2P / Versus CPU / Training push the controller-assign
## overlay; Options pushes the options popup; the tiles in COMING_SOON carry a COMING SOON ribbon, sit a little dimmer and show a
## "Coming soon" toast when chosen. All rects are 1280x720 reference pixels.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const Kit := preload("res://scripts/ui/screen_kit.gd")
const Painter := preload("res://scripts/ui/painter.gd")
const BACKDROP_SHADER := preload("res://shaders/backdrop.gdshader")
const MASCOT_SHADER := preload("res://shaders/menu_mascot.gdshader")
const LINES_PATH := "res://assets/ba/menu_lines.json"
const VOICE_PATH := "res://assets/audio/ba/menu_voice/"
const VOICE_DB := -3.0
const VOICE_AT := 1.4              # seconds in: the dialogue box has landed
const CG_PATH := "res://assets/ba/menu_cg/"
const MASCOT_HEAD_PX := 250.0       # the student's head square, like the select screen's constant face size
const MASCOT_HEAD_AT := Vector2(320.0, 215.0)
const MOODS := ["calm", "calm", "win", "lose"]    # the draw: half the visits are the normal portrait
const TALK_X := 28.0
const TALK_W := 548.0
const TALK_BOTTOM := 690.0
const TALK_SIZE := 21
const TALK_DELAY := 0.9
const CAPTION_AT := Vector2(600.0, 619.0)
const TOAST_AT := Vector2(824.0, 34.0)
static var _last_mascot := 0
static var _last_cg := {}
const SHEAR := 0.05                 # tile lean; the strips follow it
const INTRO_CARD_DELAY := 0.1
const INTRO_TRAVEL := 680.0
const DIM := 0.85                   # unselected tiles
const ENTRY_ORDER := {"story": 0, "single": 1, "extras": 2, "options": 3, "versus2p": 4, "versuscpu": 5, "training": 6, "network": 7}

# rect = layout pixels; lab = strip top-left inside the tile; size = label font px
const MODES := [
	{"id": "story", "label": "Story", "size": 40, "lab": Vector2(10, 10), "rect": Rect2(600, 84, 316, 227), "pool": "story", "pic": "bg/BG_Gehenna_Collection.jpg", "focus": Vector2(0.5, 0.35), "zoom": 1.0,
		"caption": "Experience new and familiar stories in the city of Kivotos."},
	{"id": "versus2p", "label": "Versus 2P", "size": 26, "lab": Vector2(8, 8), "rect": Rect2(928, 84, 312, 107), "pic": "collection/10005.webp", "focus": Vector2(0.5, 0.25), "zoom": 1.0,
		"caption": "Fight another player locally in epic battles."},
	{"id": "versuscpu", "label": "Versus CPU", "size": 26, "lab": Vector2(8, 8), "rect": Rect2(928, 203, 312, 108), "pic": "bg/BG_BunnyGirl_Collection.jpg", "focus": Vector2(0.5, 0.55), "zoom": 1.0,
		"caption": "Test your skills against a computer-controlled opponent."},
	{"id": "single", "label": "Single Play", "size": 22, "lab": Vector2(8, 8), "rect": Rect2(600, 323, 196, 112), "pool": "battle", "pic": "bg/BG_View_Kivotos.jpg", "focus": Vector2(0.5, 0.3), "zoom": 1.0,
		"caption": "Battle your way through a gauntlet of opponents on your own."},
	{"id": "extras", "label": "Extras", "size": 20, "lab": Vector2(8, 8), "rect": Rect2(600, 447, 196, 72), "pic": "bg/BG_CH0066_Collection.jpg", "focus": Vector2(0.5, 0.5), "zoom": 1.0,
		"caption": "Browse art, music and records collected across Kivotos."},
	{"id": "options", "label": "Options", "size": 20, "lab": Vector2(8, 8), "rect": Rect2(600, 531, 196, 72), "pic": "bg/BG_MainOffice_Night.jpg", "focus": Vector2(0.5, 0.5), "zoom": 1.0,
		"caption": "Set audio and flash options, and look up the key bindings."},
	{"id": "training", "label": "Training Mode", "size": 26, "lab": Vector2(8, 8), "rect": Rect2(808, 323, 222, 280), "pic": "bg/BG_Abydos_Collection.jpg", "focus": Vector2(0.4, 0.5), "zoom": 1.0,
		"caption": "Practice combos and techniques freely with any student."},
	{"id": "network", "label": "Network", "size": 26, "lab": Vector2(8, 8), "rect": Rect2(1042, 323, 198, 280), "pic": "bg/BG_BigPlaza_Collection.jpg", "focus": Vector2(0.5, 0.5), "zoom": 1.0,
		"caption": "Fight other players over the internet."},
]
const COMING_SOON := ["story", "network"]   # every tile that does nothing yet; add a mode here and its tile is marked
const SOON_DIM := 0.8                       # their brightness against the other tiles, selected or not

var _t := 0.0
var _selected := 1
var _sel_age := 1.0
var _cards: Array = []        # {mode, holder, card, tint, home, dim, delay}
var _backdrop: TextureRect
var _bd_mat: ShaderMaterial
var _mascot: TextureRect
var _mascot_frame := {}       # {scale, pos}: where the portrait sits so the head lands on MASCOT_HEAD_AT
var _talk: Control
var _talk_name := ""
var _talk_lines: Array = []
var _who := {"id": 0, "mood": "calm", "line": "", "clip": ""}
var _voice: AudioStreamPlayer
var _said := false
var _cursor: Control
var _caption: Control
var _toast: Control
var _toast_t := 0.0
var _cover := 0.0             # 0 = menu live, 1 = covered by an overlay
var _cover_target := 0.0
var _caption_text := ""

func enter(p: Dictionary, info: Dictionary) -> void:
	Game.session.reset()
	Sfx.set_volume(Game.session.sfx_volume)
	_pick_mascot(p)
	_build(p)
	if info.get("back", false):
		_t = 1.2  # coming back from a sub-screen: skip the long entrance
	_select(_selected, false)

func _build(p: Dictionary) -> void:
	# backdrop (overscanned so it can drift)
	_backdrop = TextureRect.new()
	_backdrop.texture = UI.tex("bg/BG_PracticeRoom_Collection.jpg")
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.position = Vector2(-50, -30)
	_backdrop.size = Vector2(1380, 780)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bd_mat = ShaderMaterial.new()
	_bd_mat.shader = BACKDROP_SHADER
	_bd_mat.set_shader_parameter("radius", 0.002)
	_bd_mat.set_shader_parameter("tint", Color(0.16, 0.5, 1.0))
	_bd_mat.set_shader_parameter("tint_amount", 0.55)
	_bd_mat.set_shader_parameter("brightness", 0.85)
	_bd_mat.set_shader_parameter("saturation", 1.6)
	_backdrop.material = _bd_mat
	add_child(_backdrop)

	# mascot
	var tex := _mascot_texture()
	_mascot_frame = frame_for(int(_who["id"]), tex)
	_mascot = TextureRect.new()
	_mascot.texture = tex
	_mascot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mascot.stretch_mode = TextureRect.STRETCH_SCALE
	_mascot.size = Vector2(tex.get_size()) * float(_mascot_frame["scale"])
	_mascot.position = _mascot_frame["pos"]
	_mascot.pivot_offset = Vector2(_mascot.size.x * 0.5, 0.0)
	_mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mm := ShaderMaterial.new()
	mm.shader = MASCOT_SHADER
	_mascot.material = mm
	add_child(_mascot)
	_talk = Painter.new().setup(Vector2(1280, 720), _draw_talk)
	add_child(_talk)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)

	# tiles
	for i in MODES.size():
		var m: Dictionary = MODES[i]
		var r: Rect2 = m["rect"]
		var pic := _tile_picture(m, p)
		var holder := Control.new()
		holder.size = r.size
		holder.position = r.position
		holder.pivot_offset = r.size * 0.5
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_entered.connect(_on_hover.bind(i))
		holder.gui_input.connect(_on_card_input.bind(i))
		var card := Card.new().setup(r.size, BaTokens.R_CARD, 3.5)
		card.set_picture(pic, m["focus"], m["zoom"]).set_shear(SHEAR).set_gloss(0.0)
		card.set_shadow(BaTokens.SHADOW_A, BaTokens.SHADOW_SIDE, Vector2(0.0, BaTokens.SHADOW_FALL - BaTokens.SHADOW_SIDE))
		holder.add_child(card)
		var tint := Kit.hue_tint(pic)
		holder.add_child(Painter.new().setup(r.size, func(c: Control) -> void: _draw_label(c, m, tint)))
		add_child(holder)
		_cards.append({"mode": m, "holder": holder, "card": card, "home": r.position, "dim": 1.0,
				"delay": INTRO_CARD_DELAY + Motion.stagger(ENTRY_ORDER[m["id"]])})

	_cursor = Painter.new().setup(Vector2(1280, 720), _draw_cursor)
	_cursor.z_index = 3
	add_child(_cursor)
	_caption = Painter.new().setup(Vector2(1280, 720), _draw_caption)
	add_child(_caption)
	_toast = Painter.new().setup(Vector2(1280, 720), _draw_toast)
	_toast.modulate.a = 0.0
	add_child(_toast)

# drawing
## The strip sits where the old label did and is only as wide as its text, so the picture stays visible.
static func label_rect(m: Dictionary) -> Rect2:
	var size := label_size(m)
	return Rect2(m["lab"], Vector2(Menu.text_width(m["label"], size) + 36.0, float(size) * 1.34))

## The font size the label is drawn at: the table's, shrunk until the strip fits inside its tile.
static func label_size(m: Dictionary) -> int:
	return Menu.fit(m["label"], int(m["size"]), (m["rect"] as Rect2).size.x - 60.0, 12)

func _draw_label(c: Control, m: Dictionary, tint: Color) -> void:
	var r := label_rect(m)
	Kit.strip(c, r, tint, SHEAR)
	var size := label_size(m)
	Menu.label(c, m["label"], Vector2(r.position.x + 20.0, r.get_center().y + float(size) * 0.34), size, BaTokens.LABEL_INK)
	if m["id"] in COMING_SOON:
		Menu.ribbon(c, soon_rect(m), "COMING SOON")

## The COMING SOON ribbon along the foot of a tile that does nothing yet.
static func soon_rect(m: Dictionary) -> Rect2:
	var size: Vector2 = (m["rect"] as Rect2).size
	return Rect2(10.0, size.y - 44.0, size.x - 20.0, 32.0)

func _draw_cursor(c: Control) -> void:
	var cs := smoothstep(0.0, 1.0, _cover)
	var holder: Control = _cards[_selected]["holder"]
	Kit.bracket(c, Rect2(holder.position, holder.size).grow(7.0), SHEAR, _t, _sel_age, 1.0 - cs)

func _draw_caption(c: Control) -> void:
	if _caption_text == "":
		return
	var w := Menu.text_width(_caption_text, 18) + 44.0
	Menu.ribbon(c, Rect2(CAPTION_AT, Vector2(w, 32.0)), _caption_text)

func _draw_toast(c: Control) -> void:
	var r := Rect2(TOAST_AT, Vector2(192.0, 38.0))
	Menu.nine(c, "Common__Common_Nonoutline_W_Bg", r, Menu.K, BaTokens.WHITE, BaTokens.SHEAR)
	Menu.label(c, "Coming soon", Vector2(r.get_center().x, r.get_center().y + 8.0), 22, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 1, 800)

# per-frame
func _process(delta: float) -> void:
	_t += delta
	_sel_age += delta
	_cover = move_toward(_cover, _cover_target, delta * 3.2)
	var cs := smoothstep(0.0, 1.0, _cover)
	# backdrop drift + cover blur/dim
	_backdrop.position = Vector2(-50 + sin(_t * 0.05) * 18, -30 + cos(_t * 0.04) * 8)
	_bd_mat.set_shader_parameter("radius", lerpf(0.002, 0.03, cs))
	_bd_mat.set_shader_parameter("darken", cs * 0.62)
	# mascot entrance + idle
	var hs := Motion.whip(_t - 0.05)
	_mascot.position = (_mascot_frame["pos"] as Vector2) + Vector2(-(1.0 - hs) * 140.0, sin(_t * 1.6) * 3.0)
	_mascot.scale = Vector2(1.0, 1.0 + sin(_t * 1.6 + 0.8) * 0.004)
	_mascot.modulate = Color.WHITE.lerp(Color(0.45, 0.5, 0.65, 1.0), cs * 0.85)
	if not _said and _t >= VOICE_AT and _who["clip"] != "":
		_said = true
		_voice.stream = load(VOICE_PATH + String(_who["clip"])) as AudioStream
		_voice.volume_db = linear_to_db(clampf(Game.session.sfx_volume, 0.0001, 1.0)) + VOICE_DB
		_voice.play()
	_talk.position.y = (1.0 - Motion.whip(_t - TALK_DELAY)) * 130.0
	_talk.modulate.a = 1.0 - cs
	_talk.queue_redraw()
	# tiles
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var holder: Control = c["holder"]
		var s := Motion.whip(_t - float(c["delay"]))
		var sel := i == _selected
		var d := lerpf(float(c["dim"]), 1.0 if sel else DIM, 1.0 - exp(-delta * 14.0))
		c["dim"] = d
		holder.position = (c["home"] as Vector2) + Vector2((1.0 - s) * INTRO_TRAVEL + cs * 420.0, 0.0)
		var k := SOON_DIM if c["mode"]["id"] in COMING_SOON else 1.0
		holder.modulate = Color(d * k, d * k, d * k, 1.0 - cs)
		holder.z_index = 2 if sel else 1
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE if cs > 0.01 else Control.MOUSE_FILTER_STOP
	_cursor.queue_redraw()
	# caption rides in after the tiles
	_caption.position.x = (1.0 - Motion.whip(_t - 0.45)) * 420.0
	_caption.modulate.a = 1.0 - cs
	_caption.queue_redraw()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t * 2.5, 0.0, 1.0)

func set_covered(b: bool) -> void:
	covered = b
	_cover_target = 1.0 if b else 0.0

func _select(i: int, sound := true) -> void:
	if sound and i != _selected:
		Sfx.play("tick")
	if i != _selected:
		_sel_age = 0.0
	_selected = i
	_caption_text = MODES[i]["caption"]

func on_action(dev: String, act: String) -> void:
	if _t < INTRO_CARD_DELAY:
		return
	match act:
		"left": _select(_neighbour(_selected, Vector2(-1, 0)))
		"right": _select(_neighbour(_selected, Vector2(1, 0)))
		"up": _select(_neighbour(_selected, Vector2(0, -1)))
		"down": _select(_neighbour(_selected, Vector2(0, 1)))
		"confirm": _choose(MODES[_selected]["id"])

func _on_hover(i: int) -> void:
	if not covered and not Game.busy and _t > INTRO_CARD_DELAY:
		_select(i)

func _on_card_input(ev: InputEvent, i: int) -> void:
	if covered or Game.busy:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_select(i)
		_choose(MODES[i]["id"])

## Nearest card whose centre lies in the pressed direction (screen y grows downward).
func _neighbour(from: int, dir: Vector2) -> int:
	var fc: Vector2 = (MODES[from]["rect"] as Rect2).get_center()
	var best := from
	var best_score := INF
	for j in MODES.size():
		if j == from:
			continue
		var v: Vector2 = (MODES[j]["rect"] as Rect2).get_center() - fc
		var along := v.dot(dir)
		if along <= 18.0:
			continue
		var across := absf(v.x * dir.y - v.y * dir.x)
		var score := along + across * 2.2
		if score < best_score:
			best_score = score
			best = j
	return best

func _choose(id: String) -> void:
	Sfx.play("confirm")
	match id:
		"versus2p", "versuscpu", "training", "single":
			var mode := "versus-cpu" if id == "versuscpu" else ("arcade" if id == "single" else id)
			Game.session.begin(mode)
			Game.push("assign", {"mode": mode})
		"options":
			Game.push("options", {})
		"extras":
			Game.go("gallery", {}, "fade")
		_:
			if id in COMING_SOON:
				_toast_t = 1.8
				Sfx.play("error")

func probe() -> Dictionary:
	return {"selected": MODES[_selected]["id"], "t": snappedf(_t, 0.01), "cover": snappedf(_cover, 0.01), "caption": _caption_text, "who": _who}


# the student on the menu
## A student that is not the last one shown, a portrait mood and a line to match. p may force them: {"mascot": id, "mood": "win"}.
func _pick_mascot(p: Dictionary) -> void:
	var ids: Array = []
	for f in Game.fighters:
		ids.append(int(f["id"]))
	var id := int(p.get("mascot", 0))
	if id == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var pool := ids.filter(func(i: int) -> bool: return i != _last_mascot)
		id = int(pool[rng.randi() % pool.size()])
	_last_mascot = id
	var mood := String(p.get("mood", ""))
	var lines := lines_for(id)
	if mood == "":
		var r2 := RandomNumberGenerator.new()
		r2.randomize()
		mood = MOODS[r2.randi() % MOODS.size()]
	var said: Array = lines.get(mood, lines.get("calm", [])) as Array
	var line := ""
	var clip := ""
	if not said.is_empty():
		var r3 := RandomNumberGenerator.new()
		r3.randomize()
		var pick: Dictionary = said[r3.randi() % said.size()]
		line = String(pick["text"])
		clip = String(pick["clip"])
	_who = {"id": id, "mood": mood, "line": line, "clip": clip}
	for f in Game.fighters:
		if int(f["id"]) == id:
			_talk_name = Fighters.display_name(f)
	_talk_lines = GalleryKit.wrap_text(line, 700, TALK_SIZE, TALK_W - 64.0)

static func lines_for(id: int) -> Dictionary:
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))["lines"]
	return all.get(str(id), {})

func _mascot_texture() -> Texture2D:
	var id := int(_who["id"])
	var suffix := "" if _who["mood"] == "calm" else "_" + String(_who["mood"])
	var t := UI.tex("portrait/%d%s.webp" % [id, suffix])
	return t if t != null else UI.portrait(id)

## {scale, pos} that puts the head square of portrait `tex` at MASCOT_HEAD_AT with a constant head size (SelectFrames.HEADS).
static func frame_for(id: int, tex: Texture2D) -> Dictionary:
	var h := SelectFrames.head(id, tex)
	var sc := MASCOT_HEAD_PX / float(h[2])
	var centre := Vector2(float(h[0]) + float(h[2]) * 0.5, float(h[1]) + float(h[2]) * 0.5)
	return {"scale": sc, "pos": MASCOT_HEAD_AT - centre * sc}

## A picture for the tile: the pool's next random chapter illustration (never the one shown last time), else the tile's own.
func _tile_picture(m: Dictionary, p: Dictionary) -> Texture2D:
	var pool := String(m.get("pool", ""))
	if pool != "":
		var names: Array = JSON.parse_string(FileAccess.get_file_as_string(CG_PATH + "menu_cg.json"))[pool]
		var pick := String(p.get("cg_" + pool, ""))
		if pick == "":
			var left := names.filter(func(n: String) -> bool: return n != _last_cg.get(pool, ""))
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			pick = String(left[rng.randi() % left.size()])
		_last_cg[pool] = pick
		var t := UI.tex("menu_cg/%s.jpg" % pick)
		if t != null:
			return t
	return UI.tex(m["pic"])

## The plate's lower 8 px are its drop shadow, so the white body is 8 px shorter than the rect.
static func talk_rect(lines: int) -> Rect2:
	var h := 22.0 + float(maxi(lines, 1)) * float(TALK_SIZE + 6) + 12.0 + 8.0
	return Rect2(TALK_X, TALK_BOTTOM - h, TALK_W, h)

func _draw_talk(c: Control) -> void:
	if _talk_lines.is_empty():
		return
	var r := talk_rect(_talk_lines.size())
	Menu.nine(c, "Combat__Common_Btn_BG", r, Menu.K, Color.WHITE, SHEAR)
	var nw := Menu.text_width(_talk_name, 18, 800) + 44.0
	Menu.ribbon(c, Rect2(r.position.x + 16.0, r.position.y - 17.0, nw, 30.0), _talk_name)
	var f := UI.font_ui(700)
	var y := r.position.y + 22.0 + float(TALK_SIZE)
	for line in _talk_lines:
		c.draw_string(f, Vector2(r.position.x + 30.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56.0, TALK_SIZE, BaTokens.LABEL_INK)
		y += float(TALK_SIZE) + 6.0
