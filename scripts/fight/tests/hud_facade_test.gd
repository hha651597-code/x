extends SceneTree
## HUD: the facade over the modules. Layers, the one guard-bar writer, one chime per meter edge, the winner of a
## mirror match, ducking under the EX cut-in, the round-start entrance and every HUD_DEMO state.
## Run: TEST=res://scripts/fight/tests/hud_facade_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real window, never headless)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

var checks := 0
var failures: Array = []
var game: Node
var sfx: Node
var screen: Node
var hud: Control
var Demo: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("HUD_FACADE_CHECK FAIL ", label)
		failures.append(label)

func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	create_timer(170.0).timeout.connect(func() -> void:
		print("HUD_FACADE_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	Demo = load("res://scripts/fight/hud_demo.gd")
	game = root.get_node("Game")
	sfx = root.get_node("Sfx")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10004
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	hud = screen.hud
	_layers()
	await _chimes()
	_winner()
	await _ducking()
	await _entrance()
	await _pause_sees_battle()
	await _paused_clock()
	_flash_cap()
	await _demo()
	print("HUD_FACADE_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# ── what the facade builds ───────────────────────────────────────────────────
func _layers() -> void:
	var kids := hud.get_children()
	var names: Array = kids.map(func(n: Node) -> String: return n.get_script().resource_path.get_file())
	check(names == ["hud_top.gd", "hud_bottom.gd", "hud_feed.gd", "hud_training.gd", "painter.gd", "hud_cutin.gd", "painter.gd", "hud_pause.gd"], "layers in draw order: " + str(names))
	check(hud.z_index == 100 and hud.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.size == Vector2(1280, 720), "z 100, ignores the mouse, fills 1280x720")
	for gone in ["_hp_bars", "_ex_bars", "_assist_icons", "_call_cards", "_assist_call", "_icons", "_timer_card", "_under", "_ink"]:
		check(hud.get(gone) == null, "the old hud's %s is gone" % gone)
	for gone in ["_guard_bar", "_draw_bottom", "_draw_hints", "_draw_ex_cue", "_ex_poly", "_call_x", "_draw_combo", "_draw_names"]:
		check(not hud.has_method(gone), "the old hud's %s is gone" % gone)
	for kept in ["setup", "round_intro", "banner", "on_combo", "cutin", "cutin_stop", "assist_callout", "flash", "show_pause", "refresh", "pause_items", "pause_activate", "pause_action"]:
		check(hud.has_method(kept), "the facade keeps " + kept)
	check(hud.get_script().meter_label(100.0) == "EX READY", "meter_label stays for super_test")
	var bars: Array = hud._guard_bars
	check(bars.size() == 2 and bars[0] == hud._top.guard_bars[0] and bars[1] == hud._top.guard_bars[1], "_guard_bars is the top rail's own pair, one writer")
	for node in [hud._top, hud._bottom, hud._feed, hud._train]:
		check(node in hud._dim_nodes, "%s ducks under the cut-in" % node.get_script().resource_path.get_file())

# ── one writer per effect ────────────────────────────────────────────────────
func _chimes() -> void:
	screen.f1.meter = 0.0
	screen.f2.meter = 0.0
	for i in 5:
		await process_frame
	var before := int(sfx.played.get("ex_ready", 0))
	screen.f1.meter = 49.0
	for i in 3:
		await process_frame
	check(int(sfx.played.get("ex_ready", 0)) == before, "49 chimes nothing")
	screen.f1.meter = 50.0
	for i in 3:
		await process_frame
	check(int(sfx.played.get("ex_ready", 0)) == before + 1, "crossing SUPER chimes once, not twice (%d)" % (int(sfx.played.get("ex_ready", 0)) - before))
	await create_timer(0.4).timeout     # the EX chime waits 0.3 s after the SUPER one, in game time
	screen.f1.meter = 100.0
	for i in 3:
		await process_frame
	check(int(sfx.played.get("ex_ready", 0)) == before + 2, "crossing EX chimes once more (%d)" % (int(sfx.played.get("ex_ready", 0)) - before))
	for i in 10:
		await process_frame
	check(int(sfx.played.get("ex_ready", 0)) == before + 2, "and nothing while it stays full")
	screen.f1.meter = 0.0

# ── the winner of a banner ───────────────────────────────────────────────────
## A Hina against a Hina: the name cannot tell the sides apart, so the side that just gained a win is the winner.
func _winner() -> void:
	game.session.players[1]["cpu"] = false
	screen.wins = [0, 0]
	hud._wins_banner = [0, 0]
	screen.wins[0] += 1
	hud.banner("HINA WINS", "ROUND 1", Color.WHITE, 2.0)
	check(hud._banner.slot == 1 and hud._banner.word == "win", "mirror match: a P1 round shows WIN for slot 1 (slot %d, %s)" % [hud._banner.slot, hud._banner.word])
	screen.wins[1] += 1
	hud.banner("HINA WINS", "ROUND 2", Color.WHITE, 2.0)
	check(hud._banner.slot == 2 and hud._banner.word == "win", "mirror match: a P2 round is slot 2, and WIN between two humans")
	game.session.players[1]["cpu"] = true
	screen.wins[0] += 1
	hud.banner("HINA WINS", "ROUND 3", Color.WHITE, 2.0)
	check(hud._banner.slot == 1 and hud._banner.word == "win", "mirror match against a CPU: the human's round still reads WIN")
	screen.wins[1] += 1
	hud.banner("HINA WINS", "ROUND 4", Color.WHITE, 2.0)
	check(hud._banner.slot == 2 and hud._banner.word == "lose", "mirror match against a CPU: the CPU's round reads LOSE")
	hud.banner("HINA WINS", "ROUND 5", Color.WHITE, 2.0)
	check(hud._banner.slot == 1, "a banner with no new win falls back to the first fighter with that name")
	hud.banner("K.O.", "", Color.WHITE, 1.6)
	check(hud._banner.slot == 0, "other banners carry no winner")
	screen.wins = [0, 0]
	hud._wins_banner = [0, 0]

# ── ducking under the EX cut-in ──────────────────────────────────────────────
func _ducking() -> void:
	await process_frame
	for node in hud._dim_nodes:
		check(near((node as Control).modulate.a, 1.0), "%s is opaque without a cut-in" % node.get_script().resource_path.get_file())
	screen.freeze_caster = screen.f1
	screen.time_stop = 40
	screen.freeze_t = 30
	await process_frame
	await process_frame
	for node in hud._dim_nodes:
		check(near((node as Control).modulate.a, 0.18, 0.02), "%s ducks to 0.18 under the band (%.2f)" % [node.get_script().resource_path.get_file(), (node as Control).modulate.a])
	check(hud._banner_layer.modulate.a == 1.0 and hud._flash_layer.modulate.a == 1.0, "the banner and flash layers are not ducked")
	screen._clear_freeze()
	await process_frame
	await process_frame
	for node in hud._dim_nodes:
		check(near((node as Control).modulate.a, 1.0), "%s comes back when the freeze ends" % node.get_script().resource_path.get_file())

# ── the round-start entrance ─────────────────────────────────────────────────
func _entrance() -> void:
	hud.set_process(false)
	hud._entered = false
	hud.round_intro(1)
	hud._process(0.0)
	check(near(hud._top.position.y, -170.0, 4.0) and near(hud._bottom.position.y, 150.0, 4.0), "round 1 starts with the rails off their places (%.0f, %.0f)" % [hud._top.position.y, hud._bottom.position.y])
	for i in 7:
		hud._process(1.0 / 60.0)
	var k: float = 1.0 + hud._top.position.y / 170.0
	check(near(k, 0.88, 0.04), "the top rail has covered 88 percent after about 7 frames (%.2f)" % k)
	check(hud._bottom.position.y / 150.0 > -hud._top.position.y / 170.0, "the bottom row follows two frames behind")
	var prev: float = hud._top.position.y
	var mono := true
	for i in 40:
		hud._process(1.0 / 60.0)
		mono = mono and hud._top.position.y >= prev - 0.001 and hud._top.position.y <= 0.001
		prev = hud._top.position.y
	check(mono and hud._top.position.y == 0.0 and hud._bottom.position.y == 0.0, "it settles with no overshoot, inside 0.7 s")
	hud.round_intro(2)
	hud._process(0.0)
	check(hud._top.position.y == 0.0 and hud._bottom.position.y == 0.0, "round 2 keeps the rails where they are")
	hud.set_process(true)
	await process_frame

# ── the HUD clock stands still while the game is paused ──────────────────────
func _paused_clock() -> void:
	hud.banner("K.O.", "", Color.WHITE, 0.8)
	for i in 3:
		await process_frame
	check(hud._banner.active, "a banner starts")
	var t: float = hud._time
	screen.set_paused(true)
	for i in 80:
		await process_frame
	screen.set_paused(false)
	await process_frame
	check(absf(hud._time - t) < 0.1, "the hud clock did not run through the pause (%.2f s)" % (hud._time - t))
	check(hud._banner.active, "a banner that was up when the game paused is still up after")
	hud._banner.active = false
	# the top rail (hp ghost, blink, tape), the status rows and the training overlay stop with it
	screen.f2.hp = screen.f2.max_hp * 0.4
	await create_timer(0.7).timeout
	var top: Control = hud._top
	var row: Control = top._status[0]
	var trail: float = top._hp_trail[1]
	var clocks := [top._time, row._time, hud._train._t, hud._train._tip_t]
	check(trail > 0.45 and trail < 1.0, "the hp ghost is mid-drain when the pause starts (%.2f)" % trail)
	screen.set_paused(true)
	await create_timer(0.5).timeout
	check(top._hp_trail[1] == trail, "paused: the hp ghost holds still (%.2f to %.2f)" % [trail, top._hp_trail[1]])
	check([top._time, row._time, hud._train._t, hud._train._tip_t] == clocks, "paused: the top rail, status row and training clocks stand still")
	screen.set_paused(false)
	screen.f2.hp = screen.f2.max_hp

# ── Reduce Flashes caps the hud's full-screen flash ──────────────────────────
func _flash_cap() -> void:
	var live: Object = game.session
	live.reduce_flashes = true
	hud.flash(Color.WHITE, 0.8)
	check(hud._flash_col.a <= 0.3001, "with Reduce Flashes on a K.O. flash is capped at 0.3 (%.2f)" % hud._flash_col.a)
	live.reduce_flashes = false
	hud.flash(Color.WHITE, 0.8)
	check(is_equal_approx(hud._flash_col.a, 0.8), "with it off the flash is untouched")
	hud._flash_col.a = 0.0

# ── the pause scrim blurs the whole battle ───────────────────────────────────
## Without a BackBufferCopy ahead of it the blur shader reads the screen as an earlier shader saw it: the stage, no fighters, no hud.
func _pause_sees_battle() -> void:
	for i in 3:
		await process_frame
	screen.set_paused(true)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / 1280.0
	var bar := img.get_pixel(int(450.0 * k), int(60.0 * k))
	check(bar.r > bar.b + 0.08, "paused: P1's red hp bar still shows under the scrim (%s)" % bar.to_html(false))
	var back := false
	for c in hud._pause.get_children():
		if c is BackBufferCopy:
			back = true
		elif c is ColorRect:
			check(back, "the scrim comes after a BackBufferCopy")
	screen.set_paused(false)
	await process_frame

# ── HUD_DEMO ─────────────────────────────────────────────────────────────────
func _demo() -> void:
	var f1: Node = screen.f1
	var f2: Node = screen.f2
	var effects := {
		"lowhp": func() -> bool: return near(f1.hp / f1.max_hp, 0.18, 0.001) and near(f2.hp / f2.max_hp, 0.55, 0.001),
		"ex": func() -> bool: return f1.meter == 100.0 and f2.meter == 62.0,
		"assist": func() -> bool: return f1.assist_cd == 0 and f2.assist_cd == 0,
		"wins": func() -> bool: return screen.wins == [1, 1] and screen.round_no == 3,
		"win1": func() -> bool: return screen.wins == [1, 0],
		"nearko": func() -> bool: return f2.hp == 4.0,
		"bothlow": func() -> bool: return f1.hp == 5.0 and f2.hp == 5.0,
		"time10": func() -> bool: return screen.timer_frames == 630,
	}
	for part in effects:
		f1.hp = f1.max_hp
		f2.hp = f2.max_hp
		screen.wins = [0, 0]
		OS.set_environment("HUD_DEMO", part)
		Demo.apply(hud)
		check(effects[part].call(), "HUD_DEMO=%s sets its state" % part)
		for i in 4:
			await process_frame
		var fill: Variant = hud._top.hp_bars[0].mat.get_shader_parameter("fill")
		check(fill is float and near(fill, f1.hp / f1.max_hp, 0.001) and (hud._bottom.cells_filled(0) > 0.0) == (f1.meter > 0.0), "HUD_DEMO=%s: four frames later the rail shows P1's hp and the cells P1's meter" % part)
	# time10 stops half a second short of the last ten seconds so the feed sees the crossing and raises its WARNING
	OS.set_environment("HUD_DEMO", "time10")
	Demo.apply(hud)
	screen.training = false
	hud._feed.reset()
	await process_frame
	await process_frame
	screen.timer_frames = 599
	await process_frame
	await process_frame
	check(hud._feed._warn.active and hud._feed._warn.side == 0, "HUD_DEMO=time10 ends in the full-width WARNING")
	screen.training = true
	OS.set_environment("HUD_DEMO", "lowhp,ex,assist,wins,win1,nearko,bothlow,time10")
	Demo.apply(hud)
	await process_frame
	check(f1.hp < f1.max_hp * 0.1 and f2.hp < f2.max_hp * 0.1 and screen.wins == [1, 0] and screen.timer_frames == 10 * 60 + 30, "all parts together apply in order: both nearly dead, P1 a round up, the timer just before the last ten seconds")
	OS.set_environment("HUD_DEMO", "")
	Demo.apply(hud)
	f1.hp = f1.max_hp
	f2.hp = f2.max_hp
	screen.wins = [0, 0]
	screen.round_no = 1
	screen.timer_frames = 3600
	# HUD_SHOT: a PNG a moment into each banner kind, once per round
	var dir := OS.get_user_data_dir() + "/hud_facade_shots_%d" % OS.get_process_id()
	OS.set_environment("HUD_SHOT", dir)
	Demo._done.clear()
	hud.banner("K.O.", "", Color.WHITE, 1.6)
	for i in 600:
		await process_frame
		if Demo._done.has("ko1"):
			break
	await RenderingServer.frame_post_draw
	await process_frame
	check(FileAccess.file_exists(dir + "/hud_auto_ko_r1.png"), "HUD_SHOT saves a picture a moment into the K.O. banner")
	var n: int = Demo._done.size()
	for i in 4:
		await process_frame
	check(Demo._done.size() == n, "and only once per round")
	OS.set_environment("HUD_SHOT", "")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
