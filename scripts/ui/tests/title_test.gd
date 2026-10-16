extends SceneTree
## The title ("Start Game") screen: which screen a launch opens, the random film, what starts the game and what does not,
## Reduce Flashes, the layout, and the art files with their provenance.
## Run: TEST=res://scripts/ui/tests/title_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

class StubTransition extends Node:
	var styles: Array = []
	func play(style: String, _opts: Dictionary, on_cover: Callable) -> void:
		if style != "cut":
			styles.append(style)
		on_cover.call()

const DT := 1.0 / 60.0
const DIR := "res://assets/ba/title/"

var checks := 0
var failures: Array = []
var game: Node
var stub: StubTransition
var real_transition: Node
var T: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("TITLE_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("TITLE_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	game = root.get_node("Game")
	T = load("res://scripts/screens/title_screen.gd")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	real_transition = game.transition
	stub = StubTransition.new()
	root.add_child(stub)
	game.transition = stub
	var reduce: bool = game.session.reduce_flashes
	game.session.reduce_flashes = false
	_boot()
	_pick()
	await _flow()
	await _flashes()
	await _layout()
	await _credits()
	_assets()
	await _pixels()
	game.session.reduce_flashes = reduce
	game.transition = real_transition
	print("TITLE_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _open(screen_name: String) -> Node:
	stub.styles.clear()
	await game.go(screen_name, {}, "cut")
	var scr: Node = game.current()
	scr.set_process(false)
	return scr

func _tick_to(scr: Node, secs: float) -> void:
	while float(scr.probe()["t"]) < secs - 0.0001:
		scr._process(DT)

func _key(code: Key, ctrl := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	return ev

# ── which screen a launch opens ──────────────────────────────────────────────
func _boot() -> void:
	var dbg: Node = root.get_node("Dbg")
	var saved_screen: String = dbg.start_screen
	var saved_script: String = dbg._script_path
	dbg.start_screen = ""
	dbg._script_path = ""
	check(dbg.boot_screen(true) == "title", "the game launched as itself opens the title")
	check(dbg.boot_screen(false) == "menu", "a test that adds main.tscn under the root stays on the menu")
	dbg._script_path = "steps.json"
	check(dbg.boot_screen(true) == "menu", "a step file starts on the menu")
	dbg.start_screen = "select"
	check(dbg.boot_screen(true) == "select", "--screen wins")
	dbg.start_screen = saved_screen
	dbg._script_path = saved_script
	check(game.SCREEN_PATHS.has("title"), "the router knows the title")

# ── the random film ──────────────────────────────────────────────────────────
func _pick() -> void:
	var avail: Array = T.available_films()
	check(avail.size() == 8, "all eight films are in the build (%d)" % avail.size())
	check(T.pick_film(["a", "b", "c"], "b", 0.0) == "a" and T.pick_film(["a", "b", "c"], "b", 0.99) == "c", "the roll spans the films but the last one")
	var never_last := true
	for i in 101:
		never_last = never_last and T.pick_film(avail, "5th", float(i) / 100.0) != "5th"
	check(never_last, "the film shown last is never picked while others exist")
	var seen := {}
	for i in 101:
		seen[T.pick_film(avail, "", float(i) / 100.0)] = true
	check(seen.size() == avail.size(), "every film can be picked (%d of %d)" % [seen.size(), avail.size()])
	check(T.pick_film(["only"], "only", 0.5) == "only" and T.pick_film([], "x", 0.5) == "", "one film repeats, none gives an empty pick")

# ── what starts the game ─────────────────────────────────────────────────────
func _flow() -> void:
	T._last_film = ""
	var scr: Node = await _open("title")
	check(game.current_name() == "title", "go(title) opens the title")
	var first: String = scr.probe()["film"]
	check(first != "" and first in T.FILMS and T._last_film == first, "a film is picked and remembered (%s)" % first)
	scr.on_action("kb1", "confirm")
	check(not scr.probe()["going"], "a press in the first 0.6 s is ignored")
	_tick_to(scr, 0.7)
	for act in ["up", "down", "left", "right", "back"]:
		scr.on_action("kb1", act)
	scr._input(_key(KEY_ESCAPE))
	scr._input(_key(KEY_SHIFT))
	scr._input(_key(KEY_TAB, true))
	var move := InputEventMouseMotion.new()
	scr._input(move)
	check(not scr.probe()["going"] and stub.styles.is_empty(), "directions, back, Esc, Shift, Ctrl combos and mouse movement do nothing")
	scr.on_action("kb1", "confirm")
	scr._input(_key(KEY_K))
	scr.on_action("pad0", "start")
	check(scr.probe()["going"] and stub.styles == ["fade"], "a press starts the game once, with a fade (%s)" % str(stub.styles))
	for i in 20:
		await process_frame
	check(game.current_name() == "menu" and game.stack.size() == 1, "the menu is open on its own, nothing pushed over it")
	# each way in
	var seen_films := [first]
	for way in ["any key", "a pad button", "a left click", "the start action"]:
		scr = await _open("title")
		seen_films.append(scr.probe()["film"])
		_tick_to(scr, 0.7)
		_press(scr, way)
		check(scr.probe()["going"], "%s starts the game" % way)
	check(seen_films[1] != seen_films[0] and seen_films[2] != seen_films[1] and seen_films[3] != seen_films[2], "each visit shows another film (%s)" % str(seen_films))
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	scr = await _open("title")
	_tick_to(scr, 0.7)
	scr._input(right_click)
	check(not scr.probe()["going"], "a right click does nothing")
	scr = await _open("title")
	_tick_to(scr, 0.7)
	scr.covered = true
	scr.on_action("kb1", "confirm")
	check(not scr.probe()["going"], "a covered title does not react")

func _press(scr: Node, way: String) -> void:
	match way:
		"any key":
			scr._input(_key(KEY_Z))
		"a pad button":
			var jb := InputEventJoypadButton.new()
			jb.button_index = JOY_BUTTON_A
			jb.pressed = true
			scr._input(jb)
		"a left click":
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = true
			scr._input(mb)
		_:
			scr.on_action("kb2", "start")

# ── Reduce Flashes ───────────────────────────────────────────────────────────
func _flashes() -> void:
	var scr: Node = await _open("title")
	var lo := 9.0
	var hi := 0.0
	for i in 220:
		scr._process(DT * 1.6)
		if float(scr.probe()["t"]) > 1.8:
			var a: float = scr.prompt_alpha()
			lo = minf(lo, a)
			hi = maxf(hi, a)
	check(lo >= 0.55 - 0.01 and hi <= 1.0 and hi - lo > 0.3, "the prompt pulses between 0.55 and 1 (%.2f to %.2f)" % [lo, hi])
	check(scr._flash == 0.0, "the entrance flash has faded")
	game.session.reduce_flashes = true
	scr = await _open("title")
	check(scr.probe()["film"] == "" and not scr.probe()["playing"], "with Reduce Flashes no film plays, the still stays")
	check(scr._flash == 0.0, "and there is no white flash")
	var vals := []
	for i in 120:
		scr._process(DT * 3.0)
		if float(scr.probe()["t"]) > 1.8:
			vals.append(scr.prompt_alpha())
	check(vals.size() > 10 and vals.all(func(v: float) -> bool: return is_equal_approx(v, vals[0])), "the prompt holds steady")
	game.session.reduce_flashes = false

# ── layout ───────────────────────────────────────────────────────────────────
func _layout() -> void:
	var scr: Node = await _open("title")
	_tick_to(scr, 2.5)
	var p: Dictionary = scr.probe()
	var safe := Rect2(16, 16, 1248, 688)
	for k in ["logo", "letters", "tentative", "prompt", "footer", "credits_button"]:
		check(safe.encloses(p[k]), "%s sits inside the 16 px margin (%s)" % [k, p[k]])
	var names := ["logo", "letters", "tentative", "prompt"]
	for i in names.size():
		for j in range(i + 1, names.size()):
			check(not (p[names[i]] as Rect2).intersects(p[names[j]]), "%s and %s do not overlap" % [names[i], names[j]])
	check(absf((p["logo"] as Rect2).get_center().x - 640.0) < 1.0 and absf((p["letters"] as Rect2).get_center().x - 640.0) < 1.0
			and absf((p["tentative"] as Rect2).get_center().x - 640.0) < 1.0 and absf((p["prompt"] as Rect2).get_center().x - 640.0) < 1.0, "logo, lettering, working title and prompt share the centre line")
	check((p["tentative"] as Rect2).position.y >= (p["letters"] as Rect2).end.y, "the working title sits under the lettering")
	check((p["footer"] as Rect2).position.y > (p["prompt"] as Rect2).end.y, "the fine print sits under the prompt")
	check((p["footer"] as Rect2).end.x < (p["credits_button"] as Rect2).position.x - 8.0, "the fine print ends before the Credits button")
	check(52.0 + preload("res://scripts/ui/ba_menu.gd").text_width("Credits", 19, 800) + 3.0 + 12.0 <= (p["credits_button"] as Rect2).size.x, "the word Credits fits inside its plate with room on the right")
	check(not (p["credits_button"] as Rect2).intersects(p["prompt"]) and (p["credits_button"] as Rect2).end.x > 1200.0 and (p["credits_button"] as Rect2).end.y > 680.0, "the Credits button sits alone in the bottom right corner")

# ── the credits ──────────────────────────────────────────────────────────────
func _credits() -> void:
	var CP: GDScript = load("res://scripts/ui/credits_panel.gd")
	var text: String = CP.all_text()
	var md := FileAccess.get_file_as_string("res://CREDITS.md")
	for who in ["mattsumi", "NEXON Games", "Yostar", "Mitsukiyo", "Nor", "KARUT", "Kenney", "Godot", "Noto Sans", "Chakra Petch", "Barlow Condensed", "Orbitron", "BA-AX", "UnityPy", "SkelToJson", "FFmpeg", "Theora", "Blender"]:
		check(text.contains(who), "the credits name %s" % who)
	var urls: Array = CP.all_urls()
	var seen := {}
	for u in urls:
		check(String(u).begins_with("https://") and not seen.has(u), "%s is a https link, listed once" % u)
		seen[u] = true
		check(md.contains(u), "CREDITS.md lists %s" % u)
	for must in ["https://github.com/mattsumi", "https://bluearchive.nexon.com/", "https://x.com/en_BlueArchive", "https://kenney.nl", "https://godotengine.org"]:
		check(urls.has(must), "the links include %s" % must)
	# opening and closing
	var opened: Array = []
	CP.opener = func(u: String) -> void: opened.append(u)
	var scr: Node = await _open("title")
	_tick_to(scr, 0.7)
	check(not scr.probe()["credits_open"], "the title starts without the credits open")
	scr._input(_key(KEY_C))
	await process_frame
	check(scr.probe()["credits_open"] and not scr.probe()["going"], "C opens the credits and does not start the game")
	var cp: Node = scr._credits
	scr._input(_key(KEY_Z))
	scr.on_action("kb1", "confirm")
	scr.on_action("kb1", "start")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(300.0, 300.0)
	scr._input(click)
	check(not scr.probe()["going"] or stub.styles.is_empty(), "while the credits are open nothing starts the game")
	check(opened.size() == 1 and opened[0] == "https://github.com/mattsumi", "confirm opens the focused link, the first one first (%s)" % str(opened))
	var n: int = cp.probe()["links"]
	check(n == urls.size(), "every link has a row (%d)" % n)
	for i in n + 3:
		scr.on_action("kb1", "down")
	var pr: Dictionary = cp.probe()
	check(pr["focus"] == n - 1 and pr["url"] == urls[-1], "down stops on the last link")
	check(absf(float(pr["scroll"]) - maxf(float(pr["content"]) - (pr["body"] as Rect2).size.y, 0.0)) < 0.2, "and the list is scrolled to its end (%s of %s)" % [pr["scroll"], pr["content"]])
	for i in n + 3:
		scr.on_action("kb1", "up")
	check(cp.probe()["focus"] == 0 and float(cp.probe()["scroll"]) == 0.0, "up goes back to the first link and the top")
	# every link row is reachable on screen: the scroll that focus asks for keeps the row inside the body
	var view: float = (cp.probe()["body"] as Rect2).size.y
	var all_in := true
	var sc := 0.0
	for i in n:
		var row: Dictionary = cp._rows[cp._links[i]]
		sc = CP.scroll_for(row, sc, view, cp.probe()["content"], i == 0, i == n - 1)
		all_in = all_in and float(row["y"]) >= sc - 0.01 and float(row["y"]) + float(row["h"]) <= sc + view + 0.01
	check(all_in, "walking down keeps every focused link inside the list")
	check(not cp.open_url("http://example.com") and not cp.open_url("javascript:alert(1)") and not cp.open_url("file:///etc/passwd") and opened.size() == 1, "only https links open")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	cp._on_body_input(wheel)
	check(float(cp.probe()["scroll"]) > 0.0, "the wheel scrolls the list")
	check((cp.probe()["box"] as Rect2).intersects(Rect2(0, 0, 1280, 720)) and Rect2(0, 0, 1280, 720).encloses(cp.probe()["box"]), "the window sits on the screen")
	scr.on_action("kb1", "back")
	await process_frame
	check(not scr.probe()["credits_open"], "back closes it")
	# the other ways in and out
	scr.on_action("kb1", "aux2")
	await process_frame
	check(scr.probe()["credits_open"], "Y (aux2) opens the credits too")
	scr._credits._on_close_input(click)
	await process_frame
	check(not scr.probe()["credits_open"], "the X closes it")
	var on_button := InputEventMouseButton.new()
	on_button.button_index = MOUSE_BUTTON_LEFT
	on_button.pressed = true
	on_button.position = (scr.probe()["credits_button"] as Rect2).get_center()
	scr._input(on_button)
	await process_frame
	check(scr.probe()["credits_open"] and not scr.probe()["going"], "a click on the Credits button opens it and does not start the game")
	scr._credits._on_scrim_input(click)
	await process_frame
	check(not scr.probe()["credits_open"], "a click outside the window closes it")
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_Y
	jb.pressed = true
	scr._input(jb)
	await process_frame
	check(scr.probe()["credits_open"] and not scr.probe()["going"], "the pad's Y opens it")
	scr.on_action("pad0", "back")
	await process_frame
	scr._input(_key(KEY_Z))
	check(scr.probe()["going"], "after closing, any other key starts the game again")
	CP.opener = Callable()

# ── the art ──────────────────────────────────────────────────────────────────
func _assets() -> void:
	var logo: Texture2D = load(DIR + "Title_Logo.png")
	var letters: Texture2D = load(DIR + "Title_FightingGame.png")
	check(logo != null and logo.get_size() == Vector2(1024, 256), "the logo is BA's 1024x256 Title_Logo")
	check(letters != null and letters.get_width() > 1200 and float(letters.get_width()) / float(letters.get_height()) > 6.0, "the lettering is a wide strip drawn at 2x")
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "PROVENANCE.json"))
	var want: Array = ["Title_Logo.png", "Title_FightingGame.png"]
	for f in T.FILMS:
		want.append("video/%s.ogv" % f)
	for rel in want:
		check(prov.has(rel), "provenance entry for " + rel)
		if prov.has(rel):
			check(FileAccess.file_exists(DIR + rel) and FileAccess.get_sha256(DIR + rel) == prov[rel]["sha256"], "%s matches its recorded hash" % rel)
	for rel in prov:
		check(rel in want, "no stale provenance entry (%s)" % rel)
	for f in T.FILMS:
		var s := load(DIR + "video/%s.ogv" % f)
		check(s is VideoStreamTheora, "%s loads as a Theora stream" % f)

# ── pixels ───────────────────────────────────────────────────────────────────
func _pixels() -> void:
	game.session.reduce_flashes = true   # the still backdrop: the same pixels every run
	var scr: Node = await _open("title")
	_tick_to(scr, 2.5)
	for i in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / 1280.0   # the test window is smaller than the 1280x720 reference
	var p: Dictionary = scr.probe()
	var white := 0
	var pr: Rect2 = p["prompt"]
	for y in range(int(pr.position.y * k), int(pr.end.y * k)):
		for x in range(int(pr.position.x * k), int(pr.end.x * k)):
			if img.get_pixel(x, y).get_luminance() > 0.95:
				white += 1
	check(white > 150 * k * k, "the prompt draws white text on the screen (%d px at scale %.2f)" % [white, k])
	var lr: Rect2 = p["letters"]
	var cyan := 0
	for y in range(int(lr.position.y * k), int(lr.end.y * k)):
		for x in range(int(lr.position.x * k), int(lr.end.x * k)):
			var c := img.get_pixel(x, y)
			if c.b > 0.9 and c.g > 0.7 and c.r < 0.25:
				cyan += 1
	check(cyan > 300 * k * k, "the lettering draws its logo cyan (%d px)" % cyan)
	game.session.reduce_flashes = false
