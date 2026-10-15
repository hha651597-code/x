extends Control
## Bottom row of the fight HUD, 1280x720 reference pixels. Per side: the assist card, the COST disc showing floor(meter / 10),
## ten cost cells that fill away from the disc, cost tags on the SUPER and EX cells, the tier plate and the assist call-out.
## Rects are written for P1 and mirrored for P2; the lean stays "/" on both sides (COST is baked into the disc, so P2 uses it unflipped).
## Owns the meter and assist edge detection, Sfx included. setup(world) -> self, callout(f), and the rect and state helpers below.
## Every alpha animates on a child layer, never on this node, so the facade can duck the whole HUD.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const Painter := preload("res://scripts/ui/painter.gd")

const CELLS := 10
const PITCH := 37.0
const CELL := Vector2(34, 26)
const STRIP := Vector2(228, 640)              # P1 cell nearest the disc
const DISC := Rect2(153, 619, 66, 69)         # the sprite is 117x123
const DISC_CENTRE := Vector2(35.4, 37.8)      # centre of its circle, from the rect's corner
const TAG := 28.0
const FACET := Rect2(16, 580, 158, 130)
const PORTRAIT := Rect2(20, 576, 148, 120)
const BRACKET := Rect2(22, 574, 164, 136)
const BRACKET_PAD := 10.0                      # the ready frame stands this far outside the leaning card
const KEY_DISC := Rect2(14, 566, 40, 40)
const NAME_PLATE := Rect2(34, 688, 130, 26)
const PLATE_MID := 513.0                      # x of the SUPER and EX READY plates, their bottom edge sits above the strip
const PLATE_BOTTOM := 636.0
const PLATE_EX := Vector2(136, 49)
const PLATE_SUPER := Vector2(109, 41)
const CALL := Vector2(236, 95)                # the call-out balloon
const CALL_HOME := Vector2(10, 462)

const CELL_FILL := BaTokens.COST
const FLARE := "UIs__00_Images__Ingame_Start_Light"

const FLASH_LIFE := 0.65                      # a cell that just filled
const FLARE_LIFE := 0.45
const FLARE_EVERY := 1.5
const CALL_LIFE := 1.1                        # short, because the balloon covers a fighter standing in the corner
const CALL_OUT := 0.8
const PRESS_LIFE := 0.167

var world: Node
var _time := 0.0
var _ink: Control
var _light: Control
var _super_t := [-10.0, -10.0]
var _super_was := [false, false]
var _ex_t := [-10.0, -10.0]
var _ex_was := [false, false]
var _ready_t := [-10.0, -10.0]
var _ready_was := [true, true]
var _press_t := [-10.0, -10.0]
var _plate := ["", ""]
var _plate_t := [-10.0, -10.0]
var _prev_meter := [-1.0, -1.0]
var _flash_t := [[], []]
var _call := [{}, {}]

func setup(w: Node) -> Control:
	world = w
	position = Vector2.ZERO
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		_flash_t[i] = []
		for k in CELLS:
			_flash_t[i].append(-10.0)
	_ink = Painter.new().setup(Vector2(1280, 720), _draw_ink)
	add_child(_ink)
	_light = Painter.new().setup(Vector2(1280, 720), _draw_light)
	_light.material = BaArt.additive()
	add_child(_light)
	return self

## The assist call-out for a fighter that just called it: a balloon with the assist's face sliding in from the player's edge.
## A new round starts clean: no call-out left over from the last one.
func reset() -> void:
	_call = [{}, {}]

func callout(f: Fighter) -> void:
	var a: Dictionary = _assist(f)
	if a.is_empty():
		return
	var i := clampi(int(_num(f, "slot", 1.0)) - 1, 0, 1)
	var skill = f.get("assist")
	_call[i] = {"t0": _time, "name": str(skill.get("name", "")) if skill is Dictionary else "", "id": int(a.get("id", 0))}
	_press_t[i] = _time

