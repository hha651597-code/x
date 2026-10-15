extends SceneTree
## Captures of the feed, the hit and guard words and every banner kind over a real stage with the old HUD hidden, 1280x720.
## Run: zsh tools/hud_feed_shots.sh [banner,feed,warn]   ->   $W3_OUT (default /tmp/ba-hud-out/feed/)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const PainterScript := preload("res://scripts/ui/painter.gd")

var out := "/tmp/ba-hud-out/feed/"
var game: Node
var screen: Node
var feed: Control
var banner: RefCounted
var host: Control
var host_t := 0.0
var M: GDScript
var att: Node
var def: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("HUD_FEED_SHOTS FAIL watchdog timeout")
		quit(3))
	await process_frame
	var o := OS.get_environment("W3_OUT")
	if o != "":
		out = o
	DirAccess.make_dir_recursive_absolute(out)
	var parts := OS.get_environment("W3_SHOTS").split(",", false)
	if parts.is_empty():
		parts = PackedStringArray(["banner", "feed", "warn"])
	M = load("res://scripts/fight/movesets.gd")
	game = root.get_node("Game")
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
	screen.hud.visible = false
	var banner_script: GDScript = load("res://scripts/fight/hud_banner.gd")
	var feed_script: GDScript = load("res://scripts/fight/hud_feed.gd")
	if banner_script == null or feed_script == null:
		quit(2)
		return
	banner = banner_script.new()
	host = PainterScript.new().setup(Vector2(1280, 720), func(c: Control) -> void: banner.draw(c, host_t))
	host.z_index = 100
	screen.add_child(host)
	feed = feed_script.new().setup(screen)
	feed.z_index = 99
	screen.add_child(feed)
	att = screen.f1
	def = screen.f2
	_stage(-170.0, 170.0)
	await _frames(6)
	if "banner" in parts:
		await _banners()
	if "feed" in parts:
		await _feed()
	if "warn" in parts:
		await _warn()
	print("HUD_FEED_SHOTS done")
	quit(0)

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _stage(x1: float, x2: float) -> void:
	var s: GDScript = att.get_script()
	for f in [att, def]:
		f._set_state(s.S.IDLE)
		f.hitstop = 0
		f.invuln = 0
		f.combo_hits = 0
		f.combo_dmg = 0.0
		f.guard_all = false
		f.hp = f.max_hp
	att.position = Vector2(x1, 560.0)
	def.position = Vector2(x2, 560.0)
	att.facing = 1
	def.facing = -1
	for i in 40:
		screen._apply_camera()

func _save(name: String) -> void:
	await _frames(3)
	root.get_texture().get_image().save_png(out + name + ".png")

func _strip(name: String, shots: Array) -> void:
	var w := 426
	var h := 240
	var img := Image.create(w * shots.size(), h, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var im := Image.load_from_file(out + str(shots[i]) + ".png")
		im.convert(Image.FORMAT_RGBA8)
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
		img.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(w * i, 0))
	img.save_png(out + name + ".png")

## One banner kind at three ages: entrance, hold, exit.
func _kind(label: String, txt: String, sub: String, dur: float, win_slot: int, ages: Array) -> void:
	banner.start(txt, sub, Color.WHITE, dur, 0.0, win_slot)
	var names: Array = []
	for i in ages.size():
		host_t = float(ages[i])
		host.queue_redraw()
		var n := "banner_%s_%d" % [label, i]
		await _save(n)
		names.append(n)
	banner.active = false
	host.queue_redraw()
	_strip("banner_%s" % label, names)

