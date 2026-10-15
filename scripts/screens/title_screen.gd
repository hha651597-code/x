extends Screen
## Title ("Start Game"): one of Blue Archive's eight title films, picked at random on each visit (never the one shown last), under its
## Title_Logo with our "Fighting Game" lettering, turning halo rings, a pulsing PRESS ANY BUTTON and drifting dust. Any button, key or
## click opens the main menu. With Reduce Flashes the films (white and gold cuts) give way to a still. All rects are 1280x720 reference
## pixels.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const Kit := preload("res://scripts/ui/screen_kit.gd")
const DIR := "res://assets/ba/title/"
const FILMS := ["opening", "2nd", "3rd", "4th", "4th_ep", "5th", "6th", "7th"]   # assets/ba/title/video/<name>.ogv, see tools/title_assets.py
const FILM_PX := Vector2(1920.0, 1080.0)   # the films cropped to 16:9 by tools/title_assets.py: they fill the canvas exactly
const STILL := "res://assets/ba/bg/BG_View_Kivotos.jpg"
const RING := "UIs__00_Images__Image_Deco_Circle"
const INPUT_DELAY := 0.6           # a key still down from the last screen must not start the game
const FLASH_S := 0.5
const AXIS_X := 640.0              # the lockup's centre line
const LOGO_W := 640.0
const LOGO_C := Vector2(AXIS_X, 232.0)
const FLARE_AT := Vector2(484.0, 75.0)   # where the logo's two blades cross, in the 1024x256 texture
const LETTER_W := 420.0
const LETTER_C := Vector2(AXIS_X, 346.0)
const TENTATIVE := "(Tentative)"       # the working title, under the lettering
const TENTATIVE_SIZE := 22
const TENTATIVE_Y := 398.0         # baseline
const PROMPT := "PRESS ANY BUTTON"
const PROMPT_SIZE := 30
const PROMPT_Y := 606.0            # baseline
const PULSE_S := 1.6
const FOOTER := "Fan Project by mattsumi on GitHub. Blue Archive and all material included relating to Blue Archive are property of NEXON and Yostar, and I do not claim any ownership."
const CREDITS_RECT := Rect2(1124.0, 666.0, 132.0, 34.0)
const FOOTER_SIZE := 13
const MOTES := 56
const REF := Vector2(1280.0, 720.0)
const KEYS_IGNORED := [KEY_ESCAPE, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK]
const ACTIONS := ["confirm", "start", "aux", "lb", "rb"]   # directions and back do nothing here; aux2 (Y, T) and the C key open the credits

static var _last_film := ""        # the film shown last in this run: the next visit picks another

var _t := 0.0
var _going := false
var _flash := 0.0
var _film := ""
var _film_done := false
var _still: TextureRect
var _player: VideoStreamPlayer
var _over: Control
var _logo: Texture2D
var _letters: Texture2D
var _ring: Texture2D
var _vignette: GradientTexture2D
var _wash: GradientTexture2D
var _dot: GradientTexture2D
var _credits: CreditsPanel
var _motes: Array = []             # {x, y, vx, vy, r, ph, near}

func enter(_p: Dictionary, _info: Dictionary) -> void:
	Sfx.set_volume(Game.session.sfx_volume)
	_logo = load(DIR + "Title_Logo.png")
	_letters = load(DIR + "Title_FightingGame.png")
	_ring = BaArt.tex(RING)
	_vignette = _radial(BaTokens.NAVY, 0.0, 0.42, 0.5)
	_wash = _radial(BaTokens.NAVY, 0.34, 0.0, 0.0)
	_dot = _radial(Color.WHITE, 1.0, 0.0, 0.0)
	_still = TextureRect.new()
	_still.texture = load(STILL)
	_still.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_still.stretch_mode = TextureRect.STRETCH_SCALE
	_still.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s: Vector2 = _still.texture.get_size()
	var k := maxf(REF.x / s.x, REF.y / s.y)
	_still.size = s * k
	_still.position = (REF - _still.size) * 0.5
	add_child(_still)
	if not Game.session.reduce_flashes:
		_film = pick_film(available_films(), _last_film, randf())
	if _film != "":
		_last_film = _film
		_player = VideoStreamPlayer.new()
		_player.stream = load(DIR + "video/" + _film + ".ogv")
		_player.expand = true
		_player.volume_db = -80.0
		_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k2 := maxf(REF.x / FILM_PX.x, REF.y / FILM_PX.y)
		_player.size = FILM_PX * k2
		_player.position = (REF - _player.size) * 0.5
		_player.modulate.a = 0.0
		_player.finished.connect(func() -> void: _film_done = true)
		add_child(_player)
		_player.play()
	_over = Control.new()
	_over.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over)
	add_child(_over)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	for i in MOTES:
		var near := i % 3 == 0
		_motes.append({"x": rng.randf() * REF.x, "y": rng.randf() * REF.y, "near": near, "ph": rng.randf() * TAU,
				"vx": rng.randf_range(10.0, 26.0) if near else rng.randf_range(3.0, 9.0),
				"vy": -(rng.randf_range(16.0, 34.0) if near else rng.randf_range(5.0, 14.0)),
				"r": rng.randf_range(4.0, 9.0) if near else rng.randf_range(1.5, 3.5)})
	if not Game.session.reduce_flashes:
		_flash = 1.0

