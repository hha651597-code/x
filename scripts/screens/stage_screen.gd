extends Screen
## Stage + BGM Select: an overlay pushed by the select screen. The screen below is blurred and
## darkened (shaders/screen_blur.gdshader), a big parallelogram preview shows the stage plate (changing stage
## crossfades with a visible ghost), the stage name sits on a hairline with a yellow bar, a white BGM bar cycles
## the music (live preview through Game.session.bgm) and a row of thumbnails (the stages + a "?" random
## tile) pick the stage. Every device may navigate. Confirm → Game.go("vs"); back → Game.pop().
## All rects are 1280×720 reference pixels measured on the stills.

const BLUR_SHADER := preload("res://shaders/screen_blur.gdshader")
const Painter := preload("res://scripts/ui/painter.gd")

const SHEAR := 0.108                                   # every slanted shape in the stills leans 0.108 px per px
const PREVIEW := Rect2(162.0, 83.0, 956.0, 270.5)
const THUMB := Vector2(93.0, 52.0)
const ROW_ORIGIN := [Vector2(586.5, 545.5), Vector2(156.5, 610.5)]   # centre of the first thumb of each row
const PITCH := 106.9
const COLS := 2
const RANDOM_INDEX := 1
const BAR := Rect2(417.5, 468.0, 444.0, 32.5)
const HAIR_Y := 446.2
const SCHOOL_Y := 376.0
const NAME_Y := 407.0
const PALE_YELLOW := Color("f5e07c")                  # selected thumb / focused bar outline
const LEMON := Color("faff2d")                        # the short bar on the hairline
const INK := Color("27304a")
const CROSSFADE := 0.4
const INTRO_LOCK := 0.3
const BGM_SHOWN := {"pachad": "PACHAD"}               # the video shows this one in capitals
# vertical crop of each plate inside the wide preview (0 = top of the plate, 1 = bottom)
const PLATE_FOCUS := {}

static var _rng: RandomNumberGenerator
static var _last_sel := 0

var _t := 0.0
var _sel := 0
var _bgm_idx := 0
var _bgm_before := "auto"
var _bar_focus := false
var _leaving := false
var _leave_t := 0.0
var _went := false
var _roll := {}                                        # random-tile roulette state
var _slideshow_t := 0.0
var _confirmed_stage := ""
var _text_age := 99.0
var _bgm_age := 99.0
var _bgm_dir := 1
var _bar_pulse := 0.0
var _chev_kick := [0.0, 0.0]
var _bar_hl := 0.0
var _ghosts: Array = []                                # fading copies of replaced labels

var _blur: ColorRect
var _blur_mat: ShaderMaterial
var _prev_holder: Control
var _layers: Array = []                                # {card, age, dur, z0}
var _school_lbl: Label
var _name_lbl: Label
var _hair: ColorRect
var _yellow: ColorRect
var _bar_holder: Control
var _bar_card: Card
var _bgm_lbl: Label
var _x_glyph: Control
var _chev: Array = []
var _thumbs: Array = []                                # {holder, card, hl, delay}

# enter
func enter(_p: Dictionary, _info: Dictionary) -> void:
	z_index = 30                                    # above the covered select screen's z-indexed tiles
	_bgm_before = Game.session.bgm
	_bgm_idx = _bgm_index(Game.session.bgm)
	_sel = _initial_selection()
	_build()
	_apply_selection(true)
	Sfx.play("whoosh", 1.1, 0.7)

func _initial_selection() -> int:
	var id: String = Game.session.stage.get("id", "")
	for i in Stages.LIST.size():
		if Stages.LIST[i]["id"] == id:
			return i
	return clampi(_last_sel, 0, RANDOM_INDEX)

func _bgm_index(id: String) -> int:
	for i in Stages.BGM.size():
		if Stages.BGM[i]["id"] == id:
			return i
	return 0

@warning_ignore("integer_division")
func _row_of(i: int) -> int:
	return i / COLS

