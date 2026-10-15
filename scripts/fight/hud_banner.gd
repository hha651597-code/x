extends RefCounted
## Round banners made of BA's own pieces: the FIGHT! and START! image fonts with the start-light flare, WIN and LOSE image
## fonts, the hazard strips and WARNING, a starburst and the blue streak for K.O., and our baked words (ROUND n, K.O.,
## TIME UP, DRAW, TRAINING) in a stage-start band. Timings are the game's own clips:
## UIAni_Start, UIAni_StageStart, UIAni_Battle_Result_Arena, UIAni_Battle_BossWarning.
## kinds: round (ROUND n, FINAL ROUND, TRAINING) · fight · start · ko · timeup · win · draw · warning.
## FightHud drives it with start() and draw(canvas, now); a banner is gone at age == dur whatever it is.
## Light flares are additive: draw() hangs one child under the canvas that carries BaArt.additive().

const PainterScript := preload("res://scripts/ui/painter.gd")

const FLARE := "UIs__00_Images__Ingame_Start_Light"
const STREAK := "UIs__00_Images__Formation__UITex_BGBlueLight"
const HAZARD := "UIs__00_Images__Ingame_Warning_Deco_1"
const FACET := "UIs__00_Images__Image_Triangle_Pattern_Deco_1"
const RIBBON := "Combat__Combat_Title_Bg"
const BURST := "Floater__Imagefont_Cri_Bg"
const RING := "UIs__00_Images__Image_Deco_Circle"

const CX := 640.0
const YC := 306.0
const BAND_H := 104.0
const OPEN := 11.0 / 60.0         # UIAni_StageStart: the band opens in 11 frames and closes in 10
const CLOSE := 10.0 / 60.0
const CALL_IN := 8.0 / 60.0       # UIAni_Start: the word covers 80 percent of its way in 8 frames, then creeps through the centre
const CALL_OUT := 3.0 / 60.0
const CALL_W := 520.0
const CREEP := 371.0              # px per second, UIAni_Start's 742 units at half size
const WARN_LEN := 2.0             # UIAni_Battle_BossWarning
const WARN_BEAT := 1.0 / 3.0

var kind := ""
var text := ""
var sub := ""
var t0 := 0.0
var dur := 1.0
var slot := 0
var active := false
var word := ""
var yc := YC
var side := 0                       # warning only: 0 across the screen, 1 or 2 over that player's half
var gain := 1.0                     # warning only: the band's dimmer

var _glow: Control
var _glow_items: Array = []

static func kind_of(txt: String) -> String:
	if txt.begins_with("FIGHT"):
		return "fight"
	if txt.begins_with("START"):
		return "start"
	if txt.begins_with("K.O"):
		return "ko"
	if txt.begins_with("TIME"):
		return "timeup"
	if txt.ends_with("WINS"):
		return "win"
	if txt == "DRAW":
		return "draw"
	if txt == "WARNING":
		return "warning"
	return "round"

## The key of the word a banner draws. A tenth round shows ROUND 9 (nine draws in a row), the baked set ends there.
static func word_of(txt: String, lost := false) -> String:
	match kind_of(txt):
		"fight": return "fight"
		"start": return "start"
		"ko": return "ko"
		"timeup": return "time_up"
		"win": return "lose" if lost else "win"
		"draw": return "draw"
		"warning": return "warning"
	if txt == "FINAL ROUND":
		return "final"
	if txt == "TRAINING":
		return "training"
	if txt.begins_with("ROUND "):
		return "round_%d" % clampi(int(txt.substr(6)), 1, 9)
	return "round_1"

## A round the human lost to the cpu shows LOSE, everything else WIN.
static func _lost(win_slot: int) -> bool:
	var s = Game.session
	return s != null and win_slot == 2 and bool(s.players[1].get("cpu", false))

func start(txt: String, sub_txt: String, _col: Color, duration: float, now: float, win_slot := 0) -> void:
	text = txt
	sub = sub_txt
	t0 = now
	dur = duration
	slot = win_slot
	kind = kind_of(txt)
	word = word_of(txt, kind == "win" and _lost(win_slot))
	active = true