func _process(delta: float) -> void:
	if world != null and world.get("paused") == true:
		return
	_time += delta
	var fight: bool = world != null and str(world.get("phase")) == "fight"
	for i in 2:
		var f := _f(i)
		if f == null:
			continue
		var m := _meter(i)
		var has_super := m >= Arena.SUPER_COST
		if has_super and not _super_was[i]:
			_super_t[i] = _time
			if fight:
				Sfx.play("ex_ready", 1.0 + 0.07 * float(i), 0.85)
		_super_was[i] = has_super
		var has_ex := m >= Arena.EX_COST
		if has_ex and not _ex_was[i]:
			_ex_t[i] = _time
			if fight and _time - float(_super_t[i]) > 0.3:
				Sfx.play("ex_ready", 1.25 + 0.07 * float(i), 0.6)
		_ex_was[i] = has_ex
		if float(_prev_meter[i]) >= 0.0:
			for k in CELLS:
				var full := float(k + 1) * _per_cell()
				if m >= full and float(_prev_meter[i]) < full:
					_flash_t[i][k] = _time
		_prev_meter[i] = m
		var kind := plate_kind(i)
		if kind != _plate[i]:
			_plate[i] = kind
			_plate_t[i] = _time
		if not _assist(f).is_empty():
			var ready := _assist_ready(f)
			if ready and not _ready_was[i]:
				_ready_t[i] = _time
			_ready_was[i] = ready
		var c: Dictionary = _call[i]
		if not c.is_empty() and _time - float(c["t0"]) > CALL_LIFE:
			_call[i] = {}
	_ink.queue_redraw()
	_light.queue_redraw()

# ── what the fighters say ────────────────────────────────────────────────────
func _f(i: int) -> Object:
	var fs = world.get("fighters") if world != null else null
	return fs[i] if fs is Array and fs.size() > i else null

func _num(o: Object, key: String, fallback: float) -> float:
	var v = o.get(key) if o != null else null
	return float(v) if v is int or v is float else fallback

static func _per_cell() -> float:
	return Arena.MAX_METER / float(CELLS)

func _meter(i: int) -> float:
	return clampf(_num(_f(i), "meter", 0.0), 0.0, Arena.MAX_METER)

func _assist(f: Object) -> Dictionary:
	var d = f.get("assist_data") if f != null else null
	return d if d is Dictionary else {}

func _assist_ready(f: Object) -> bool:
	return f.has_method("assist_ready") and f.assist_ready()

## "" without an assist, else "ready" or "cooldown".
func assist_state(i: int) -> String:
	var f := _f(i)
	if f == null or _assist(f).is_empty():
		return ""
	return "ready" if _assist_ready(f) else "cooldown"

func cooldown_secs(i: int) -> int:
	return ceili(_num(_f(i), "assist_cd", 0.0) / 60.0)

func disc_value(i: int) -> int:
	return int(_meter(i) / _per_cell())

## Cells filled, with the fraction of the one being filled: 0.0 to 10.0.
func cells_filled(i: int) -> float:
	return _meter(i) / _per_cell()

## "" under the SUPER cost, "super", or "ex" from the EX cost.
func plate_kind(i: int) -> String:
	var m := _meter(i)
	if m >= Arena.EX_COST:
		return "ex"
	return "super" if m >= Arena.SUPER_COST else ""

## The cost tag n (the SUPER cell or the EX cell, counted from the disc) glows when its tier is affordable.
func tag_lit(i: int, n: int) -> bool:
	return _meter(i) >= float(n) * _per_cell()

## The ready bracket's alpha: 1.0 at the ready edge, 0.7 half a cycle later. 0 unless the assist is ready.
func bracket_alpha(i: int) -> float:
	return Motion.pulse(_time - float(_ready_t[i])) if assist_state(i) == "ready" else 0.0

## The EX plate's start-light alpha: 0.8 at the EX edge, gone after 0.45 s, again every 1.5 s while the meter is full.
func ex_flare(i: int) -> float:
	if _meter(i) < Arena.EX_COST:
		return 0.0
	var ph := fposmod(_time - float(_ex_t[i]), FLARE_EVERY)
	return 0.8 * (1.0 - ph / FLARE_LIFE) if ph < FLARE_LIFE else 0.0

## The same flash over the card when the assist comes off cooldown.
func ready_flare(i: int) -> float:
	var age := _time - float(_ready_t[i])
	return 0.8 * (1.0 - age / FLARE_LIFE) if age >= 0.0 and age < FLARE_LIFE and assist_state(i) == "ready" else 0.0

## Only a human presses the assist key: slot 2 is a CPU or a dummy outside a two-player game.
func has_key(i: int) -> bool:
	return not Dbg.cpu_vs_cpu and (i == 0 or str(world.get("mode")) == "versus2p")

