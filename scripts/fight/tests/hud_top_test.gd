extends SceneTree
## Top rail (hud_top.gd, hud_status.gd, hud_status_table.gd, the sprite HudBar): bar pixels (fill, ghost, anchor, lean, rim),
## the HP ghost timing, the guard bar the way guard_test reads it, the timer plate and its tiers, round words and
## pips, names, status rows, the old HudBar API, and a smoke run on a real training fight.
## Run: TEST=res://scripts/fight/tests/hud_top_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const RED := Color("D63636")
const CYAN := Color("00A0FF")
const DT := 1.0 / 60.0

class StubFighter extends RefCounted:
	var data := {"id": 10004, "name": "Hina", "school": "Gehenna", "role": "DamageDealer", "bullet": "Explosion"}
	var slot := 1
	var hp := 1000.0
	var max_hp := 1000.0
	var stats := {"guard_max": 100.0, "guard_crush": 60.0}
	var guard := 100.0
	var crush_t := 0
	var state := 0
	var powered := false
	var armor_hits_left := 0
	var move := {}
	var mf := 0
	var kv := {}

## A fighter with no guard fields at all.
class StubBare extends RefCounted:
	var data := {"id": 10005, "name": "Hoshino", "school": "Abydos", "role": "Tanker", "bullet": "Pierce"}
	var slot := 2
	var hp := 1000.0
	var max_hp := 1000.0
	var stats := {}

## An object with none of the fields the rail reads.
class StubNone extends RefCounted:
	pass

class StubWorld extends Node:
	var fighters: Array = []
	var timer_frames := 3600
	var training := false
	var mode := "versus2p"
	var wins := [0, 0]
	var phase := "fight"
	var round_no := 1

