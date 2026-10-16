extends SceneTree
## HUD: the combo feed, the hit and guard words, the banners and the WARNING watcher.
## Run: TEST=res://scripts/fight/tests/hud_feed_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real window, never headless)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

var checks := 0
var failures: Array = []
var game: Node
var screen: Node
var Feed: GDScript
var Banner: GDScript
var Num: GDScript
var Art: GDScript
var Words: GDScript
var M: GDScript
var att: Node
var def: Node
var host_t := 0.0
var host_b: RefCounted

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("HUD_FEED_CHECK FAIL ", label)
		failures.append(label)

func near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps

func _run() -> void:
	create_timer(170.0).timeout.connect(func() -> void:
		print("HUD_FEED_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	Feed = load("res://scripts/fight/hud_feed.gd")
	Banner = load("res://scripts/fight/hud_banner.gd")
	Num = load("res://scripts/ui/ba_numerals.gd")
	Art = load("res://scripts/ui/ba_art.gd")
	Words = load("res://scripts/ui/ba_words.gd")
	M = load("res://scripts/fight/movesets.gd")
	if Feed == null or Banner == null:
		print("HUD_FEED_TEST FAIL scripts did not load")
		quit(2)
		return
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	game.session.stage = {"id": "plate-test", "plate": "bg/BG_BunnyGirl_Collection.jpg"}     # the pixel counts need a plain backdrop, not the 3D arena
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	att = screen.f1
	def = screen.f2
	_banner_mapping()
	await _banner_timeline()
	_banner_lose_rule()
	_tiers()
	_guard_events()
	_feed_logic()
	_provenance()
	await _render()
	await _legacy_hud()
	print("HUD_FEED_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# banners: what each text fight_screen sends becomes
func _banner_mapping() -> void:
	var sent := {
		"ROUND 1": ["round", "round_1"], "ROUND 2": ["round", "round_2"], "ROUND 3": ["round", "round_3"], "FINAL ROUND": ["round", "final"],
		"TRAINING": ["round", "training"], "FIGHT!": ["fight", "fight"], "START!": ["start", "start"], "K.O.": ["ko", "ko"],
		"TIME UP": ["timeup", "time_up"], "HINA WINS": ["win", "win"], "DRAW": ["draw", "draw"], "WARNING": ["warning", "warning"],
		"ROUND 4": ["round", "round_4"], "ROUND 9": ["round", "round_9"], "ROUND 12": ["round", "round_9"],
	}
	for txt in sent:
		check(Banner.kind_of(txt) == sent[txt][0], "kind of " + txt)
		check(Banner.word_of(txt) == sent[txt][1], "word of " + txt)
		var t: Texture2D = Words.tex(sent[txt][1])
		check(t != null and t.get_width() > 100, "texture of " + sent[txt][1])
	check(Banner.word_of("HOSHINO WINS", true) == "lose", "a lost round shows LOSE")
	var seen := {}
	for n in ["round_1", "round_2", "round_3", "round_4", "round_5", "round_6", "round_7", "round_8", "round_9"]:
		seen[(Words.tex(n) as Texture2D).get_width()] = true
	check(seen.size() >= 2, "the round words are not one texture")

func _banner_timeline() -> void:
	var Motion: GDScript = load("res://scripts/ui/motion.gd")
	check(near(Motion.whip(7.0 / 60.0), 0.88, 0.005), "the whip covers 88 percent in 7 frames")
	var prev := -1.0
	var mono := true
	for i in 100:
		var v: float = Motion.whip(float(i) / 100.0)
		mono = mono and v >= prev
		prev = v
	check(mono and near(prev, 1.0, 0.001), "the whip never goes back and ends at 1")
	check(near(Motion.whip(0.0), 0.0) and Motion.whip(1.0) <= 1.0, "the whip does not overshoot")
	check(near(Banner.stamp_of(0.0), 1.5) and near(Banner.stamp_of(7.0 / 60.0), 1.1) and near(Banner.stamp_of(23.0 / 60.0), 1.0), "the stage-start stamp is 1.5, 1.1, 1.0")
	var shrinking := true
	var low := 99.0
	for i in 60:
		var k: float = Banner.result_of(float(i) / 60.0 * 0.8)
		shrinking = shrinking and k <= low + 0.0001
		low = minf(low, k)
	check(near(Banner.result_of(0.0), 2.0) and shrinking and low >= 1.0 and near(Banner.result_of(0.8), 1.0, 0.002), "WIN and LOSE shrink from 2.0 to 1.0 and never below it")
	check(near(Banner.flare_of(0.0), 0.0) and near(Banner.flare_of(5.0 / 60.0), 1.25) and near(Banner.flare_of(23.0 / 60.0), 1.0), "the start light pops to 1.25 and settles to 1")
	var host: Control = load("res://scripts/ui/painter.gd").new().setup(Vector2(1280, 720), func(c: Control) -> void: host_b.draw(c, host_t))
	root.add_child(host)
	for pair in [["FIGHT!", 0.9], ["START!", 0.9], ["ROUND 1", 0.98], ["K.O.", 1.6], ["TIME UP", 1.4], ["HINA WINS", 2.0], ["DRAW", 1.6], ["WARNING", 2.0]]:
		host_b = Banner.new()
		var txt: String = pair[0]
		var dur: float = pair[1]
		host_b.start(txt, "ROUND 1", Color.WHITE, dur, 10.0, 1)
		check(host_b.active and host_b.kind == Banner.kind_of(txt) and near(host_b.t0, 10.0) and near(host_b.dur, dur), "start sets " + txt)
		host_t = 10.0 + dur - 0.001
		host.queue_redraw()
		await process_frame
		await process_frame
		check(host_b.active, txt + " is live just before its dur")
		host_t = 10.0 + dur + 0.0001
		host.queue_redraw()
		await process_frame
		await process_frame
		check(not host_b.active, txt + " is gone at age == dur")
	host.queue_free()
	check(near(Banner.open_of(0.0, 0.98), 0.0) and near(Banner.open_of(Banner.OPEN, 0.98), 1.0) and near(Banner.open_of(0.98, 0.98), 0.0), "the band opens in 11 frames and is shut at dur")
	for dur in [0.9, 1.0, 1.5]:
		var last := -99999.0
		var up := true
		var steps := 200
		for i in steps + 1:
			var x: float = Banner.call_x(dur * float(i) / float(steps), dur)
			up = up and x >= last
			last = x
		check(up, "FIGHT! only moves forward over %.1f s" % dur)
		check(Banner.call_x(0.0, dur) < -1100.0 and Banner.call_x(dur, dur) > 1700.0, "FIGHT! enters from beyond the left and leaves beyond the right (%.1f s)" % dur)
		var hold: float = dur - Banner.CALL_IN - Banner.CALL_OUT
		check(absf(Banner.call_x(Banner.CALL_IN + hold * 0.5, dur)) < 1.0, "FIGHT! passes the centre in the middle of its hold (%.1f s)" % dur)

func _banner_lose_rule() -> void:
	var s = game.session
	s.players[1]["cpu"] = true
	var b: RefCounted = Banner.new()
	b.start("HOSHINO WINS", "", Color.WHITE, 2.0, 0.0, 2)
	check(b.word == "lose", "the cpu beating P1 shows LOSE")
	b.start("HINA WINS", "", Color.WHITE, 2.0, 0.0, 1)
	check(b.word == "win", "P1 beating the cpu shows WIN")
	s.players[1]["cpu"] = false
	b.start("HOSHINO WINS", "", Color.WHITE, 2.0, 0.0, 2)
	check(b.word == "win", "P2 beating P1 in versus shows WIN")
	s.players[1]["cpu"] = true

# feed: tiers, visibility, mirror
func _tiers() -> void:
	var T = Num.Tier
	check(Feed.hit_tier("light", 36.0) == T.NORMAL, "a light hit is NORMAL")
	check(Feed.hit_tier("heavy", 20.0) == T.WEAK and Feed.hit_tier("ex", 5.0) == T.WEAK, "heavy and EX are yellow")
	check(Feed.hit_tier("light", Feed.BIG) == T.WEAK and Feed.hit_tier("light", Feed.BIG - 0.1) == T.NORMAL, "55 damage is the edge of a big hit")
	check(Feed.hit_tier("light", 20.0, true) == T.EFFECTIVE, "a hit flagged counter is orange")
	check(Feed.hit_tier("heavy", 80.0, true) == T.WEAK, "a big flagged counter stays yellow")
	check(Feed.louder(T.NORMAL, T.WEAK) == T.WEAK and Feed.louder(T.WEAK, T.EFFECTIVE) == T.WEAK and Feed.louder(T.NORMAL, T.EFFECTIVE) == T.EFFECTIVE, "the loudest tier wins")
	check(near(Feed.fade_of(0.0), 1.0) and near(Feed.fade_of(1.7), 0.0) and near(Feed.fade_of(1.6), 0.35, 0.001) and near(Feed.fade_of(1.0), 1.0), "the old fade: full, then out over the last 0.29 s")

func _read(state: int, hitstop: int, hp: float, crush := 0, jg := false) -> Dictionary:
	return {"state": state, "hitstop": hitstop, "hp": hp, "max_hp": 1000.0, "crush": crush, "jg": jg}

func _guard_events() -> void:
	var S = load("res://scripts/fight/fighter.gd").S
	var idle := _read(S.IDLE, 0, 1000.0)
	var first: Array = Feed.guard_events(idle, _read(S.BLOCK, 4, 993.0))
	check(first == [["block", 7.0]], "a new block names the chip it took")
	check(Feed.guard_events(_read(S.BLOCK, 4, 993.0), _read(S.BLOCK, 3, 993.0)).is_empty(), "a block in progress says nothing")
	check(Feed.guard_events(_read(S.BLOCK, 1, 993.0), _read(S.BLOCK, 4, 986.0)) == [["block", 7.0]], "a second block inside the first is seen by its hitstop")
	check(Feed.guard_events(idle, _read(S.BLOCK, 4, 1000.0, 0, true)) == [["just_guard", 0.0]], "a just guard is its own word")
	check(Feed.guard_events(_read(S.BLOCK, 0, 1000.0), _read(S.BLOCK, 3, 1000.0, 0, true)) == [["just_guard", 0.0]], "a just guard inside a block is seen")
	var crush: Array = Feed.guard_events(_read(S.BLOCK, 0, 900.0), _read(S.BLOCK, 3, 890.0, 50))
	check(crush.size() == 2 and crush[1][0] == "guard_crush", "the crushing block gives BLOCK and GUARD CRUSH")
	check(Feed.guard_events(_read(S.BLOCK, 0, 900.0, 50), _read(S.BLOCK, 0, 900.0, 49)).is_empty(), "a crush already running says nothing")
	check(Feed.guard_events(idle, _read(S.HIT, 6, 960.0)).is_empty(), "a hit is not a block")
	var bare := Node.new()
	var r: Dictionary = Feed._read(bare)
	check(r["state"] == -1 and r["crush"] == 0 and not r["jg"] and r["hitstop"] == 0, "fields a fighter lacks read as nothing")
	check(Feed.guard_events(r, r).is_empty(), "a fighter without the fields raises nothing")
	bare.free()

func _make_feed() -> Control:
	var f: Control = Feed.new().setup(screen)
	f.visible = false
	screen.add_child(f)
	f.set_process(false)
	return f

func _combo_state(f: Control, i: int) -> Dictionary:
	return f._combo[i]

func _feed_logic() -> void:
	var f := _make_feed()
	def.combo_dmg = 36.0
	f.on_combo(att, def, 1)
	check(_combo_state(f, 0).is_empty(), "one hit shows nothing")
	def.combo_dmg = 72.0
	f.on_combo(att, def, 2)
	var cb := _combo_state(f, 0)
	check(not cb.is_empty() and cb["hits"] == 2 and near(cb["dmg"], 72.0), "two hits show the combo and its damage")
	check(_combo_state(f, 1).is_empty(), "the other side stays empty")
	var first: float = cb["first"]
	f._process(0.3)
	def.combo_dmg = 108.0
	f.on_combo(att, def, 3)
	cb = _combo_state(f, 0)
	check(near(float(cb["first"]), first) and near(float(cb["pop"]), f._time) and cb["hits"] == 3, "a longer combo keeps its first time and restarts the pop")
	f._process(1.69)
	check(not _combo_state(f, 0).is_empty(), "a combo is still there 1.69 s after its last hit")
	f._process(0.02)
	check(_combo_state(f, 0).is_empty(), "a combo is gone 1.71 s after its last hit")
	def.combo_dmg = 72.0
	f.on_combo(att, def, 2)
	f.on_combo(att, def, 1)
	check(_combo_state(f, 0).is_empty(), "a single hit clears the combo")
	f.on_combo(att, def, 5)
	f.reset()
	check(_combo_state(f, 0).is_empty() and f._words.is_empty(), "reset clears the feed")
	# the first display holds two hits, but only the second one counts toward its colour
	f.reset()
	def.combo_dmg = 30.0
	f.on_combo(att, def, 1, {"spark": "light"})
	def.combo_dmg = 60.0
	f.on_combo(att, def, 2, {"spark": "light"})
	check(_combo_state(f, 0)["tier"] == Num.Tier.NORMAL, "two 30 damage light hits start the combo white, not yellow")
	def.combo_dmg = 120.0
	f.on_combo(att, def, 3, {"spark": "light"})
	check(_combo_state(f, 0)["tier"] == Num.Tier.WEAK, "a 60 damage third hit is a big hit and turns it yellow")
	f.reset()
	# tiers over a real attacker: a heavy move keeps the combo yellow after a light poke
	att.move = {"hit": {"spark": "heavy"}}
	def.combo_dmg = 40.0
	f.on_combo(att, def, 2)
	check(_combo_state(f, 0)["tier"] == Num.Tier.WEAK, "the attacker's heavy move makes the combo yellow")
	att.move = {"hit": {"spark": "light"}}
	def.combo_dmg = 50.0
	f.on_combo(att, def, 3, {"spark": "light"})
	check(_combo_state(f, 0)["tier"] == Num.Tier.WEAK, "a later light hit does not quiet the combo")
	f.reset()
	def.combo_dmg = 40.0
	f.on_combo(att, def, 2, {"counter": true})
	check(_combo_state(f, 0)["tier"] == Num.Tier.EFFECTIVE, "a hit dict flagged counter makes the combo orange (no engine hit carries the flag yet)")
	att.move = {}
	f.reset()
	# mirror
	check(near(f._row_x(true, 200.0, 0.0), Feed.EDGE) and near(f._row_x(false, 200.0, 0.0) + 200.0, 1280.0 - Feed.EDGE), "the two sides are mirrored about the centre")
	check(f._slide(0, f._time) < -250.0 and f._slide(1, f._time) > 250.0 and near(f._slide(0, f._time - 5.0), 0.0, 0.5), "the sides slide in from opposite edges and settle")
	# words: one live word per slot and id; chip goes to the attacker's feed
	f.word(2, "block", def.position, 7.0)
	f.word(2, "block", def.position, 5.0)
	check(f._words.size() == 1 and f._words[0]["chip"] == 5, "a repeated word restarts instead of stacking")
	check(near(float(f._chip[0]["dmg"]), 12.0) and f._chip[1].is_empty(), "chip adds up on the attacker's side (slot 2 defends, P1 attacks)")
	f.word(1, "block", att.position, 3.0)
	check(f._words.size() == 2 and near(float(f._chip[1]["dmg"]), 3.0), "the other defender has its own word and chip")
	f.word(2, "miss", def.position)
	f.word(2, "bogus", def.position)
	check(f._words.size() == 3, "an unknown word is ignored")
	f._process(Feed.HOLD + 0.05)
	check(f._chip[0].is_empty() and f._words.is_empty(), "chip and words expire")
	f.word(2, "block", def.position, 4.0)
	check(near(float(f._chip[0]["dmg"]), 4.0), "chip starts again after the old one expired")
	# world position to screen: the same point the fighter's own node is drawn at
	screen._apply_camera()
	var p: Vector2 = f._screen(att.position)
	var at: Vector2 = att.get_global_transform().origin
	check(near(p.x, at.x, 0.5) and near(p.y, at.y, 0.5), "a world position lands where the fighter is drawn")
	var root_node: Node2D = screen.world_root
	var keep_s := root_node.scale
	var keep_p := root_node.position
	root_node.scale = keep_s * 0.8
	root_node.position = keep_p + Vector2(37.0, -11.0)
	at = att.get_global_transform().origin
	p = f._screen(att.position)
	check(near(p.x, at.x, 0.5) and near(p.y, at.y, 0.5), "the word follows a camera that zooms and moves")
	root_node.scale = keep_s
	root_node.position = keep_p
	check(f._screen(Vector2(-99999, -99999)).is_equal_approx(Vector2(90, 200)), "a word far off screen is held at the edge")
	# WARNING: the clock and low hp, read from the world
	screen.training = false
	screen.phase = "fight"
	screen.timer_frames = 700
	f._process(0.016)
	check(not f._warn.active, "no warning at 700 frames")
	screen.timer_frames = 600
	f._process(0.016)
	check(f._warn.active and f._warn.side == 0 and near(f._warn.dur, 2.0), "the last 10 seconds raise a full-width WARNING")
	f._warn.active = false
	screen.timer_frames = 599
	f._process(0.016)
	check(not f._warn.active, "the 10 second warning fires once")
	screen.training = true
	f.reset()
	screen.timer_frames = 700
	f._process(0.016)
	screen.timer_frames = 600
	f._process(0.016)
	check(not f._warn.active, "training has no clock warning")
	screen.training = false
	def.hp = def.max_hp
	f._process(0.016)
	def.hp = def.max_hp * 0.3
	f._process(0.016)
	check(not f._warn.active, "30 percent hp is not low")
	def.hp = def.max_hp * 0.24
	f._process(0.016)
	check(f._warn.active and f._warn.side == 2, "a fighter under 25 percent raises WARNING over his half")
	f._warn.active = false
	def.hp = def.max_hp * 0.2
	f._process(0.016)
	def.hp = def.max_hp
	f._process(0.016)
	def.hp = def.max_hp * 0.2
	f._process(0.016)
	check(not f._warn.active, "low hp warns once a round")
	def.hp = def.max_hp
	att.hp = att.max_hp
	screen.timer_frames = 3600
	f.reset()
	f._process(0.016)
	att.hp = att.max_hp * 0.1
	f._process(0.016)
	check(f._warn.active and f._warn.side == 1, "P1 low on hp warns over P1's half")
	# one WARNING at a time: the 10 second one waits for a live low hp band instead of restarting it
	att.hp = att.max_hp
	f.reset()
	screen.timer_frames = 700
	f._process(0.016)
	def.hp = def.max_hp * 0.2
	f._process(0.016)
	var t0: float = f._warn.t0
	f._process(1.0)
	screen.timer_frames = 600
	f._process(0.016)
	check(f._warn.active and f._warn.side == 2 and near(f._warn.t0, t0), "the 10 second WARNING does not restart a live low hp band")
	f._warn.active = false
	f._process(0.016)
	check(f._warn.active and f._warn.side == 0, "and runs when the band is free")
	# the band steps back over a side that has a combo or chip row up, and returns when it is gone
	f._warn.side = 1
	def.combo_dmg = 40.0
	f.on_combo(att, def, 3)
	f._process(0.016)
	f._process(0.5)
	check(near(f._warn.gain, Feed.WARN_CALM, 0.001), "a combo on the warned side dims the WARNING (%.2f)" % f._warn.gain)
	f._warn.side = 2
	f._process(0.5)
	check(near(f._warn.gain, 1.0, 0.001), "a combo on the other side leaves it alone")
	# the chip row eases to its rest when the combo above it ends, with no jump
	f.reset()
	f._warn.active = false
	f.on_combo(att, def, 2)
	for i in 5:
		f._process(0.016)
	f.word(2, "block", def.position, 7.0)
	f._process(0.016)
	check(near(float(f._chip_y[0]), Feed.ROW_Y + 52.0, 0.5), "a chip row sits under a live combo")
	f.on_combo(att, def, 1)
	f._process(0.016)
	check(absf(float(f._chip_y[0]) - (Feed.ROW_Y + 52.0)) < 40.0, "a single hit that clears the combo does not teleport the chip row (%.0f)" % float(f._chip_y[0]))
	f._process(0.5)
	check(near(float(f._chip_y[0]), Feed.TOP + 8.0, 0.5), "it settles at the top")
	att.hp = att.max_hp
	def.hp = def.max_hp
	screen.phase = "ko"
	f._process(0.016)
	check(not f._warn.active, "a WARNING does not run under the K.O. banner")
	screen.phase = "fight"
	att.hp = att.max_hp
	f._warn.active = false
	screen.phase = "intro"
	f._process(0.016)
	check(f._warned.is_empty(), "the intro phase clears the feed")
	screen.phase = "fight"
	screen.timer_frames = 3600
	f.queue_free()

func _provenance() -> void:
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ba/hud/PROVENANCE.json"))
	var listed := {}
	for e in prov["files"]:
		listed[str(e["runtime_path"])] = true
	for n in ["time_up", "draw", "training", "round_4", "round_5", "round_6", "round_7", "round_8", "round_9"]:
		var t: Texture2D = Words.tex(n)
		check(t != null and t.get_width() > 100, "baked word " + n + " loads")
		check(listed.has("assets/ba/hud/words/" + n + ".png"), "provenance lists " + n)
	check(Art.warnings().is_empty(), "no BaArt warnings: " + str(Art.warnings()))

## A combo of n hits built the way the game builds one: each hit adds its damage to the defender's total.
func _ramp(feed: Control, a: Node, d: Node, n: int, per: float, spark: String) -> void:
	d.combo_dmg = 0.0
	for hits in range(1, n + 1):
		d.combo_dmg += per
		feed.on_combo(a, d, hits, {"spark": spark})

# pixels
func _shot() -> Image:
	for i in 4:
		await process_frame
	var img := root.get_texture().get_image()
	if img.get_width() != 1280:
		img.resize(1280, 720, Image.INTERPOLATE_NEAREST)
	return img

## Count the pixels in rect that pass test(color).
func _count(img: Image, r: Rect2i, test: Callable) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			if test.call(img.get_pixel(x, y)):
				n += 1
	return n

func _diff(a: Image, b: Image, r: Rect2i) -> float:
	var sum := 0.0
	for y in range(r.position.y, r.end.y, 3):
		for x in range(r.position.x, r.end.x, 3):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			sum += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
	return sum

func _render() -> void:
	screen.hud.visible = false
	var s: GDScript = att.get_script()
	for f in [att, def]:
		f._set_state(s.S.IDLE)
		f.hitstop = 0
		f.invuln = 0
		f.hp = f.max_hp
	att.position = Vector2(-170.0, 560.0)
	def.position = Vector2(170.0, 560.0)
	for i in 40:
		screen._apply_camera()
	var feed: Control = Feed.new().setup(screen)
	feed.z_index = 99
	screen.add_child(feed)
	var base := await _shot()
	await create_timer(0.4).timeout
	var base2 := await _shot()
	var yellow := func(c: Color) -> bool: return c.r > 0.85 and c.g > 0.7 and c.b < 0.35
	var red := func(c: Color) -> bool: return c.r > 0.7 and c.g < 0.3 and c.b < 0.3
	var left := Rect2i(0, 160, 320, 160)
	var right := Rect2i(960, 160, 320, 160)
	var sky := Rect2i(600, 140, 350, 160)
	var noise_l := _diff(base, base2, left)
	var noise_r := _diff(base, base2, right)
	var noise_s := _diff(base, base2, sky)
	# 9 hits: no starburst; 10: the starburst; P1 draws on the left only
	_ramp(feed, att, def, 9, 20.0, "light")
	await create_timer(0.7).timeout
	var nine := await _shot()
	var dl := _diff(base, nine, left)
	var dr := _diff(base, nine, right)
	check(dl > noise_l + 700.0, "P1's combo draws on the left (%.0f over noise %.0f)" % [dl, noise_l])
	check(dr < noise_r + 250.0, "and nothing on the right (%.0f over noise %.0f)" % [dr, noise_r])
	var burst9 := _count(nine, left, red)
	check(burst9 < 40, "9 hits have no starburst (%d red)" % burst9)
	_ramp(feed, att, def, 10, 20.0, "light")
	await create_timer(0.7).timeout
	var ten := await _shot()
	var burst10 := _count(ten, left, red)
	check(burst10 > burst9 + 150, "10 hits put a starburst behind the numeral (%d red)" % burst10)
	var y_light := _count(ten, left, yellow)
	check(y_light < 20, "light hits are not yellow (%d)" % y_light)
	# tiers on the pixels
	feed.reset()
	_ramp(feed, att, def, 5, 20.0, "heavy")
	await create_timer(0.7).timeout
	var heavy := await _shot()
	var y_heavy := _count(heavy, left, yellow)
	check(y_heavy > y_light + 60, "a heavy hit makes the numeral yellow (%d)" % y_heavy)
	# P2 mirrors to the right
	feed.reset()
	_ramp(feed, def, att, 5, 20.0, "light")
	await create_timer(0.7).timeout
	var p2 := await _shot()
	var p2r := _diff(base, p2, right)
	var p2l := _diff(base, p2, left)
	check(p2r > noise_r + 700.0 and p2l < noise_l + 250.0, "P2's combo draws on the right only (%.0f right, %.0f left)" % [p2r, p2l])
	feed.reset()
	# a real block through the watcher: the word and the chip
	def.guard_all = true
	await process_frame
	var h: Dictionary = M.H(Rect2(), 60.0, 12, 10, 4.0, {"hitstop": 0, "chip": 0.2})
	def.receive_hit(att, h, att.position, false)
	await create_timer(0.2).timeout     # the word's rise takes 0.12 s
	check(feed._words.size() == 1 and feed._words[0]["id"] == "block" and feed._words[0]["slot"] == 2, "a real block raises a BLOCK word over the defender")
	check(feed._words.size() == 1 and feed._words[0]["chip"] == 12, "with the chip the guard let through")
	check(not feed._chip[0].is_empty() and near(float(feed._chip[0]["dmg"]), 12.0), "and the chip on the attacker's side")
	check(near(def.hp, def.max_hp - 12.0, 0.01), "the engine took the same 12")
	var blocked := await _shot()
	var d_word := _diff(base, blocked, Rect2i(560, 230, 340, 130))
	check(d_word > 600.0, "the word is on screen over the defender (%.0f)" % d_word)
	def.guard_all = false
	feed.reset()
	def.hp = def.max_hp
	# banners on the pixels
	var host: Control = load("res://scripts/ui/painter.gd").new().setup(Vector2(1280, 720), Callable())
	var b: RefCounted = Banner.new()
	host_b = b
	host.painter = func(c: Control) -> void: host_b.draw(c, host_t)
	host.z_index = 100
	screen.add_child(host)
	b.start("K.O.", "", Color.WHITE, 1.6, 0.0)
	host_t = 0.6
	host.queue_redraw()
	var ko := await _shot()
	check(_count(ko, Rect2i(380, 270, 90, 60), red) > 300, "K.O. puts a red starburst behind the word")
	check(host.get_child_count() == 1 and host.get_child(0).material is CanvasItemMaterial and (host.get_child(0).material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "the blue streak is drawn by one additive child")
	var d_line := _diff(base, ko, Rect2i(0, 290, 300, 32)) + _diff(base, ko, Rect2i(980, 290, 300, 32))
	check(d_line > 150.0, "the blue streak crosses the whole screen (%.0f)" % d_line)
	host_t = 1.7
	host.queue_redraw()
	var gone := await _shot()
	var d_gone := _diff(base, gone, sky)
	check(not b.active and d_gone < noise_s + 250.0, "after dur K.O. leaves nothing, not even its light (%.0f over noise %.0f)" % [d_gone, noise_s])
	b.start("FIGHT!", "", Color.WHITE, 0.9, 0.0)
	host_t = 0.4
	host.queue_redraw()
	var fight := await _shot()
	check(_count(fight, Rect2i(380, 250, 520, 110), yellow) > 120, "FIGHT! is the yellow and orange image font")
	var dark_base := _count(base, Rect2i(0, 0, 200, 200), func(c: Color) -> bool: return c.v < 0.4)
	var dark_fight := _count(fight, Rect2i(0, 0, 200, 200), func(c: Color) -> bool: return c.v < 0.4)
	check(dark_fight > dark_base + 100, "the stage dims behind FIGHT!")
	b.start("WARNING", "", Color.WHITE, 2.0, 0.0)
	host_t = 1.0
	host.queue_redraw()
	var warn := await _shot()
	check(_count(warn, Rect2i(0, 230, 1280, 18), red) > 300, "WARNING draws the hazard strips")
	b.gain = Feed.WARN_CALM
	host.queue_redraw()
	var calm := await _shot()
	check(_count(calm, Rect2i(0, 230, 1280, 18), red) < _count(warn, Rect2i(0, 230, 1280, 18), red) / 2, "a dimmed WARNING draws less of its strips")
	b.gain = 1.0
	var ribbon := Rect2i(380, 180, 520, 76)
	b.start("HOSHINO WINS", "ROUND 1", Color.WHITE, 2.0, 0.0, 1)
	host_t = 1.0
	host.queue_redraw()
	var won := await _shot()
	b.start("HOSHINO WINS", "ROUND 1", Color.WHITE, 2.0, 0.0, 2)
	host.queue_redraw()
	var lost := await _shot()
	var dark := func(c: Color) -> bool: return c.v < 0.4
	check(b.word == "lose" and _count(won, ribbon, dark) > _count(lost, ribbon, dark) * 2, "a lost round shows LOSE without the winner's name ribbon")
	b.start("ROUND 2", "", Color.WHITE, 0.98, 0.0)
	host_t = 0.5
	host.queue_redraw()
	var rnd := await _shot()
	check(_count(rnd, Rect2i(40, 270, 300, 70), func(c: Color) -> bool: return c.b > 0.7 and c.r < 0.2) > 800, "ROUND n sits in the blue stage-start band")
	b.start("K.O.", "", Color.WHITE, 1.6, 0.0)
	host_t = 0.6
	host.queue_redraw()
	await _shot()
	check(not b._glow_items.is_empty(), "K.O. has light to draw")
	b.active = false
	host.queue_redraw()
	await _shot()
	check(b._glow_items.is_empty(), "a banner stopped from outside takes its light with it")
	host.queue_free()
	feed.queue_free()
	await process_frame

# the unchanged FightHud still drives the new banner
func _legacy_hud() -> void:
	var hud: Control = screen.hud
	hud.visible = true
	for pair in [["ROUND 1", 0.98], ["FINAL ROUND", 0.98], ["TRAINING", 0.98], ["FIGHT!", 0.9], ["K.O.", 1.6], ["TIME UP", 1.4], ["HINA WINS", 2.0], ["DRAW", 1.6]]:
		hud.banner(pair[0], "ROUND 2", Color.WHITE, pair[1])
		var b = hud._banner
		check(b.active and b.kind != "" and near(b.dur, pair[1]), "FightHud.banner starts " + pair[0])
		var win: int = b.slot
		check(win == (1 if pair[0] == "HINA WINS" else 0), "FightHud passes the winner slot for " + pair[0])
		for i in 3:
			await process_frame
		check(b.active and hud._time - float(b.t0) < float(pair[1]), pair[0] + " is still on screen")
	hud.banner("FIGHT!", "", Color.WHITE, 0.9)
	await create_timer(1.0).timeout
	check(not hud._banner.active, "FIGHT! is over inside the old 0.9 s budget")
