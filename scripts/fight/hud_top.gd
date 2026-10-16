extends Control
## The fight HUD's top rail, built from BA's sprites: per side a halo ring and triangle field, the portrait card over the outer
## end of an HP bar (name and school crest inside it), a guard bar with its label disc, a role chip and the 1P/CPU tag; in the
## middle the timer plate, round pips and the ROUND n ribbon. Status badges come from hud_status.gd.
## Layers: this node's own _draw (back), the bars (children), the ink painter (front), the status rows.
## Fills 1280x720, mouse ignored, ticks itself in _process; read-only on `world` (fighters[i], timer_frames, training, mode,
## wins, phase, round_no). A fighter field that is missing hides its element.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const Painter := preload("res://scripts/ui/painter.gd")
const Bar := preload("res://scripts/fight/hud_bar.gd")
const Status := preload("res://scripts/fight/hud_status.gd")
const Table := preload("res://scripts/fight/hud_status_table.gd")
const Mood := preload("res://scripts/ui/portrait_mood.gd")

# P1 layout in 1280x720 px. P2 is the mirror image of every rect; the lean is not mirrored.
const CARD := Rect2(22, 28, 160, 129)
const PORTRAIT := Rect2(26, 24, 150, 121)
const BAR := Rect2(129, 40, 480, 42)
const EMOTE := "Combat__Ingame_Emo_NearlyDead"
const CREST := Rect2(194, 43, 40, 28)     # the box a school crest's ink is fitted into, centred
# The HP fill's x range on the bar per side, from under the card to under the plate. P2's is not the mirror of P1's: the lean does not
# mirror, so P2's card edge sits 6 px further out, and the fill must reach it or a dark sliver shows between them.
const FILL_X := [Vector2(168, 566), Vector2(714, 1118)]
const NAME_X := 236.0
const NAME_W := 317.0
const GUARD := Rect2(234, 89, 250, 12)
const DISC := Rect2(200, 82, 30, 30)
const CHIP := Rect2(168, 106, 36, 34)
const TAG := Rect2(13, 112, 54, 20)
const BADGES := Vector2(234, 112)
const HALO := Rect2(78, -40, 240, 240)
const FIELD := Rect2(0, -60, 380, 380)
const WARN_BAR := Rect2(182, 74, 300, 14)
const WARN_GUARD := Rect2(234, 94, 250, 12)
const PLATE := Rect2(558, 16, 164, 72)
const CLOCK := Rect2(578, 38, 26, 29)
const DIGITS := Vector2(664, 28)
const RIBBON := Rect2(583, 90, 114, 22)
const TRAINING := Rect2(572, 37, 136, 30)
const PIP := Rect2(546, 88, 26, 26)
const PIP_PITCH := 30.0

const GUARD_LOW_AT := 0.3
const LOW_HP := Mood.CRITICAL_BELOW
const BLINK := 0.333     # BA's warning decos alternate alpha 0.95 and 0.65 on this beat
const TAPE_SPEED := 250.0
const GUARD_RISE := 2.5     # bar fractions per second back up from a crush that a hit ended

var world: Node
## The gauges' fill is anchored at the outer edge and drains toward the centre, so the last sliver stays by the face. false
## anchors it at the VS side instead, the way BA's arena bar does.
var anchor_outer := true:
	set(v):
		anchor_outer = v
		for i in hp_bars.size():
			hp_bars[i].param("mirror", (i == 1) == v)
			guard_bars[i].param("mirror", (i == 1) == v)
var hp_bars: Array = []
var guard_bars: Array = []
var _hp_prev := [1.0, 1.0]
var _hp_trail := [1.0, 1.0]
var _hp_hold := [0.0, 0.0]
var _gd_prev := [1.0, 1.0]
var _gd_trail := [1.0, 1.0]
var _gd_hold := [0.0, 0.0]
var _gd_rise := [false, false]     # the bar is climbing back after a crush a hit ended early
var _crush_t0 := [-10.0, -10.0]
var _was_crushed := [false, false]
var _wins_seen := [0, 0]
var _lvl := [0, 0]     # PortraitMood hp level per side
var _flinch := [0.0, 0.0]     # seconds of flinch face left, on the HUD clock so a pause holds it
var _won := [false, false]     # the round's winner keeps the win face while the round_end phase lasts
var _face := ["calm", "calm"]
var _pip_t := [[-10.0, -10.0], [-10.0, -10.0]]
var _status: Array = []
var _ink: Control
var _time := 0.0