static func _radial(c: Color, a_in: float, a_out: float, from: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([from, 1.0])
	g.colors = PackedColorArray([Color(c, a_in), Color(c, a_out)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t

static func available_films() -> Array:
	return FILMS.filter(func(f: String) -> bool: return ResourceLoader.exists(DIR + "video/" + f + ".ogv"))

## One film of avail for the roll r (0 to 1), never `last` while another is there; "" with none.
static func pick_film(avail: Array, last: String, r: float) -> String:
	var pool: Array = avail.filter(func(f: String) -> bool: return f != last)
	if pool.is_empty():
		pool = avail
	return "" if pool.is_empty() else pool[mini(int(r * pool.size()), pool.size() - 1)]

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta / FLASH_S)
	if _player != null:
		_player.modulate.a = clampf((_t - 0.1) / 0.6, 0.0, 1.0)
	_over.queue_redraw()

func on_action(_dev: String, act: String) -> void:
	if _credits != null:
		_credits.handle(act)
	elif act == "aux2":
		_open_credits()
	elif act in ACTIONS:
		_start()

func _input(ev: InputEvent) -> void:
	if _credits != null:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if not (ev.keycode in KEYS_IGNORED or ev.ctrl_pressed or ev.alt_pressed or ev.meta_pressed):
			if ev.keycode == KEY_C:
				_open_credits()
			else:
				_start()
	elif ev is InputEventJoypadButton and ev.pressed:
		if ev.button_index == JOY_BUTTON_Y:
			_open_credits()
		else:
			_start()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if CREDITS_RECT.has_point((ev as InputEventMouseButton).position):
			_open_credits()
		else:
			_start()

func _open_credits() -> void:
	if _t < INPUT_DELAY or _going or covered or Game.busy or _credits != null:
		return
	Sfx.play("confirm")
	_credits = CreditsPanel.new()
	_credits.closed.connect(func() -> void: _credits = null)
	add_child(_credits)

func _start() -> void:
	if _t < INPUT_DELAY or _going or covered or Game.busy or _credits != null:
		return
	_going = true
	if not Game.session.reduce_flashes:
		_flash = 1.0
	Sfx.play("confirm")
	Game.go("menu", {}, "fade")

static func _ease(x: float) -> float:
	var k := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - k * k * k

func _draw_over() -> void:
	var c := _over
	var navy := BaTokens.NAVY
	c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, REF), false)
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(REF.x, 0), Vector2(REF.x, 150), Vector2(0, 150)]),
			PackedColorArray([Color(navy, 0.36), Color(navy, 0.36), Color(navy, 0.0), Color(navy, 0.0)]))
	c.draw_polygon(PackedVector2Array([Vector2(0, 430), Vector2(REF.x, 430), Vector2(REF.x, REF.y), Vector2(0, REF.y)]),
			PackedColorArray([Color(navy, 0.0), Color(navy, 0.0), Color(navy, 0.62), Color(navy, 0.62)]))
	var e := _ease((_t - 0.2) / 0.7)
	var ui := _ease((_t - 0.8) / 0.5)
	c.draw_texture_rect(_wash, Rect2(LOGO_C + Vector2(-450.0, -170.0), Vector2(900.0, 400.0)), false, Color(1, 1, 1, e))
	_draw_rings(c)
	_draw_motes(c)
	var lr := logo_rect()
	c.draw_texture_rect(_logo, lr, false, Color(1, 1, 1, e))
	_draw_flare(c, lr)
	var le := _ease((_t - 0.6) / 0.5)
	if le > 0.0:
		var ls := letters_rect()
		c.draw_texture_rect(_letters, Rect2(ls.position + Vector2(0.0, (1.0 - le) * 10.0), ls.size), false, Color(1, 1, 1, le))
		var ry := LETTER_C.y + 2.0
		Kit.dots(c, AXIS_X - LETTER_W * 0.5 - 150.0, AXIS_X - LETTER_W * 0.5 - 22.0, ry, Color(1, 1, 1, 0.75 * le))
		Kit.dots(c, AXIS_X + LETTER_W * 0.5 + 22.0, AXIS_X + LETTER_W * 0.5 + 150.0, ry, Color(1, 1, 1, 0.75 * le))
		Menu.label(c, TENTATIVE, Vector2(AXIS_X, TENTATIVE_Y + (1.0 - le) * 10.0), TENTATIVE_SIZE, Color(1, 1, 1, le), Color(BaTokens.LABEL_INK, le), 4, 1)
	var pa := prompt_alpha()
	if pa > 0.0:
		Menu.label(c, PROMPT, Vector2(AXIS_X, PROMPT_Y), PROMPT_SIZE, Color(1, 1, 1, pa), Color(BaTokens.LABEL_INK, pa), 6, 1)
	_draw_frame(c, ui)
	if _flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, REF), Color(1, 1, 1, _flash))