## The device P`slot`'s key hints read from: its own, else the keyboard side it falls back to; "" for a CPU.
static func hint_dev(slot: int) -> String:
	var s: Session = Game.session
	if slot != 1 and s.humans() == 1:
		return ""
	var d: String = s.device_of(slot)
	if d == "" or d == "shared":
		d = "kb1" if slot == 1 else "kb2"
	return d

func key_label(i: int) -> String:
	var dev := hint_dev(i + 1)
	return Controls.label_for(dev if dev != "" else "kb2", "lb")

## A pad's own glyph for the assist key; a keyboard shows its letter instead.
func key_glyph(i: int) -> Texture2D:
	var dev := hint_dev(i + 1)
	return Controls.glyph_for(dev, "lb") if dev.begins_with("pad") else null

# ── geometry ─────────────────────────────────────────────────────────────────
## A P1 rect on side i: P2 mirrors across the screen centre.
func _m(i: int, r: Rect2) -> Rect2:
	return r if i == 0 else Rect2(1280.0 - r.end.x, r.position.y, r.size.x, r.size.y)

## An assist card piece, shrunk toward the card's centre while the card is pressed.
func _g(i: int, r: Rect2) -> Rect2:
	var k := 1.0 - 0.05 * (1.0 - clampf((_time - float(_press_t[i])) / PRESS_LIFE, 0.0, 1.0))
	var c := _m(i, BRACKET).get_center()
	return Rect2(c + (_m(i, r).position - c) * k, r.size * k)

func rect_card(i: int) -> Rect2:
	return _m(i, FACET)

func rect_disc(i: int) -> Rect2:
	return _m(i, DISC)

## The ready frame before it leans: as wide as the card's own parallelogram plus the padding, so once it leans like the card
## it surrounds the card on every side.
func _frame(i: int) -> Rect2:
	var f := _g(i, FACET)
	var size := Vector2(f.size.x - f.size.y * BaArt.LEAN + 2.0 * BRACKET_PAD, f.size.y + 2.0 * BRACKET_PAD)
	return Rect2(f.get_center() - size * 0.5, size)

## The ready frame's bounding box once it leans.
func rect_bracket(i: int) -> Rect2:
	var r := _frame(i)
	return r.grow_individual(r.size.y * BaArt.LEAN * 0.5, 0.0, r.size.y * BaArt.LEAN * 0.5, 0.0)

## Cell k (0 is the one next to the disc).
func rect_cell(i: int, k: int) -> Rect2:
	return _m(i, Rect2(STRIP.x + PITCH * float(k), STRIP.y, CELL.x, CELL.y))

## Tag n sits over the far end of cell n, on its top edge, nudged by the lean.
func rect_tag(i: int, n: int) -> Rect2:
	var cell := rect_cell(i, n - 1)
	var lean := BaTokens.shear_px(CELL.y * 0.5)
	var x := (cell.end.x + 9.0 if i == 0 else cell.position.x - 9.0) + lean
	return Rect2(x - TAG * 0.5, cell.position.y - 1.0 - TAG * 0.5, TAG, TAG)

func rect_plate(i: int) -> Rect2:
	var sz := PLATE_EX if plate_kind(i) == "ex" else PLATE_SUPER
	return _m(i, Rect2(PLATE_MID - sz.x * 0.5, PLATE_BOTTOM - sz.y, sz.x, sz.y))

## Where the call-out balloon is now, Rect2() when none is showing.
func callout_rect(i: int) -> Rect2:
	var c: Dictionary = _call[i]
	if c.is_empty():
		return Rect2()
	var age := _time - float(c["t0"])
	var home := _m(i, Rect2(CALL_HOME, CALL))
	var off := -CALL.x - 20.0 - CALL_HOME.x if i == 0 else CALL.x + 20.0 + CALL_HOME.x
	var out := clampf((age - CALL_OUT) / (CALL_LIFE - CALL_OUT), 0.0, 1.0)
	var at := Motion.whip(age) if out == 0.0 else 1.0 - out * out
	return Rect2(home.position + Vector2(off * (1.0 - at), 0.0), home.size)

# ── cooldown art ─────────────────────────────────────────────────────────────
## The portrait with its colour mostly gone.
static func _gray(id: int) -> Texture2D:
	var src := BaArt.portrait(id)
	return BaArt.gray(src, 0.15) if src != null else null

