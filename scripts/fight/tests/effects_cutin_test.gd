extends SceneTree
## Effects, the ult cut-in and the Reduce Flashes helper: layer timing, the white name plate, the caster accent, the
## impact frame, flash caps, ducking and the sim-clock follow. Kinds are in fx_test.gd.
## Run: TEST=res://scripts/fight/tests/effects_cutin_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real window, never headless)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

var checks := 0
var failures: Array = []
var game: Node
var screen: Node
var hud: Control
var cutin: Control
var Cutin: GDScript
var Flash: GDScript

## A session with the setting on, for the helper and the cut-in to read.
class StubSession extends Session:
	func _init() -> void:
		super()
		reduce_flashes = true

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("EFFECTS_CUTIN_CHECK FAIL ", label)
		failures.append(label)

func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	create_timer(170.0).timeout.connect(func() -> void:
		print("EFFECTS_CUTIN_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	Cutin = load("res://scripts/fight/hud_cutin.gd")
	Flash = load("res://scripts/fight/fx_flash.gd")
	game = root.get_node("Game")
	game.session.reduce_flashes = false
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	hud = screen.hud
	cutin = hud._cutin
	_flash_helper()
	_accent()
	_name_fit()
	await _plate()
	await _timing()
	await _veil_impact()
	await _flash_caps()
	await _sim_clock()
	print("EFFECTS_CUTIN_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

## Puts the screen at `tick` of the current cut-in (the sim clock the cut-in follows) and lets the HUD sync.
func _at(tick: int, caster: Object = null) -> void:
	screen.freeze_caster = caster if caster != null else screen.f1
	screen.time_stop = 72 - tick
	screen.freeze_t = tick
	await process_frame
	await process_frame

func _stop() -> void:
	screen._clear_freeze()
	await process_frame
	await process_frame

# ── the Reduce Flashes helper ────────────────────────────────────────────────
func _flash_helper() -> void:
	var on := StubSession.new()
	var off := Session.new()
	off.reduce_flashes = false
	game.session.reduce_flashes = false
	check(not Flash.reduced(), "the live session reads as off by default")
	check(not Flash.reduced(off), "a session with the setting off reads as off")
	check(Flash.reduced(on), "a session with the setting on reads as on")
	check(near(Flash.flash(0.92, on), 0.3) and near(Flash.flash(0.2, on), 0.2) and near(Flash.flash(0.92, off), 0.92), "flash alpha is capped at 0.3 only while reduced")
	check(near(Flash.shake(10.0, on), 5.0) and near(Flash.shake(10.0, off), 10.0), "shake is halved only while reduced")
	check(Flash.stepped(0.5, 30.0, off) == 15.0 and Flash.stepped(0.5, 30.0, on) == 0.0, "a stepped pattern holds one step while reduced")
	check(not Flash.impact_ok(on), "no impact frame while reduced")
	check(Flash.impact_ok(off), "an impact frame may start")
	check(not Flash.impact_ok(off), "a second one inside 340 ms is refused (at most 3 a second)")
	Flash.set("_last_impact_ms", -100000)
	var not_bool := Object.new()
	check(not Flash.reduced(not_bool), "an object without the property is off, not an error")
	not_bool.free()

# ── the caster's accent ──────────────────────────────────────────────────────
func _accent() -> void:
	var hina: Color = Cutin.accent_for({"id": 10004, "bullet": "Explosion"})
	var hoshino: Color = Cutin.accent_for({"id": 10005, "bullet": "Pierce"})
	check(hina.b > hina.r and hina.r > hina.g and hina.b > 0.9, "Hina's lines are violet (%s)" % str(hina))
	check(hoshino.r > hoshino.g and hoshino.g > hoshino.b and hoshino.r > 0.85, "Hoshino's lines are coral (%s)" % str(hoshino))
	var seen := {}
	for e in _roster():
		var c: Color = Cutin.accent_for(e)
		check(c.s >= 0.4 and c.v >= 0.6, "%s has a saturated accent (%s)" % [e["name"], str(c)])
		seen[c.to_html()] = true
	check(seen.size() >= 2, "the fighters keep their own accents (%d)" % seen.size())

func _roster() -> Array:
	var f := FileAccess.open("res://assets/ba/roster.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())["fighters"]

# ── the plate ────────────────────────────────────────────────────────────────
func _name_fit() -> void:
	var F: GDScript = load("res://scripts/core/fighters.gd")
	var worst := 99
	var font: Font = (load("res://scripts/ui/ui.gd") as GDScript).font_ui(700)
	var Kit: GDScript = load("res://scripts/fight/hud_kit.gd")
	for e in _roster():
		var who: String = F.display_name(e)
		var sz: int = Cutin.plate_text_size(who)
		worst = mini(worst, sz)
		check(Kit.width(font, who, sz) <= Cutin.PLATE_W - 40.0 + 0.5, "%s fits the plate at %d px" % [who, sz])
	check(worst >= 18, "every roster name reads at 18 px or more on the plate (%d)" % worst)
	var long := "Hoshino (Swimsuit) Special Edition"
	var ls: int = Cutin.plate_text_size(long)
	check(ls < worst and ls >= 12, "a very long name shrinks (%d px) and stops at 12" % ls)
	check(Cutin.plate_width("Hina") < Cutin.plate_width("Hoshino") and Cutin.plate_width("Hina") >= 128.0 and Cutin.plate_width("Hoshino") < Cutin.PLATE_W,
			"the plate is sized to the name (Hina %.0f, Hoshino %.0f)" % [Cutin.plate_width("Hina"), Cutin.plate_width("Hoshino")])
	check(Cutin.plate_width("A name far too long for any plate to hold") == Cutin.PLATE_W, "a long name takes the full plate")
	check(Cutin.PLATE_W == 241.0 and Cutin.PLATE_H == 35.0 and Cutin.BAR_W == 248.0 and Cutin.BAR_H == 16.0, "the plate is 241 x 35 and the deco bar 248 x 16, half the real 482 x 70 and 495 x 32")

## The plate drawn alone on a dark ground: white across its width, leaning "/" by 10 degrees, the name in navy on it, the bar
## in the side's light tint below it.
func _plate() -> void:
	await _at(30)
	var Painter: GDScript = load("res://scripts/ui/painter.gd")
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 240)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.14, 0.23)
	bg.size = Vector2(480, 240)
	vp.add_child(bg)
	var rect := Rect2(100.0, 80.0, 241.0, 35.0)
	vp.add_child(Painter.new().setup(Vector2(480, 240), func(c: Control) -> void: cutin._draw_plate(c, rect, 1.0)))
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var row := func(y: int) -> Array:
		var lo := 9999
		var hi := -1
		for x in 480:
			var c := img.get_pixel(x, y)
			if c.r > 0.9 and c.g > 0.9 and c.b > 0.9:
				lo = mini(lo, x)
				hi = maxi(hi, x)
		return [lo, hi]
	var first := -1
	var last := -1
	for y in range(76, 120):
		var r: Array = row.call(y)
		if int(r[1]) - int(r[0]) >= 150:
			if first < 0:
				first = y
			last = y
	var top: Array = row.call(first)
	var bottom: Array = row.call(last)
	var w: int = int(top[1]) - int(top[0])
	check(first >= 76 and last - first >= 14, "the plate has a white body at least 15 rows tall (rows %d to %d)" % [first, last])
	check(w >= 200 and w <= 262, "the plate is about 241 px wide (%d)" % w)
	var lean_px := float(int(top[0]) - int(bottom[0]))
	var want := shear() * float(last - first)
	check(lean_px >= want - 2.0 and lean_px <= want + 2.0, "it leans / by 10 degrees: the top edge is %.0f px right of the bottom one over %d rows (want %.1f)" % [lean_px, last - first, want])
	var navy := 0
	var bar := 0
	var side: Color = side_light()
	for y in range(80, 130):
		for x in range(90, 380):
			var c := img.get_pixel(x, y)
			if y < 118 and c.b < 0.5 and c.r < 0.4 and c.g < 0.45 and c.r > 0.1 and absf(c.r - 0.07) > 0.05:
				navy += 1
			if y >= 114 and absf(c.r - side.r) < 0.08 and absf(c.g - side.g) < 0.08 and absf(c.b - side.b) < 0.08:
				bar += 1
	check(navy >= 80, "the name is drawn in navy on the plate (%d px)" % navy)
	check(bar >= 1500, "the deco bar shows below the plate in the side's tint (%d px)" % bar)
	vp.queue_free()
	await _stop()

func side_light() -> Color:
	return (load("res://scripts/ui/ba_tokens.gd") as GDScript).P1_LIGHT

func shear() -> float:
	return (load("res://scripts/ui/ba_tokens.gd") as GDScript).SHEAR

# ── whip timing and the duck ─────────────────────────────────────────────────
func _timing() -> void:
	check(near(Cutin.ART_T, 5.0 / 60.0, 0.0001) and near(Cutin.TAG_T, 9.0 / 60.0, 0.0001) and near(Cutin.PLATE_T, 11.0 / 60.0, 0.0001), "layers start 5, 9 and 11 frames after the band")
	check(near(Cutin.EXIT_T, 0.86, 0.0001) and near(Cutin.EXIT_LEN, 0.16, 0.0001), "the exit keeps its constants, so the HUD duck is unchanged")
	var prev := -1.0
	var mono := true
	var peak := 0.0
	var at7 := 0.0
	var at4 := -1.0
	for t in range(1, 40):
		await _at(t)
		var k: float = cutin._k
		peak = maxf(peak, k)
		mono = mono and k >= prev - 0.0001
		prev = k
		if t == 4:
			at4 = k
		if t == 12:
			at7 = k
	check(mono, "the art's travel never goes backwards")
	check(peak <= 1.0, "and never overshoots (%.3f)" % peak)
	check(at4 == 0.0, "the art waits its 5 frames (travel %.3f at tick 4)" % at4)
	check(at7 > 0.8 and at7 < 0.95, "it has covered about 88 percent 7 frames after its start (%.2f)" % at7)
	for t in [0, 3, 6, 9]:
		await _at(t)
		var lo := clampf(float(t) / 6.0, 0.0, 1.0)
		var hi := clampf(float(t + 1) / 6.0, 0.0, 1.0)
		var q: float = cutin.strength()
		check(q >= lo - 0.001 and q <= hi + 0.001, "the HUD duck at tick %d follows the band's 0.1 s rise (%.2f, between %.2f and %.2f)" % [t, q, lo, hi])
	await _at(40)
	check(near(cutin.strength(), 1.0), "the HUD is fully ducked under the band")
	await _at(70)
	check(cutin.strength() == 0.0, "and back up once the band has left")
	var sx := []
	for t in [8, 20, 40, 50]:
		await _at(t)
		sx.append(cutin._art.position.x)
	check(float(sx[0]) < float(sx[1]) - 100.0 and float(sx[2]) - float(sx[1]) < 40.0, "the art slides in from its side and has settled by tick 20 (%s)" % str(sx))
	await _stop()

# ── the impact frame on the stamp ────────────────────────────────────────────
func _veil_impact() -> void:
	var land := 20
	var seen := {}
	for t in [land - 2, land, land + 1, land + 3, land + 6]:
		await _at(t)
		seen[t] = cutin._veil_mat.get_shader_parameter("impact")
	check(float(seen[land - 2]) == 0.0, "no impact frame before the stamp lands")
	check(float(seen[land]) == 1.0 and float(seen[land + 1]) == 1.0, "the impact frame holds for the stamp's tick and the next")
	check(float(seen[land + 3]) == 0.0 and float(seen[land + 6]) == 0.0, "and is over by the third tick after the stamp")
	var on := StubSession.new()
	var real: Object = game.session
	game.session = on
	await _at(land)
	check(float(cutin._veil_mat.get_shader_parameter("impact")) == 0.0, "no impact frame while Reduce Flashes is on")
	game.session = real
	await _stop()

# ── flashes, and the strobe, respect Reduce Flashes ──────────────────────────
func _flash_caps() -> void:
	await _at(0)
	var full := float(cutin._mat.get_shader_parameter("flash"))
	check(full >= 0.6, "the portrait's white-out is strong at the trigger (%.2f)" % full)
	var on := StubSession.new()
	var real: Object = game.session
	game.session = on
	await _at(0)
	var capped := float(cutin._mat.get_shader_parameter("flash"))
	check(capped <= 0.3 + 0.001, "and capped while Reduce Flashes is on (%.2f)" % capped)
	await _at(25)
	var glow_a := float(cutin._mat.get_shader_parameter("glow_amt"))
	await _at(29)
	var glow_b := float(cutin._mat.get_shader_parameter("glow_amt"))
	check(near(glow_a, glow_b, 0.0001), "the portrait's rim stops pulsing while Reduce Flashes is on")
	game.session = real
	await _at(25)
	var pa := float(cutin._mat.get_shader_parameter("glow_amt"))
	await _at(29)
	check(not near(pa, float(cutin._mat.get_shader_parameter("glow_amt")), 0.0001), "and pulses otherwise")
	await _stop()

# ── the cut-in follows the sim clock, not the wall clock ─────────────────────
func _sim_clock() -> void:
	await _at(33)
	var a: float = cutin._age
	var pos: Vector2 = cutin._art.position
	for i in 20:
		await process_frame
	check(absf(float(cutin._age) - a) < 1.0 / 60.0 + 0.001, "the cut-in's age holds while the sim holds (%.3f then %.3f)" % [a, cutin._age])
	check(cutin._art.position.distance_to(pos) < 1.0, "so the art does not move")
	await _at(36)
	check(float(cutin._age) > a + 0.01, "and advances with the sim")
	await _stop()
	check(not cutin.live and cutin.strength() == 0.0, "it is off once the freeze is cleared")