## Progress of the band's opening and closing: 0 closed, 1 open.
static func open_of(age: float, length: float) -> float:
	return minf(age / OPEN, 1.0) * (1.0 - clampf((age - (length - CLOSE)) / CLOSE, 0.0, 1.0))

## UIAni_StageStart's word stamp: scale 1.5 to 1.1 in 7 frames, then to 1.0 by frame 23.
static func stamp_of(age: float) -> float:
	if age < 7.0 / 60.0:
		return lerpf(1.5, 1.1, age / (7.0 / 60.0))
	return lerpf(1.1, 1.0, clampf((age - 7.0 / 60.0) / (16.0 / 60.0), 0.0, 1.0))

## WIN and LOSE come down from twice their size to 1.0 and stop there.
static func result_of(age: float) -> float:
	return lerpf(2.0, 1.0, Motion.whip(age))

## The start light pops 0 to 1.25 in 5 frames and settles to 1.0 by frame 23.
static func flare_of(age: float) -> float:
	if age < 5.0 / 60.0:
		return 1.25 * age / (5.0 / 60.0)
	return lerpf(1.25, 1.0, clampf((age - 5.0 / 60.0) / (18.0 / 60.0), 0.0, 1.0))

## Horizontal offset from the centre of FIGHT! and START!: in from the left fast, a slow drift, out to the right in 3 frames.
static func call_x(age: float, length: float) -> float:
	var hold := maxf(length - CALL_IN - CALL_OUT, 0.001)
	var half := CREEP * hold * 0.5
	if age < CALL_IN:
		return lerpf(-1188.0, -half, 1.0 - pow(1.0 - age / CALL_IN, 3.0))
	if age <= length - CALL_OUT:
		return lerpf(-half, half, (age - CALL_IN) / hold)
	var u := clampf((age - (length - CALL_OUT)) / CALL_OUT, 0.0, 1.0)
	return half + (1760.0 - half) * u * u

func draw(c: CanvasItem, now: float) -> void:
	if not active:
		if not _glow_items.is_empty():
			_glow_items.clear()
			_glow_flush(c)
		return
	var age := now - t0
	_glow_items.clear()
	if age >= dur:
		active = false
		_glow_flush(c)
		return
	match kind:
		"fight", "start":
			_call(c, age)
		"ko":
			_ko(c, age)
		"win":
			_result(c, age)
		"warning":
			_warning(c, age)
		_:
			_band(c, age)
	_glow_flush(c)

# ── the additive layer ───────────────────────────────────────────────────────
func _light(tex_name: String, rect: Rect2, a: float, angle := 0.0) -> void:
	if a > 0.001:
		_glow_items.append([tex_name, rect, a, angle])

func _glow_flush(c: CanvasItem) -> void:
	if _glow == null or not is_instance_valid(_glow) or _glow.get_parent() != c:
		if _glow_items.is_empty():
			return
		_glow = PainterScript.new().setup(Vector2(1280, 720), _paint_glow)
		_glow.material = BaArt.additive()
		c.add_child(_glow)
	_glow.queue_redraw()

func _paint_glow(g: Control) -> void:
	for it in _glow_items:
		var r: Rect2 = it[1]
		g.draw_set_transform(r.get_center(), float(it[3]), Vector2.ONE)
		BaArt.blit(g, str(it[0]), Rect2(-r.size * 0.5, r.size), Color(1, 1, 1, float(it[2])))
	g.draw_set_transform_matrix(Transform2D.IDENTITY)

func _dim(c: CanvasItem, a: float, col := Color(0.02, 0.07, 0.18)) -> void:
	if a > 0.001:
		c.draw_rect(Rect2(0, 0, 1280, 720), Color(col.r, col.g, col.b, a))

static func _fit(t: Texture2D, centre: Vector2, h: float, k := 1.0) -> Rect2:
	var size := Vector2(h * float(t.get_width()) / float(t.get_height()), h) * k
	return Rect2(centre - size * 0.5, size)