# ── drawing ──────────────────────────────────────────────────────────────────
func _draw_ink(c: Control) -> void:
	for i in 2:
		if _f(i) == null:
			continue
		_draw_card(c, i)
		_draw_meter(c, i)
	for i in 2:
		_draw_callout(c, i)

func _draw_card(c: Control, i: int) -> void:
	var f := _f(i)
	var a := _assist(f)
	if a.is_empty():
		return
	var id := int(a.get("id", 0))
	var cool := not _assist_ready(f)
	BaArt.blit(c, "Combat__Combat_CardBg_EX", _g(i, FACET), BaTokens.CARD_DISABLED if cool else BaTokens.CARD_TINT[i])
	if not cool:
		var settle := 6.0 * (1.0 - clampf((_time - float(_ready_t[i])) / 0.25, 0.0, 1.0))
		BaArt.nine(c, "Common__Card_Select_Line", _frame(i).grow(settle), Color(1, 1, 1, bracket_alpha(i)), BaArt.LEAN)
	var face: Texture2D = _gray(id) if cool else BaArt.portrait(id)
	if face != null:
		c.draw_texture_rect(face, _g(i, PORTRAIT), false)
	if cool:
		var r := _g(i, PORTRAIT)
		BaNumerals.draw(c, str(cooldown_secs(i)), Vector2(r.position.x + r.size.x * 0.62, r.position.y + r.size.y * 0.2), r.size.y * 0.5, BaNumerals.Tier.NORMAL, Color.WHITE, 1)
	var plate := _g(i, NAME_PLATE)
	BaArt.nine(c, "Common__Common_Nonoutline_W_Bg", plate, Color.WHITE, BaArt.LEAN)
	var skill = f.get("assist")
	_text_fit(c, str(skill.get("name", "")).to_upper() if skill is Dictionary else "", Vector2(plate.get_center().x, plate.position.y + plate.size.y * 0.5), 13, plate.size.x - 22.0, BaTokens.LABEL_INK)
	if has_key(i):
		var key := _g(i, KEY_DISC)
		BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", key)
		var glyph := key_glyph(i)
		if glyph != null:
			c.draw_texture_rect(glyph, Rect2(key.get_center() - key.size * 0.375, key.size * 0.75), false)
		else:
			_text_fit(c, key_label(i), key.get_center() + Vector2(0, 7), 20, key.size.x - 12.0, Color.WHITE)

func _draw_meter(c: Control, i: int) -> void:
	var disc := rect_disc(i)
	BaArt.blit(c, "Combat__Combat_CostBg", disc)
	BaNumerals.draw(c, str(disc_value(i)), disc.position + DISC_CENTRE - Vector2(0, 14.0), 28.0, BaNumerals.Tier.NORMAL, Color.WHITE, 1)
	var filled := cells_filled(i)
	for k in CELLS:
		var r := rect_cell(i, k)
		BaArt.nine(c, "Combat__Common_Bg_Raius5px", r, BaTokens.GAUGE_EMPTY, BaArt.LEAN)
		var inner := r.grow_individual(-2, -3, -2, -3)
		var part := clampf(filled - float(k), 0.0, 1.0)
		if part * inner.size.x < 2.0:
			continue
		var w := inner.size.x * part
		var bar := Rect2(inner.position.x + (0.0 if i == 0 else inner.size.x - w), inner.position.y, w, inner.size.y)
		BaArt.nine(c, "Combat__Combat_Cost_Gauge", bar, CELL_FILL, BaArt.LEAN)
		var age := _time - float(_flash_t[i][k])
		if age < FLASH_LIFE:
			BaArt.nine(c, "Combat__Combat_Cost_Gauge", bar, BaTokens.alpha(BaTokens.FLASH, 0.8 * (1.0 - age / FLASH_LIFE)), BaArt.LEAN)
	for n in [int(Arena.SUPER_COST / _per_cell()), int(Arena.EX_COST / _per_cell())]:
		_draw_tag(c, i, n)
	_draw_plate(c, i)

