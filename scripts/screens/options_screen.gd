extends Screen
## Options as BA's system popup: Common_Popup_Bg with a navy title strip, dotted row dividers, volume sliders made of twenty
## leaned cells (one cell per Left/Right step), a Reduce Flashes capsule, a Glyphs capsule that picks the button pictures
## and a row that opens the Controls page. Pushed over the
## menu. Up/Down select, Left/Right adjust, mouse drags the sliders, Back closes (or leaves the Controls page) and everything
## is saved on exit. Volumes are live: they write Game.session.bgm_volume / sfx_volume and call Sfx.set_volume.
## All rects are 1280x720 reference pixels.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const Kit := preload("res://scripts/ui/screen_kit.gd")
const BLUR := preload("res://shaders/screen_blur.gdshader")
const Painter := preload("res://scripts/ui/painter.gd")

const ICONS := "res://assets/ba/ui/"
const STEP := 0.05
const CELLS := 20                   # 1 / STEP
const IDS := ["bgm", "sfx", "flashes", "glyphs", "controls"]
const POP_W := 640.0
const CONTROLS_W := 860.0
const HEADER_H := 58.0
const BODY_TOP := 24.0              # between the title strip and the first row
const ROW_GAP := 14.0
const SLIDER_H := 88.0
const ROW_H := 70.0
const FOOT_H := 46.0
const SIDE := 28.0
const CAP_W := 96.0
const CAP_W_GLYPHS := 136.0
const PREVIEW_H := 24.0           # the four face-button pictures beside the Glyphs capsule
const CAP_H := 36.0
const CELL_W := 24.0
const CELL_H := 20.0
const SCRIM_BLUR := 3.0
const SCRIM_DARKEN := 0.45
const CLOSE_AFTER := 0.16

# action label, input action name (-> Controls.label_for, Controls.glyph_for) or custom token lists. "pad" lists the
# gamepad's actions: each shows as its glyph.
const CONTROL_ROWS := [
	{"label": "Move / Jump / Crouch", "kb1": ["A", "W", "S", "D"], "kb2": ["<", "^", "v", ">"], "pad": ["dpad", "stick_l"]},
	{"label": "Light attack", "act": "confirm"},
	{"label": "Heavy attack", "act": "back"},
	{"label": "Skill", "act": "aux"},
	{"label": "EX", "act": "aux2"},
	{"label": "Assist call", "act": "lb"},
	{"label": "Dash", "act": "rb"},
	{"label": "Pause", "kb1": ["V", "Tab", "Esc"], "kb2": ["Num 5"], "pad": ["start"]},
]
const CONTROL_HEADS := ["ACTION", "PLAYER 1  KEYBOARD", "PLAYER 2  KEYBOARD", "GAMEPAD"]
const COL_X := [34.0, 262.0, 444.0, 626.0]
const COL_W := [216.0, 170.0, 170.0, 200.0]
const CONTROLS_ROW_H := 38.0
const RIBBON_H := 24.0
const TOKEN_H := 26.0
const PAD_TOKEN := 30.0          # gamepad glyphs carry padding in their canvas, so they draw larger than a key disc
const GLYPH_NAMES := {"auto": "AUTO", "xbox": "XBOX", "playstation": "PLAYSTATION", "switch": "SWITCH", "steam": "STEAM"}
const GUARD_NOTE := "Hold the direction AWAY from your opponent"

static var _icons := {}

var _t := 0.0
var _open_t := 0.0
var _vals := {"bgm": 0.7, "sfx": 0.8}
var _focus := 0
var _page := "main"
var _sel_t := 1.0
var _closing := false
var _close_t := 0.0
var _drag := -1
var _tick_cd := 0.0
var _hover_close := false
var _scrim: ColorRect
var _scrim_mat: ShaderMaterial
var _paint: Control

# ── enter / build ────────────────────────────────────────────────────────────
func enter(_p: Dictionary, _info: Dictionary) -> void:
	z_index = 30                                    # above the covered screen's own z-indexed cards
	_vals["bgm"] = Game.session.bgm_volume
	_vals["sfx"] = Game.session.sfx_volume
	_build()
	Sfx.play("pop", 0.9, 0.7)

func exit() -> void:
	Game.session.save_settings()

func _build() -> void:
	var back := BackBufferCopy.new()                # the blur must read the screen as it is now, menu included
	back.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(back)
	_scrim_mat = ShaderMaterial.new()
	_scrim_mat.shader = BLUR
	_scrim_mat.set_shader_parameter("dark_color", BaTokens.NAVY)
	_scrim = ColorRect.new()
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.material = _scrim_mat
	_scrim.gui_input.connect(_on_mouse)
	add_child(_scrim)
	_paint = Painter.new().setup(Vector2(1280, 720), _draw_panel)
	add_child(_paint)

