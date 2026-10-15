extends Screen
## Match result in the look of BA's arena summary: the winner's art large and bleeding
## off the left edge, the loser's dimmed on the right, a pastel field split on a slash with the loser's side pink, BA's real
## Win and Lose lettering and maroon VS between them, navy ribbons for the stats and yellow and cyan plates for the menu.
## params: {winner: 1|2, wins: [a, b], rounds: n (unused), stats: [{damage, combo, hits}, {…}]}
## Arcade: "Next Fight" / "Continue" instead of Rematch; clearing the ladder (arcade_stage reaches its length, five when none is built) shows ARCADE CLEAR.

const ART_SHADER := preload("res://shaders/select_art.gdshader")
const Kit := preload("res://scripts/fight/hud_kit.gd")
const Menu := preload("res://scripts/ui/ba_menu.gd")
const PainterScript := preload("res://scripts/ui/painter.gd")

const BG := "UIs__00_Images__BG__Tactic_Result_Bg"
const PATTERN := "UIs__00_Images__Image_Triangle_Pattern_Deco_1"
const RING := "UIs__00_Images__Image_Deco_Circle"

const MENU_Y := 512.0
const MENU_W := 262.0
const MENU_H := 52.0
const MENU_PITCH := 62.0
const RIBBON_X := 550.0
const RIBBON_W := 180.0
const RIBBON_H := 26.0
const RIBBON_Y := 318.0
const RIBBON_PITCH := 46.0
const NUM_H := 28.0
const WIN_W := 500.0
const LOSE_W := 250.0
const VS_W := 180.0
const LOSER_SAT := 0.5     # the loser keeps enough colour for the lose face to read
const CONFIRM_GAP := 0.4       # a Light mashed through the match end must not land on Rematch

var _t := 0.0
var _winner := 1
var _wins := [0, 0]
var _stats := [{}, {}]
var _items: Array = []
var _sel := 0
var _fighter: Dictionary = {}
var _loser: Dictionary = {}
var _arcade_over := false
var _arcade_lost := false
var _art_w: TextureRect
var _art_l: TextureRect
var _mat_w: ShaderMaterial
var _mat_l: ShaderMaterial
var _frame_w := {}
var _frame_l := {}
var _ink: Control
var _menu: Array = []          # menu hit areas, one Control per item
var _ready_at := 0.9
var _last_confirm := -10.0

func enter(p: Dictionary, _info: Dictionary) -> void:
	_winner = int(p.get("winner", 1))
	_wins = p.get("wins", [0, 0])
	_stats = p.get("stats", [{}, {}])
	var pw: Dictionary = Game.session.players[_winner - 1]
	var pl: Dictionary = Game.session.players[2 - _winner]
	_fighter = Game.by_id.get(int(pw["fighter"]), {})
	_loser = Game.by_id.get(int(pl["fighter"]), {})
	if Game.session.mode == "arcade":
		if _winner == 1:
			Game.session.arcade_stage += 1
			var rungs: int = Game.session.arcade_ladder.size() if not Game.session.arcade_ladder.is_empty() else 5
			_items = ["Next Fight", "Main Menu"] if Game.session.arcade_stage < rungs else ["Main Menu"]
			_arcade_over = Game.session.arcade_stage >= rungs
		else:
			_items = ["Continue", "Main Menu"]
			_arcade_lost = true
	else:
		_items = ["Rematch", "Character Select", "Main Menu"]
	_build()
	Sfx.play("claim", 0.9)