## Two halo rings (BA's own deco circle) turning against each other behind the logo.
func _draw_rings(c: Control) -> void:
	if _ring == null:
		return
	var grow := _ease(_t / 1.0)
	for spec in [[600.0, 3.0, 0.24], [400.0, -5.0, 0.18]]:
		var s: float = float(spec[0]) * (0.7 + 0.3 * grow)
		c.draw_set_transform(LOGO_C + Vector2(0.0, 18.0), deg_to_rad(_t * float(spec[1])), Vector2.ONE)
		c.draw_texture_rect(_ring, Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, float(spec[2]) * grow))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

## A four-point glint where the logo's blades cross, every four seconds. Skipped with Reduce Flashes.
func _draw_flare(c: Control, lr: Rect2) -> void:
	if Game.session.reduce_flashes:
		return
	var ph := fposmod(_t - 1.4, 4.0) / 0.7
	if _t < 1.4 or ph >= 1.0:
		return
	var a := sin(ph * PI)
	var p := lr.position + FLARE_AT * (lr.size.x / 1024.0)
	var l := 64.0 * a
	var w := 3.5 * a
	var col := Color(0.85, 0.97, 1.0, a)
	c.draw_polygon(PackedVector2Array([p + Vector2(-l, 0), p + Vector2(0, -w), p + Vector2(l, 0), p + Vector2(0, w)]), PackedColorArray([col, col, col, col]))
	c.draw_polygon(PackedVector2Array([p + Vector2(0, -l), p + Vector2(w, 0), p + Vector2(0, l), p + Vector2(-w, 0)]), PackedColorArray([col, col, col, col]))
	c.draw_texture_rect(_dot, Rect2(p - Vector2(26, 26) * a, Vector2(52, 52) * a), false, Color(1, 1, 1, 0.9 * a))

func _draw_motes(c: Control) -> void:
	for m in _motes:
		var x := fposmod(float(m["x"]) + float(m["vx"]) * _t, REF.x + 40.0) - 20.0
		var y := fposmod(float(m["y"]) + float(m["vy"]) * _t, REF.y + 40.0) - 20.0
		var tw := 0.5 + 0.5 * sin(_t * 1.7 + float(m["ph"]))
		var r := float(m["r"]) * (0.8 + 0.4 * tw)
		var a := (0.16 + 0.34 * tw) * (1.0 if m["near"] else 0.7)
		c.draw_texture_rect(_dot, Rect2(Vector2(x, y) - Vector2(r, r) * 2.0, Vector2(r, r) * 4.0), false, Color(0.92, 0.98, 1.0, a))