static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = load(ICONS + name + ".png")
	return _icons[name]

# ── geometry ─────────────────────────────────────────────────────────────────
func _row_h(i: int) -> float:
	return SLIDER_H if i < 2 else ROW_H

func popup_rect() -> Rect2:
	var h := HEADER_H + FOOT_H
	var w := POP_W
	if _page == "controls":
		w = CONTROLS_W
		h += BODY_TOP + RIBBON_H + 12.0 + CONTROLS_ROW_H * float(CONTROL_ROWS.size() + 1)
	else:
		h += BODY_TOP + ROW_GAP * float(IDS.size() - 1)
		for i in IDS.size():
			h += _row_h(i)
	return Rect2(640.0 - w * 0.5, 360.0 - h * 0.5, w, h)

func row_rect(i: int) -> Rect2:
	var p := popup_rect()
	var y := p.position.y + HEADER_H + BODY_TOP
	for k in i:
		y += _row_h(k) + ROW_GAP
	return Rect2(p.position.x + SIDE, y, p.size.x - SIDE * 2.0, _row_h(i))

## The span of the twenty cells of slider row i.
func cells_span(i: int) -> Vector2:
	var r := row_rect(i)
	return Vector2(r.position.x + 10.0, r.end.x - 10.0)

func _cell_y(i: int) -> float:
	return row_rect(i).position.y + 46.0

func cap_rect(i: int) -> Rect2:
	var r := row_rect(i)
	var w := CAP_W_GLYPHS if IDS[i] == "glyphs" else CAP_W
	return Rect2(r.end.x - w - 10.0, r.position.y + (r.size.y - CAP_H) * 0.5, w, CAP_H)

func close_rect() -> Rect2:
	var p := popup_rect()
	return Rect2(p.end.x - 12.0 - 14.0 - 34.0, p.position.y + 12.0 + (HEADER_H - 34.0) * 0.5, 34.0, 34.0)

static func _on_tint() -> Color:
	return BaTokens.COST.lerp(Color.WHITE, 0.45)

# ── drawing ──────────────────────────────────────────────────────────────────
func _draw_panel(c: Control) -> void:
	var p := popup_rect()
	Menu.nine(c, "Common__Common_Popup_Bg", p)
	var strip := Rect2(p.position.x + 12.0, p.position.y + 12.0, p.size.x - 24.0, HEADER_H)
	Menu.nine(c, "Combat__Combat_Title_Bg", strip)
	Menu.label(c, "CONTROLS" if _page == "controls" else "OPTIONS", Vector2(strip.position.x + 26.0, strip.get_center().y + 11.0), 30,
			BaTokens.WHITE, BaTokens.HEAD_OUTLINE, 2, 0, 800)
	var x := close_rect()
	c.draw_texture_rect(icon("Common__Common_Icon_Close"), x, false, BaTokens.BRACKET if _hover_close else BaTokens.WHITE)
	if _page == "controls":
		_draw_controls(c, p)
	else:
		_draw_main(c, p)

