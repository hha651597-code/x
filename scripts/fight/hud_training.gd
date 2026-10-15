extends Control
## Training-mode overlay in BA's vocabulary: P1's input history on a pale facet card (arrow glyphs and cost-tag disc buttons),
## the last and best combo as BA's combo block, the dummy mode on a ribbon (where a match has the ROUND ribbon), and a tip bubble with the key hints for the first
## five seconds (hud_pause.gd draws the same bubble in the pause menu through draw_tip).
## The history is sampled from Fighter.input once per simulation frame by the HUD via sample().

const Menu := preload("res://scripts/ui/ba_menu.gd")
const Bottom := preload("res://scripts/fight/hud_bottom.gd")

const CARD_ART := "Combat__Combat_CardBg_Tactice_Support"
const DISC_ART := "Combat__Combat_CardBg_EX_CostTag"
const ARROW_ART := "Combat__Combat_Icon_Arrow"
const BUBBLE_ART := "Combat__Ingame_Operater_Text_Bg"
const CHIP_GLYPH_H := 24.0   # a glyph chip stands taller than a letter chip: the picture needs the room
const CARD := Rect2(10.0, 328.0, 236.0, 222.0)
const CARD_TINT := Color(1.07, 1.16, 1.2)
const CARD_LEAN := 0.18          # the lean baked into the card sprite
const ROW_PITCH := 25.0
const ROWS := 7
const DISC := 22.0
const TIP_SECONDS := 5.0
const TIP_AT := Vector2(300.0, 176.0)    # above the fighters' heads and clear of the combo feed, whose numeral ends near x 280
const BEST_FLASH := 1.6

const BTN_TXT := {"light": "L", "heavy": "H", "skill": "S", "ex": "EX", "assist": "A", "dash": "D"}

var hud: Control
var _hist: Array = []
var last := {"hits": 0, "dmg": 0.0}
var _last_pop := -10.0
var _t := 0.0
var _tip_t := 0.0
var _push_t := -10.0
var _top_f0 := -1
var _best_seen := 0
var _best_t := -10.0

func setup(h: Control) -> Control:
	hud = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = h.world.training
	return self

func note_combo(hits: int, dmg: float, now: float) -> void:
	last = {"hits": hits, "dmg": dmg}
	_last_pop = now

func reset() -> void:
	_hist.clear()
	_tip_t = 0.0

func sample(world: Node) -> void:
	if not visible or world.phase != "fight" or world.time_stop > 0 or world.paused:
		return
	var inp: FightInput = world.f1.input
	if inp == null:
		return
	var mask := 0
	for i in FightInput.BUTTONS.size():
		if inp.is_held(FightInput.BUTTONS[i]):
			mask |= 1 << i
	var fr: int = world._frame
	if not _hist.is_empty():
		var h: Dictionary = _hist[0]
		if h["x"] == inp.x and h["y"] == inp.y and h["mask"] == mask:
			return
	_hist.push_front({"x": inp.x, "y": inp.y, "mask": mask, "f0": fr})
	if _hist.size() > 10:
		_hist.pop_back()

func _process(delta: float) -> void:
	if not visible or hud.world.get("paused") == true:
		return
	_t += delta
	_tip_t += delta
	if not _hist.is_empty() and int(_hist[0]["f0"]) != _top_f0:
		_top_f0 = int(_hist[0]["f0"])
		_push_t = _t
	var f1 = hud.world.get("f1")
	if f1 != null:
		var mx: int = f1.stat_max_combo
		if mx > _best_seen:
			if _best_seen > 0:
				_best_t = _t
			_best_seen = mx
	queue_redraw()

## Opacity of the tip bubble on its own: up for the first seconds of a round, off while paused (the pause menu draws it).
func tip_alpha() -> float:
	if hud.get("_paused") == true:
		return 0.0
	return clampf((TIP_SECONDS - _tip_t) / 0.3, 0.0, 1.0) * clampf(_tip_t / 0.2, 0.0, 1.0)