func setup(w: Node) -> Control:
	world = w
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		hp_bars.append(_add_bar(i, BAR, BaTokens.side(i + 1), true))
	for i in 2:
		_span_hp(i)
	for i in 2:
		guard_bars.append(_add_bar(i, GUARD, BaTokens.GUARD_FULL, false))
		guard_bars[i].visible = false
	_ink = Painter.new().setup(size, _draw_ink)
	_ink.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS     # for the crests: the rest of the HUD art has no mipmaps
	add_child(_ink)
	for i in 2:
		var s: Control = Status.new().setup(w, i, _m(Rect2(BADGES, Vector2.ZERO), i).position)
		add_child(s)
		_status.append(s)
	_wins_seen = [int(w.wins[0]), int(w.wins[1])]
	return self

## r mirrored to side i (0 = left, 1 = right).
static func _m(r: Rect2, i: int) -> Rect2:
	return r if i == 0 else Rect2(1280.0 - r.end.x, r.position.y, r.size.x, r.size.y)

func _add_bar(i: int, r: Rect2, col: Color, ticks: bool) -> Control:
	var sh := BaTokens.shear_px(r.size.y)
	var b: Control = Bar.new().setup(r.size.x, r.size.y, sh, (i == 1) == anchor_outer, Color.WHITE, col)
	b.position = Vector2(_m(r, i).position.x - sh * 0.5, r.position.y)
	b.param("ticks", 1.0 if ticks else 0.0)
	add_child(b)
	return b

func _span_hp(i: int) -> void:
	var win: Vector2 = FILL_X[i]
	var frame := _m(BAR, i)
	(hp_bars[i] as Control).fill_span(win.x - frame.position.x, win.y - frame.position.x)

## The portrait, card, HP bar, guard bar and the timer plate of side i, for the facade and tests.
func rects(i: int) -> Dictionary:
	return {"portrait": _m(PORTRAIT, i), "card": _m(CARD, i), "bar": _m(BAR, i), "guard": _m(GUARD, i), "plate": PLATE}

# state
func _process(delta: float) -> void:
	if world != null and world.get("paused") == true:
		return
	_time += delta
	if world == null or world.fighters.size() < 2:
		return
	for i in 2:
		var f: Object = world.fighters[i]
		if int(world.wins[i]) > int(_wins_seen[i]):
			_pip_t[i][clampi(int(_wins_seen[i]), 0, 1)] = _time
			_won[i] = true
		_wins_seen[i] = int(world.wins[i])
		_won[i] = _won[i] and world.phase == "round_end"
		_hp(i, f, delta)
		_guard(i, f, delta)
	queue_redraw()
	_ink.queue_redraw()

static func _data(f: Object) -> Dictionary:
	return Table.field(f, "data", {})

func _hp(i: int, f: Object, delta: float) -> void:
	var b: Control = hp_bars[i]
	var hp: Variant = f.get("hp")
	var max_hp: Variant = f.get("max_hp")
	b.visible = hp != null and max_hp != null
	if not b.visible:
		return
	var r := clampf(float(hp) / maxf(float(max_hp), 1.0), 0.0, 1.0)
	if r < float(_hp_prev[i]) - 0.0005:
		_hp_hold[i] = 0.45
	_flinch[i] = maxf(0.0, float(_flinch[i]) - delta)
	if Mood.big_hit(float(_hp_prev[i]), r):
		_flinch[i] = Mood.FLINCH_SECONDS
	_lvl[i] = Mood.level(int(_lvl[i]), r)
	_face[i] = Mood.state(int(_lvl[i]), r, float(_flinch[i]), bool(_won[i]))
	_hp_prev[i] = r
	_hp_hold[i] = maxf(0.0, float(_hp_hold[i]) - delta)
	var tr := float(_hp_trail[i])
	if r >= tr:
		tr = r
	elif float(_hp_hold[i]) <= 0.0:
		tr = maxf(r, tr - delta * 0.5)
	_hp_trail[i] = tr
	b.param("fill", r)
	b.param("trail", tr)