# ── construction ─────────────────────────────────────────────────────────────
func _build() -> void:
	add_child(PainterScript.new().setup(Vector2(1280, 720), _draw_field))
	var wid := int(_fighter.get("id", 10005))
	var lid := int(_loser.get("id", 10005))
	var face_w := _face(wid, "win")
	var face_l := _face(lid, "lose")
	_frame_w = SelectFrames.frame(wid, face_w, 1)
	_frame_l = _small_frame(lid, face_l, 180.0, Vector2(1095.0, 258.0))
	_art_l = _make_art(face_l, _frame_l)
	_mat_l = _art_l.material
	_art_w = _make_art(face_w, _frame_w)
	_mat_w = _art_w.material
	for i in _items.size():
		var area := Control.new()
		area.size = Vector2(MENU_W, MENU_H)
		area.mouse_filter = Control.MOUSE_FILTER_STOP
		area.mouse_entered.connect(_on_hover.bind(i))
		area.gui_input.connect(_on_item_input.bind(i))
		add_child(area)
		_menu.append(area)
	_ink = PainterScript.new().setup(Vector2(1280, 720), _draw_ink)
	_ink.z_index = 10
	add_child(_ink)

## Like SelectFrames.frame but with a chosen head size / anchor (the loser's smaller art).
func _small_frame(id: int, tex: Texture2D, head_px: float, anchor: Vector2) -> Dictionary:
	var w := float(tex.get_width())
	var h: Array = SelectFrames.HEADS.get(id, [w * 0.3, 60.0, w * 0.4])
	var sc := head_px / float(h[2])
	var ctr := Vector2(float(h[0]) + float(h[2]) * 0.5, float(h[1]) + float(h[2]) * 0.5)
	return {"scale": sc, "pos": anchor - ctr * sc, "size": Vector2(tex.get_size()) * sc}

## The win or lose face on the plain portrait's canvas, or the plain portrait when the install has none of that name.
static func _face(id: int, state: String) -> Texture2D:
	var rel := "portrait/%d_%s.webp" % [id, state]
	return UI.tex(rel) if ResourceLoader.exists(UI.BA + rel) else UI.portrait(id)

func _make_art(tex: Texture2D, f: Dictionary) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = ART_SHADER
	r.material = m
	r.size = f["size"]
	r.position = f["pos"]
	add_child(r)
	return r

# ── motion ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_t += delta
	var fw: Dictionary = _frame_w
	_art_w.position = (fw["pos"] as Vector2) + Vector2(-(1.0 - Motion.whip(_t, 0.2, 0.5)) * 460.0, 0.0)
	var sc: float = fw["scale"]
	_mat_w.set_shader_parameter("shadow_px", 11.0 / sc)
	_mat_w.set_shader_parameter("shadow_off", Vector2(5.0, 9.0) / sc)
	var fl: Dictionary = _frame_l
	_art_l.position = (fl["pos"] as Vector2) + Vector2((1.0 - Motion.whip(_t - 0.15, 0.2, 0.5)) * 460.0, 0.0)
	var scl: float = fl["scale"]
	_mat_l.set_shader_parameter("shadow_px", 11.0 / scl)
	_mat_l.set_shader_parameter("shadow_off", Vector2(5.0, 9.0) / scl)
	_mat_l.set_shader_parameter("dim", 0.9)
	_mat_l.set_shader_parameter("saturation", LOSER_SAT)
	for i in _menu.size():
		var area: Control = _menu[i]
		area.position = _menu_pos(i) + Vector2(0.0, (1.0 - _menu_k(i)) * 120.0)
	_ink.queue_redraw()

func _menu_pos(i: int) -> Vector2:
	return Vector2(515.0 + float(i) * 14.0 - float(_items.size() - 1) * 7.0 + 7.0, MENU_Y + float(i) * MENU_PITCH)

## UIAni_Battle_Result_Arena: the OK button leaves y -818 units at 0.617 s, reaches -11.55 at 0.767 s and settles at 1.033 s.
func _menu_k(i: int) -> float:
	return Motion.whip(_t - 0.617 - 0.1 * float(i), 0.15, 0.27, 0.97)

## The stamp: scale 2.0, 0.95 at 0.267 s, 1.0 at 0.4 s, alpha 0.05 to 1 by 0.4 s. Returns (scale, alpha).
func _stamp(delay: float) -> Vector2:
	var t := _t - delay
	if t < 0.0:
		return Vector2(2.0, 0.0)
	var s := lerpf(2.0, 0.95, t / 0.267) if t < 0.267 else lerpf(0.95, 1.0, clampf((t - 0.267) / 0.133, 0.0, 1.0))
	return Vector2(s, lerpf(0.05, 1.0, clampf(t / 0.4, 0.0, 1.0)))