func _draw() -> void:
	var world: Node = hud.world
	var dm := str(world.get("dummy_mode") if world.get("dummy_mode") != null else "stand")
	var rail = hud.get("_top")     # the ribbon rides in with the top rail
	Menu.ribbon(self, Rect2(640.0 - 78.0, 90.0 + (rail.position.y if rail != null else 0.0), 156.0, 22.0), "DUMMY " + dm.to_upper())
	_draw_history(world)
	_draw_combo(hud._time)
	var a := tip_alpha()
	if a > 0.0:
		draw_tip(self, TIP_AT, a)

# ── input history ────────────────────────────────────────────────────────────
func _draw_history(world: Node) -> void:
	var k := Motion.whip(_t - 0.2, 0.2, 0.45)
	var card := Rect2(CARD.position + Vector2(-(1.0 - k) * 280.0, 0.0), CARD.size)
	BaArt.blit(self, CARD_ART, Rect2(card.position + Vector2(0.0, 5.0), card.size), Color(0.04, 0.14, 0.28, 0.25))
	BaArt.blit(self, CARD_ART, card, CARD_TINT)
	Menu.ribbon(self, Rect2(card.position.x + 36.0, card.position.y - 8.0, 76.0, 20.0), "INPUT")
	if _hist.is_empty():
		Menu.label(self, "Nothing pressed yet", card.get_center() + Vector2(0.0, -4.0), 14, BaTokens.INK, Color(0, 0, 0, 0), 0, 1)
		Menu.label(self, "Move or attack to fill the list", card.get_center() + Vector2(0.0, 16.0), 11, Color(BaTokens.INK, 0.7), Color(0, 0, 0, 0), 0, 1, 600)
		return
	var fr_now: int = world._frame
	var push := clampf((_t - _push_t) / 0.1, 0.0, 1.0)
	for i in mini(_hist.size(), ROWS):
		var e: Dictionary = _hist[i]
		var y := card.position.y + 46.0 + ROW_PITCH * float(i) - ROW_PITCH * (1.0 - push)
		var a := (1.0 - 0.06 * float(i)) * (push if i == 0 else 1.0)
		var lx := card.position.x + 16.0 + (card.end.y - y) * CARD_LEAN
		_arrow(Vector2(lx + 10.0, y), Vector2i(int(e["x"]), int(e["y"])), Color(BaTokens.INK, a))
		var bx := lx + 30.0
		for b in FightInput.BUTTONS.size():
			if (int(e["mask"]) >> b) & 1 == 1:
				var nm: String = FightInput.BUTTONS[b]
				BaArt.blit(self, DISC_ART, Rect2(bx, y - DISC * 0.5, DISC, DISC), Color(1, 1, 1, a))
				var txt: String = BTN_TXT[nm]
				Menu.label(self, txt, Vector2(bx + DISC * 0.5, y + 4.5), 12 if txt.length() == 1 else 10, Color(BaTokens.TRAIN_BTN[nm], a), Color(0, 0, 0, 0), 0, 1, 800)
				bx += DISC + 3.0
		var nxt := fr_now if i == 0 else int((_hist[i - 1] as Dictionary)["f0"])
		var dur := mini(99, nxt - int(e["f0"]))
		var rx := card.end.x - 22.0 - (y - card.position.y) * CARD_LEAN
		BaNumerals.draw(self, "%d" % dur, Vector2(rx, y - 6.5), 13.0, BaNumerals.Tier.NORMAL, Color(1, 1, 1, a), 2)

func _arrow(ctr: Vector2, dir: Vector2i, col: Color) -> void:
	if dir == Vector2i.ZERO:
		draw_circle(ctr, 3.0, Color(col, col.a * 0.6))
		return
	draw_set_transform(ctr, Vector2(dir).angle() + PI * 0.5, Vector2.ONE)
	BaArt.blit(self, ARROW_ART, Rect2(-9.0, -11.5, 18.0, 23.0), col)
	draw_set_transform_matrix(Transform2D.IDENTITY)