func _guard(i: int, f: Object, delta: float) -> void:
	var b: Control = guard_bars[i]
	var stats: Dictionary = Table.field(f, "stats", {})
	var gmax := float(stats.get("guard_max", 0.0))
	var g: Variant = f.get("guard")
	b.visible = gmax > 0.0 and g != null
	if not b.visible:
		return
	var crush := int(Table.field(f, "crush_t", 0))
	var total := float(stats.get("guard_crush", 0.0))
	var crushed := crush > 0 and total > 0.0
	var want := clampf(float(g) / gmax, 0.0, 1.0)
	var r := want
	if crushed:
		r = clampf(1.0 - float(crush) / total, 0.0, 1.0)
		_gd_rise[i] = true
	elif bool(_gd_rise[i]):
		r = minf(want, float(_gd_prev[i]) + delta * GUARD_RISE)
		_gd_rise[i] = r < want
	if not crushed and r < float(_gd_prev[i]) - 0.0005:
		_gd_hold[i] = 0.3
	_gd_prev[i] = r
	_gd_hold[i] = maxf(0.0, float(_gd_hold[i]) - delta)
	var tr := float(_gd_trail[i])
	if r >= tr or crushed:
		tr = r
	elif float(_gd_hold[i]) <= 0.0:
		tr = maxf(r, tr - delta * 0.6)
	_gd_trail[i] = tr
	if crushed and not bool(_was_crushed[i]):
		_crush_t0[i] = _time
	_was_crushed[i] = crushed
	b.param("fill", r)
	b.param("trail", tr)
	b.param("col_bot", BaTokens.ALERT if crushed else (BaTokens.CONFIRM if r < GUARD_LOW_AT else BaTokens.GUARD_FULL))

func _low_hp(i: int) -> bool:
	var r := float(_hp_prev[i])
	return r > 0.0 and r < LOW_HP

func _crushed(i: int) -> bool:
	return guard_bars[i].visible and bool(_was_crushed[i])

## The timer plate: seconds shown, the digit sheet, and in the last ten seconds a blink (0.95, 0.65) that washes the plate in
## BA's low-time rose. The plate stays opaque, so the bar ends tucked under it never show through.
func timer_state() -> Dictionary:
	var low: bool = not world.training and world.phase == "fight" and int(world.timer_frames) <= 600
	return {"text": str(maxi(0, int(ceil(float(world.timer_frames) / 60.0)))), "low": low, "training": bool(world.training),
		"tier": BaNumerals.Tier.EFFECTIVE if low else BaNumerals.Tier.WHITE, "blink": _blink() if low else 0.0}

func _blink() -> float:
	return 0.95 if int(_time / BLINK) % 2 == 0 else 0.65

## The word under the plate: ROUND n, or FINAL ROUND when the rounds are one all. The win that makes it one all lands at
## round_end, while the banner still says that round's number, so the word waits for the next round.
func round_word() -> String:
	if int(world.wins[0]) == 1 and int(world.wins[1]) == 1 and world.phase != "round_end":
		return "final"
	var n: Variant = world.get("round_no")
	return "round_%d" % clampi(int(n) if n != null else int(world.wins[0]) + int(world.wins[1]) + 1, 1, 9)

func tag_text(i: int) -> String:
	if i == 0:
		return "1P"
	return "2P" if world.mode == "versus2p" else "CPU"

## Scale of a won pip's sparkle `age` s after the win: 0 to 1.25 in 0.083 s, then down to 1.0 by 0.383 s (UIAni_StageStart).
static func spark(age: float) -> float:
	if age < 0.0:
		return 0.0
	if age < 0.083:
		return 1.25 * age / 0.083
	return lerpf(1.25, 1.0, clampf((age - 0.083) / 0.3, 0.0, 1.0))