func _banners() -> void:
	_stage(-170.0, 170.0)
	await _kind("round2", "ROUND 2", "", 0.98, 0, [0.08, 0.5, 0.9])
	await _kind("final", "FINAL ROUND", "", 0.98, 0, [0.08, 0.5, 0.9])
	await _kind("training", "TRAINING", "", 0.98, 0, [0.08, 0.5, 0.9])
	await _kind("fight", "FIGHT!", "", 0.9, 0, [0.08, 0.4, 0.84])
	await _kind("start", "START!", "", 0.9, 0, [0.08, 0.4, 0.84])
	await _kind("ko", "K.O.", "", 1.6, 0, [0.12, 0.6, 1.5])
	await _kind("timeup", "TIME UP", "", 1.4, 0, [0.1, 0.7, 1.32])
	await _kind("win", "HINA WINS", "ROUND 2", 2.0, 1, [0.15, 1.0, 1.9])
	await _kind("lose", "HOSHINO WINS", "ROUND 1", 2.0, 2, [0.15, 1.0, 1.9])
	await _kind("draw", "DRAW", "", 1.6, 0, [0.1, 0.8, 1.52])
	await _kind("warning", "WARNING", "", 2.0, 0, [0.3, 1.0, 1.8])

func _hit(a: Node, d: Node, dmg: float, spark: String, counter := false) -> void:
	var h: Dictionary = M.H(Rect2(), dmg, 12, 10, 4.0, {"hitstop": 0, "spark": spark})
	if counter:
		h["counter"] = true
	d.invuln = 0
	d.receive_hit(a, h, a.position, false)
	feed.on_combo(a, d, d.combo_hits, h)

func _combo(a: Node, d: Node, n: int, dmg: float, spark: String, counter := false) -> void:
	for i in n:
		_hit(a, d, dmg, spark, counter)
		await process_frame

func _feed() -> void:
	# tiers and counts, both sides
	_stage(-170.0, 170.0)
	await _combo(att, def, 2, 14.0, "light")
	await _save("feed_p1_2")
	await _combo(att, def, 3, 14.0, "light")
	await _save("feed_p1_5")
	await _combo(att, def, 7, 14.0, "light")
	await _save("feed_p1_12")
	feed.reset()
	_stage(-170.0, 170.0)
	await _combo(def, att, 2, 14.0, "light")
	await _save("feed_p2_2")
	feed.reset()
	_stage(-170.0, 170.0)
	await _combo(def, att, 2, 30.0, "heavy")
	await _combo(def, att, 3, 30.0, "heavy")
	await _save("feed_p2_5_big")
	await _combo(def, att, 7, 30.0, "heavy")
	await _save("feed_p2_12_big")
	feed.reset()
	_stage(-170.0, 170.0)
	await _combo(att, def, 5, 14.0, "light", true)
	await _save("feed_p1_5_counter")
	feed.reset()
	_stage(-170.0, 170.0)
	await _combo(def, att, 5, 14.0, "light", true)
	await _combo(att, def, 5, 14.0, "light")
	await _save("feed_both_sides")
	# real block through the watcher, then the words by hand
	feed.reset()
	_stage(-170.0, 170.0)
	def.guard_all = true
	var h: Dictionary = M.H(Rect2(), 60.0, 12, 10, 4.0, {"hitstop": 0, "chip": 0.2})
	await _frames(2)
	def.receive_hit(att, h, att.position, false)
	await _frames(8)
	await _save("words_block_chip")
	def.guard_all = false
	feed.reset()
	feed.word(2, "block", def.position + Vector2(50, -250), 7.0)
	feed.word(2, "miss", def.position + Vector2(-20, -330))
	feed.word(1, "immune", att.position + Vector2(40, -290))
	feed.word(1, "just_guard", att.position + Vector2(0, -330))
	await _frames(6)
	await _save("words_all_a")
	feed.reset()
	feed.word(2, "guard_crush", def.position + Vector2(0, -330))
	feed.word(1, "block", att.position + Vector2(-50, -250), 12.0)
	await _frames(6)
	await _save("words_all_b")
	feed.reset()

func _warn() -> void:
	_stage(-170.0, 170.0)
	screen.training = false
	screen.timer_frames = 700
	await _frames(3)
	screen.timer_frames = 600
	await _frames(20)
	await _save("warn_time_0")
	await create_timer(0.7).timeout
	await _save("warn_time_1")
	await create_timer(0.9).timeout
	await _save("warn_time_2")
	feed.reset()
	_stage(-170.0, 170.0)
	await _frames(3)
	att.hp = att.max_hp * 0.2
	await _frames(25)
	await _save("warn_lowhp")