# ── FIGHT! and START! ────────────────────────────────────────────────────────
func _call(c: CanvasItem, age: float) -> void:
	var t := BaWords.tex(word)
	if t == null:
		return
	var out := clampf((age - (dur - 0.2)) / 0.2, 0.0, 1.0)
	_dim(c, 0.5 * minf(age / 0.15, 1.0) * (1.0 - out))
	var r := Rect2(Vector2(CX + call_x(age, dur) - CALL_W * 0.5, yc - CALL_W * 0.125), Vector2(CALL_W, CALL_W * 0.25))
	c.draw_texture_rect(t, r, false)
	var fa := minf(age / 0.33, 1.0) * (1.0 - clampf((age - dur * 0.6) / (dur * 0.4), 0.0, 1.0))
	var size := Vector2(412.0, 396.0) * flare_of(age)
	_light(FLARE, Rect2(r.position + Vector2(r.size.x * 0.1, r.size.y * 0.36) - size * 0.5, size), fa, deg_to_rad(100.0 + 50.0 * minf(age / 1.2, 1.0)))

# ── ROUND n, TRAINING, TIME UP, DRAW: the stage-start band ───────────────────
func _band_colour() -> Color:
	match kind:
		"timeup": return BaTokens.INK
		"draw": return BaTokens.BAND_DRAW
	return BaTokens.BAND_BLUE if word != "final" else BaTokens.ALERT.darkened(0.2)

func _band(c: CanvasItem, age: float) -> void:
	var open := open_of(age, dur)
	if open <= 0.0:
		return
	var h := BAND_H * open
	var rect := Rect2(0, yc - h * 0.5, 1280, h)
	var col := _band_colour()
	c.draw_rect(rect, Color(col.r, col.g, col.b, 0.94))
	c.draw_texture_rect_region(BaArt.tex(FACET), rect, Rect2(0, 300, 1024, 1024.0 * rect.size.y / 1280.0), Color(1, 1, 1, 0.12))
	for ring_x in [130.0, 1150.0]:
		_clip(c, BaArt.tex(RING), Rect2(ring_x - 130.0, yc - 130.0, 260.0, 260.0), rect, Color(1, 1, 1, 0.3))
	var t := BaWords.tex(word)
	if t == null:
		return
	var tall := 88.0 if kind == "timeup" or kind == "draw" else 68.0
	var a := clampf(age / 0.05, 0.0, 1.0) * clampf(open * 3.0, 0.0, 1.0)
	var r := _fit(t, Vector2(CX, yc), tall, stamp_of(age))
	c.draw_texture_rect(t, r, false, Color(1, 1, 1, a))
	var size := Vector2(412.0, 396.0) * flare_of(age) * open
	_light(FLARE, Rect2(r.position + Vector2(r.size.x * 0.04, r.size.y * 0.2) - size * 0.5, size), open, deg_to_rad(100.0))

# ── K.O. ─────────────────────────────────────────────────────────────────────
func _ko(c: CanvasItem, age: float) -> void:
	var out := clampf((age - (dur - 0.3)) / 0.3, 0.0, 1.0)
	var a := 1.0 - out
	_dim(c, 0.26 * minf(age / 0.1, 1.0) * a, Color(0.14, 0.0, 0.05))
	var k := Motion.whip(age)
	var shake := Vector2(sin(age * 90.0), cos(age * 77.0)) * 6.0 * FxFlash.shake(1.0) * maxf(0.0, 1.0 - age * 3.0)
	var centre := Vector2(CX, yc) + shake
	_light(STREAK, Rect2(CX - 780.0, yc - 100.0, 1560.0, 200.0), minf(age / 0.1, 1.0) * a)
	var burst := BaArt.tex(BURST)
	var ko := BaWords.tex(word)
	if burst == null or ko == null:
		return
	var bs := Vector2(800.0, 361.0) * (0.55 + 0.45 * k)
	c.draw_texture_rect(burst, Rect2(centre - bs * 0.5, bs), false, Color(1, 1, 1, a))
	c.draw_texture_rect(ko, _fit(ko, centre + Vector2(0, -4), 162.0, lerpf(1.5, 1.0, k)), false, Color(1, 1, 1, a * clampf(age / 0.05, 0.0, 1.0)))