# drawing: back layer
func _draw() -> void:
	if world == null:
		return
	var field := BaArt.tex("UIs__00_Images__Image_Triangle_Pattern_Deco_1")
	var halo := BaArt.tex("UIs__00_Images__Image_Deco_Circle")
	for i in 2:
		var fr := FIELD if i == 0 else Rect2(1280.0 - FIELD.position.x, FIELD.position.y, -FIELD.size.x, FIELD.size.y)
		if field != null:
			draw_texture_rect(field, fr, false, Color(1, 1, 1, 0.5))
		if halo != null:
			draw_texture_rect(halo, _m(HALO, i), false, Color(1, 1, 1, 0.5))
		var dir := -1.0 if i == 0 else 1.0
		if world.fighters.size() > i and _low_hp(i):
			_tape(self, "UIs__00_Images__Ingame_Warning_Deco_1", _m(WARN_BAR, i), dir * _time * TAPE_SPEED, _blink())
		if guard_bars.size() > i and _crushed(i):
			_tape(self, "UIs__00_Images__Ingame_Warning_Deco_3", _m(WARN_GUARD, i), dir * _time * TAPE_SPEED, _blink())

## A hazard tape of texture `art` scrolling along r at the texture's own aspect, clipped to r.
static func _tape(c: CanvasItem, art: String, r: Rect2, scroll: float, a: float) -> void:
	var t := BaArt.tex(art)
	if t == null:
		return
	var tw := r.size.y * float(t.get_width()) / float(t.get_height())
	var x := -fposmod(scroll, tw)
	while x < r.size.x:
		var x0 := maxf(x, 0.0)
		var x1 := minf(x + tw, r.size.x)
		var src := Rect2((x0 - x) / tw * t.get_width(), 0.0, (x1 - x0) / tw * t.get_width(), t.get_height())
		c.draw_texture_rect_region(t, Rect2(r.position.x + x0, r.position.y, x1 - x0, r.size.y), src, Color(1, 1, 1, a))
		x += tw

# drawing: front layer
func _draw_ink(c: Control) -> void:
	if world == null or world.fighters.size() < 2:
		return
	for i in 2:
		_draw_name(c, i)
	for i in 2:
		_draw_card(c, i)
	for i in 2:
		_draw_disc(c, i)
	_draw_centre(c)

## Italic label leaned like BA's: anchor 0 = pos.x is the left edge, 1 centre, 2 right. pos.y is the baseline.
static func _label(c: CanvasItem, text: String, pos: Vector2, size: int, anchor := 0) -> void:
	Menu.label(c, text, pos, size, Color.WHITE, BaTokens.LABEL_EDGE, 4, anchor)

## The name at 22 px, shrunk to fit max_w, cut with a dot after that. Returns [text, size].
static func fit_name(text: String, max_w: float) -> Array:
	var font := UI.font_ui(700)
	var size := Menu.fit(text, 22, max_w, 14)
	while text.length() > 1 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		text = text.left(text.length() - 2) + "."
	return [text, size]

func _draw_name(c: Control, i: int) -> void:
	var d := _data(world.fighters[i])
	var school := str(d.get("school", ""))
	var crest := CrestIcon.get_icon(school, CREST.size) if school != "" else null
	if crest != null:
		var sz := CrestIcon.fit(school, CREST.size)
		c.draw_texture_rect(crest, Rect2(_m(CREST, i).get_center() - sz * 0.5, sz), false)
	var fit := fit_name(Fighters.display_name(d) if d.has("name") else "", NAME_W)
	var y := 61.0 + 0.364 * float(fit[1])
	if i == 0:
		_label(c, fit[0], Vector2(NAME_X, y), fit[1])
	else:
		_label(c, fit[0], Vector2(1280.0 - NAME_X, y), fit[1], 2)

