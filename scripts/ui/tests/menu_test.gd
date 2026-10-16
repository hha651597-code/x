extends SceneTree
## The main menu, the controller-assign overlay and the options popup. Settings persistence (a scratch ConfigFile, never the
## player's), slider and toggle behaviour, sub-page navigation, the claim flow, entrance timing without overshoot, and that no
## label outgrows its plate. Run: TEST=res://scripts/ui/tests/menu_test.gd MAXLINES=200 zsh tools/sd_test.sh
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const SCRATCH := "user://s2_test_settings.cfg"

var checks := 0
var failures: Array = []
var game: Node
var controls: Node
var sfx: Node
var BT: GDScript
var SESS: GDScript
var MENU: GDScript
var KIT: GDScript
var OPT: GDScript
var BA_MENU: GDScript
var ASSIGN_PANEL: GDScript
var real_path := ""

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("MENU_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("MENU_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	BT = load("res://scripts/ui/ba_tokens.gd")
	SESS = load("res://scripts/core/session.gd")
	MENU = load("res://scripts/screens/menu_screen.gd")
	KIT = load("res://scripts/ui/screen_kit.gd")
	OPT = load("res://scripts/screens/options_screen.gd")
	BA_MENU = load("res://scripts/ui/ba_menu.gd")
	ASSIGN_PANEL = load("res://scripts/ui/assign_panel.gd")
	real_path = SESS.settings_path
	SESS.settings_path = SCRATCH
	_wipe_scratch()
	_settings()
	_assets()
	game = root.get_node("Game")
	controls = root.get_node("Controls")
	sfx = root.get_node("Sfx")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	await _menu_entrance()
	await _menu_flow()
	_menu_text()
	_menu_grid()
	_menu_soon()
	await _menu_soon_pixels()
	await _menu_student()
	await _options_flow()
	_options_text()
	_controls_page()
	await _assign_flow(2, "versus2p")
	await _assign_flow(1, "training")
	await _assign_return()
	_assign_text()
	_wipe_scratch()
	game.session.bgm_volume = 0.123
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(is_equal_approx(SESS.new().bgm_volume, 0.123), "closing the window saves the settings")
	SESS.settings_path = real_path
	check(real_path == SESS.REAL_PATH and not SESS._persists(), "a scripted run with the default path neither reads nor writes the real settings file")
	_wipe_scratch()
	print("MENU_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# ── helpers ──────────────────────────────────────────────────────────────────
func _wipe_scratch() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _press(dev: String, act: String) -> void:
	controls.inject(dev, act)
	await process_frame

func _screen() -> Node:
	return game.current()

func _mouse(screen: Node, pos: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.position = pos
	b.pressed = pressed
	screen._on_mouse(b)

# ── settings ─────────────────────────────────────────────────────────────────
func _settings() -> void:
	var a = SESS.new()
	check(a.reduce_flashes == false, "Reduce Flashes is off by default")
	check(is_equal_approx(a.bgm_volume, 0.7) and is_equal_approx(a.sfx_volume, 0.8), "volumes default to 0.7 and 0.8")
	a.reduce_flashes = true
	a.bgm_volume = 0.35
	a.sfx_volume = 0.55
	a.save_settings()
	var b = SESS.new()
	check(b.reduce_flashes == true, "Reduce Flashes survives a reload")
	check(is_equal_approx(b.bgm_volume, 0.35) and is_equal_approx(b.sfx_volume, 0.55), "both volumes survive a reload")
	b.begin("versus2p")
	b.reset()
	check(b.reduce_flashes == true and is_equal_approx(b.bgm_volume, 0.35), "begin and reset keep the options")
	var cf := ConfigFile.new()
	cf.set_value("audio", "bgm", 7.0)
	cf.set_value("audio", "sfx", -2.0)
	cf.set_value("access", "reduce_flashes", "false")
	cf.save(SCRATCH)
	var c = SESS.new()
	check(is_equal_approx(c.bgm_volume, 1.0) and is_equal_approx(c.sfx_volume, 0.0), "stored volumes are clamped")
	check(c.reduce_flashes == false, "a non-bool flag in the file reads as off")
	cf = ConfigFile.new()
	cf.set_value("audio", "bgm", [1, 2])
	cf.set_value("audio", "sfx", NAN)
	cf.set_value("access", "reduce_flashes", true)
	cf.save(SCRATCH)
	var e = SESS.new()
	check(is_equal_approx(e.bgm_volume, 0.7) and is_equal_approx(e.sfx_volume, 0.8), "an array or a NaN in the file leaves the default volumes")
	check(e.reduce_flashes == true, "and does not stop the flag after it from loading")
	_wipe_scratch()
	var d = SESS.new()
	check(d.reduce_flashes == false and is_equal_approx(d.bgm_volume, 0.7), "a missing file leaves the defaults")

func _assets() -> void:
	var f := FileAccess.open("res://assets/ba/ui/PROVENANCE.json", FileAccess.READ)
	check(f != null, "ui PROVENANCE exists")
	if f == null:
		return
	var prov: Dictionary = JSON.parse_string(f.get_as_text())
	check(prov["files"].size() == 3, "three extra sprites are tracked")
	for e in prov["files"]:
		var path: String = "res://" + str(e["runtime_path"])
		var bytes := FileAccess.get_file_as_bytes(path)
		check(bytes.size() == int(e["bytes"]), "size of " + path)
		check(FileAccess.get_sha256(path) == str(e["sha256"]), "sha256 of " + path)
		var img := Image.new()
		check(img.load_png_from_buffer(bytes) == OK and img.get_width() == int(e["width"]) and img.get_height() == int(e["height"]), "dimensions of " + path)

# ── menu ─────────────────────────────────────────────────────────────────────
func _menu_entrance() -> void:
	game.session.reset()
	await game.go("menu", {}, "cut")
	var m: Node = _screen()
	check(game.current_name() == "menu", "menu is up")
	var n: int = m._cards.size()
	var last_x := []
	var never_past := true
	var monotone := true
	for i in n:
		last_x.append(INF)
	var start_t: float = m._t
	var settled_at := -1.0
	while m._t < start_t + 1.6:
		await process_frame
		var all_home := true
		for i in n:
			var c: Dictionary = m._cards[i]
			var x: float = (c["holder"] as Control).position.x
			var home: float = (c["home"] as Vector2).x
			never_past = never_past and x >= home - 0.5
			monotone = monotone and x <= float(last_x[i]) + 0.5
			last_x[i] = x
			all_home = all_home and absf(x - home) < 0.5
		if all_home and settled_at < 0.0:
			settled_at = m._t
	check(never_past, "no tile ever passes its home position")
	check(monotone, "every tile only moves toward home")
	var delays := []
	for c in m._cards:
		delays.append(float(c["delay"]))
	delays.sort()
	var step_ok := true
	for i in range(1, delays.size()):
		var step: float = delays[i] - delays[i - 1]
		step_ok = step_ok and step >= 1.0 / 60.0 - 0.0001 and step <= 3.0 / 60.0 + 0.0001
	check(step_ok, "tiles start one to three frames apart")
	var last_delay: float = delays[delays.size() - 1]
	check(settled_at > 0.0 and settled_at <= last_delay + 0.55 + 0.05, "the last tile is home about 0.5 s after it starts (%.2f, last start %.2f)" % [settled_at, last_delay])
	var first_whole: float = delays[0] + BT.WHIP_FAST + BT.WHIP_SETTLE
	check(is_equal_approx(first_whole, delays[0] + 32.0 / 60.0), "one tile travels in 32 frames")
	for i in n:
		var holder: Control = m._cards[i]["holder"]
		check(holder.modulate.a >= 0.99, "tile %d is opaque once settled (no fade)" % i)

func _menu_flow() -> void:
	var m: Node = _screen()
	check(m.probe()["selected"] == "versus2p", "menu starts on Versus 2P")
	await _press("kb1", "down")
	check(m.probe()["selected"] == "versuscpu", "down from Versus 2P is Versus CPU")
	await _press("kb1", "left")
	check(m.probe()["selected"] == "story", "left from Versus CPU is Story")
	await _press("kb1", "down")
	var below: String = m.probe()["selected"]
	check(below in ["single", "extras", "options"], "down from Story is a small tile (%s)" % below)
	await _press("kb1", "right")
	check(m.probe()["selected"] == "training", "right from the small tiles is Training Mode")
	await _press("kb1", "right")
	check(m.probe()["selected"] == "network", "right from Training Mode is Network")
	check(m.probe()["caption"] == MENU.MODES[7]["caption"], "the caption follows the selection")
	await create_timer(0.8).timeout
	for i in m._cards.size():
		var sel: bool = i == 7
		var mod: Color = (m._cards[i]["holder"] as Control).modulate
		var soon: float = MENU.SOON_DIM if m._cards[i]["mode"]["id"] in MENU.COMING_SOON else 1.0
		check(absf(mod.r - (1.0 if sel else 0.85) * soon) < 0.01, "tile %d is %s%s" % [i, "full" if sel else "multiplied by 0.85", " and dimmed for COMING SOON" if soon < 1.0 else ""])
	for c in m._cards:
		var card = c["card"]
		check(is_equal_approx(float(card.get_param("gloss")), 0.0), "no gloss on " + str(c["mode"]["id"]))
		check(is_equal_approx(float(card.get_param("shadow_amt")), BT.SHADOW_A), "shadow token on " + str(c["mode"]["id"]))
		check(not card.highlighted, "no yellow card border on " + str(c["mode"]["id"]))
	check(float(m._bd_mat.get_shader_parameter("radius")) <= 0.004, "the backdrop is blurred lightly")
	check(is_equal_approx(sfx.volume_sfx, game.session.sfx_volume), "the menu applies the saved SFX volume")
	await _press("kb1", "confirm")
	check(game.current_name() == "menu" and m._toast_t > 0.0, "Network shows the Coming soon toast and stays")
	m._select(5, false)
	await _press("kb1", "confirm")
	await _frames(2)
	check(game.current_name() == "options", "Options pushes the options popup")
	game.pop()
	await _frames(2)
	check(game.current_name() == "menu", "closing options returns to the menu")

## The tiles that do nothing yet carry a COMING SOON ribbon inside the tile and clear of the label strip.
func _menu_soon() -> void:
	var ids := []
	for m in MENU.MODES:
		ids.append(m["id"])
	for id in MENU.COMING_SOON:
		check(id in ids, "COMING_SOON names a real tile (%s)" % id)
	var marked := 0
	for m in MENU.MODES:
		if not m["id"] in MENU.COMING_SOON:
			continue
		marked += 1
		var tile := Rect2(Vector2.ZERO, (m["rect"] as Rect2).size)
		var ribbon: Rect2 = MENU.soon_rect(m)
		check(tile.encloses(ribbon), "%s: the COMING SOON ribbon sits inside its tile (%s in %s)" % [m["id"], ribbon, tile])
		check(not ribbon.intersects(MENU.label_rect(m)), "%s: the ribbon clears the label strip" % m["id"])
		check(ribbon.size.x >= BA_MENU.text_width("COMING SOON", int(ribbon.size.y * 0.58)) + 16.0, "%s: the ribbon is wide enough for its words" % m["id"])
	check(marked == MENU.COMING_SOON.size() and marked >= 2, "every COMING_SOON tile is marked (%d)" % marked)

## The ribbon is really drawn: its navy end shows on the tile, and only on the COMING SOON tiles.
func _menu_soon_pixels() -> void:
	var m: Node = _screen()
	await create_timer(0.6).timeout   # the options overlay just closed: let the tiles come back to full
	var img := root.get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / 1280.0
	for c in m._cards:
		var mode: Dictionary = c["mode"]
		var r: Rect2 = MENU.soon_rect(mode)
		var lum := 1.0
		for dx in [8.0, 12.0, 16.0, 20.0, 24.0, 28.0]:   # along the ribbon's left padding, clear of its words
			var at: Vector2 = ((c["holder"] as Control).position + r.position + Vector2(dx, r.size.y * 0.5)) * k
			lum = minf(lum, img.get_pixel(clampi(int(at.x), 0, img.get_width() - 1), clampi(int(at.y), 0, img.get_height() - 1)).get_luminance())
		if mode["id"] in MENU.COMING_SOON:
			check(lum < 0.25, "%s: the ribbon's navy shows at its left end (luminance %.2f)" % [mode["id"], lum])
		else:
			check(lum > 0.1, "%s: no ribbon where a working tile has its art (luminance %.2f)" % [mode["id"], lum])

## No two tiles touch: a 12 px gutter between neighbours, and the label strips and ribbons stay inside their own tile.
func _menu_grid() -> void:
	var rects: Array = []
	for m in MENU.MODES:
		var r: Rect2 = m["rect"]
		check(Rect2(0, 0, 1280, 720).encloses(r), "%s sits on the screen" % m["id"])
		check(Rect2(Vector2.ZERO, r.size).encloses(MENU.label_rect(m)), "%s: the label strip stays inside its tile" % m["id"])
		rects.append(r)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			check(not (rects[i] as Rect2).grow(11.0).intersects(rects[j]), "%s and %s keep a gutter" % [MENU.MODES[i]["id"], MENU.MODES[j]["id"]])
	var grid := Rect2(rects[0])
	for r in rects:
		grid = grid.merge(r)
	var caption := Rect2(MENU.CAPTION_AT, Vector2(BA_MENU.text_width(MENU.MODES[3]["caption"], 18) + 44.0, 32.0))
	check(not grid.intersects(caption) and caption.end.y <= 720.0, "the caption ribbon sits below the grid")
	check(not grid.intersects(MENU.talk_rect(2)), "the student's line box stays clear of the grid")

## The student: every fighter has a spoken line for each portrait mood, its subtitle fits the box, and a visit never repeats the last student or picture.
func _menu_student() -> void:
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ba/menu_lines.json"))["lines"]
	check(all.size() == game.fighters.size(), "a line set for every fighter (%d)" % all.size())
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/ba/menu_voice/PROVENANCE.json"))
	var used := {}
	for f in game.fighters:
		var set: Dictionary = MENU.lines_for(int(f["id"]))
		for mood in ["calm", "win", "lose"]:
			var said: Array = set.get(mood, [])
			check(not said.is_empty(), "%s has a %s line" % [f["name"], mood])
			for e in said:
				used[e["clip"]] = true
				var wrapped: Array = (load("res://scripts/ui/gallery_kit.gd") as GDScript).wrap_text(e["text"], 700, MENU.TALK_SIZE, MENU.TALK_W - 64.0)
				check(wrapped.size() <= 3 and not String(e["text"]).contains("—"), "%s: '%s' fits three lines" % [f["name"], e["text"]])
				var st := load("res://assets/audio/ba/menu_voice/" + String(e["clip"])) as AudioStream
				check(st != null and st.get_length() >= 0.5 and st.get_length() <= 20.0 and prov.has(e["clip"]), "%s plays and is recorded in the provenance (%s)" % [e["clip"], str(st.get_length()) if st else "no stream"])
		for mood in ["win", "lose"]:
			check(ResourceLoader.exists("res://assets/ba/portrait/%d_%s.webp" % [int(f["id"]), mood]), "%s has the %s portrait" % [f["name"], mood])
	var on_disk := 0
	for fn in DirAccess.get_files_at("res://assets/audio/ba/menu_voice"):
		if fn.ends_with(".ogg"):
			on_disk += 1
	check(on_disk == used.size() and on_disk == prov.size(), "every voice file is used and recorded (%d)" % on_disk)
	var pools: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ba/menu_cg/menu_cg.json"))
	for pool in pools:
		check((pools[pool] as Array).size() >= 10, "the %s pool has at least ten pictures" % pool)
		for n in pools[pool]:
			check(ResourceLoader.exists("res://assets/ba/menu_cg/%s.jpg" % n), "%s exists" % n)
	var seen := {}
	var last := -1
	var repeats := 0
	for i in 12:
		await game.go("menu", {}, "cut")
		var who: Dictionary = _screen().probe()["who"]
		seen[who["id"]] = true
		repeats += 1 if int(who["id"]) == last else 0
		last = int(who["id"])
		check(String(who["line"]) != "", "visit %d: the student has something to say" % i)
	check(repeats == 0 and seen.size() >= 2, "twelve visits never repeat back to back and meet both students (%d)" % seen.size())
	await game.go("menu", {"mascot": 10005, "mood": "win"}, "cut")
	var forced: Dictionary = _screen().probe()["who"]
	var wins: Array = (MENU.lines_for(10005)["win"] as Array).map(func(e: Dictionary) -> String: return e["text"])
	check(forced["id"] == 10005 and forced["mood"] == "win" and wins.has(forced["line"]) and String(forced["clip"]).begins_with("10005_win_"), "a step file can pick the student, the mood and so the line and its clip")
	var sc := _screen()
	await create_timer(MENU.VOICE_AT + 0.4).timeout
	check(sc._said and sc._voice.stream != null and sc._voice.stream.resource_path.ends_with(String(forced["clip"])), "the student's voice line plays with the text (%s)" % forced["clip"])
	await create_timer(1.6).timeout   # let the entrance finish, the options flow after this presses the tiles

func _menu_text() -> void:
	for m in MENU.MODES:
		var r: Rect2 = MENU.label_rect(m)
		var tile: Rect2 = m["rect"]
		var size: int = MENU.label_size(m)
		var tw: float = BA_MENU.text_width(m["label"], size)
		check(r.size.x <= tile.size.x - 20.0, "%s strip (%.0f) fits its tile (%.0f)" % [m["label"], r.size.x, tile.size.x])
		check(tw + 36.0 <= r.size.x + 0.5, "%s text fits its strip" % m["label"])
		check(size >= 14, "%s stays readable (%d px)" % [m["label"], size])
		check(float(size) * 1.34 <= tile.size.y * 0.6, "%s strip leaves most of its picture visible" % m["label"])
		var cap_w: float = BA_MENU.text_width(m["caption"], 18) + 44.0
		check(cap_w <= 640.0, "%s caption ribbon (%.0f) fits under the tile grid" % [m["id"], cap_w])
	check(KIT.pop(0.0) == 0.8 and is_equal_approx(KIT.pop(0.25), 1.0), "selection pop runs 0.8 to 1.0 in a quarter second")

# ── options ──────────────────────────────────────────────────────────────────
func _options_flow() -> void:
	game.session.bgm_volume = 0.7
	game.session.sfx_volume = 0.8
	game.session.reduce_flashes = false
	sfx.set_volume(0.8)
	game.push("options", {})
	await create_timer(0.3).timeout
	var o: Node = _screen()
	check(game.current_name() == "options", "options is on top")
	var p: Dictionary = o.probe()
	check(p["focus"] == "bgm" and p["page"] == "main" and p["reduce_flashes"] == false, "options opens on BGM, main page, flashes off")
	var pop: Rect2 = o.popup_rect()
	check(Rect2(0, 0, 1280, 720).encloses(pop), "popup stays on screen")
	for i in 4:
		check(pop.encloses(o.row_rect(i)), "row %d is inside the popup" % i)
	check(o.cells_span(0).y - o.cells_span(0).x > 400.0, "the slider spans a usable width")
	# sliders: one cell per press, live
	await _press("kb1", "left")
	check(is_equal_approx(game.session.bgm_volume, 0.65), "Left lowers BGM one cell")
	await _press("kb1", "right")
	await _press("kb1", "right")
	check(is_equal_approx(game.session.bgm_volume, 0.75), "Right raises BGM one cell")
	for i in 8:
		await _press("kb1", "right")
	check(is_equal_approx(game.session.bgm_volume, 1.0), "BGM stops at 100 percent")
	await _press("kb1", "down")
	check(o.probe()["focus"] == "sfx", "Down moves to SFX")
	await _press("kb1", "left")
	await _press("kb1", "left")
	check(is_equal_approx(game.session.sfx_volume, 0.7) and is_equal_approx(sfx.volume_sfx, 0.7), "SFX changes are live on the mixer")
	for i in 20:
		await _press("kb1", "left")
	check(is_equal_approx(game.session.sfx_volume, 0.0), "SFX stops at zero")
	# Reduce Flashes
	await _press("kb1", "down")
	check(o.probe()["focus"] == "flashes", "Down moves to Reduce Flashes")
	await _press("kb1", "right")
	check(game.session.reduce_flashes == true and o.probe()["reduce_flashes"] == true, "Right turns Reduce Flashes on")
	await _press("kb1", "confirm")
	check(game.session.reduce_flashes == false, "Confirm flips it off")
	await _press("kb1", "confirm")
	check(game.session.reduce_flashes == true, "Confirm flips it on")
	# the Controls sub-page
	await _press("kb1", "down")
	check(o.probe()["focus"] == "glyphs", "Down moves to Glyphs")
	await _press("kb1", "down")
	check(o.probe()["focus"] == "controls", "Down moves to Controls")
	await _press("kb1", "down")
	check(o.probe()["focus"] == "controls", "Down stops at the last row")
	await _press("kb1", "confirm")
	await _frames(2)
	check(o.probe()["page"] == "controls", "Confirm opens the Controls page")
	check(o._paint.modulate.a > 0.99 and o._paint.scale.y > 0.99, "switching page does not replay the popup entrance (alpha %.2f, scale %.2f)" % [o._paint.modulate.a, o._paint.scale.y])
	check(Rect2(0, 0, 1280, 720).encloses(o.popup_rect()), "the Controls popup stays on screen")
	await _press("kb1", "left")
	check(is_equal_approx(game.session.sfx_volume, 0.0) and game.session.reduce_flashes == true, "sliders and toggles ignore input on the Controls page")
	await _press("kb1", "back")
	await _frames(2)
	check(o.probe()["page"] == "main" and game.current_name() == "options", "Back leaves the Controls page, not the popup")
	check(o._paint.modulate.a > 0.99 and o._paint.scale.y > 0.99, "and back to the main page keeps the popup solid (alpha %.2f)" % o._paint.modulate.a)
	# mouse
	var span: Vector2 = o.cells_span(0)
	var y: float = o.row_rect(0).position.y + 56.0
	await create_timer(0.3).timeout
	_mouse(o, Vector2(span.x + (span.y - span.x) * 0.5, y), true)
	check(is_equal_approx(game.session.bgm_volume, 0.5), "a click in the middle of the BGM cells sets 50 percent")
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(span.x + (span.y - span.x) * 0.25, y)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	o._on_mouse(mv)
	check(is_equal_approx(game.session.bgm_volume, 0.25), "dragging follows the pointer")
	_mouse(o, Vector2(span.y, y), false)
	mv.position = Vector2(span.x + 10.0, y)
	o._on_mouse(mv)
	check(is_equal_approx(game.session.bgm_volume, 0.25), "after release the pointer no longer drags")
	# back closes and saves
	await _press("kb1", "back")
	await create_timer(0.4).timeout
	check(game.current_name() == "menu", "Back on the main page closes the popup")
	var reloaded = SESS.new()
	check(reloaded.reduce_flashes == true, "Reduce Flashes is on after a reload")
	check(is_equal_approx(reloaded.bgm_volume, 0.25) and is_equal_approx(reloaded.sfx_volume, 0.0), "volumes are saved on close")
	game.session.reduce_flashes = false
	game.session.bgm_volume = 0.7
	game.session.sfx_volume = 0.8
	sfx.set_volume(0.8)

func _options_text() -> void:
	var widths: Array = OPT.COL_W
	var texts := 0
	for row in OPT.CONTROL_ROWS:
		var size: int = BA_MENU.fit(row["label"], 19, widths[0] - 14.0, 13)
		check(BA_MENU.text_width(row["label"], size) <= widths[0] - 14.0 + 0.5, "%s fits the action column" % row["label"])
		var act: String = row.get("act", "")
		var cols := [row.get("kb1", [controls.label_for("kb1", act)]), row.get("kb2", ["Enter", "/"] if act == "confirm" else (["Bksp"] if act == "back" else [controls.label_for("kb2", act)])),
				OPT.pad_keys(row)]
		for k in 3:
			var w := 0.0
			for key in cols[k]:
				w += OPT.token_width(key if key is Texture2D else str(key)) + 6.0
			check(w - 6.0 <= widths[k + 1], "%s keys (%.0f) fit column %d (%.0f)" % [row["label"], w - 6.0, k + 1, widths[k + 1]])
			texts += 1
	var room: float = OPT.CONTROLS_W - OPT.SIDE - OPT.COL_X[1] - OPT.SIDE
	var gs: int = BA_MENU.fit(OPT.GUARD_NOTE, 18, room, 12, 600)
	check(BA_MENU.text_width(OPT.GUARD_NOTE, gs, 600) <= room and gs >= 14, "the guard note fits at a readable size (%d px)" % gs)
	check(BA_MENU.text_width("Fewer bright flashes and less screen shake", 14, 600) < OPT.POP_W - OPT.SIDE * 2.0 - OPT.CAP_W - 40.0, "the Reduce Flashes note clears its capsule")
	check(BA_MENU.text_width("Up / Down: select    Left / Right: adjust    Back: save and close", 13, 600) < OPT.POP_W - 60.0, "the footer hint fits the popup")

## The Controls page names the pause keys the game really binds, and the wording matches the rest of the game.
func _controls_page() -> void:
	var rows := {}
	for row in OPT.CONTROL_ROWS:
		rows[row["label"]] = row
	var pause: Dictionary = rows.get("Pause", {})
	check(not pause.is_empty(), "the Controls page has a Pause row")
	check(controls.KB1[KEY_V] == "start" and pause.get("kb1", []).has("V"), "P1's keyboard pauses with V")
	check(controls.KB2[KEY_KP_5] == "start" and pause.get("kb2", []) == ["Num 5"], "P2's keyboard pauses with Num 5")
	check(controls.SHARED[KEY_TAB] == "start" and controls.SHARED[KEY_ESCAPE] == "back" and pause.get("kb1", []).has("Tab") and pause.get("kb1", []).has("Esc"), "Tab and Esc pause from either keyboard")
	check(controls.PAD_BUTTONS[JOY_BUTTON_START] == "start" and pause.get("pad", []) == ["start"] and controls.label_for("pad0", "start") == "Start", "a gamepad pauses with Start")
	check(rows.has("EX") and not rows.has("EX Super"), "the EX button is called EX, as in the training tip")
	var caption := ""
	for m in MENU.MODES:
		if m["id"] == "options":
			caption = m["caption"]
	check(caption != "" and not caption.to_lower().contains("display"), "the Options caption does not promise display settings (%s)" % caption)

# ── assign ───────────────────────────────────────────────────────────────────
func _assign_flow(humans: int, mode: String) -> void:
	game.session.reset()
	game.session.begin(mode)
	game.push("assign", {"mode": mode})
	await create_timer(0.5).timeout
	var a: Node = _screen()
	var tag := "%s: " % mode
	check(game.current_name() == "assign", tag + "assign is on top")
	check(a.probe()["humans"] == humans, tag + "needs %d human(s)" % humans)
	var pl: Array = game.session.players
	check(not pl[0]["claimed"] and not pl[1]["claimed"], tag + "nothing is claimed on entry")
	check(not a._panels[0].claimed and not a._panels[1].claimed, tag + "no bracket on entry")
	check(is_equal_approx(a._panels[0].modulate.r, 1.0) and is_equal_approx(a._panels[1].modulate.r, 1.0), tag + "panels are full before anything is claimed")
	# entrance never overshoots
	var errors_before: int = int(sfx.played.get("error", 0))
	await _press("kb1", "confirm")
	check(pl[0]["claimed"] and pl[0]["device"] == "kb1", tag + "kb1 claims Player 1")
	check(a._panels[0].claimed, tag + "the claimed panel takes the bracket")
	await create_timer(0.3).timeout
	check(absf(a._panels[1].modulate.r - 0.85) < 0.01 or humans == 1, tag + "the other panel sits at 0.85")
	await _press("kb1", "confirm")
	check(int(sfx.played.get("error", 0)) == errors_before + 1, tag + "the same device twice is refused")
	check(a._slots[0]["shake"] > 0.0, tag + "the refused glyph shakes")
	await _press("shared", "confirm")
	if humans == 2:
		check(not pl[1]["claimed"], tag + "Space does not claim Player 2")
		await _press("kb2", "confirm")
		check(pl[1]["claimed"] and pl[1]["device"] == "kb2", tag + "kb2 claims Player 2")
		check(a._panels[0].claimed and a._panels[1].claimed, tag + "both panels carry the bracket")
		check(a._finish_t > 0.0, tag + "both claimed starts the beat")
		await _press("kb1", "back")
		check(not pl[1]["claimed"] and pl[0]["claimed"], tag + "Back unclaims the last claim first")
		check(a._finish_t < 0.0, tag + "unclaiming cancels the beat")
		await _press("kb1", "back")
		check(not pl[0]["claimed"], tag + "Back unclaims the earlier claim")
		check(not a._panels[0].claimed and not a._panels[1].claimed, tag + "no brackets remain")
	else:
		check(pl[0]["claimed"] and not pl[1]["claimed"], tag + "other devices cannot take the CPU seat")
		check(a._panels[1].claimed, tag + "the CPU panel is ready once the human is")
		check(a._finish_t > 0.0, tag + "one human claimed starts the beat")
		await _press("kb1", "back")
		check(not pl[0]["claimed"] and not a._panels[1].claimed, tag + "Back unclaims and the CPU panel lets go")
	await create_timer(0.35).timeout
	await _press("kb1", "back")
	await _frames(2)
	var sliding: bool = game.current_name() == "assign" and is_instance_valid(a) and a.get("_closing") == true and a.modulate.a < 1.0
	check(sliding, tag + "Back with nothing claimed slides the overlay out first")
	await create_timer(0.4).timeout
	check(game.current_name() == "menu", tag + "Back with nothing claimed closes the overlay")

## Back from character select rebuilds the assign screen as a full screen: the earlier claim stays docked, the last one is undone.
## Only Game.back() reaches this (select's own Back goes to the menu). S2_SHOT_DIR=<dir> saves a picture of the state.
func _assign_return() -> void:
	game.session.reset()
	game.session.begin("versus2p")
	game.push("assign", {"mode": "versus2p"})
	await create_timer(0.5).timeout
	await _press("kb1", "confirm")
	await _press("kb2", "confirm")
	await create_timer(0.2).timeout
	check(game.session.players[1]["claimed"], "return: both players claimed before leaving")
	await game.go("select", {}, "cut")
	check(game.current_name() == "select", "return: select is up")
	await create_timer(0.3).timeout
	await game.back("cut")
	await create_timer(0.8).timeout
	var a: Node = _screen()
	var pl: Array = game.session.players
	check(game.current_name() == "assign" and a._overlay == false, "return: assign is back as a full screen")
	check(pl[0]["claimed"] and pl[0]["device"] == "kb1", "return: Player 1 is still on kb1")
	check(not pl[1]["claimed"] and pl[1]["device"] == "", "return: Player 2 is released")
	var glyph: Control = a._slots[0]["glyph"]
	check(glyph.position.distance_to(a.DOCK_POS[0]) < 2.0, "return: the claimed glyph sits in its panel (%.1f px off)" % glyph.position.distance_to(a.DOCK_POS[0]))
	check(a._panels[0].claimed and not a._panels[1].claimed, "return: only Player 1's panel has the bracket")
	check(absf(a._panels[1].modulate.r - 0.85) < 0.01 and absf(a._panels[0].modulate.r - 1.0) < 0.01, "return: the open panel sits at 0.85")
	check(a._panels[0].position.distance_to(a.PANEL_POS[0]) < 1.0 and a._panels[1].position.distance_to(a.PANEL_POS[1]) < 1.0, "return: both panels are home")
	var out := OS.get_environment("S2_SHOT_DIR")
	if out != "":
		get_root().get_window().size = Vector2i(1280, 720)
		await create_timer(0.3).timeout
		root.get_viewport().get_texture().get_image().save_png(out + "/assign_back.png")
	var probe: Dictionary = a.probe()
	check(probe["slots"][0].has("glow") and probe["slots"][0]["glow"] == 1.0 and probe["slots"][1]["glow"] == 0.0, "return: the probe keeps its glow key")
	await game.go("menu", {}, "cut")

func _assign_text() -> void:
	var p := Rect2(Vector2.ZERO, ASSIGN_PANEL.SIZE)
	for t in ["Player 1", "Player 2"]:
		var panel = ASSIGN_PANEL.new().setup(t, BT.P1_LIGHT)
		var tag: Rect2 = panel.tag_rect()
		check(tag.size.x < p.size.x * 0.5, "%s tag (%.0f) is a tag, not a banner" % [t, tag.size.x])
		panel.free()
	for text in ["KEYBOARD  /  WASD + F", "KEYBOARD  /  ARROWS + ENTER", "KEYBOARD  /  SPACE", "GAMEPAD 4"]:
		check(BA_MENU.text_width(text, 15, 800) <= p.size.x - 24.0, "%s fits inside its panel" % text)
	for text in ["F  /  Enter  /  A  /  Space  to start", "G  /  Bksp  /  B   back"]:
		check(BA_MENU.text_width(text, 16) + 44.0 <= 560.0, "%s fits its ribbon" % text)