func _thumb_center(i: int) -> Vector2:
	return (ROW_ORIGIN[_row_of(i)] as Vector2) + Vector2((i % COLS) * PITCH, 0.0)

# build
func _build() -> void:
	_blur = ColorRect.new()
	_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_STOP     # swallow clicks meant for the covered screen
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = BLUR_SHADER
	_blur.material = _blur_mat
	add_child(_blur)

	_prev_holder = Control.new()
	_prev_holder.position = PREVIEW.position
	_prev_holder.size = PREVIEW.size
	_prev_holder.pivot_offset = PREVIEW.size * 0.5
	_prev_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prev_holder)

	_hair = ColorRect.new()
	_hair.color = Color(1, 1, 1, 0.96)
	_hair.position = Vector2(0, HAIR_Y)
	_hair.size = Vector2(1280, 2.6)
	_hair.pivot_offset = Vector2(640, 1.3)
	_hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hair)
	_yellow = ColorRect.new()
	_yellow.color = LEMON
	_yellow.position = Vector2(495, 445.8)
	_yellow.size = Vector2(290, 4.4)
	_yellow.pivot_offset = Vector2(145, 2.2)
	_yellow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_yellow)

	_school_lbl = _mk_label("", 18, 600, Color(1, 1, 1, 0.94), SCHOOL_Y, 30.0)
	add_child(_school_lbl)
	_name_lbl = _mk_label("", 38, 700, Color.WHITE, NAME_Y, 54.0)
	UI.label_shadow(_name_lbl, Color(0, 0, 0, 0.45), Vector2(0, 2))
	add_child(_name_lbl)

	_build_bgm_bar()
	_build_thumbs()

