extends SceneTree
## HUD bottom row (scripts/fight/hud_bottom.gd): geometry and mirroring, disc and plate thresholds, cell fill and no tearing in real
## pixels, assist states and ready transition, the meter edges and their Sfx, the call-out, and missing fields.
## Run: TEST=res://scripts/fight/tests/hud_bottom_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

class FakeWorld extends Node:
	var fighters: Array = []
	var phase := "fight"

class Bare extends RefCounted:
	pass

const BG := Color(0.5, 0.5, 0.5)

var checks := 0
var failures: Array = []
var Module: GDScript
var screen: Node
var f1: Node
var f2: Node
var sfx: Node
var bottom: Control

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("HUD_BOTTOM_CHECK FAIL ", label)
		failures.append(label)

func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("HUD_BOTTOM_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	Module = load("res://scripts/fight/hud_bottom.gd")
	var game: Node = root.get_node("Game")
	sfx = root.get_node("Sfx")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	game.session.players[0]["special"] = 20001
	game.session.players[1]["special"] = 23005
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.hud.visible = false
	screen.hud.process_mode = Node.PROCESS_MODE_DISABLED
	f1 = screen.f1
	f2 = screen.f2
	bottom = _module(screen)
	screen.add_child(bottom)
	_geometry()
	_values()
	_assist()
	_edges()
	_callout()
	await _pixels()
	await _missing()
	check(BaArt.warnings().is_empty(), "no art warnings: " + str(BaArt.warnings()))
	print("HUD_BOTTOM_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _module(world: Node) -> Control:
	var m: Control = Module.new()
	m.setup(world)
	m.set_process(false)
	return m

func _step(m: Control, frames: int) -> void:
	for i in frames:
		m._process(1.0 / 60.0)

func _meters(a: float, b: float) -> void:
	f1.meter = a
	f2.meter = b

# ── geometry ─────────────────────────────────────────────────────────────────
func _geometry() -> void:
	var screen_rect := Rect2(0, 0, 1280, 720)
	_meters(100.0, 100.0)
	f1.assist_cd = 0
	f2.assist_cd = 0
	for i in 2:
		var sign := 1.0 if i == 0 else -1.0
		var disc: Rect2 = bottom.rect_disc(i)
		for k in 10:
			var r: Rect2 = bottom.rect_cell(i, k)
			check(r.size == Vector2(34, 26), "side %d cell %d is 34x26" % [i, k])
			check(screen_rect.encloses(r), "side %d cell %d on screen" % [i, k])
			if k > 0:
				var prev: Rect2 = bottom.rect_cell(i, k - 1)
				check(near(r.position.x - prev.position.x, 37.0 * sign), "side %d cell %d sits 37 px from the last" % [i, k])
				check(near(absf(r.get_center().x - prev.get_center().x) - 34.0, 3.0), "side %d cells %d and %d leave a 3 px gap" % [i, k - 1, k])
			if i == 0:
				check(near(r.get_center().x + bottom.rect_cell(1, k).get_center().x, 1280.0), "cell %d mirrors across the centre" % k)
		check((bottom.rect_cell(i, 0).get_center().x - disc.get_center().x) * sign > 0.0, "side %d cells run away from the disc" % i)
		check(absf(bottom.rect_cell(i, 0).get_center().x - disc.get_center().x) < absf(bottom.rect_cell(i, 9).get_center().x - disc.get_center().x), "side %d cell 0 is the one by the disc" % i)
		check(disc.intersects(bottom.rect_card(i)), "side %d disc overlaps the card" % i)
		var card: Rect2 = bottom.rect_card(i)
		var fr: Rect2 = bottom._frame(i)
		var lc := card.size.y * 0.1763     # BaArt.LEAN
		var lf := fr.size.y * 0.1763 * 0.5
		var frame_poly := PackedVector2Array([Vector2(fr.position.x + lf, fr.position.y), Vector2(fr.end.x + lf, fr.position.y), Vector2(fr.end.x - lf, fr.end.y), Vector2(fr.position.x - lf, fr.end.y)])
		for corner in [Vector2(card.position.x + lc, card.position.y), Vector2(card.end.x, card.position.y), Vector2(card.end.x - lc, card.end.y), Vector2(card.position.x, card.end.y)]:
			check(Geometry2D.is_point_in_polygon(corner, frame_poly), "side %d ready frame surrounds the card corner %s" % [i, corner])
		check(not disc.intersects(bottom.rect_cell(i, 0)), "side %d disc leaves the first cell clear" % i)
		for r: Rect2 in [bottom.rect_card(i), bottom.rect_bracket(i), disc, bottom.rect_plate(i)]:
			check(screen_rect.encloses(r), "side %d piece %s on screen" % [i, r])
		check(bottom.rect_card(i).end.y <= 710.5, "side %d card keeps its 10 px bottom margin" % i)
		for n in [5, 10]:
			var tag: Rect2 = bottom.rect_tag(i, n)
			var cell: Rect2 = bottom.rect_cell(i, n - 1)
			var end_x: float = cell.end.x if i == 0 else cell.position.x
			check(tag.size == Vector2(28, 28), "side %d tag %d is 28 px" % [i, n])
			check(absf(tag.get_center().x - end_x) <= 14.0 and (tag.get_center().x - end_x) * sign > 0.0, "side %d tag %d sits past the far end of cell %d" % [i, n, n])
			check(absf(tag.get_center().y - cell.position.y) <= 2.0, "side %d tag %d rides the strip's top edge" % [i, n])
			check(not tag.intersects(bottom.rect_plate(i)), "side %d tag %d clear of the plate" % [i, n])
		check(absf(bottom.rect_tag(i, 10).get_center().x - disc.get_center().x) > absf(bottom.rect_tag(i, 5).get_center().x - disc.get_center().x), "side %d tag 10 is further out than tag 5" % i)
	check(near(bottom.rect_disc(0).get_center().x + bottom.rect_disc(1).get_center().x, 1280.0), "discs mirror")
	check(near(bottom.rect_card(0).get_center().x + bottom.rect_card(1).get_center().x, 1280.0), "cards mirror")
	_meters(60.0, 60.0)
	check(bottom.rect_plate(0).size == Vector2(109, 41), "SUPER plate is 109x41")
	check(screen_rect.encloses(bottom.rect_plate(1)), "SUPER plate on screen")
	_meters(100.0, 100.0)
	check(bottom.rect_plate(0).size == Vector2(136, 49), "EX READY plate is 136x49")
	check(near(bottom.rect_plate(0).end.y, 636.0), "plate bottom sits 4 px above the strip")
	check(bottom.rect_plate(0).end.y < bottom.rect_cell(0, 0).position.y, "plate stays above the cells")

# ── values ───────────────────────────────────────────────────────────────────
func _values() -> void:
	var table := [[0.0, 0, "", false, false], [9.99, 0, "", false, false], [10.0, 1, "", false, false], [49.9, 4, "", false, false],
			[50.0, 5, "super", true, false], [99.9, 9, "super", true, false], [100.0, 10, "ex", true, true]]
	for row in table:
		_meters(row[0], 100.0 - row[0])
		for i in 2:
			var m: float = row[0] if i == 0 else 100.0 - row[0]
			var expect_disc := int(m / 10.0)
			check(bottom.disc_value(i) == expect_disc, "disc shows %d at meter %.2f" % [expect_disc, m])
			check(near(bottom.cells_filled(i), m / 10.0), "cells filled at meter %.2f" % m)
			var kind := "ex" if m >= 100.0 else ("super" if m >= 50.0 else "")
			check(bottom.plate_kind(i) == kind, "plate '%s' at meter %.2f" % [kind, m])
			check(bottom.tag_lit(i, 5) == (m >= 50.0), "tag 5 lit at meter %.2f" % m)
			check(bottom.tag_lit(i, 10) == (m >= 100.0), "tag 10 lit at meter %.2f" % m)
	_meters(35.0, 35.0)
	check(near(bottom.cells_filled(0), 3.5), "a half cell reads 3.5")

# ── assist ───────────────────────────────────────────────────────────────────
func _assist() -> void:
	var m := _module(screen)
	for pair in [[0, "ready", 0], [90, "cooldown", 2], [61, "cooldown", 2], [60, "cooldown", 1], [1, "cooldown", 1]]:
		f1.assist_cd = pair[0]
		check(m.assist_state(0) == pair[1], "assist_cd %d is %s" % [pair[0], pair[1]])
		check(m.cooldown_secs(0) == pair[2], "assist_cd %d shows %d s" % [pair[0], pair[2]])
	f1.assist_cd = 30
	_step(m, 2)
	check(m.bracket_alpha(0) == 0.0 and m.ready_flare(0) == 0.0, "no bracket and no flash while cooling")
	f1.assist_cd = 0
	_step(m, 1)
	check(m.assist_state(0) == "ready", "assist ready at 0")
	check(m.ready_flare(0) > 0.75, "flash at the ready edge")
	check(m.bracket_alpha(0) > 0.99, "bracket starts at 1.0")
	_step(m, 30)
	check(m.ready_flare(0) == 0.0, "flash gone after 0.45 s")
	_step(m, 12)
	check(near(m.bracket_alpha(0), 0.7, 0.01), "bracket 0.7 after 0.7 s: %f" % m.bracket_alpha(0))
	_step(m, 42)
	check(near(m.bracket_alpha(0), 1.0, 0.01), "bracket back to 1.0 after 1.4 s: %f" % m.bracket_alpha(0))
	check(m.assist_state(1) == "ready" and m.bracket_alpha(1) > 0.0, "the other side keeps its own bracket")
	f2.assist_cd = 50
	check(m.assist_state(1) == "cooldown" and m.bracket_alpha(1) == 0.0, "a cooling side shows no bracket")
	f2.assist_cd = 0
	var saved: Dictionary = f1.assist_data
	f1.assist_data = {}
	check(m.assist_state(0) == "", "no assist data gives no card state")
	check(m.bracket_alpha(0) == 0.0, "no bracket without an assist")
	f1.assist_data = saved
	check(m.key_label(0) == "Q", "P1 assist key is Q: " + m.key_label(0))
	check(m.key_label(1) == ",", "the kb2 key reads: " + m.key_label(1))
	check(m.has_key(0) and not m.has_key(1), "a training dummy has no assist key")
	screen.mode = "versus2p"
	check(m.has_key(0) and m.has_key(1), "two players both show their key")
	screen.mode = "versus-cpu"
	check(m.has_key(0) and not m.has_key(1), "the CPU side shows no key")
	screen.mode = "training"
	m.free()

# ── the meter edges and their sounds ─────────────────────────────────────────
func _chimes() -> int:
	return int(sfx.played.get("ex_ready", 0))

func _edges() -> void:
	var m := _module(screen)
	screen.phase = "intro"
	_meters(0.0, 0.0)
	_step(m, 2)
	var base := _chimes()
	_meters(60.0, 0.0)
	_step(m, 3)
	check(_chimes() == base, "no chime in the round intro")
	screen.phase = "fight"
	_step(m, 10)
	check(_chimes() == base, "a meter already past SUPER does not chime again once the fight starts")
	_meters(0.0, 0.0)
	_step(m, 2)
	_meters(60.0, 0.0)
	_step(m, 2)
	check(_chimes() == base + 1, "SUPER chimes once in the fight")
	_step(m, 30)
	check(_chimes() == base + 1, "holding SUPER does not repeat the chime")
	_meters(0.0, 0.0)
	_step(m, 2)
	_meters(60.0, 0.0)
	_step(m, 2)
	_meters(100.0, 0.0)
	_step(m, 12)
	check(_chimes() == base + 2, "EX within 0.3 s of SUPER stays quiet")
	_meters(0.0, 0.0)
	_step(m, 2)
	_meters(60.0, 0.0)
	_step(m, 25)
	_meters(100.0, 0.0)
	_step(m, 2)
	check(_chimes() == base + 4, "EX after 0.3 s chimes: SUPER then EX")
	_meters(0.0, 0.0)
	_step(m, 2)
	_meters(100.0, 0.0)
	_step(m, 2)
	check(_chimes() == base + 5, "0 to 100 in one frame chimes SUPER only")
	_meters(100.0, 0.0)
	_step(m, 30)
	check(_chimes() == base + 5, "a full meter stays quiet")
	_meters(100.0, 60.0)
	_step(m, 2)
	check(_chimes() == base + 6, "P2 chimes on its own SUPER edge")
	# the EX plate's start light, every 1.5 s while full
	_meters(0.0, 0.0)
	_step(m, 2)
	check(m.ex_flare(0) == 0.0, "no start light below EX")
	_meters(100.0, 0.0)
	_step(m, 1)
	check(m.ex_flare(0) > 0.75, "start light at the EX edge")
	_step(m, 30)
	check(m.ex_flare(0) == 0.0, "start light gone after 0.45 s")
	_step(m, 66)
	check(m.ex_flare(0) > 0.0, "start light again 1.5 s after the edge")
	# cells that just filled flash, only while still filled
	_meters(0.0, 0.0)
	_step(m, 40)
	_meters(25.0, 0.0)
	_step(m, 1)
	check(m._flash_t[0][0] > m._time - 0.1 and m._flash_t[0][1] > m._time - 0.1, "cells 0 and 1 flash when the meter reaches 25")
	check(m._flash_t[0][2] < m._time - 1.0, "cell 2 does not flash at 25")
	m.free()
	screen.phase = "intro"

# ── the call-out ─────────────────────────────────────────────────────────────
func _callout() -> void:
	var m := _module(screen)
	_step(m, 1)
	check(m.callout_rect(0).size == Vector2.ZERO and m.callout_rect(1).size == Vector2.ZERO, "no call-out before a call")
	m.callout(f1)
	m.callout(f2)
	check(m.callout_rect(0).end.x <= 0.0, "P1 call-out starts off the left edge")
	check(m.callout_rect(1).position.x >= 1280.0, "P2 call-out starts off the right edge")
	var home := Rect2(10, 462, 236, 95)
	var last := -1e9
	var peak := -1e9
	for n in 120:
		_step(m, 1)
		var x: float = m.callout_rect(0).position.x
		if n < 30:
			check(x >= last - 0.001, "P1 call-out only moves inward while it settles (frame %d)" % n)
		last = x
		peak = maxf(peak, x)
	check(peak <= home.position.x + 0.001, "the call-out never overshoots home: %f" % peak)
	check(m.callout_rect(0).size == Vector2.ZERO, "P1 call-out is gone after 1.1 s")
	m.callout(f1)
	m.callout(f2)
	check(m._g(0, Module.BRACKET).size.x < Module.BRACKET.size.x * 0.96, "the card is pressed at the call")
	_step(m, 12)
	check(near(m._g(0, Module.BRACKET).size.x, Module.BRACKET.size.x), "the card is back to full size after 0.167 s")
	_step(m, 24)
	var r0: Rect2 = m.callout_rect(0)
	var r1: Rect2 = m.callout_rect(1)
	check(r0.position.is_equal_approx(home.position) and r0.size == home.size, "P1 call-out rests at home: %s" % r0)
	check(near(r1.position.x, 1280.0 - home.end.x) and near(r1.position.y, home.position.y) and r1.size == home.size, "P2 call-out rests at the mirrored home: %s" % r1)
	_step(m, 18)
	check(m.callout_rect(0).position.x < home.position.x - 1.0, "the call-out leaves from 0.8 s")
	var saved: Dictionary = f2.assist_data
	f2.assist_data = {}
	_step(m, 60)
	m.callout(f2)
	check(m.callout_rect(1).size == Vector2.ZERO, "no call-out for a fighter without an assist")
	f2.assist_data = saved
	m.free()

# ── real pixels ──────────────────────────────────────────────────────────────
func _render(m: Control) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var r := ColorRect.new()
	r.color = BG
	r.size = Vector2(1280, 720)
	vp.add_child(r)
	vp.add_child(m)
	for i in 3:
		await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img

func _px(img: Image, x: float, y: float) -> Color:
	return img.get_pixel(clampi(int(x), 0, 1279), clampi(int(y), 0, 719))

func _is_bg(c: Color) -> bool:
	return absf(c.r - BG.r) < 0.02 and absf(c.g - BG.g) < 0.02 and absf(c.b - BG.b) < 0.02

func _cyan(c: Color) -> bool:
	return c.r < 0.1 and c.g > 0.55 and c.g < 0.78 and c.b > 0.9

func _slot(c: Color) -> bool:
	return absf(c.r - 0.094) < 0.05 and absf(c.g - 0.141) < 0.05 and absf(c.b - 0.259) < 0.06

func _shot(a: float, b: float, cd1 := 0, cd2 := 0) -> Image:
	_meters(a, b)
	f1.assist_cd = cd1
	f2.assist_cd = cd2
	var m := _module(screen)
	_step(m, 1)
	m._process(1.2)
	var img: Image = await _render(m)
	return img

func _yellow(img: Image, r: Rect2) -> int:
	var n := 0
	for y in range(int(r.position.y), int(r.end.y)):
		for x in range(int(r.position.x), int(r.end.x)):
			var c := img.get_pixel(x, y)
			if c.r > 0.85 and c.g > 0.75 and c.b < 0.5:
				n += 1
	return n

func _saturation(img: Image, r: Rect2) -> float:
	var sum := 0.0
	var n := 0
	for y in range(int(r.position.y), int(r.end.y), 2):
		for x in range(int(r.position.x), int(r.end.x), 2):
			sum += img.get_pixel(x, y).s
			n += 1
	return sum / float(n)

func _pixels() -> void:
	screen.phase = "intro"
	var img: Image = await _shot(100.0, 5.0)
	for i in 2:
		var p1 := i == 0
		for k in 10:
			var r: Rect2 = bottom.rect_cell(i, k)
			var y := r.end.y - 6.0
			var lean := BaTokens.SHEAR * (y - r.get_center().y)
			if p1:
				check(_cyan(_px(img, r.get_center().x - lean, y)), "P1 cell %d is cyan at meter 100: %s" % [k, _px(img, r.get_center().x - lean, y)])
			if k < 9:
				var gap: float = (bottom.rect_cell(i, k).end.x + bottom.rect_cell(i, k + 1).position.x) * 0.5 if p1 else (bottom.rect_cell(i, k).position.x + bottom.rect_cell(i, k + 1).end.x) * 0.5
				check(_is_bg(_px(img, gap - lean, y)), "side %d gap after cell %d shows the background, not a torn fill" % [i, k])
	var p2: Rect2 = bottom.rect_cell(1, 0)
	check(_cyan(_px(img, p2.end.x - 6.0, p2.get_center().y)), "P2 half cell is filled at the disc side")
	check(_slot(_px(img, p2.position.x + 6.0, p2.get_center().y)), "P2 half cell is empty at the far side: %s" % _px(img, p2.position.x + 6.0, p2.get_center().y))
	var p2n: Rect2 = bottom.rect_cell(1, 1)
	check(_slot(_px(img, p2n.get_center().x, p2n.get_center().y)), "P2 cell 1 is empty at meter 5")
	img = await _shot(5.0, 100.0)
	var p1: Rect2 = bottom.rect_cell(0, 0)
	check(_cyan(_px(img, p1.position.x + 6.0, p1.get_center().y)), "P1 half cell is filled at the disc side")
	check(_slot(_px(img, p1.end.x - 6.0, p1.get_center().y)), "P1 half cell is empty at the far side")
	# tier plates
	img = await _shot(60.0, 100.0)
	var sp: Rect2 = bottom.rect_plate(0)
	var sc: Color = _px(img, sp.position.x + 16.0, sp.get_center().y)
	check(_is_bg(sc), "no SUPER bubble is drawn at meter 60: %s" % sc)
	var ep: Rect2 = bottom.rect_plate(1)
	var ec: Color = _px(img, ep.position.x + 16.0, ep.get_center().y)
	check(ec.r > 0.85 and ec.g > 0.72 and ec.b < 0.55, "EX READY plate is the yellow tint: %s" % ec)
	var ec_br: Color = _px(img, ep.end.x - 34.0, ep.end.y - 17.0)
	check(absf(ec_br.r - ec.r) < 0.04 and absf(ec_br.g - ec.g) < 0.04 and absf(ec_br.b - ec.b) < 0.06, "the EX READY plate's lower right corner is the same yellow, no orange patch: %s against %s" % [ec_br, ec])
	check(_is_bg(_px(img, 640, 560)), "nothing else is drawn mid-screen")
	var lit5 := _yellow(img, bottom.rect_tag(0, 5))
	var dim10 := _yellow(img, bottom.rect_tag(0, 10))
	check(lit5 > 15, "lit tag 5 glows yellow (%d px)" % lit5)
	check(dim10 == 0, "unlit tag 10 has no yellow (%d px)" % dim10)
	# cooldown card: colour drains and the seconds show
	var ready_img: Image = await _shot(0.0, 0.0, 0, 0)
	var cool_img: Image = await _shot(0.0, 0.0, 150, 0)
	var face := Rect2(bottom.rect_card(0).position + Vector2(22, 25), Vector2(45, 70))
	var s_ready := _saturation(ready_img, face)
	var s_cool := _saturation(cool_img, face)
	check(s_ready > 0.15, "ready portrait keeps its colour: %f" % s_ready)
	check(s_cool < s_ready * 0.4, "cooling portrait is desaturated: %f vs %f" % [s_cool, s_ready])
	var digit := Rect2(bottom.rect_card(0).position + Vector2(70, 22), Vector2(70, 70))
	var white := 0
	for y in range(int(digit.position.y), int(digit.end.y)):
		for x in range(int(digit.position.x), int(digit.end.x)):
			if _px(cool_img, x, y).get_luminance() > 0.95:
				white += 1
	check(white > 40, "the cooldown seconds draw white digits (%d px)" % white)
	# no assist: the card area is empty
	var with_card: Image = ready_img
	var saved: Dictionary = f1.assist_data
	f1.assist_data = {}
	var bare: Image = await _shot(0.0, 0.0, 0, 0)
	f1.assist_data = saved
	var c0: Vector2 = bottom.rect_card(0).get_center()
	check(not _is_bg(_px(with_card, c0.x, c0.y)), "with an assist the card draws")
	check(_is_bg(_px(bare, c0.x, c0.y)), "without an assist the card is hidden")
	check(_is_bg(_px(bare, bottom.rect_bracket(0).position.x + 4.0, bottom.rect_bracket(0).get_center().y)), "without an assist the bracket is hidden")
	check(not _is_bg(_px(bare, bottom.rect_disc(0).get_center().x, bottom.rect_disc(0).get_center().y)), "without an assist the COST disc stays")

# ── missing fields ───────────────────────────────────────────────────────────
func _missing() -> void:
	var w := FakeWorld.new()
	w.fighters = [Bare.new(), Bare.new()]
	var m := _module(w)
	_step(m, 3)
	for i in 2:
		check(m.assist_state(i) == "", "bare fighter %d has no assist state" % i)
		check(m.disc_value(i) == 0 and m.plate_kind(i) == "" and m.cooldown_secs(i) == 0, "bare fighter %d reads zeros" % i)
		check(m.callout_rect(i).size == Vector2.ZERO, "bare fighter %d has no call-out" % i)
	var img: Image = await _render(_module(w))
	var c0: Vector2 = bottom.rect_card(0).get_center()
	check(_is_bg(_px(img, c0.x, c0.y)) and _is_bg(_px(img, 1280.0 - c0.x, c0.y)), "bare fighters draw no assist card")
	w.fighters = []
	_step(m, 3)
	check(m.disc_value(0) == 0 and m.assist_state(1) == "", "no fighters at all reads zero")
	w.free()