# ── last and best combo ──────────────────────────────────────────────────────
func _draw_combo(now: float) -> void:
	var k := Motion.whip(_t - 0.3, 0.2, 0.45)
	var x := 1262.0 + (1.0 - k) * 300.0
	var top := CARD.position.y
	var hits := int(last["hits"])
	var a := 1.0 if hits > 0 else 0.45
	var tint := Color(1, 1, 1, a)
	Menu.ribbon(self, Rect2(x - 62.0, top - 8.0, 62.0, 20.0), "LAST")
	var pop := 1.0 + 0.2 * maxf(0.0, 1.0 - (now - _last_pop) * 5.0)
	draw_set_transform(Vector2(x - 126.0, top + 46.0), 0.0, Vector2(pop, pop))
	BaNumerals.draw(self, "%d" % hits, Vector2(0.0, -30.0), 60.0, BaNumerals.Tier.EFFECTIVE, tint, 2)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	BaWords.draw(self, "combo", Vector2(x - 60.0, top + 54.0), 120.0, tint)
	var dmg := "%d" % int(round(float(last["dmg"])))
	var dw := BaNumerals.width(dmg, 26.0, BaNumerals.Tier.NORMAL)
	BaArt.blit(self, "Common__Common_Attack_Icon", Rect2(x - dw - 48.0, top + 84.0, 36.0, 37.0), tint)
	BaNumerals.draw(self, dmg, Vector2(x, top + 90.0), 26.0, BaNumerals.Tier.NORMAL, tint, 2)
	var best := "%d" % _best_seen
	var bw := BaNumerals.width(best, 26.0, BaNumerals.Tier.NORMAL)
	Menu.ribbon(self, Rect2(x - bw - 72.0, top + 134.0, 62.0, 20.0), "BEST")
	BaNumerals.draw(self, best, Vector2(x, top + 128.0), 26.0, BaNumerals.Tier.NORMAL, tint, 2)
	var age := _t - _best_t
	if age < BEST_FLASH:
		var s := lerpf(1.5, 1.0, clampf(age / 0.3, 0.0, 1.0))
		BaWords.draw(self, "best_record", Vector2(x - 130.0, top + 178.0), 190.0 * s, Color(1, 1, 1, clampf((BEST_FLASH - age) / 0.4, 0.0, 1.0)))

# ── key hints ────────────────────────────────────────────────────────────────
## The tip bubble: BA's operator text bubble with the P1 key hints in two columns, each key on a navy ribbon chip. origin is
## the bubble's top-left. Returns its size.
static func draw_tip(ci: CanvasItem, origin: Vector2, a := 1.0) -> Vector2:
	var dev := Bottom.hint_dev(1)
	var move: Variant = "WASD" if dev == "kb1" else ("ARROWS" if dev == "kb2" else Controls.glyph_for(dev, "dpad"))
	var entries: Array = [[move, "Move"]]
	for pair in [["confirm", "Light"], ["back", "Heavy"], ["aux", "Skill"], ["aux2", "EX"], ["lb", "Assist"], ["rb", "Dash"]]:
		var g := Controls.glyph_for(dev, str(pair[0])) if dev.begins_with("pad") else null
		entries.append([g if g != null else Controls.label_for(dev, str(pair[0])), pair[1]])
	var cols := [entries.slice(0, 4), entries.slice(4)]
	var widths := [0.0, 0.0]
	for c in 2:
		for e in cols[c]:
			widths[c] = maxf(widths[c], _chip_w(e[0]) + 8.0 + Menu.text_width(str(e[1]), 14))
	var size := Vector2(float(widths[0]) + float(widths[1]) + 22.0 + 44.0, 4.0 * 26.0 + 36.0)
	Menu.nine(ci, BUBBLE_ART, Rect2(origin, size), Menu.K, Color(1, 1, 1, a))
	for c in 2:
		var x: float = origin.x + 22.0 + (0.0 if c == 0 else float(widths[0]) + 22.0)
		for r in cols[c].size():
			var e: Array = cols[c][r]
			var cy := origin.y + 22.0 + 26.0 * float(r)
			var cw := _chip_w(e[0])
			var ch := CHIP_GLYPH_H if e[0] is Texture2D else 20.0
			Menu.ribbon_parts(ci, Rect2(x, cy - ch * 0.5, cw, ch), [e[0]], a, 0.84)
			Menu.label(ci, str(e[1]), Vector2(x + cw + 8.0, cy + 5.0), 14, Color(BaTokens.INK, a))
	return size

static func _chip_w(key: Variant) -> float:
	return 34.0 if key is Texture2D else maxf(20.0, Menu.text_width(key, 11) + 16.0)