var checks := 0
var failures: Array = []
var TOP: GDScript
var BAR: GDScript
var STATUS: GDScript
var TABLE: GDScript
var ART: GDScript
var NUM: GDScript
var S: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("HUD_TOP_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(200.0).timeout.connect(func() -> void:
		print("HUD_TOP_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	TOP = load("res://scripts/fight/hud_top.gd")
	BAR = load("res://scripts/fight/hud_bar.gd")
	STATUS = load("res://scripts/fight/hud_status.gd")
	TABLE = load("res://scripts/fight/hud_status_table.gd")
	ART = load("res://scripts/ui/ba_art.gd")
	NUM = load("res://scripts/ui/ba_numerals.gd")
	S = (load("res://scripts/fight/fighter.gd") as GDScript).get_script_constant_map()["S"]
	await _bar_pixels()
	await _fill_joins()
	_bar_api()
	_hp_ghost()
	_portrait_face()
	_guard()
	_timer()
	await _centre()
	_words_and_names()
	await _crests()
	_geometry()
	_status()
	await _real_fight()
	_assets()
	print("HUD_TOP_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
## Renders what make(viewport) adds into a transparent viewport and returns the image.
func _render(size: Vector2i, make: Callable) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	make.call(vp)
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img

func _near(a: Color, b: Color, tol := 0.07) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol

func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

## The last column on row y whose pixel is near col, or -1.
func _last_x(img: Image, y: int, col: Color) -> int:
	for x in range(img.get_width() - 1, -1, -1):
		if _near(img.get_pixel(x, y), col, 0.1):
			return x
	return -1

func _world(fighters: Array) -> StubWorld:
	var w := StubWorld.new()
	w.fighters = fighters
	root.add_child(w)
	return w

func _top(w: StubWorld) -> Control:
	var t: Control = TOP.new().setup(w)
	root.add_child(t)
	t.set_process(false)
	return t

func _step(t: Control, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		t._process(DT)

# ── the bar's own pixels ─────────────────────────────────────────────────────
# A 480x42 bar at (10, 8), lean 7.4: the frame's left edge is x 13.7, the fill's range 19.7 to 487.7 (468 wide), centre row y 29.
func _bar_pixels() -> void:
	var img: Image = await _render(Vector2i(520, 60), func(vp: Node) -> void:
		var b: Control = BAR.new().setup(480.0, 42.0, 7.4, false, Color.WHITE, RED)
		b.position = Vector2(10, 8)
		b.param("fill", 0.6)
		b.param("trail", 0.8)
		b.param("ticks", 1.0)
		vp.add_child(b))
	var px := func(u: float, y := 29) -> Color: return img.get_pixel(int(19.7 + u * 468.0), y)
	check(_near(px.call(0.1), RED, 0.05), "the fill is the colour it was given")
	var ghost: Color = px.call(0.7)
	check(_lum(ghost) > 0.5 and ghost.r - ghost.b < 0.12, "between fill and trail the ghost is pale, not the fill colour")
	check(_lum(px.call(0.9)) < 0.25, "beyond the ghost the track is dark")
	var tick: Color = px.call(0.25)
	check(_lum(tick) < _lum(px.call(0.22)) - 0.04, "quarter ticks darken the fill (%.3f vs %.3f)" % [_lum(tick), _lum(px.call(0.22))])
	# lean: the fill's end sits further right on a higher row, 0.1763 px per px
	var top_x := _last_x(img, 17, RED)
	var bot_x := _last_x(img, 39, RED)   # the fill's last row is 40: row 41 is the frame's white lip
	check(top_x > 0 and bot_x > 0 and absf(float(top_x - bot_x) - 0.1763 * 22.0) < 1.3, "the fill's edge leans / by 10 degrees (%d vs %d)" % [top_x, bot_x])
	# the rim: the frame's top edge is one unbroken light line between the corners
	var rim_y := -1
	for y in 30:
		if _lum(img.get_pixel(260, y)) > 0.85 and img.get_pixel(260, y).a > 0.9:
			rim_y = y
			break
	var gaps := 0
	for x in range(40, 460):
		if rim_y < 0 or img.get_pixel(x, rim_y).a < 0.9 or _lum(img.get_pixel(x, rim_y)) < 0.7:
			gaps += 1
	check(rim_y >= 0 and gaps == 0, "the frame's top rim is unbroken (row %d, %d gaps)" % [rim_y, gaps])
	# anchored on the right: P2's side
	var mir: Image = await _render(Vector2i(520, 60), func(vp: Node) -> void:
		var b: Control = BAR.new().setup(480.0, 42.0, 7.4, true, Color.WHITE, CYAN)
		b.position = Vector2(10, 8)
		b.param("fill", 0.3)
		b.param("trail", 0.3)
		vp.add_child(b))
	check(_near(mir.get_pixel(int(19.7 + 0.9 * 468.0), 29), CYAN, 0.05) and _lum(mir.get_pixel(int(19.7 + 0.2 * 468.0), 29)) < 0.25, "mirror anchors the fill on the right edge")
	var full: Image = await _render(Vector2i(520, 60), func(vp: Node) -> void:
		var b: Control = BAR.new().setup(480.0, 42.0, 7.4, false, Color.WHITE, RED)
		b.position = Vector2(10, 8)
		vp.add_child(b))
	check(_near(full.get_pixel(int(19.7 + 0.02 * 468.0), 29), RED, 0.05) and _near(full.get_pixel(int(19.7 + 0.98 * 468.0), 29), RED, 0.05), "a full bar is filled end to end")
	# the fill sits inside the frame's track: it ends on the row above the sprite's white lip and starts one row into the track
	var spr: Image = BaArt.tex("Combat__Combat_Bg_Hp").get_image()
	var lip := -1
	for y in range(12, spr.get_height()):
		var c := spr.get_pixel(12, y)
		if c.a > 0.99 and c.r > 0.99 and c.g > 0.99:
			lip = y
			break
	var track_top := -1
	for y in spr.get_height():
		var c := spr.get_pixel(12, y)
		if c.a > 0.1 and c.a < 0.99:
			track_top = y
			break
	var lip_y := 8 + 42 - (spr.get_height() - lip)   # the bar sits at y 8 and is 42 tall: the frame's bottom margin is drawn at 1x
	check(lip > 0 and track_top > 0, "the frame sprite's track and white lip are found (rows %d, %d)" % [track_top, lip])
	var col_x := int(19.7 + 0.5 * 468.0)
	check(_lum(full.get_pixel(col_x, lip_y)) > 0.9 and _near(full.get_pixel(col_x, lip_y - 1), RED, 0.06), "the fill stops on the row above the frame's white lip (lip row %d)" % lip_y)
	check(_near(full.get_pixel(col_x, 8 + track_top + 1), RED, 0.06) and not _near(full.get_pixel(col_x, 8 + track_top), RED, 0.06), "the fill starts one row into the track (row %d)" % (8 + track_top + 1))
	# the guard bar's 12 px frame has a 5 px track: the fill fills it and no more
	var g: Image = await _render(Vector2i(280, 30), func(vp: Node) -> void:
		var b: Control = BAR.new().setup(250.0, 12.0, 2.1, false, Color.WHITE, Color("EAF6FF"))
		b.position = Vector2(10, 8)
		vp.add_child(b))
	var rows := 0
	for y in 30:
		if _near(g.get_pixel(100, y), Color("EAF6FF"), 0.04):
			rows += 1
	check(rows >= 4 and rows <= 6, "a 12 px guard bar's fill is as thick as the frame's 5 px track (%d)" % rows)

## The fill reaches the card on both sides: no dark sliver of track shows between them. The lean does not mirror, so P2's card edge is
## not P1's mirrored.
func _fill_joins() -> void:
	var w := _world([StubFighter.new(), StubFighter.new()])
	var img: Image = await _render(Vector2i(1280, 160), func(vp: Node) -> void:
		var t: Control = TOP.new().setup(w)
		vp.add_child(t)
		t.set_process(false)
		t._process(DT)
		t._time = 0.0)
	for y in [46, 61, 70]:
		var left := -1
		for x in range(140, 230):
			if _near(img.get_pixel(x, y), RED, 0.08):
				left = x
				break
		var right := -1
		for x in range(1140, 1050, -1):
			if _near(img.get_pixel(x, y), CYAN, 0.08):
				right = x
				break
		check(left > 0 and _lum(img.get_pixel(left - 2, y)) > 0.25, "P1's fill meets its card on row %d, no dark track between (fill from x %d, pixel beside it %.2f)" % [y, left, _lum(img.get_pixel(maxi(left - 2, 0), y))])
		check(right > 0 and _lum(img.get_pixel(right + 2, y)) > 0.25, "P2's fill meets its card on row %d, no dark track between (fill to x %d, pixel beside it %.2f)" % [y, right, _lum(img.get_pixel(mini(right + 2, 1279), y))])

func _bar_api() -> void:
	var old: Control = BAR.new().setup(452.0, 28.0, 20.0, true, Color(1.0, 0.7, 0.8), Color(0.9, 0.1, 0.3))
	check(old.size == Vector2(472.0, 28.0), "the old setup() sizes the control to bar width plus shear")
	for p in ["segments", "notch", "ready", "glow", "warn", "time", "border_color", "col_top"]:
		old.param(p, 0.5)
	old.param("fill", 0.5)
	old.param("trail", 0.75)
	check(is_equal_approx(float(old.mat.get_shader_parameter("fill")), 0.5) and is_equal_approx(float(old.mat.get_shader_parameter("trail")), 0.75), "fill and trail reach mat")
	check(old.mat.get_shader_parameter("col_bot") == Color(0.9, 0.1, 0.3), "col_bot reaches mat")
	var neg: Control = BAR.new().setup(452.0, 28.0, -20.0, false, Color.WHITE, RED)
	check(neg.size == Vector2(472.0, 28.0) and float(neg.mat.get_shader_parameter("shear")) < 0.0, "a negative shear leans the other way and keeps the size")
	old.free()
	neg.free()

# ── HP ghost ─────────────────────────────────────────────────────────────────
func _hp_ghost() -> void:
	var a := StubFighter.new()
	var w := _world([a, StubBare.new()])
	var t := _top(w)
	var hp: Control = t.hp_bars[0]
	_step(t, 0.1)
	check(is_equal_approx(float(hp.mat.get_shader_parameter("fill")), 1.0), "a full bar is at 1.0")
	a.hp = 600.0
	_step(t, DT)
	check(is_equal_approx(float(hp.mat.get_shader_parameter("fill")), 0.6) and is_equal_approx(float(hp.mat.get_shader_parameter("trail")), 1.0), "damage drops the fill at once and the ghost stays")
	_step(t, 0.37)
	check(is_equal_approx(float(hp.mat.get_shader_parameter("trail")), 1.0), "the ghost holds for 0.45 s (still full at 0.39 s)")
	_step(t, 0.61)
	var tr := float(hp.mat.get_shader_parameter("trail"))
	check(absf(tr - 0.725) < 0.03, "then drains 0.5 per second (%.3f at 1.0 s, want 0.725)" % tr)
	_step(t, 1.5)
	check(is_equal_approx(float(hp.mat.get_shader_parameter("trail")), 0.6), "the ghost settles on the fill")
	a.hp = 900.0
	_step(t, DT)
	check(is_equal_approx(float(hp.mat.get_shader_parameter("trail")), 0.9), "healing lifts the ghost with the fill")
	a.hp = 200.0
	_step(t, DT)
	check(t._low_hp(0) and not t._low_hp(1), "under 25 percent is low hp, and only for that side")
	a.hp = 0.0
	_step(t, DT)
	check(not t._low_hp(0), "a dead fighter is not low hp")
	t.queue_free()
	w.queue_free()

# ── the card's face follows hp (PortraitMood has its own suite: portrait_mood_test) ──
func _portrait_face() -> void:
	var a := StubFighter.new()
	var w := _world([a, StubBare.new()])
	var t := _top(w)
	_step(t, 0.1)
	check(t._face == ["calm", "calm"] and t.LOW_HP == 0.25, "full hp shows the calm face, and the low-hp edge is still 0.25")
	for step in [[800.0, "calm"], [760.0, "scratched"], [520.0, "hurt"], [240.0, "critical"], [0.0, "ko"]]:
		a.hp = step[0]
		_step(t, 0.5)
		check(t._face[0] == step[1] and t._face[1] == "calm", "%d of 1000 hp shows %s (%s)" % [int(step[0]), step[1], t._face[0]])
	a.hp = 1000.0
	_step(t, DT)
	check(t._face[0] == "calm", "a new round's full hp is calm at once")
	a.hp = 700.0
	_step(t, DT)
	check(t._face[0] == "flinch", "a drop of 0.3 in one tick is a flinch")
	_step(t, 0.5)
	check(t._face[0] == "scratched", "and settles on the level")
	t.queue_free()
	w.queue_free()

# ── guard bar, read the way guard_test.gd reads it ───────────────────────────
func _guard() -> void:
	var a := StubFighter.new()
	var w := _world([a, StubBare.new()])
	var t := _top(w)
	var bars: Array = t.guard_bars
	check(bars.size() == 2, "one guard bar per player")
	check(not bars[0].visible and not bars[1].visible, "a guard bar stays hidden until its fighter reports a guard")
	_step(t, DT)
	check(bars[0].visible and not bars[1].visible, "a fighter without guard fields gets no guard bar")
	var gmax := float(a.stats["guard_max"])
	a.guard = gmax * 0.4
	_step(t, DT)
	var bar: Control = bars[0]
	check(bar.visible and is_equal_approx(float(bar.mat.get_shader_parameter("fill")), 0.4), "fill follows the guard")
	check(float(bar.mat.get_shader_parameter("trail")) >= 0.4 - 0.001, "the trail never trails below the fill")
	a.guard = gmax
	_step(t, DT)
	var full: Color = bar.mat.get_shader_parameter("col_bot")
	check(full.g > full.r and full == Color("EAF6FF"), "a full guard is the pale blue-white")
	a.guard = gmax * 0.1
	_step(t, DT)
	var low: Color = bar.mat.get_shader_parameter("col_bot")
	check(low.r > low.g and low == Color("FEE600"), "a low guard is yellow")
	a.guard = gmax * 0.31
	_step(t, DT)
	check(bar.mat.get_shader_parameter("col_bot") == Color("EAF6FF"), "31 percent is still pale")
	a.guard = gmax * 0.29
	_step(t, DT)
	check(bar.mat.get_shader_parameter("col_bot") == Color("FEE600"), "29 percent is yellow")
	a.guard = gmax
	a.crush_t = 20
	_step(t, DT)
	check(is_equal_approx(float(bar.mat.get_shader_parameter("fill")), 1.0 - 20.0 / float(a.stats["guard_crush"])), "a crush sweeps the bar back")
	var red: Color = bar.mat.get_shader_parameter("col_bot")
	check(red.r > 0.9 and red.g < 0.4, "a crushed bar is red")
	check(t._crushed(0) and not t._crushed(1), "crushed is read from crush_t")
	a.crush_t = 0
	_step(t, DT)
	var up := float(bar.mat.get_shader_parameter("fill"))
	check(up > 0.66 and up < 0.72, "a hit that ends a crush early lifts the bar over time, not in one frame (%.3f)" % up)
	check(is_equal_approx(float(bar.mat.get_shader_parameter("trail")), up), "and the ghost rides with it")
	_step(t, 0.05)
	check(float(bar.mat.get_shader_parameter("fill")) > up and float(bar.mat.get_shader_parameter("fill")) < 0.9, "still climbing")
	a.guard = gmax
	_step(t, 0.2)
	check(is_equal_approx(float(bar.mat.get_shader_parameter("fill")), 1.0), "and full a third of a second later")
	a.guard = gmax * 0.5
	_step(t, 0.2)
	check(is_equal_approx(float(bar.mat.get_shader_parameter("trail")), 1.0), "the guard ghost holds 0.3 s")
	_step(t, 0.4)
	var gtr := float(bar.mat.get_shader_parameter("trail"))
	check(gtr < 1.0 and gtr > 0.5, "then drains (%.3f)" % gtr)
	t.queue_free()
	w.queue_free()

# ── timer plate ──────────────────────────────────────────────────────────────
func _timer() -> void:
	var w := _world([StubFighter.new(), StubFighter.new()])
	var t := _top(w)
	var st: Dictionary = t.timer_state()
	check(st["text"] == "60" and not st["low"] and st["tier"] == NUM.Tier.WHITE and st["blink"] == 0.0, "60 seconds: white digits, a steady plate")
	w.timer_frames = 601
	check(t.timer_state()["text"] == "11" and not t.timer_state()["low"], "11 seconds is not yet low")
	w.timer_frames = 600
	st = t.timer_state()
	check(st["text"] == "10" and st["low"] and st["tier"] == NUM.Tier.EFFECTIVE, "the last ten seconds turn the digits orange")
	w.timer_frames = 1
	check(t.timer_state()["text"] == "1", "a single frame left shows 1")
	w.timer_frames = 0
	check(t.timer_state()["text"] == "0", "zero shows 0")
	w.timer_frames = 300
	w.phase = "intro"
	check(not t.timer_state()["low"], "no warning outside the fight phase")
	w.phase = "fight"
	w.training = true
	check(not t.timer_state()["low"] and t.timer_state()["training"], "training never warns")
	w.training = false
	var alphas := {}
	var flips := 0
	var prev := -1.0
	for i in 60:
		t._time += DT
		var a: float = t.timer_state()["blink"]
		alphas[int(round(a * 100.0))] = true
		if prev >= 0.0 and a != prev:
			flips += 1
		prev = a
	check(alphas.size() == 2 and alphas.has(95) and alphas.has(65), "the low-time wash alternates 0.95 and 0.65")
	check(flips >= 2 and flips <= 4, "about every third of a second (%d flips in a second)" % flips)
	t.queue_free()
	w.queue_free()

# What the plate actually draws: orange digits in the last ten seconds, white before, the TRAINING ribbon with no digits.
func _centre() -> void:
	var a := StubFighter.new()
	var b := StubFighter.new()
	var w := _world([a, b])
	var shots := {}
	for key in ["calm", "low", "training"]:
		w.timer_frames = 3000 if key == "calm" else 540
		w.training = key == "training"
		w.wins = [1, 0]
		shots[key] = await _render(Vector2i(1280, 160), func(vp: Node) -> void:
			var t: Control = TOP.new().setup(w)
			vp.add_child(t)
			t.set_process(false)
			t._process(DT)
			t._time = 0.0)
	var count := func(img: Image, rect: Rect2i, pred: Callable) -> int:
		var n := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if pred.call(img.get_pixel(x, y)):
					n += 1
		return n
	var digits := Rect2i(630, 28, 70, 40)
	var orange := func(c: Color) -> bool: return c.a > 0.9 and c.r > 0.85 and c.g > 0.35 and c.g < 0.75 and c.b < 0.4
	var white := func(c: Color) -> bool: return c.a > 0.9 and c.r > 0.9 and c.g > 0.9 and c.b > 0.9
	check(count.call(shots["low"], digits, orange) > 40 and count.call(shots["low"], digits, white) < 40, "the last ten seconds draw orange digits")
	check(count.call(shots["calm"], digits, white) > 80 and count.call(shots["calm"], digits, orange) < 10, "the rest of the round draws white digits")
	check(count.call(shots["training"], digits, white) < 60 and count.call(shots["training"], Rect2i(600, 40, 80, 24), white) > 20, "training swaps the digits for the ribbon's word")
	var calm_plate: Color = shots["calm"].get_pixel(700, 74)
	var low_plate: Color = shots["low"].get_pixel(700, 74)
	check(_near(calm_plate, Color("062D51"), 0.08), "the plate is navy in a calm round (%s)" % str(calm_plate))
	check(low_plate.r > 0.35 and low_plate.a > 0.99 and not _near(low_plate, RED, 0.12), "the last ten seconds turn the plate rose and keep it opaque (%s)" % str(low_plate))
	# pips: P1 has won one round, so the pip next to the ribbon holds the sparkle and the outer one does not
	var p1_near: Color = shots["calm"].get_pixel(559, 101)
	var p1_far: Color = shots["calm"].get_pixel(529, 101)
	var p2_near: Color = shots["calm"].get_pixel(721, 101)
	check(_lum(p1_near) > 0.5 and _lum(p1_far) < 0.3 and _lum(p2_near) < 0.3, "a won round shows the sparkle on its own side, first pip nearest the ribbon")
	var pips_in_training: int = count.call(shots["training"], Rect2i(510, 98, 35, 16), func(c: Color) -> bool: return c.a > 0.5)
	check(pips_in_training == 0, "training draws no pips (%d px)" % pips_in_training)
	# 10 percent of hp is 40 px of fill: it must show beside the card, not vanish under it
	w.training = false
	w.timer_frames = 3000
	a.hp = 100.0
	var low_img: Image = await _render(Vector2i(1280, 160), func(vp: Node) -> void:
		var t: Control = TOP.new().setup(w)
		vp.add_child(t)
		t.set_process(false)
		_step(t, 3.0))
	check(_near(low_img.get_pixel(190, 66), RED, 0.06) and _lum(low_img.get_pixel(420, 66)) < 0.3, "at 10 percent hp the fill shows beside the card and the rest is track")
	var vs_img: Image = await _render(Vector2i(1280, 160), func(vp: Node) -> void:
		var t: Control = TOP.new().setup(w)
		t.anchor_outer = false
		vp.add_child(t)
		t.set_process(false)
		_step(t, 3.0))
	check(_near(vs_img.get_pixel(535, 66), RED, 0.06) and _lum(vs_img.get_pixel(420, 66)) < 0.3 and _lum(vs_img.get_pixel(190, 66)) < 0.4, "with the flag flipped the last sliver sits at the plate end")
	w.queue_free()
	var bare := _world([StubNone.new(), StubNone.new()])
	var bare_img: Image = await _render(Vector2i(1280, 160), func(vp: Node) -> void:
		var t: Control = TOP.new().setup(bare)
		vp.add_child(t)
		t.set_process(false)
		_step(t, 0.2))
	check(bare_img.get_pixel(640, 52).a > 0.9, "fighters with none of the fields still draw the plate and raise no error")
	bare.queue_free()

# ── school crests in the name item ───────────────────────────────────────────
## Bounding box of the white ink inside r on the red or cyan bar.
func _ink_box(img: Image, r: Rect2i) -> Rect2i:
	var box := Rect2i()
	var any := false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.g > 0.7 and c.r > 0.7 and c.b > 0.7:
				box = Rect2i(x, y, 1, 1) if not any else box.expand(Vector2i(x, y))
				any = true
	return box

func _crests() -> void:
	var left := StubFighter.new()
	left.data = {"id": 10004, "name": "Hina", "school": "Hyakkiyako", "role": "DamageDealer", "bullet": "Explosion"}
	var right := StubFighter.new()
	right.data = {"id": 10005, "name": "Hoshino", "school": "Abydos", "role": "Tanker", "bullet": "Pierce"}
	var w := _world([left, right])
	var img: Image = await _render(Vector2i(1280, 160), func(vp: Node) -> void:
		var t: Control = TOP.new().setup(w)
		vp.add_child(t)
		t.set_process(false)
		_step(t, 0.2))
	var wide := _ink_box(img, Rect2i(190, 44, 45, 28))
	check(wide.size.x >= 36 and wide.size.y <= 20, "a wide logotype (Hyakkiyako) fills the crest box's width, %d x %d px" % [wide.size.x, wide.size.y])
	var square := _ink_box(img, Rect2i(1280 - 235, 44, 45, 28))
	check(square.size.y >= 18 and square.size.x <= 40, "an emblem (Abydos) stays in the box on the right side too, %d x %d px" % [square.size.x, square.size.y])
	var CI: GDScript = load("res://scripts/ui/crest_icon.gd")
	var box: Vector2 = TOP.CREST.size
	var hud_top: Control = _top(w)
	check(hud_top._ink.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and CI.get_icon("Abydos", box).get_image().has_mipmaps(), "the name item filters its crests through mipmaps, so a smaller window does not alias them")
	hud_top.queue_free()
	for school in ["Abydos", "Arius", "Gehenna", "Hyakkiyako", "Millennium", "RedWinter", "Shanhaijing", "SRT", "Trinity", "Valkyrie"]:
		var sz: Vector2 = CI.fit(school, box)
		check(sz.x <= box.x + 0.5 and sz.y <= box.y + 0.5 and maxf(sz.x / box.x, sz.y / box.y) > 0.95, "%s's crest is cut to its ink and fills the HUD box (%s of %s)" % [school, sz, box])
	w.queue_free()

# ── round words, tags, names, sparkle ────────────────────────────────────────
func _words_and_names() -> void:
	var w := _world([StubFighter.new(), StubFighter.new()])
	var t := _top(w)
	check(t.round_word() == "round_1", "round 1")
	w.round_no = 2
	w.wins = [1, 0]
	check(t.round_word() == "round_2", "round 2 from round_no")
	w.wins = [1, 1]
	check(t.round_word() == "final", "one round all is the final round")
	w.phase = "round_end"
	check(t.round_word() == "round_2", "the win that makes it one all still reads ROUND 2 under its banner")
	w.phase = "fight"
	w.wins = [0, 0]
	w.round_no = 9
	check(t.round_word() == "round_9", "round numbers clamp to 9, like the banner")
	w.round_no = 4
	check(t.round_word() == "round_4" and load("res://scripts/ui/ba_words.gd").tex("round_4") != null, "a fourth round after draws shows ROUND 4")
	check(t.tag_text(0) == "1P" and t.tag_text(1) == "2P", "versus: 1P and 2P")
	w.mode = "training"
	check(t.tag_text(1) == "CPU", "against the dummy or the cpu the tag says CPU")
	w.mode = "arcade"
	check(t.tag_text(1) == "CPU", "arcade says CPU")
	check(is_equal_approx(TOP.spark(-1.0), 0.0) and is_equal_approx(TOP.spark(0.083), 1.25) and is_equal_approx(TOP.spark(0.383), 1.0) and is_equal_approx(TOP.spark(3.0), 1.0), "the sparkle pops 0 to 1.25 to 1.0 by 0.383 s")
	check(TOP.spark(0.04) < TOP.spark(0.083) and TOP.spark(0.2) < TOP.spark(0.1), "up fast, down slowly")
	var short: Array = TOP.fit_name("Hina", 317.0)
	check(short[0] == "Hina" and short[1] == 22, "a short name stays at 22 px")
	var mid: Array = TOP.fit_name("Hinakamishimoyama Prefect Gehenna", 317.0)
	check(mid[1] < 22 and mid[1] >= 14 and not str(mid[0]).ends_with("."), "a long name shrinks and keeps its letters")
	var long: Array = TOP.fit_name("Hinakamishimoyama-Nakajima Prefect of the Gehenna Academy", 317.0)
	var font: Font = load("res://scripts/ui/ui.gd").font_ui(700)
	check(long[1] == 14 and str(long[0]).ends_with(".") and font.get_string_size(long[0], HORIZONTAL_ALIGNMENT_LEFT, -1, long[1]).x <= 317.0, "a very long name stops at 14 px and is cut to fit")
	# the pop is set when a round is won, on the right pip
	w.wins = [1, 0]
	_step(t, DT)
	check(float(t._pip_t[0][0]) > 0.0 and float(t._pip_t[0][1]) < 0.0 and float(t._pip_t[1][0]) < 0.0, "a first win pops pip 0 of that side only")
	w.wins = [1, 1]
	_step(t, DT)
	check(float(t._pip_t[1][0]) > 0.0 and float(t._pip_t[0][1]) < 0.0, "the other side's win pops its own pip")
	t.queue_free()
	w.queue_free()

# ── geometry for the facade ──────────────────────────────────────────────────
func _geometry() -> void:
	var w := _world([StubFighter.new(), StubFighter.new()])
	var t := _top(w)
	var r0: Dictionary = t.rects(0)
	var r1: Dictionary = t.rects(1)
	check((r0["portrait"] as Rect2).intersection(r0["bar"]).size.x >= 40.0, "the portrait overlaps the outer end of the bar")
	check((r1["portrait"] as Rect2).intersection(r1["bar"]).size.x >= 40.0, "and on the right too")
	check((r0["plate"] as Rect2).intersection(r0["bar"]).size.x >= 40.0 and (r1["plate"] as Rect2).intersection(r1["bar"]).size.x >= 40.0, "the timer plate overlaps the inner end of both bars")
	check(is_equal_approx((r0["portrait"] as Rect2).end.x + (r1["portrait"] as Rect2).position.x, 1280.0) and is_equal_approx((r0["bar"] as Rect2).end.x + (r1["bar"] as Rect2).position.x, 1280.0), "the right side mirrors the left")
	check((r0["card"] as Rect2).size == (r1["card"] as Rect2).size and (r0["bar"] as Rect2).size == Vector2(480.0, 42.0), "the bars are 480x42 and the cards match")
	check((r0["guard"] as Rect2).position.y > (r0["bar"] as Rect2).end.y and (r0["guard"] as Rect2).size == Vector2(250.0, 12.0), "the guard bar hangs under the HP bar")
	var hp0: Control = t.hp_bars[0]
	var hp1: Control = t.hp_bars[1]
	check(not hp0.mat.get_shader_parameter("mirror") and hp1.mat.get_shader_parameter("mirror"), "each HP bar is anchored at its outer edge")
	t.anchor_outer = false
	check(hp0.mat.get_shader_parameter("mirror") and not hp1.mat.get_shader_parameter("mirror") and t.guard_bars[0].mat.get_shader_parameter("mirror") and not t.guard_bars[1].mat.get_shader_parameter("mirror"), "the drain flag moves both gauges' anchor to the VS side")
	t.anchor_outer = true
	check(not hp0.mat.get_shader_parameter("mirror") and hp1.mat.get_shader_parameter("mirror") and not t.guard_bars[0].mat.get_shader_parameter("mirror"), "and back")
	check(t.size == Vector2(1280, 720) and t.mouse_filter == Control.MOUSE_FILTER_IGNORE and is_equal_approx(t.modulate.a, 1.0), "fills 1280x720, ignores the mouse, leaves modulate alone")
	t.queue_free()
	w.queue_free()

# ── status badges ────────────────────────────────────────────────────────────
func _hue(img: Image) -> float:
	var sum := Vector2.ZERO
	var n := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.9 and c.s > 0.35 and c.v > 0.3:
				sum += Vector2.from_angle(c.h * TAU)
				n += 1.0
	return fposmod(sum.angle() / TAU, 1.0) if n > 20.0 else -1.0

func _status() -> void:
	var f := StubFighter.new()
	check(TABLE.badges(f).is_empty(), "a fighter with nothing going on shows no badge")
	check(TABLE.badges(StubBare.new()).is_empty(), "a fighter without those fields shows none and does not error")
	f.crush_t = 5
	check(TABLE.badges(f).is_empty(), "a guard crush shows no row badge: the guard disc carries it")
	f.crush_t = 0
	f.state = S["BLOCK"]
	check(TABLE.badges(f)[0]["id"] == "block", "blocking shows the guard badge")
	f.state = S["ATTACK"]
	check(TABLE.badges(f).is_empty(), "attacking without armor shows nothing")
	f.armor_hits_left = 1
	check(TABLE.badges(f).is_empty(), "armor hits left outside the armor window show nothing")
	f.move = {"armor": {"from": 4, "to": 9}}
	f.mf = 6
	check(TABLE.badges(f)[0]["id"] == "armor", "inside the move's armor window the armor badge shows")
	f.mf = 12
	check(TABLE.badges(f).is_empty(), "and goes when the window closes")
	f.move = {}
	f.powered = true
	var ids: Array = TABLE.badges(f).map(func(b: Dictionary) -> String: return b["id"])
	check(ids == ["armor", "power"], "a powered skill shows armor and power, in row order (%s)" % str(ids))
	f.powered = false
	f.state = 0
	f.kv = {"mag": 31, "lock_t": 0}
	var ammo: Array = TABLE.badges(f)
	check(ammo.size() == 1 and ammo[0]["id"] == "ammo" and ammo[0]["count"] == 31, "a kit with a magazine shows its count")
	f.kv["lock_t"] = 12
	check(TABLE.badges(f).size() == 2 and TABLE.badges(f)[1]["kind"] == "special", "Lock & Load adds the special badge")
	# colour grammar: buff red, crowd control purple, debuff blue, special yellow, read off the sprites
	var want := {"buff": [0.0, 0.07], "cc": [0.72, 0.86], "debuff": [0.55, 0.7], "special": [0.09, 0.2]}
	var seen := {}
	for r in TABLE.rows():
		var img: Image = ART.tex(TABLE.ICON + str(r["icon"])).get_image()
		img.convert(Image.FORMAT_RGBA8)
		var h := _hue(img)
		var rng: Array = want[r["kind"]]
		seen[r["kind"]] = true
		var ok: bool = (h >= float(rng[0]) and h <= float(rng[1])) or (r["kind"] == "buff" and h >= 0.95)
		check(ok, "%s is a %s badge: hue %.2f" % [r["icon"], r["kind"], h])
	check(seen.has("buff") and seen.has("special"), "the table uses buff and special badges")
	var stun: Image = ART.tex(TABLE.ICON + "CC_Stunned").get_image()
	stun.convert(Image.FORMAT_RGBA8)
	check(_hue(stun) >= 0.72 and _hue(stun) <= 0.86, "CC_Stunned is purple, for the guard disc and kits that add a cc row")
	var debuff: Image = ART.tex(TABLE.ICON + "Debuff_ATK").get_image()
	debuff.convert(Image.FORMAT_RGBA8)
	check(_hue(debuff) >= 0.55 and _hue(debuff) <= 0.7, "Debuff_ATK is blue, for kits that add a debuff row")
	# the row
	var w := _world([StubFighter.new(), StubFighter.new()])
	var left: Control = STATUS.new().setup(w, 0, Vector2(234, 112))
	var right: Control = STATUS.new().setup(w, 1, Vector2(1046, 112))
	check(is_equal_approx(left.slot_rect(1).position.x - left.slot_rect(0).position.x, 31.0), "the left row runs right at a 31 px pitch")
	check(is_equal_approx(right.slot_rect(0).position.x - right.slot_rect(1).position.x, 31.0) and right.slot_rect(0).end.x == 1046.0, "the right row runs left from its outer edge")
	check(left.slot_rect(0).size == Vector2(28.0, 32.0), "badges are 28 px wide")
	left.shown = []
	for i in 11:
		left.shown.append({"id": "x%d" % i, "icon": "Combat__Combat_Icon_Buff_ATK", "kind": "buff", "count": -1})
	check(left.visible_count() == 8 and left.has_ellipsis(), "eleven entries draw eight and an ellipsis")
	left.shown.resize(8)
	check(left.visible_count() == 8 and not left.has_ellipsis(), "exactly eight draw no ellipsis")
	left.shown.resize(3)
	check(left.visible_count() == 3 and not left.has_ellipsis(), "three draw three")
	left.free()
	right.free()
	check(is_equal_approx(STATUS.pop(0.0), 0.8) and is_equal_approx(STATUS.pop(0.067), 0.962) and STATUS.pop(0.25) == 1.0 and STATUS.pop(5.0) == 1.0, "a new badge pops 0.8 to 1.0 in a quarter second")
	# a badge that appears gets a birth time, and loses it when it goes
	var live := StubFighter.new()
	w.fighters = [live, StubFighter.new()]
	var row: Control = STATUS.new().setup(w, 0, Vector2(234, 112))
	root.add_child(row)
	row.set_process(false)
	live.powered = true
	row._process(DT)
	check(row.shown.size() == 1 and row._born.has("power"), "a new badge is timed from when it appeared")
	live.powered = false
	row._process(DT)
	row._process(STATUS.GRACE)
	check(row.shown.is_empty() and not row._born.has("power"), "and forgotten when it goes")
	live.state = S["BLOCK"]
	row._process(DT)
	var born: float = row._born["block"]
	live.state = 0
	row._process(DT)
	row._process(DT)
	check(row.shown.size() == 1 and row._born["block"] == born, "a block that drops for two ticks between hits keeps its badge")
	live.state = S["BLOCK"]
	row._process(DT)
	check(row._born["block"] == born, "and does not pop in again")
	live.state = 0
	row._process(0.2)
	check(row.shown.is_empty() and not row._born.has("block"), "a released block goes after the grace")
	row.queue_free()
	w.queue_free()

# ── a real training fight ────────────────────────────────────────────────────
func _real_fight() -> void:
	var game: Node = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	var screen: Node = game.stack.back()
	screen.set_physics_process(false)
	var t: Control = TOP.new().setup(screen)
	screen.add_child(t)
	for i in 3:
		await process_frame
	check(is_equal_approx(float(t.hp_bars[0].mat.get_shader_parameter("fill")), 1.0), "real fight: full hp reads as 1.0")
	check(t.guard_bars[0].visible and t.guard_bars[1].visible, "real fight: both guard bars show")
	check(is_equal_approx(float(t.guard_bars[0].mat.get_shader_parameter("fill")), 1.0), "real fight: a full guard reads as 1.0")
	check(t.tag_text(1) == "CPU" and t.timer_state()["training"], "real training fight: CPU tag and the training plate")
	var hina: Array = TABLE.badges(screen.f1)
	check(hina.size() >= 1 and hina[0]["id"] == "ammo" and hina[0]["count"] == int(screen.f1.kv["mag"]), "real Hina shows her magazine (%s)" % str(hina))
	screen.f1.hp = 400.0
	for i in 5:
		await process_frame
	check(is_equal_approx(float(t.hp_bars[0].mat.get_shader_parameter("fill")), 0.4), "real fight: damage moves the bar")
	check(t._face[0] == "flinch" and t._face[1] == "calm" and t._lvl[0] == 2, "real fight: the card reads the same hp (flinch now, hurt after)")
	check(t.round_word() == "round_1", "real fight: round 1")
	check(ART.warnings().is_empty(), "no BaArt warnings (%s)" % str(ART.warnings()))

func _assets() -> void:
	var t: Texture2D = load("res://scripts/ui/ba_words.gd").tex("training")
	check(t != null and t.get_width() > 100, "the TRAINING word loads from the main hud set")