# ── drawing ──────────────────────────────────────────────────────────────────
func _draw_field(c: Control) -> void:
	BaArt.blit(c, BG, Rect2(0, 0, 1280, 720))
	BaArt.blit(c, PATTERN, Rect2(-120, 60, 760, 760), Color(1, 1, 1, 0.5))
	BaArt.blit(c, RING, Rect2(380, -140, 520, 520), Color(1, 1, 1, 0.45))
	c.draw_colored_polygon(PackedVector2Array([Vector2(760, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(690, 720)]), Color(BaTokens.LOSER_FIELD, 0.92))

func _word(c: Control, word: String, centre: Vector2, width: float, st: Vector2) -> void:
	BaWords.draw(c, word, centre, width * st.x, Color(1, 1, 1, st.y))

func _draw_ink(c: Control) -> void:
	_word(c, "win", Vector2(640, 124), WIN_W, _stamp(0.0))
	_word(c, "lose", Vector2(1135, 96), LOSE_W, _stamp(0.12))
	_word(c, "vs", Vector2(640, 262), VS_W, _stamp(0.25))
	if Game.session.mode == "arcade":
		var k := Motion.whip(_t - 0.2)
		Menu.ribbon(c, Rect2(30.0 - (1.0 - k) * 400.0, 34.0, 300.0, 40.0), _header_text())
	_draw_stats(c)
	_draw_menu(c)
	_draw_names(c)

func _stat_rows() -> Array:
	var s: Dictionary = _stats[_winner - 1]
	var o: Dictionary = _stats[2 - _winner]
	return [
		["TOTAL DAMAGE", str(int(round(float(s.get("damage", 0.0))))), str(int(round(float(o.get("damage", 0.0)))))],
		["MAX COMBO", str(int(s.get("combo", 0))), str(int(o.get("combo", 0)))],
		["HITS LANDED", str(int(s.get("hits", 0))), str(int(o.get("hits", 0)))],
		["ROUNDS WON", str(int(_wins[_winner - 1])), str(int(_wins[2 - _winner]))],
	]

func _draw_stats(c: Control) -> void:
	var rows := _stat_rows()
	for i in rows.size():
		var k := Motion.whip(_t - 0.5 - 0.09 * float(i), 0.15, 0.4)
		var y := RIBBON_Y + RIBBON_PITCH * float(i)
		var a := clampf(k * 3.0, 0.0, 1.0)
		Menu.ribbon(c, Rect2(RIBBON_X, y, RIBBON_W, RIBBON_H), rows[i][0], a)
		var ny := y + RIBBON_H * 0.5 - NUM_H * 0.5
		BaNumerals.draw(c, rows[i][1], Vector2(RIBBON_X - 12.0 - (1.0 - k) * 300.0, ny), NUM_H, BaNumerals.Tier.NORMAL, Color(1, 1, 1, a), 2)
		BaNumerals.draw(c, rows[i][2], Vector2(RIBBON_X + RIBBON_W + 12.0 + (1.0 - k) * 300.0, ny), NUM_H, BaNumerals.Tier.NORMAL, Color(0.82, 0.84, 0.9, a), 0)

func _draw_menu(c: Control) -> void:
	for i in _items.size():
		var area: Control = _menu[i]
		var sel := i == _sel
		var r := Rect2(area.position, area.size)
		var a := clampf(_menu_k(i) * 4.0, 0.0, 1.0)
		Menu.nine(c, "Combat__Common_Btn_BG", r, Menu.K, Color(BaTokens.CONFIRM if sel else BaTokens.CYAN_PLATE, a), BaTokens.SHEAR)
		BaArt.blit(c, "Common__Common_Btn_Normal_Y_S_Pt" if sel else "Common__Common_Btn_Normal_B_S_Pt", r.grow_individual(2.0, 1.0, 2.0, 0.0), Color(1, 1, 1, a))
		var text := str(_items[i]).to_upper()
		var size := Menu.fit(text, 24, MENU_W - 40.0, 14, 800)
		if sel:
			Menu.label(c, text, Vector2(r.get_center().x, r.position.y + 31.0), size, Color(BaTokens.CONFIRM_INK, a), Color(0, 0, 0, 0), 0, 1, 800)
			Menu.bracket(c, r.grow_individual(14.0, 8.0, 14.0, 4.0), Motion.pulse(_t), a)
		else:
			Menu.label(c, text, Vector2(r.get_center().x, r.position.y + 31.0), size, Color(1, 1, 1, a), Color(BaTokens.HEAD_OUTLINE, a), 3, 1, 800)

func _draw_names(c: Control) -> void:
	var font := UI.font_name()
	var k := Motion.whip(_t - 0.45, 0.2, 0.45)
	var nx := 31.0 - (1.0 - k) * 340.0
	var a := clampf(k * 3.0, 0.0, 1.0)
	Menu.ribbon(c, Rect2(nx + 6.0, 506.0, 118.0, 24.0), _who_text(), a)
	var nm := Fighters.display_name(_fighter).to_upper()
	Kit.lean(c, Vector2(nx, 606.0), BaTokens.SHEAR)
	Kit.text_fit(c, font, Vector2.ZERO, nm, 92, 340.0, Color(1, 1, 1, a), Color(BaTokens.HEAD_OUTLINE, a), 11)
	Kit.unlean(c)
	var kr := Motion.whip(_t - 0.6, 0.2, 0.45)
	var rx := 1250.0 + (1.0 - kr) * 340.0
	var ar := clampf(kr * 3.0, 0.0, 1.0)
	Menu.ribbon(c, Rect2(rx - 150.0, 566.0, 150.0, 24.0), _loser_text(), ar)
	var lnm := Fighters.display_name(_loser).to_upper()
	Kit.text_fit(c, font, Vector2(rx, 650.0), lnm, 56, 300.0, Color(0.36, 0.4, 0.5, ar), Color(1, 1, 1, ar), 8, 2)

func _header_text() -> String:
	if _arcade_over:
		return "ARCADE CLEAR"
	if Game.session.mode == "arcade":
		return "GAME OVER" if _arcade_lost else "STAGE %d CLEAR" % int(Game.session.arcade_stage)
	return ""

func _who_text() -> String:
	if Game.session.mode == "versus2p":
		return "PLAYER %d" % _winner
	return "YOU" if _winner == 1 else "CPU"

func _loser_text() -> String:
	return "DEFEATED"

# ── input ────────────────────────────────────────────────────────────────────
func _select(i: int, sound := true) -> void:
	if i == _sel:
		return
	_sel = i
	if sound:
		Sfx.play("tick")

func _on_hover(i: int) -> void:
	if _t > _ready_at and not covered and not Game.busy:
		_select(i)

func _on_item_input(ev: InputEvent, i: int) -> void:
	if covered or Game.busy or _t < _ready_at:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_select(i, false)
		_choose(_items[i])

func on_action(_dev: String, act: String) -> void:
	var settled := _t - _last_confirm >= CONFIRM_GAP
	if act == "confirm":
		_last_confirm = _t
	if _t < 0.6:
		return
	match act:
		"up":
			_select((_sel + _items.size() - 1) % _items.size())
		"down":
			_select((_sel + 1) % _items.size())
		"confirm":
			if settled:
				_choose(_items[_sel])

func _choose(item: String) -> void:
	if item not in ["Rematch", "Next Fight", "Continue"]:
		Sfx.stop_all()     # the winner's line outlasts the round end on purpose; the fight's own start stops it for the ones above
	Sfx.play("confirm")
	match item:
		"Rematch", "Next Fight", "Continue":
			Game.go("fight", {}, "slam")
		"Character Select":
			Game.session.new_picks()
			Game.go("select", {}, "crest", {"crest": "gold"})
		_:
			Game.go("menu", {}, "fade")

func probe() -> Dictionary:
	return {"winner": _winner, "wins": _wins, "items": _items, "sel": _sel, "arcade_over": _arcade_over}