func _draw_tag(c: Control, i: int, n: int) -> void:
	var r := rect_tag(i, n)
	var lit := tag_lit(i, n)
	if lit:
		var glow := Motion.pulse(_time)
		for k in 3:
			c.draw_circle(r.get_center(), 21.0 - 3.5 * float(k), BaTokens.alpha(BaTokens.BRACKET, (0.10 + 0.08 * float(k)) * glow))
	BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", r, Color.WHITE if lit else Color(1, 1, 1, 0.55))
	if lit:
		c.draw_arc(r.get_center(), TAG * 0.5 - 1.0, 0.0, TAU, 32, BaTokens.BRACKET, 1.5, true)
	BaNumerals.draw(c, str(n), r.get_center() - Vector2(0, 5.5), 11.0, BaNumerals.Tier.MINI, Color(1, 0.93, 0.4) if lit else Color(1, 1, 1, 0.75), 1)

## The pop is BA's confirm-plate scale: 0.8, 0.962 at 0.067 s, 1.0 at 0.25 s.
static func _pop(age: float) -> float:
	if age < 0.067:
		return lerpf(0.8, 0.962, maxf(age, 0.0) / 0.067)
	return lerpf(0.962, 1.0, clampf((age - 0.067) / 0.183, 0.0, 1.0))

func _draw_plate(c: Control, i: int) -> void:
	if plate_kind(i) != "ex":   # only EX READY gets a plate: the SUPER bubble is gone, the 5 tag and the chime still mark that tier
		return
	var base := rect_plate(i)
	var k := _pop(_time - float(_plate_t[i]))
	var r := Rect2(base.get_center() - base.size * k * 0.5, base.size * k)
	BaArt.nine(c, "Combat__Common_Btn_BG", r, BaTokens.CONFIRM, BaArt.LEAN)   # no gloss sprite: its orange patch showed as a stray glow
	var size := Menu.fit("EX READY", 24, r.size.x - 40.0, 12, 800)   # BA's yellow plates take flat dark lettering in the UI face
	Menu.label(c, "EX READY", Vector2(r.get_center().x, r.get_center().y + float(size) * 0.34), size, BaTokens.CONFIRM_INK, Color(0, 0, 0, 0), 0, 1, 800)

func _draw_callout(c: Control, i: int) -> void:
	var r := callout_rect(i)
	if r.size == Vector2.ZERO:
		return
	var call: Dictionary = _call[i]
	var flip := i == 1
	if flip:
		c.draw_set_transform(Vector2(r.position.x * 2.0 + r.size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
	BaArt.nine(c, "Combat__Combat_Balloon_Sup", r)
	if flip:
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var face := BaArt.portrait_small(int(call["id"]))
	var fw := 112.0
	var fx := r.position.x + 12.0 if i == 0 else r.end.x - 12.0 - fw
	if face != null:
		c.draw_texture_rect(face, Rect2(fx, r.position.y - 10.0, fw, fw * float(face.get_height()) / float(face.get_width())), false)
	var lines := str(call["name"]).to_upper().split(" ", true, 1)
	var tx := (fx + fw + 6.0) if i == 0 else (fx - 6.0)
	for n in lines.size():
		_text_fit(c, lines[n], Vector2(tx + (50.0 if i == 0 else -50.0), r.position.y + 40.0 + 22.0 * float(n)), 20, 98.0, BaTokens.LABEL_INK)

func _draw_light(c: Control) -> void:
	for i in 2:
		if _f(i) == null:
			continue
		_flare(c, rect_plate(i).get_center(), 300.0, ex_flare(i), fposmod(_time - float(_ex_t[i]), FLARE_EVERY))
		_flare(c, _m(i, BRACKET).get_center(), 190.0, ready_flare(i), _time - float(_ready_t[i]))

## BA's start light pops from nothing to 1.25 in 0.083 s and settles to 1.0 by 0.383 s.
func _flare(c: Control, at: Vector2, w: float, a: float, age: float) -> void:
	if a <= 0.0:
		return
	var k := lerpf(0.0, 1.25, age / 0.083) if age < 0.083 else lerpf(1.25, 1.0, clampf((age - 0.083) / 0.3, 0.0, 1.0))
	var size := Vector2(w, w * 792.0 / 824.0) * k
	BaArt.blit(c, FLARE, Rect2(at - size * 0.5, size), Color(1, 1, 1, a))

## Italic display text centred on pos (baseline), shrunk until it fits max_w.
func _text_fit(c: CanvasItem, s: String, pos: Vector2, size: int, max_w: float, col: Color) -> void:
	var font := UI.font_display()
	var sz := Menu.fit_font(font, s, size, max_w, 9)
	c.draw_string(font, pos - Vector2(font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x * 0.5, 0.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