func _draw_card(c: Control, i: int) -> void:
	var d := _data(world.fighters[i])
	BaArt.blit(c, "Combat__Combat_CardBg_EX", _m(CARD, i), BaTokens.CARD_TINT[i])
	var face := str(_face[i])
	var pt: Texture2D = BaArt.portrait(int(d["id"]), face) if d.has("id") else null
	if pt != null:
		var r := _m(PORTRAIT, i)
		if face == "flinch":
			r.position += Mood.shake(_time)
		if face == "ko":
			c.draw_texture_rect(BaArt.gray(pt, BaTokens.KO_SATURATION), r, false, BaTokens.KO_DIM)
		else:
			c.draw_texture_rect(pt, r, false)
	var chip := _m(CHIP, i)
	var glyph: Texture2D = BaArt.role_icon(str(d["role"])) if d.has("role") else null
	if glyph != null:
		BaArt.blit(c, "Common__Card_Role_Bg", chip, BaArt.attack_color(str(d.get("bullet", ""))))
		c.draw_texture_rect(glyph, chip.grow(-6.0), false)
	var tag := _m(TAG, i)
	BaArt.nine(c, "Combat__Combat_Title_Bg", tag, Color.WHITE, BaTokens.SHEAR)
	_label(c, tag_text(i), Vector2(tag.get_center().x, tag.end.y - 5.0), 13, 1)
	if _low_hp(i):
		var bob := sin(_time * 7.0) * 2.0
		var e := _m(Rect2(148, 6, 50, 42), i)
		BaArt.blit(c, EMOTE, Rect2(e.position + Vector2(0.0, bob), e.size))

func _draw_disc(c: Control, i: int) -> void:
	if not guard_bars[i].visible:
		return
	var d := _m(DISC, i)
	if _crushed(i):
		var s := lerpf(1.25, 1.0, clampf((_time - float(_crush_t0[i])) / 0.117, 0.0, 1.0))
		var box := Vector2(28.0, 32.0) * s
		BaArt.blit(c, "Combat__Combat_Icon_CC_Stunned", Rect2(d.get_center() - box * 0.5, box))
		return
	BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", d)
	var shield := BaArt.role_icon("Tanker")
	if shield != null:
		c.draw_texture_rect(shield, d.grow(-7.0), false)

func _draw_centre(c: Control) -> void:
	var st := timer_state()
	BaArt.nine(c, "Common__Common_Bg_Raius10px", PLATE, BaTokens.PLATE_NAVY, BaTokens.SHEAR)
	BaArt.nine(c, "Combat__Combat_Bg_Hp", PLATE, Color.WHITE, BaTokens.SHEAR)
	if float(st["blink"]) > 0.0:
		BaArt.nine(c, "Common__Common_Bg_Raius10px", PLATE.grow(-3.0), Color(BaTokens.PLATE_LOW, float(st["blink"]) * 0.8), BaTokens.SHEAR)
	if st["training"]:
		BaArt.nine(c, "Combat__Combat_Title_Bg", TRAINING, Color.WHITE, BaTokens.SHEAR)
		var word := BaWords.tex("training")
		if word != null:
			var h := 15.0
			var sz := Vector2(h * float(word.get_width()) / float(word.get_height()), h)
			c.draw_texture_rect(word, Rect2(TRAINING.get_center() - sz * 0.5, sz), false)
	else:
		BaArt.blit(c, "Combat__Combat_Time_Icon", CLOCK)
		BaNumerals.draw(c, st["text"], DIGITS, 40.0, st["tier"], Color.WHITE, 1)
	if st["training"]:
		return
	for i in 2:
		for k in 2:
			var r := _m(Rect2(PIP.position - Vector2(PIP_PITCH * k, 0.0), PIP.size), i)
			BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", r)
			if int(world.wins[i]) > k:
				var s := spark(_time - float(_pip_t[i][k]))
				var box := Vector2(16.0, 18.0) * s
				BaArt.blit(c, "Emoji__Emoji_Twinkle", Rect2(r.get_center() - box * 0.5, box))
	BaArt.nine(c, "Combat__Combat_Title_Bg", RIBBON, Color.WHITE, BaTokens.SHEAR)
	var word := BaWords.tex(round_word())
	if word != null:
		var sz := Vector2(13.0 * float(word.get_width()) / float(word.get_height()), 13.0)
		c.draw_texture_rect(word, Rect2(RIBBON.get_center() - sz * 0.5, sz), false)