## The framing: hairlines with ticks top and bottom, and the fine print.
func _draw_frame(c: Control, a: float) -> void:
	var line := Color(1, 1, 1, 0.3 * a)
	for y in [60.0, 660.0]:
		c.draw_line(Vector2(24.0, y), Vector2(REF.x - 24.0, y), line, 1.0)
		var tx := 24.0
		while tx <= REF.x - 24.0:
			c.draw_line(Vector2(tx, y), Vector2(tx, y + (6.0 if y < 100.0 else -6.0)), line, 1.0)
			tx += 64.0
	Menu.label(c, FOOTER, Vector2(24.0, 696.0), FOOTER_SIZE, Color(1, 1, 1, 0.85 * a), Color(BaTokens.LABEL_INK, 0.85 * a), 3, 0, 500)
	_draw_credits_button(c, a)

## The Credits button in the bottom right corner: BA's blue plate, a C key disc and the word; it turns yellow under the mouse.
func _draw_credits_button(c: Control, a: float) -> void:
	var hot := CREDITS_RECT.has_point(_over.get_local_mouse_position()) and _credits == null
	var r := CREDITS_RECT
	Menu.nine(c, "Combat__Common_Btn_BG", r, Menu.K, Color(BaTokens.CONFIRM if hot else BaTokens.CYAN_PLATE, a), BaTokens.SHEAR)
	var disc := Rect2(r.position + Vector2(10.0, 4.0), Vector2(26.0, 26.0))
	BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", disc, Color(1, 1, 1, a))
	Menu.label(c, "C", Vector2(disc.get_center().x, disc.get_center().y + 6.0), 16, Color(1, 1, 1, a), Color(0, 0, 0, 0), 0, 1, 800)
	var ink := Color(BaTokens.CONFIRM_INK, a) if hot else Color(1, 1, 1, a)
	Menu.label(c, "Credits", Vector2(r.position.x + 84.0, r.get_center().y + 7.0), 19, ink, Color(0, 0, 0, 0) if hot else Color(BaTokens.HEAD_OUTLINE, a), 0 if hot else 3, 1, 800)

func logo_rect() -> Rect2:
	var e := _ease((_t - 0.2) / 0.7)
	var h := LOGO_W * float(_logo.get_height()) / float(_logo.get_width())
	return Rect2(LOGO_C - Vector2(LOGO_W, h) * 0.5 + Vector2(0.0, (1.0 - e) * -36.0), Vector2(LOGO_W, h))

func letters_rect() -> Rect2:
	var h := LETTER_W * float(_letters.get_height()) / float(_letters.get_width())
	return Rect2(LETTER_C - Vector2(LETTER_W, h) * 0.5, Vector2(LETTER_W, h))

## The prompt's alpha now: in from 1.2 s, then a slow pulse between 0.55 and 1 (steady with Reduce Flashes).
func prompt_alpha() -> float:
	var ramp := clampf((_t - 1.2) / 0.4, 0.0, 1.0)
	var pulse := 0.95 if Game.session.reduce_flashes else 0.55 + 0.45 * (0.5 + 0.5 * cos(TAU * _t / PULSE_S))
	return ramp * pulse

func probe() -> Dictionary:
	var pw := Menu.text_width(PROMPT, PROMPT_SIZE)
	var tw := Menu.text_width(TENTATIVE, TENTATIVE_SIZE)
	return {"t": _t, "going": _going, "film": _film, "film_done": _film_done, "playing": _player != null and _player.is_playing(),
			"logo": logo_rect(), "letters": letters_rect(), "tentative": Rect2(AXIS_X - tw * 0.5, TENTATIVE_Y - TENTATIVE_SIZE, tw, TENTATIVE_SIZE * 1.25),
			"prompt": Rect2(AXIS_X - pw * 0.5, PROMPT_Y - PROMPT_SIZE, pw, PROMPT_SIZE * 1.25),
			"footer": Rect2(24.0, 696.0 - float(FOOTER_SIZE), Menu.text_width(FOOTER, FOOTER_SIZE, 500), 18.0),
			"credits_button": CREDITS_RECT, "credits_open": _credits != null}