func _mk_label(text: String, size: int, weight: int, color: Color, cy: float, h: float, w := 1280.0, x := 0.0) -> Label:
	var l := UI.label(text, size, "ui", color, weight, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(x, cy - h * 0.5)
	l.size = Vector2(w, h)
	l.pivot_offset = l.size * 0.5
	return l

func _build_bgm_bar() -> void:
	_bar_holder = Control.new()
	_bar_holder.position = BAR.position
	_bar_holder.size = BAR.size
	_bar_holder.pivot_offset = BAR.size * 0.5
	_bar_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar_holder.mouse_entered.connect(_on_bar_hover)
	_bar_holder.gui_input.connect(_on_bar_input)
	add_child(_bar_holder)
	_bar_card = Card.new().setup(BAR.size, 4.0, 0.0)
	_bar_card.set_picture(null).set_fill(Color.WHITE).set_shear(SHEAR).set_gloss(0.0).set_shadow(0.35, 8.0, Vector2(0, 3))
	_bar_card.set_param("shadow_color", Color.BLACK)
	_bar_card.set_param("border_color", PALE_YELLOW)
	_bar_holder.add_child(_bar_card)
	_bgm_lbl = _mk_label(_bgm_text(_bgm_idx), 18, 700, INK, BAR.size.y * 0.5, BAR.size.y, BAR.size.x)
	_bar_holder.add_child(_bgm_lbl)
	_fit_bgm_label()
	# the (X) prompt: black disc, blue X
	_x_glyph = Painter.new().setup(Vector2(24, 24), func(c: Control) -> void:
		c.draw_circle(Vector2(12, 12), 11.5, Color("1c1d21"))
		c.draw_string(UI.font_ui(800), Vector2(0, 18.2), "X", HORIZONTAL_ALIGNMENT_CENTER, 24, 17, Color("33a9f1")))
	_x_glyph.position = Vector2(439.0 - 12.0 - BAR.position.x, 484.0 - 12.0 - BAR.position.y)
	_bar_holder.add_child(_x_glyph)
	# ◀ ▶ chevrons (white, thick, rounded) outside the bar, shown while the bar has focus
	for side in [-1, 1]:
		var pts := PackedVector2Array([Vector2(13, 3), Vector2(3, 14), Vector2(13, 25)]) if side < 0 \
			else PackedVector2Array([Vector2(5, 3), Vector2(15, 14), Vector2(5, 25)])
		var ch := Painter.new().setup(Vector2(18, 28), func(c: Control) -> void:
			c.draw_polyline(pts, Color.WHITE, 4.0, true)
			c.draw_circle(pts[0], 2.0, Color.WHITE)
			c.draw_circle(pts[2], 2.0, Color.WHITE))
		ch.mouse_filter = Control.MOUSE_FILTER_STOP
		ch.gui_input.connect(_on_chevron_input.bind(side))
		add_child(ch)
		_chev.append({"node": ch, "home": Vector2(385.0 if side < 0 else 886.0, 484.0) - ch.size * 0.5, "side": side})

func _build_thumbs() -> void:
	for i in RANDOM_INDEX + 1:
		var c := _thumb_center(i)
		var holder := Control.new()
		holder.size = THUMB
		holder.position = c - THUMB * 0.5
		holder.pivot_offset = THUMB * 0.5
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_entered.connect(_on_thumb_hover.bind(i))
		holder.gui_input.connect(_on_thumb_input.bind(i))
		var card := Card.new().setup(THUMB, 7.0, 3.0)
		if i < RANDOM_INDEX:
			card.set_picture(UI.tex(Stages.LIST[i]["plate"]), Vector2(0.5, 0.5), 1.0)
		else:
			card.set_picture(null).set_fill(Color("0d0d10"))
		card.set_shear(SHEAR).set_gloss(0.08).set_shadow(0.4, 8.0, Vector2(0, 3))
		card.set_param("shadow_color", Color.BLACK)
		holder.add_child(card)
		if i == RANDOM_INDEX:
			var q := _mk_label("?", 38, 800, Color.WHITE, THUMB.y * 0.5, THUMB.y, THUMB.x)
			holder.add_child(q)
		add_child(holder)
		var row := _row_of(i)
		_thumbs.append({"holder": holder, "card": card, "hl": 0.0, "delay": 0.1 + float(row) * 0.03 + float(i % COLS) * 0.009})

# selection / preview
func _stage_of(i: int) -> Dictionary:
	return Stages.LIST[i] if i < RANDOM_INDEX else Stages.RANDOM

func _plate_tex(i: int) -> Texture2D:
	if i < RANDOM_INDEX:
		return UI.tex(Stages.LIST[i]["plate"])
	return UI.tex(Stages.LIST[(_slideshow_idx()) % RANDOM_INDEX]["plate"])

func _slideshow_idx() -> int:
	return int(_slideshow_t / 0.7) * 7 + 3

func _apply_selection(first: bool) -> void:
	if first:
		# the entrance shows a ghost of another plate dissolving into the real one
		_add_layer(UI.tex(Stages.LIST[(_sel + 13) % RANDOM_INDEX]["plate"]), "", true, 0.0)
		_add_layer(_plate_tex(_sel), _stage_of(_sel).get("id", ""), false, 0.6, -0.04)
		_set_texts(_stage_of(_sel), true)
	else:
		_add_layer(_plate_tex(_sel), _stage_of(_sel).get("id", ""), false, 0.11 if not _roll.is_empty() else CROSSFADE)
		_set_texts(_stage_of(_sel), false)
	_last_sel = _sel
	if not first:
		_bar_pulse = 1.0

func _add_layer(tex: Texture2D, id: String, instant: bool, dur: float, age0 := 0.0) -> void:
	var card := Card.new().setup(PREVIEW.size, 11.0, 3.5)
	card.set_picture(tex, Vector2(0.5, PLATE_FOCUS.get(id, 0.5)), 1.0).set_shear(SHEAR).set_gloss(0.22)
	card.set_shadow(0.45, 16.0, Vector2(0, 6))
	card.set_param("shadow_color", Color.BLACK)
	card.modulate.a = 0.0 if not instant else 1.0
	_prev_holder.add_child(card)
	_layers.append({"card": card, "age": 99.0 if instant else age0, "dur": maxf(dur, 0.01), "z0": 1.0 if instant else 1.13})
	while _layers.size() > 5:
		(_layers[0]["card"] as Card).queue_free()
		_layers.remove_at(0)

func _set_texts(stage: Dictionary, first: bool) -> void:
	var school: String = stage.get("school", "")
	var nm: String = stage.get("name", "")
	if stage.get("id", "") == "random":
		school = "Anywhere in Kivotos"
		nm = "Random Stage"
	if not first:
		_ghost(_school_lbl, Vector2(0, -16), 0.2)
		_ghost(_name_lbl, Vector2(0, -22), 0.2)
	_school_lbl.text = school
	_name_lbl.text = nm
	_text_age = 0.0 if not first else -0.08

## A fading, drifting copy of a label that is about to change (the ghost trail of the video's text swaps).
func _ghost(src: Label, drift: Vector2, life: float) -> void:
	if src.text == "":
		return
	var g := src.duplicate() as Label
	g.modulate.a = src.modulate.a
	src.get_parent().add_child(g)
	g.move_to_front()
	_ghosts.append({"node": g, "age": 0.0, "life": life, "drift": drift, "home": g.position, "a0": src.modulate.a})

func _select(i: int, sound := true) -> void:
	if i == _sel:
		return
	if sound:
		Sfx.play("tick", 1.0 + 0.012 * float(i % COLS))
	_sel = i
	_apply_selection(false)
	if i == RANDOM_INDEX:
		_slideshow_t = 0.0

func _on_thumb_hover(i: int) -> void:
	if _usable():
		if _bar_focus:
			_set_bar_focus(false, false)
		_select(i)

func _on_thumb_input(ev: InputEvent, i: int) -> void:
	if not _usable():
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_set_bar_focus(false, false)
		_select(i)
		_choose()

func _usable() -> bool:
	return not covered and not Game.busy and not _leaving and _roll.is_empty() and _t > INTRO_LOCK

# BGM bar
func _bgm_text(i: int) -> String:
	var track: Dictionary = Stages.BGM[i]
	return BGM_SHOWN.get(track["id"], track["name"])

## Long track titles shrink to fit the pill (it also holds the X prompt on the left and the chevrons outside).
func _fit_bgm_label() -> void:
	var fs := 18
	var font := UI.font_ui(700)
	while fs > 11 and font.get_string_size(_bgm_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > BAR.size.x - 130.0:
		fs -= 1
	_bgm_lbl.add_theme_font_size_override("font_size", fs)

func _set_bar_focus(on: bool, sound := true) -> void:
	if on == _bar_focus:
		return
	_bar_focus = on
	if sound:
		Sfx.play("pop", 1.15 if on else 0.9, 0.6)

func _cycle_bgm(dir: int) -> void:
	_bgm_idx = posmod(_bgm_idx + dir, Stages.BGM.size())
	Game.session.bgm = Stages.BGM[_bgm_idx]["id"]
	Sfx.play("tick", 0.9 + 0.08 * _bgm_idx)
	_ghost(_bgm_lbl, Vector2(-dir * 26.0, 0), 0.18)
	_bgm_lbl.text = _bgm_text(_bgm_idx)
	_fit_bgm_label()
	_bgm_dir = dir
	_bgm_age = 0.0
	_chev_kick[0 if dir < 0 else 1] = 1.0

func _on_bar_hover() -> void:
	if _usable():
		_set_bar_focus(true)

func _on_bar_input(ev: InputEvent) -> void:
	if not _usable():
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if not _bar_focus:
			_set_bar_focus(true)
		else:
			_cycle_bgm(-1 if (ev as InputEventMouseButton).position.x < BAR.size.x * 0.5 else 1)

func _on_chevron_input(ev: InputEvent, side: int) -> void:
	if _usable() and _bar_focus and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_cycle_bgm(side)

# input
func on_action(_dev: String, act: String) -> void:
	if _t < INTRO_LOCK or _leaving or not _roll.is_empty():
		return
	var row := _row_of(_sel)
	match act:
		"left":
			if _bar_focus:
				_cycle_bgm(-1)
			else:
				_select(row * COLS + posmod(_sel % COLS - 1, COLS))
		"right":
			if _bar_focus:
				_cycle_bgm(1)
			else:
				_select(row * COLS + posmod(_sel % COLS + 1, COLS))
		"up":
			if not _bar_focus:
				if row == 0:
					_set_bar_focus(true)
				else:
					_select(_sel - COLS)
		"down":
			if _bar_focus:
				_set_bar_focus(false)
			elif row == 0 and _sel + COLS <= RANDOM_INDEX:
				_select(_sel + COLS)
		"aux":
			_set_bar_focus(not _bar_focus)
		"lb":
			_set_bar_focus(true, false)
			_cycle_bgm(-1)
		"rb":
			_set_bar_focus(true, false)
			_cycle_bgm(1)
		"confirm":
			if _bar_focus:
				_set_bar_focus(false)
				Sfx.play("confirm", 1.2, 0.5)
			else:
				_choose()
		"back":
			Sfx.play("back")
			Game.session.bgm = _bgm_before
			Game.pop()

# choosing
func _choose() -> void:
	if _leaving or not _roll.is_empty():
		return
	if _sel == RANDOM_INDEX:
		_start_roulette()
		return
	_lock_in(_sel)

func _lock_in(i: int) -> void:
	_leaving = true
	_leave_t = 0.32
	Game.session.stage = Stages.LIST[i]
	_confirmed_stage = Stages.LIST[i]["id"]
	_bar_pulse = 1.6
	Sfx.play("confirm")

func _random_gen() -> RandomNumberGenerator:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = 20240607
	return _rng

## The "?" tile: the highlight hops across the stages (slowing down) and lands on a seeded pick.
func _start_roulette() -> void:
	var target := _random_gen().randi_range(0, RANDOM_INDEX - 1)
	var hops := 9
	var order: Array = []
	for k in hops:
		order.append(posmod(target - (hops - 1 - k), RANDOM_INDEX))
	_roll = {"order": order, "k": 0, "timer": 0.0, "target": target}
	Sfx.play("pop", 1.2)

func _update_roulette(delta: float) -> void:
	if _roll.is_empty():
		return
	_roll["timer"] = float(_roll["timer"]) - delta
	if float(_roll["timer"]) > 0.0:
		return
	var k: int = _roll["k"]
	var order: Array = _roll["order"]
	if k < order.size():
		_select(order[k], false)
		Sfx.play("tick", 0.9 + 0.07 * float(k))
		_roll["timer"] = 0.05 + 0.011 * float(k)
		_roll["k"] = k + 1
	else:
		var target: int = _roll["target"]
		_roll = {}
		_lock_in(target)

func _update_leave(delta: float) -> void:
	if not _leaving:
		return
	_leave_t -= delta
	if _leave_t <= 0.0 and not _went and not Game.busy:
		_went = true
		Game.go("vs", {}, "fade")

# per-frame animation
func _process(delta: float) -> void:
	_t += delta
	_update_backdrop()
	_update_intro()
	_update_layers(delta)
	_update_texts(delta)
	_update_thumbs(delta)
	_update_bar(delta)
	_update_roulette(delta)
	_update_leave(delta)
	if _sel == RANDOM_INDEX and _roll.is_empty():
		_update_slideshow(delta)

func _update_backdrop() -> void:
	_blur_mat.set_shader_parameter("blur", 40.0 * (1.0 - exp(-_t * 4.2)))
	_blur_mat.set_shader_parameter("darken", 0.17 + 0.54 * smoothstep(0.05, 1.05, _t))
	_blur_mat.set_shader_parameter("desaturate", 0.25 * smoothstep(0.0, 0.9, _t))
	_blur_mat.set_shader_parameter("vignette", 0.12 * smoothstep(0.2, 1.0, _t))

func _update_intro() -> void:
	var pt := maxf(0.0, _t - 0.0)
	_prev_holder.modulate.a = clampf(pt * 3.0, 0.0, 1.0)
	var ps := 0.9 + 0.1 * UI.spring(pt, 7.0, 10.0)
	_prev_holder.scale = Vector2(ps, ps)
	_prev_holder.position = PREVIEW.position + Vector2(0, (1.0 - clampf(pt * 3.0, 0.0, 1.0)) * 14.0)
	# hairline sweeps out from the centre, the yellow bar springs in after it
	var ht := maxf(0.0, _t - 0.06)
	_hair.scale = Vector2(1.0 - pow(1.0 - clampf(ht / 0.45, 0.0, 1.0), 3.0), 1.0)
	_hair.modulate.a = clampf(ht * 7.0, 0.0, 1.0)
	var yt := maxf(0.0, _t - 0.14)
	var ys := UI.spring(yt, 8.0, 12.0)
	var pulse := _bar_pulse
	_yellow.scale = Vector2(maxf(ys, 0.0) * (1.0 + 0.05 * pulse), 1.0 + 0.6 * pulse)
	_yellow.modulate.a = clampf(yt * 8.0, 0.0, 1.0)

func _update_layers(delta: float) -> void:
	for i in _layers.size():
		var L: Dictionary = _layers[i]
		L["age"] = float(L["age"]) + delta
		var card: Card = L["card"]
		var a := 1.0 if i == 0 else smoothstep(0.0, 1.0, clampf(float(L["age"]) / float(L["dur"]), 0.0, 1.0))
		card.modulate.a = a
		var e := 1.0 - pow(1.0 - clampf(float(L["age"]) / 0.85, 0.0, 1.0), 3.0)
		card.set_param("zoom", lerpf(float(L["z0"]), 1.0, e))
	if _layers.size() > 1:
		var top: Dictionary = _layers.back()
		if float(top["age"]) >= float(top["dur"]):
			while _layers.size() > 1:
				(_layers[0]["card"] as Card).queue_free()
				_layers.remove_at(0)

func _update_slideshow(delta: float) -> void:
	var before := _slideshow_idx()
	_slideshow_t += delta
	if _slideshow_idx() != before and _t > 1.0:
		_add_layer(_plate_tex(RANDOM_INDEX), "", false, CROSSFADE)

func _update_texts(delta: float) -> void:
	_text_age += delta
	_bgm_age += delta
	_bar_pulse = move_toward(_bar_pulse, 0.0, delta * 3.0)
	# school + name: ghost swap, plus the entrance
	var ia := clampf((_t - 0.08) / 0.3, 0.0, 1.0)
	var sa := clampf(_text_age * 9.0, 0.0, 1.0)
	var se := 1.0 - pow(1.0 - clampf(_text_age / 0.28, 0.0, 1.0), 3.0)
	_school_lbl.modulate.a = ia * sa
	_school_lbl.position.y = SCHOOL_Y - 15.0 + (1.0 - se) * 10.0 + (1.0 - clampf((_t - 0.08) / 0.3, 0.0, 1.0)) * 8.0
	_name_lbl.modulate.a = ia * clampf(_text_age * 8.0, 0.0, 1.0)
	_name_lbl.position.y = NAME_Y - 27.0 + (1.0 - se) * 14.0
	var nt := maxf(0.0, _t - 0.1)
	var ns := 0.92 + 0.08 * UI.spring(nt, 7.0, 11.0)
	var bump := 1.0 + 0.035 * clampf(1.0 - _text_age * 5.0, 0.0, 1.0)
	_name_lbl.scale = Vector2(ns * bump, ns * bump)
	# bgm label slides in from the side it was cycled towards
	var be := 1.0 - pow(1.0 - clampf(_bgm_age / 0.24, 0.0, 1.0), 3.0)
	_bgm_lbl.position.x = _bgm_dir * (1.0 - be) * 26.0
	_bgm_lbl.modulate.a = clampf(_bgm_age * 9.0, 0.0, 1.0)
	# ghost trails
	for g in _ghosts.duplicate():
		g["age"] = float(g["age"]) + delta
		var node: Label = g["node"]
		var k := clampf(float(g["age"]) / float(g["life"]), 0.0, 1.0)
		if k >= 1.0:
			node.queue_free()
			_ghosts.erase(g)
			continue
		node.modulate.a = float(g["a0"]) * (1.0 - k) * 0.7
		node.position = (g["home"] as Vector2) + (g["drift"] as Vector2) * k

func _update_thumbs(delta: float) -> void:
	for i in _thumbs.size():
		var th: Dictionary = _thumbs[i]
		var holder: Control = th["holder"]
		var card: Card = th["card"]
		var sel := i == _sel
		th["hl"] = lerpf(float(th["hl"]), 1.0 if sel else 0.0, 1.0 - exp(-delta * 18.0))
		var hl: float = th["hl"]
		var ct := _t - float(th["delay"])
		var pop := UI.spring(maxf(ct, 0.0), 9.0, 12.5)
		var s := lerpf(0.35, 1.0, pop) * (1.0 + 0.07 * hl + 0.03 * _bar_pulse * (1.0 if sel else 0.0))
		holder.scale = Vector2(s, s)
		holder.modulate.a = clampf(ct * 9.0, 0.0, 1.0)
		holder.z_index = 3 if sel else 1
		card.set_param("border", lerpf(3.0, 5.4, hl))
		card.set_param("border_color", Color.WHITE.lerp(PALE_YELLOW, hl))

func _update_bar(delta: float) -> void:
	_bar_hl = lerpf(_bar_hl, 1.0 if _bar_focus else 0.0, 1.0 - exp(-delta * 16.0))
	var bt := maxf(0.0, _t - 0.1)
	var bs := UI.spring(bt, 8.0, 12.0)
	var enter_a := clampf(bt * 8.0, 0.0, 1.0)
	_bar_holder.modulate.a = enter_a
	_bar_holder.position = BAR.position + Vector2(0, (1.0 - bs) * 16.0)
	_bar_holder.scale = Vector2.ONE
	# the focused bar swells a little and gains a pale yellow outline (the outline grows outwards)
	var grow := Vector2(3.0, 2.6) * _bar_hl
	_bar_card.position = -grow
	_bar_card.size = BAR.size + grow * 2.0
	_bar_card.set_param("border", 4.2 * _bar_hl)
	_x_glyph.modulate.a = 1.0 - clampf(_bar_hl * 1.4, 0.0, 1.0)
	_x_glyph.scale = Vector2.ONE * (1.0 - 0.25 * _bar_hl)
	for k in _chev.size():
		var c: Dictionary = _chev[k]
		var node: Control = c["node"]
		_chev_kick[k] = move_toward(_chev_kick[k], 0.0, delta * 5.0)
		var side: int = c["side"]
		var slide := (1.0 - UI.spring(_bar_hl, 7.0, 10.0)) * 16.0 * side
		var kick := sin(_chev_kick[k] * PI) * 7.0 * side
		node.position = (c["home"] as Vector2) + Vector2(slide + kick, (1.0 - bs) * 16.0)
		node.modulate.a = clampf(_bar_hl * 1.6, 0.0, 1.0) * enter_a
		node.mouse_filter = Control.MOUSE_FILTER_STOP if _bar_focus else Control.MOUSE_FILTER_IGNORE

# debug
func probe() -> Dictionary:
	return {
		"t": snappedf(_t, 0.01),
		"selected": _sel,
		"stage": _stage_of(_sel).get("id", ""),
		"name": _name_lbl.text if _name_lbl else "",
		"bgm": Game.session.bgm,
		"bar_focus": _bar_focus,
		"layers": _layers.size(),
		"leaving": _leaving,
		"roulette": not _roll.is_empty(),
		"confirmed": _confirmed_stage,
		"session_stage": Game.session.stage.get("id", ""),
	}