func _draw_main(c: Control, p: Rect2) -> void:
	for i in IDS.size():
		var r := row_rect(i)
		if i < IDS.size() - 1:
			Kit.dots(c, p.position.x + SIDE + 6.0, p.end.x - SIDE - 6.0, r.end.y + ROW_GAP * 0.5 - 1.5, BaTokens.alpha(BaTokens.INK, 0.4))
		if i < 2:
			_draw_slider(c, i, r)
		else:
			_draw_toggle(c, i, r)
	Menu.label(c, "Up / Down: select    Left / Right: adjust    Back: save and close", Vector2(p.end.x - 30.0, p.end.y - 26.0), 13,
			BaTokens.alpha(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 2, 600)
	var r := row_rect(_focus).grow_individual(14.0, 7.0, 14.0, 4.0)
	Kit.bracket(c, r, 0.0, _t, _sel_t)

func _draw_slider(c: Control, i: int, r: Rect2) -> void:
	var id: String = IDS[i]
	var v: float = _vals[id]
	c.draw_texture_rect(icon("Common__Common_Option_Sound_Full" if v > 0.0 else "Common__Common_Option_Sound_Mute"),
			Rect2(r.position.x + 8.0, r.position.y + 2.0, 43.0, 32.0), false)
	Menu.label(c, "BGM Volume" if i == 0 else "SFX Volume", Vector2(r.position.x + 62.0, r.position.y + 28.0), 22, BaTokens.LABEL_INK)
	Menu.label(c, "%d%%" % int(round(v * 100.0)), Vector2(r.end.x - 10.0, r.position.y + 28.0), 24, BaTokens.INK, Color(0, 0, 0, 0), 0, 2, 800)
	var span := cells_span(i)
	var pitch := (span.y - span.x) / float(CELLS)
	var lit := int(round(v * float(CELLS)))
	for k in CELLS:
		BaArt.blit(c, "Combat__Combat_Cost_Gauge", Rect2(span.x + pitch * float(k) + (pitch - CELL_W) * 0.5, _cell_y(i), CELL_W, CELL_H),
				BaTokens.COST if k < lit else BaTokens.alpha(BaTokens.GAUGE_EMPTY, 0.16), BaTokens.SHEAR)

func _draw_toggle(c: Control, i: int, r: Rect2) -> void:
	var cap := cap_rect(i)
	var id: String = IDS[i]
	var on := true
	var title := "Controls"
	var note := "Keyboard and gamepad buttons"
	var word := "OPEN"
	match id:
		"flashes":
			on = Game.session.reduce_flashes
			title = "Reduce Flashes"
			note = "Fewer bright flashes and less screen shake"
			word = "ON" if on else "OFF"
		"glyphs":
			title = "Glyphs"
			note = "Button pictures for your gamepad"
			word = GLYPH_NAMES[Game.session.glyphs]
	Menu.label(c, title, Vector2(r.position.x + 14.0, r.position.y + 31.0), 22, BaTokens.LABEL_INK)
	Menu.label(c, note, Vector2(r.position.x + 14.0, r.position.y + 54.0), 14, BaTokens.alpha(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 0, 600)
	if id == "glyphs":
		var fam := ControllerGlyphs.family(0)
		var x := cap.position.x - 14.0 - (PREVIEW_H + 4.0) * 4.0
		for act in ["confirm", "back", "aux", "aux2"]:
			c.draw_texture_rect(ControllerGlyphs.texture(fam, act), Rect2(x, cap.get_center().y - PREVIEW_H * 0.5, PREVIEW_H, PREVIEW_H), false, BaTokens.INK)
			x += PREVIEW_H + 4.0
	Menu.nine(c, "Combat__Common_Btn_BG", cap, Menu.K, _on_tint() if on else BaTokens.GREY_OFF, BaTokens.SHEAR)
	var size := Menu.fit(word, 16, cap.size.x - 20.0, 11, 800)
	if on:
		Menu.label(c, word, Vector2(cap.get_center().x, cap.position.y + 25.0), size, BaTokens.WHITE, BaTokens.HEAD_OUTLINE, 2, 1, 800)
	else:
		Menu.label(c, word, Vector2(cap.get_center().x, cap.position.y + 25.0), size, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 1, 800)

func _draw_controls(c: Control, p: Rect2) -> void:
	var y := p.position.y + HEADER_H + BODY_TOP
	for k in 4:
		Menu.ribbon(c, Rect2(p.position.x + COL_X[k], y, COL_W[k], RIBBON_H), CONTROL_HEADS[k])
	y += RIBBON_H + 12.0
	for n in CONTROL_ROWS.size():
		var row: Dictionary = CONTROL_ROWS[n]
		var ry := y + CONTROLS_ROW_H * float(n)
		var size := Menu.fit(row["label"], 19, COL_W[0] - 14.0, 13)
		Menu.label(c, row["label"], Vector2(p.position.x + COL_X[0] + 4.0, ry + 26.0), size, BaTokens.LABEL_INK)
		var act: String = row.get("act", "")
		_tokens(c, row.get("kb1", [Controls.label_for("kb1", act)]), Vector2(p.position.x + COL_X[1], ry + 4.0))
		_tokens(c, row.get("kb2", _kb2_keys(act)), Vector2(p.position.x + COL_X[2], ry + 4.0))
		_tokens(c, pad_keys(row), Vector2(p.position.x + COL_X[3], ry + 4.0))
		Kit.dots(c, p.position.x + SIDE, p.end.x - SIDE, ry + CONTROLS_ROW_H - 3.0, BaTokens.alpha(BaTokens.INK, 0.4))
	var gy := y + CONTROLS_ROW_H * float(CONTROL_ROWS.size())
	Menu.label(c, "Guard", Vector2(p.position.x + COL_X[0] + 4.0, gy + 26.0), 19, BaTokens.LABEL_INK)
	var gx: float = p.position.x + COL_X[1]
	var room := p.end.x - SIDE - gx
	var gs := Menu.fit(GUARD_NOTE, 18, room, 12, 600)
	Menu.label(c, GUARD_NOTE, Vector2(gx, gy + 26.0), gs, BaTokens.alpha(BaTokens.INK, 0.9), Color(0, 0, 0, 0), 0, 0, 600)
	Menu.label(c, "Back: return to options", Vector2(p.end.x - 30.0, p.end.y - 26.0), 13, BaTokens.alpha(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 2, 600)

## A row's gamepad column: each action as the pad's glyph.
static func pad_keys(row: Dictionary) -> Array:
	var out := []
	for act in row.get("pad", [row.get("act", "")]):
		var g := Controls.glyph_for("pad0", act)
		out.append(g if g != null else Controls.label_for("pad0", act))
	return out

## The second cluster has alternates (Enter or /, Backspace or Right Shift): show the main ones.
func _kb2_keys(act: String) -> Array:
	match act:
		"confirm": return ["Enter", "/"]
		"back": return ["Bksp"]
	return [Controls.label_for("kb2", act)]

## One binding as BA's cost-tag disc (one character), a leaned navy pill (a word), a disc with an arrow, or a glyph picture
## (in ink on the white card). Returns the x after it.
func _tokens(c: Control, keys: Array, at: Vector2) -> float:
	var x := at.x
	for k in keys:
		var w := token_width(k)
		var r := Rect2(x, at.y, w, TOKEN_H)
		if k is Texture2D:
			c.draw_texture_rect(k, Rect2(x, at.y - 2.0, w, w), false, BaTokens.INK)
			x += w + 6.0
			continue
		var key: String = k
		if key in ["<", ">", "^", "v"]:
			BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", r)
			var angle: float = {"^": 0.0, ">": PI * 0.5, "v": PI, "<": -PI * 0.5}[key]
			c.draw_set_transform(r.get_center(), angle)
			BaArt.blit(c, "Combat__Combat_Icon_Arrow", Rect2(-5.0, -6.5, 10.0, 13.0))
			c.draw_set_transform_matrix(Transform2D.IDENTITY)
		elif key.length() == 1:
			BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", r)
			Menu.label(c, key, Vector2(r.get_center().x, r.position.y + 19.0), 16, BaTokens.WHITE, Color(0, 0, 0, 0), 0, 1, 800)
		else:
			Menu.nine(c, "Combat__Combat_Title_Bg", r, Menu.K, BaTokens.WHITE, BaTokens.SHEAR)
			Menu.label(c, key, Vector2(r.get_center().x, r.position.y + 18.0), 14, BaTokens.WHITE, Color(0, 0, 0, 0), 0, 1, 800)
		x += w + 6.0
	return x

static func token_width(key: Variant) -> float:
	if key is Texture2D:
		return PAD_TOKEN
	if key.length() == 1:
		return TOKEN_H
	return maxf(TOKEN_H, Menu.text_width(key, 14, 800) + 22.0)

# ── input ────────────────────────────────────────────────────────────────────
func on_action(_dev: String, act: String) -> void:
	if _closing or _t < 0.12:
		return
	if _page == "controls":
		if act in ["back", "start", "confirm"]:
			_set_page("main")
		return
	match act:
		"up":
			_set_focus(maxi(_focus - 1, 0))
		"down":
			_set_focus(mini(_focus + 1, IDS.size() - 1))
		"left":
			_adjust(-1)
		"right":
			_adjust(1)
		"confirm":
			_activate(_focus)
		"back", "start":
			_close()

func _set_focus(i: int) -> void:
	if i != _focus:
		_focus = i
		_sel_t = 0.0
		Sfx.play("tick")

## dir -1 or +1: a slider moves one cell, the Reduce Flashes row sets itself off or on, the Glyphs row steps through its choices.
func _adjust(dir: int) -> void:
	match IDS[_focus]:
		"bgm", "sfx":
			_set_value(IDS[_focus], float(_vals[IDS[_focus]]) + STEP * float(dir))
		"flashes":
			_set_flashes(dir > 0)
		"glyphs":
			_step_glyphs(dir)

func _activate(i: int) -> void:
	match IDS[i]:
		"flashes":
			_set_flashes(not Game.session.reduce_flashes)
		"glyphs":
			_step_glyphs(1)
		"controls":
			Sfx.play("confirm")
			_set_page("controls")
		_:
			Sfx.play("confirm", 1.0, 0.8)

func _set_page(page: String) -> void:
	if page == _page:
		return
	_page = page
	_sel_t = 0.0
	Sfx.play("back" if page == "main" else "tick")

func _set_flashes(on: bool) -> void:
	if on == Game.session.reduce_flashes:
		return
	Game.session.reduce_flashes = on
	Sfx.play("confirm" if on else "back", 1.0, 0.7)

func _step_glyphs(dir: int) -> void:
	var n := ControllerGlyphs.OVERRIDES.size()
	Game.session.glyphs = ControllerGlyphs.OVERRIDES[posmod(ControllerGlyphs.OVERRIDES.find(Game.session.glyphs) + dir, n)]
	Sfx.play("tick")

func _set_value(id: String, v: float) -> void:
	v = snappedf(clampf(v, 0.0, 1.0), 0.01)
	if is_equal_approx(v, float(_vals[id])):
		return
	_vals[id] = v
	if id == "bgm":
		Game.session.bgm_volume = v
	else:
		Game.session.sfx_volume = v
		Sfx.set_volume(v)
	if _tick_cd <= 0.0:
		_tick_cd = 0.07
		Sfx.play("tick", 0.8 + 0.5 * v)

func _on_mouse(ev: InputEvent) -> void:
	if _closing or _t < 0.12:
		return
	if ev is InputEventMouseMotion:
		var m := ev as InputEventMouseMotion
		_hover_close = close_rect().grow(6.0).has_point(m.position)
		if _drag >= 0 and (m.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_set_from_mouse(_drag, m.position.x)
		elif _page == "main":
			for i in IDS.size():
				if row_rect(i).grow(6.0).has_point(m.position):
					_set_focus(i)
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var b := ev as InputEventMouseButton
		if not b.pressed:
			_drag = -1
			return
		if close_rect().grow(6.0).has_point(b.position):
			_back_or_close()
		elif not popup_rect().has_point(b.position):
			_back_or_close()
		elif _page == "main":
			for i in IDS.size():
				if row_rect(i).grow(6.0).has_point(b.position):
					_set_focus(i)
					if i < 2:
						var span := cells_span(i)
						if b.position.x >= span.x - 8.0 and b.position.x <= span.y + 8.0 and absf(b.position.y - _cell_y(i) - CELL_H * 0.5) < 22.0:
							_drag = i
							_set_from_mouse(i, b.position.x)
					else:
						_activate(i)
					return

func _back_or_close() -> void:
	if _page == "controls":
		_set_page("main")
	else:
		_close()

func _set_from_mouse(i: int, x: float) -> void:
	var span := cells_span(i)
	_set_value(IDS[i], snappedf((x - span.x) / (span.y - span.x), STEP))

func _close() -> void:
	if _closing:
		return
	_closing = true
	_close_t = 0.0
	Sfx.play("back")

# ── per-frame animation ──────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_t += delta
	_open_t += delta
	_sel_t += delta
	_tick_cd = maxf(0.0, _tick_cd - delta)
	if _closing:
		_close_t += delta
		if _close_t >= CLOSE_AFTER:
			Game.pop()
			return
	var out := clampf(_close_t / CLOSE_AFTER, 0.0, 1.0)
	var k := clampf(_t / 0.133, 0.0, 1.0) * (1.0 - out)
	_scrim_mat.set_shader_parameter("blur", SCRIM_BLUR * k)
	_scrim_mat.set_shader_parameter("darken", SCRIM_DARKEN * k)
	_paint.position.y = -(1.0 - Motion.whip(_open_t)) * 300.0 - out * out * 120.0
	_paint.scale.y = lerpf(0.5, 1.0, clampf(_open_t / 0.183, 0.0, 1.0))
	_paint.modulate.a = clampf(_open_t / 0.217, 0.0, 1.0) * (1.0 - out)
	_paint.queue_redraw()

func probe() -> Dictionary:
	return {
		"t": snappedf(_t, 0.01),
		"page": _page,
		"focus": IDS[_focus],
		"bgm_volume": snappedf(float(_vals["bgm"]), 0.001),
		"sfx_volume": snappedf(float(_vals["sfx"]), 0.001),
		"reduce_flashes": Game.session.reduce_flashes,
		"glyphs": Game.session.glyphs,
		"session_bgm_volume": Game.session.bgm_volume,
		"session_sfx_volume": Game.session.sfx_volume,
		"sfx_node_volume": Sfx.volume_sfx,
		"closing": _closing,
	}