# ── "<NAME> WINS" ────────────────────────────────────────────────────────────
func _result(c: CanvasItem, age: float) -> void:
	var out := clampf((age - (dur - 0.3)) / 0.3, 0.0, 1.0)
	var a := minf(age / 0.4, 1.0) * (1.0 - out)
	_dim(c, 0.3 * minf(age / 0.2, 1.0) * (1.0 - out))
	var t := BaWords.tex(word)
	if t == null:
		return
	var s := result_of(age)
	var lost := word == "lose"
	var wc := Vector2(CX, yc + (30.0 if lost else 10.0))
	c.draw_texture_rect(t, _fit(t, wc, 160.0 if lost else 190.0, s), false, Color(1, 1, 1, a))
	if not lost:     # the ribbon names the winner, so a loss shows LOSE alone
		var nm := text.substr(0, maxi(text.length() - 5, 0))
		var font := UI.font_ui(700)
		var size := 46
		while size > 24 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 560.0:
			size -= 2
		var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var ribbon := Rect2(CX - tw * 0.5 - 44.0, yc - 118.0, tw + 88.0, 62.0)
		BaArt.nine(c, RIBBON, ribbon, Color(1, 1, 1, a), BaArt.LEAN)
		var base := Vector2(CX - tw * 0.5, ribbon.get_center().y + size * 0.35)
		c.draw_set_transform_matrix(BaArt.lean_xform(BaArt.LEAN, base.y))
		c.draw_string_outline(font, base, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(BaTokens.HEAD_OUTLINE, a))
		c.draw_string(font, base, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, a))
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	if sub.begins_with("ROUND "):
		var st := BaWords.tex(word_of(sub))
		if st != null:
			c.draw_texture_rect(st, _fit(st, Vector2(CX, yc + (136.0 if lost else 128.0)), 40.0), false, Color(1, 1, 1, a))

# ── WARNING: UIAni_Battle_BossWarning ────────────────────────────────────────
## A texture drawn into r, cut off at the edges of clip.
static func _clip(c: CanvasItem, t: Texture2D, r: Rect2, clip: Rect2, tint: Color) -> void:
	var cut := r.intersection(clip)
	if cut.size.x > 0.0 and cut.size.y > 0.0:
		var k := Vector2(t.get_size()) / r.size
		c.draw_texture_rect_region(t, cut, Rect2((cut.position - r.position) * k, cut.size * k), tint)

func _warning(c: CanvasItem, age: float) -> void:
	var ts := age * WARN_LEN / dur
	var env := clampf(age / 0.2, 0.0, 1.0) * clampf((dur - age) / 0.2, 0.0, 1.0) * gain
	var beat := 0.5 - 0.5 * cos(TAU * ts / (2.0 * WARN_BEAT))
	var strip := BaArt.tex(HAZARD)
	var t := BaWords.tex("warning")
	if strip == null or t == null:
		return
	var x0 := 640.0 if side == 2 else 0.0
	var x1 := 640.0 if side == 1 else 1280.0
	var period := float(strip.get_width()) * 0.43
	var sh := float(strip.get_height()) * 0.43
	c.draw_rect(Rect2(x0, yc - 58.0, x1 - x0, 116.0), Color(0.09, 0.02, 0.03, 0.7 * env))
	for row in 2:
		var y := yc + (58.0 if row == 1 else -58.0) - sh * 0.5
		var off := fposmod(216.0 * ts * (1.0 if row == 0 else -1.0), period)
		for i in 4:
			_clip(c, strip, Rect2(off + period * (i - 1), y, period, sh), Rect2(x0, 0.0, x1 - x0, 720.0), Color(1, 1, 1, (0.65 + 0.3 * beat) * env))
	var k := 1.0
	if ts < 0.0667:
		k = lerpf(0.0, 1.5, ts / 0.0667)
	elif ts < 0.1167:
		k = lerpf(1.5, 1.0, (ts - 0.0667) / 0.05)
	elif ts > 1.9167:
		k = lerpf(1.2, 0.0, (ts - 1.9167) / 0.0833)
	elif ts > 1.8667:
		k = lerpf(1.0, 1.2, (ts - 1.8667) / 0.05)
	var r := _fit(t, Vector2((x0 + x1) * 0.5, yc), 44.0)
	r = Rect2(r.get_center() - Vector2(r.size.x, r.size.y * k) * 0.5, Vector2(r.size.x, r.size.y * k))
	c.draw_texture_rect(t, r, false, Color(BaTokens.PEACH, (1.0 - 0.3 * beat) * env))
