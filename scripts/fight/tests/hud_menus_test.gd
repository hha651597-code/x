extends SceneTree
## The pause menu, the result screen and the training overlay. Geometry, navigation, the sampling of the input history,
## the tip timing and real pixels (selected row yellow, grey and cyan capsules, the navy scrim, the pink loser field).
## Run: TEST=res://scripts/fight/tests/hud_menus_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

class StubWorld extends Node:
	var training := true
	var round_no := 2

class StubHud extends Control:
	var world: Node
	var items: Array = []
	var activated := -1
	var _time := 0.0
	var _paused := false
	func pause_items() -> Array:
		return items
	func pause_activate(i: int) -> void:
		activated = i

var checks := 0
var failures: Array = []
var game: Node
var screen: Node
var hud: Control
var FI: GDScript
var PAUSE: GDScript
var MENU: GDScript
var TRAIN: GDScript
var RESULT: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("HUD_MENUS_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(200.0).timeout.connect(func() -> void:
		print("HUD_MENUS_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	PAUSE = load("res://scripts/fight/hud_pause.gd")
	MENU = load("res://scripts/ui/ba_menu.gd")
	TRAIN = load("res://scripts/fight/hud_training.gd")
	RESULT = load("res://scripts/screens/result_screen.gd")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	await _nine_slice()
	await _pause_pixels()
	await _facade_pause("training", 7)
	await _facade_pause("versus2p", 4)
	await _training_logic()
	await _result_logic()
	await _result_pixels()
	print("HUD_MENUS_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# helpers
func _viewport(bg: Color) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var r := ColorRect.new()
	r.color = bg
	r.size = Vector2(1280, 720)
	vp.add_child(r)
	return vp

func _stub_hud(vp: Node, training: bool, items: Array) -> StubHud:
	var h := StubHud.new()
	h.world = StubWorld.new()
	h.world.training = training
	h.items = items
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(h)
	h.add_child(h.world)
	return h

func _px(img: Image, x: float, y: float) -> Color:
	return img.get_pixel(clampi(int(x), 0, img.get_width() - 1), clampi(int(y), 0, img.get_height() - 1))

func _near(c: Color, want: Color, tol: float) -> bool:
	return absf(c.r - want.r) <= tol and absf(c.g - want.g) <= tol and absf(c.b - want.b) <= tol

func _items() -> Array:
	return [
		{"id": "resume", "label": "Resume", "value": ""},
		{"id": "restart", "label": "Reset Positions", "value": ""},
		{"id": "dummy", "label": "Dummy", "value": "Stand"},
		{"id": "boxes", "label": "Hitboxes", "value": "Off"},
		{"id": "exinf", "label": "Infinite EX", "value": "On"},
		{"id": "select", "label": "Character Select", "value": ""},
		{"id": "menu", "label": "Main Menu", "value": ""},
	]

# the 9-slice at half scale never tears
func _nine_slice() -> void:
	await _tear([["Combat__Common_Btn_BG", Rect2(20, 10, 84, 35)], ["Combat__Common_Btn_BG", Rect2(20, 60, 400, 42)],
			["Combat__Common_Btn_BG", Rect2(20, 120, 262, 52)], ["Combat__Common_Btn_BG", Rect2(20, 190, 100, 30)],
			["Combat__Combat_Title_Bg", Rect2(20, 240, 100, 22)], ["Combat__Combat_Title_Bg", Rect2(20, 280, 180, 26)],
			["Combat__Combat_Title_Bg", Rect2(20, 320, 62, 20)], ["Combat__Combat_Title_Bg", Rect2(20, 360, 156, 22)],
			["Common__Common_Popup_Bg", Rect2(560, 10, 500, 355)]])
	await _tear([["Common__Common_Popup_Bg", Rect2(20, 10, 500, 493)]])

## Renders [name, rect] pairs with MENU.nine over black and checks that a line through the middle of each has no black gap.
func _tear(rects: Array) -> void:
	var vp := _viewport(Color(0, 0, 0, 1))
	var canvas := Node2D.new()
	vp.add_child(canvas)
	canvas.draw.connect(func() -> void:
		for r in rects:
			MENU.nine(canvas, r[0], r[1]))
	canvas.queue_redraw()
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	for e in rects:
		var r: Rect2 = e[1]
		var y0 := int(r.position.y + r.size.y * 0.5)
		var gap := -1
		for x in range(int(r.position.x) + 14, int(r.end.x) - 14):
			var c := _px(img, x, y0)
			if c.r + c.g + c.b < 0.02:
				gap = x
				break
		check(gap < 0, "%s at %dx%d has no gap along its middle (x=%d)" % [e[0], int(r.size.x), int(r.size.y), gap])

# the pause popup, drawn
func _pause_pixels() -> void:
	var vp := _viewport(Color.WHITE)
	var h := _stub_hud(vp, true, _items())
	var p: Control = PAUSE.new().setup(h)
	h.add_child(p)
	p.open()
	await create_timer(1.4).timeout
	var img := vp.get_texture().get_image()
	check(p.visible and p.mouse_filter == Control.MOUSE_FILTER_STOP, "open pause is visible and takes the mouse")
	check(p._rows.size() == 7, "training pause lists 7 rows")
	for i in 7:
		var r: Rect2 = p._row_rect(i)
		check(r.size == Vector2(400, 42), "row %d is 400x42" % i)
		check(is_equal_approx(r.get_center().x, 640.0), "row %d is centred" % i)
		if i > 0:
			check(is_equal_approx(r.position.y - p._row_rect(i - 1).position.y, 46.0), "row %d sits 46 px under the one before" % i)
	var panel: Rect2 = p._panel_rect()
	check(is_equal_approx(panel.get_center().y, 360.0), "panel is centred vertically")
	check(is_equal_approx(panel.size.x, 500.0) and is_equal_approx(panel.size.y, 493.0), "training panel is 500x493 (%s)" % panel.size)
	check(p._row_rect(6).end.y <= panel.end.y - 40.0, "the last row ends above the footer")
	var r0: Rect2 = p._row_rect(0)
	check(_near(_px(img, r0.position.x + 250.0, r0.position.y + 8.0), Color("F6E94B"), 0.06), "the selected row is #F6E94B (%s)" % _px(img, r0.position.x + 250.0, r0.position.y + 8.0).to_html(false))
	var r1: Rect2 = p._row_rect(1)
	check(_px(img, r1.position.x + 250.0, r1.position.y + 8.0).r > 0.95 and _px(img, r1.position.x + 250.0, r1.position.y + 8.0).b > 0.95, "an idle row is white")
	var off_cap := Rect2(p._row_rect(3).end.x - 108.0, p._row_rect(3).position.y + 3.5, 84.0, 35.0)
	var off_px := _px(img, off_cap.position.x + 8.0, off_cap.position.y + 9.0)
	check(absf(off_px.r - off_px.b) < 0.06 and off_px.r > 0.7 and off_px.r < 0.95, "the Off capsule is grey (%s)" % off_px.to_html(false))
	var on_cap := Rect2(p._row_rect(4).end.x - 108.0, p._row_rect(4).position.y + 3.5, 84.0, 35.0)
	var on_px := _px(img, on_cap.position.x + 8.0, on_cap.position.y + 9.0)
	check(on_px.b - on_px.r > 0.25, "the On capsule is cyan (%s)" % on_px.to_html(false))
	var scrim := _px(img, 20.0, 20.0)
	check(_near(scrim, Color(145.0 / 255.0, 157.0 / 255.0, 172.0 / 255.0), 0.06), "the scrim is white pulled 45 percent to navy (%s)" % scrim.to_html(false))
	check(_px(img, panel.end.x - 60.0, panel.position.y + 20.0).r > 0.9, "the scrim does not reach the panel")
	# navigation
	p.select(-1, false)
	check(p.index == 6, "select(-1) wraps to the last row")
	p.select(7, false)
	check(p.index == 0, "select(7) wraps to the first row")
	var hover := InputEventMouseMotion.new()
	hover.position = p._row_rect(4).get_center()
	p._gui_input(hover)
	check(p.index == 4, "hovering row 4 selects it")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = p._row_rect(2).get_center()
	p._gui_input(click)
	check(h.activated == 2 and p.index == 2, "clicking row 2 selects and activates it")
	p.close()
	check(not p.visible and p.mouse_filter == Control.MOUSE_FILTER_IGNORE, "close hides the pause and frees the mouse")
	vp.queue_free()
	# long labels are cut with an ellipsis and stay clear of the capsule
	var room := 400.0 - 60.0 - 108.0
	var long := "Dummy Behaviour During Combo Practice"
	var size: int = MENU.fit(long, 22, room, 16)
	var cut: String = MENU.clip(long, size, room)
	check(size == 16 and cut.ends_with("…") and MENU.text_width(cut, size) <= room, "a long label is cut to its room (%s)" % cut)
	check(MENU.clip("Resume", 22, room) == "Resume", "a short label is left alone")
	# the tip bubble shows in a training pause and not in a versus one
	var tips := []
	for training in [true, false]:
		var v2 := _viewport(Color(0.25, 0.25, 0.3))
		var h2 := _stub_hud(v2, training, _items())
		var p2: Control = PAUSE.new().setup(h2)
		h2.add_child(p2)
		p2.open()
		await create_timer(0.8).timeout
		var pr: Rect2 = p2._panel_rect()
		tips.append(_px(v2.get_texture().get_image(), pr.end.x + 24.0 + 130.0, pr.position.y + 250.0 + 6.0))
		v2.queue_free()
	check(tips[0].r > 0.6, "the training pause draws the key tip (%s)" % tips[0].to_html(false))
	check(tips[1].r < 0.4, "the versus pause draws none (%s)" % tips[1].to_html(false))

# the real facade: navigation and actions through the new pause
func _fight(mode: String) -> void:
	game.session.begin(mode)
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	hud = screen.hud
	await create_timer(1.6).timeout
	screen.set_physics_process(false)
	screen.phase = "fight"

func _facade_pause(mode: String, rows: int) -> void:
	await _fight(mode)
	check(hud.pause_items().size() == rows, "%s pause has %d items" % [mode, rows])
	screen.set_paused(true)
	await process_frame
	var p: Control = hud._pause
	check(p.visible and p.index == 0 and p._rows.size() == rows, "%s: show_pause opens on Resume with %d rows" % [mode, rows])
	hud.pause_action("down")
	check(p.index == 1, "%s: down moves to row 1" % mode)
	hud.pause_action("up")
	hud.pause_action("up")
	check(p.index == rows - 1, "%s: up from Resume wraps to the last row" % mode)
	if mode == "training":
		var before: bool = screen.debug_boxes
		p.select(3, false)
		hud.pause_action("confirm")
		check(screen.debug_boxes != before, "training: confirming Hitboxes flips them")
		check(hud.pause_items()[3]["value"] == ("On" if screen.debug_boxes else "Off"), "training: the Hitboxes value follows")
		hud.pause_action("confirm")
		check(screen.debug_boxes == before, "training: confirming again flips them back")
		var dummy: String = screen.dummy_mode
		p.select(2, false)
		check(p.hint_text().contains("Left / Right") and not p.hint_text().contains("Confirm"), "training: the Dummy row's hint names Left / Right")
		var hint_w: float = MENU.text_width(p.hint_text(), 12, 600)
		check(hint_w < p.PANEL_W - 30.0 - 106.0, "training: the toggle hint clears the deco at the panel's foot (%.0f px)" % hint_w)
		p.select(0, false)
		check(p.hint_text().contains("Confirm") and not p.hint_text().contains("Left"), "training: Resume's hint names Confirm only")
		p.select(2, false)
		hud.pause_action("right")
		check(screen.dummy_mode != dummy, "training: right on Dummy cycles the dummy")
		check(str(hud.pause_items()[2]["value"]).to_lower() == screen.dummy_mode, "training: the Dummy value follows")
		hud.pause_action("left")
		check(screen.dummy_mode == dummy, "training: left on Dummy cycles it back")
		hud.pause_action("left")
		check(screen.dummy_mode == "cpu", "training: left from the first mode wraps to the last")
		hud.pause_action("right")
		check(hud._train.tip_alpha() == 0.0, "training: the tip is off while the pause shows it")
	hud.pause_action("back")
	check(not screen.paused and not p.visible, "%s: back resumes and hides the pause" % mode)

# training overlay
func _feed(tr: Control, x: int, y: int, btns: Array, frames: int) -> void:
	screen.f1.input = FI.from_held(screen.f1.input, x, y, btns)
	screen._frame += frames
	tr.sample(screen)

func _training_logic() -> void:
	await _fight("training")
	var tr: Control = hud._train
	var f1: Node = screen.f1
	for m in ["setup", "note_combo", "reset", "sample"]:
		check(tr.has_method(m), "training keeps %s" % m)
	check(tr.visible, "the overlay is on in training")
	tr.reset()
	check(tr._hist.is_empty(), "reset clears the history")
	check(tr._tip_t == 0.0, "reset restarts the tip")
	var f0: int = screen._frame
	_feed(tr, 0, 0, [], 1)
	_feed(tr, 0, 0, [], 1)
	_feed(tr, 0, 0, [], 1)
	check(tr._hist.size() == 1, "three identical frames are one entry (%d)" % tr._hist.size())
	_feed(tr, 1, 0, [], 4)
	check(tr._hist.size() == 2 and tr._hist[0]["x"] == 1, "a new direction is a new entry")
	_feed(tr, 1, 0, ["light"], 2)
	check(tr._hist.size() == 3 and int(tr._hist[0]["mask"]) == 1, "a new button is a new entry (mask %d)" % int(tr._hist[0]["mask"]))
	_feed(tr, 1, 0, ["light", "dash"], 2)
	check(int(tr._hist[0]["mask"]) == (1 | (1 << 5)), "two held buttons share one mask")
	check(int(tr._hist[0]["f0"]) == int(tr._hist[1]["f0"]) + 2 and int(tr._hist[1]["f0"]) > f0, "entries keep their frame numbers")
	for i in 14:
		_feed(tr, (i % 3) - 1, (i % 2) * 2 - 1, [], 1)
	check(tr._hist.size() == 10, "the history is capped at 10 (%d)" % tr._hist.size())
	var n: int = tr._hist.size()
	screen.paused = true
	_feed(tr, -1, -1, ["heavy"], 1)
	screen.paused = false
	check(tr._hist.size() == n and int(tr._hist[0]["mask"]) != 2, "nothing is sampled while paused")
	screen.phase = "ko"
	_feed(tr, 1, 1, ["ex"], 1)
	screen.phase = "fight"
	check(int(tr._hist[0]["mask"]) != 8, "nothing is sampled outside the fight phase")
	# tip
	tr._tip_t = 0.0
	check(tr.tip_alpha() == 0.0, "the tip fades in from nothing")
	tr._tip_t = 1.0
	check(tr.tip_alpha() == 1.0, "the tip is fully up at 1 s")
	tr._tip_t = 4.9
	check(tr.tip_alpha() > 0.0 and tr.tip_alpha() < 1.0, "the tip is fading at 4.9 s")
	tr._tip_t = 5.1
	check(tr.tip_alpha() == 0.0, "the tip is gone after 5 s")
	tr._tip_t = 1.0
	screen.set_paused(true)
	check(tr.tip_alpha() == 0.0, "the tip leaves the overlay while the pause shows it")
	screen.set_paused(false)
	check(tr.tip_alpha() == 1.0, "the tip comes back after the pause when still inside 5 s")
	# combo block
	tr.note_combo(8, 129.0, 3.0)
	check(int(tr.last["hits"]) == 8 and is_equal_approx(float(tr.last["dmg"]), 129.0), "note_combo sets last")
	f1.stat_max_combo = 4
	tr._process(0.016)
	check(tr._best_seen == 4 and tr._best_t < 0.0, "the first record does not flash")
	f1.stat_max_combo = 6
	tr._process(0.016)
	check(tr._best_seen == 6 and tr._best_t > 0.0, "beating the best flashes Best Record")
	var t_flash: float = tr._best_t
	tr._process(0.016)
	check(tr._best_t == t_flash, "an unchanged best does not flash again")
	# layout stays between the feed and the bottom row, and clear of the top rail
	check(TRAIN.CARD.position.y >= 320.0 and TRAIN.CARD.end.y <= 566.0, "the input card sits between the combo feed and the assist card")
	check(TRAIN.CARD.position.x >= 0.0 and TRAIN.CARD.end.x <= 260.0, "the input card stays at the left edge")
	check(TRAIN.ROWS * TRAIN.ROW_PITCH + 46.0 <= TRAIN.CARD.size.y, "the card holds its rows")

# result screen
func _result_logic() -> void:
	game.session.begin("versus2p")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	var stats := [{"damage": 800.0, "combo": 5, "hits": 22}, {"damage": 1234.0, "combo": 9, "hits": 31}]
	await game.go("result", {"winner": 2, "wins": [1, 2], "rounds": 3, "stats": stats}, "cut")
	var r: Node = game.stack.back()
	await create_timer(0.3).timeout
	var pr: Dictionary = r.probe()
	check(pr["winner"] == 2 and pr["wins"] == [1, 2] and pr["sel"] == 0 and not pr["arcade_over"], "probe reports winner, wins, sel and arcade_over")
	check(pr["items"] == ["Rematch", "Character Select", "Main Menu"], "versus keeps its three menu items")
	var rows: Array = r._stat_rows()
	check(rows[0] == ["TOTAL DAMAGE", "1234", "800"], "the winner's damage is on the left (%s)" % str(rows[0]))
	check(rows[1] == ["MAX COMBO", "9", "5"] and rows[2] == ["HITS LANDED", "31", "22"], "combo and hits follow the winner")
	check(rows[3] == ["ROUNDS WON", "2", "1"], "rounds won are the winner's first")
	r.on_action("kb1", "down")
	check(r.probe()["sel"] == 0, "input before 0.6 s is ignored")
	await create_timer(0.5).timeout
	r.on_action("kb1", "down")
	check(r.probe()["sel"] == 1, "down moves the cursor")
	r.on_action("kb1", "up")
	r.on_action("kb1", "up")
	check(r.probe()["sel"] == 2, "up from the first item wraps to the last")
	check(r._menu.size() == 3, "one hit area per item")
	var sfx: Node = root.get_node("Sfx")
	var line: String = str(sfx.manifest["sets"]["hina"]["voice"].keys()[0])
	check(sfx.voice("hina", 1, 0, line), "a voice line starts (%s)" % line)
	var confirms := int(sfx.played.get("confirm", 0))
	for t in [0.05, 0.3, 0.55, 0.75, 1.0, 1.25]:
		r._t = t
		r.on_action("kb1", "confirm")
	check(int(sfx.played.get("confirm", 0)) == confirms, "a Light mashed through the match end picks nothing")
	r._t = 1.25 + r.CONFIRM_GAP + 0.01
	r.on_action("kb1", "confirm")
	check(int(sfx.played.get("confirm", 0)) == confirms + 1, "one press after the mashing stops picks the highlighted item")
	check(sfx._speaking.is_empty(), "leaving to the menu stops the winner's line")
	await create_timer(1.0).timeout
	game.session.begin("versus2p")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	await game.go("result", {"winner": 2, "wins": [1, 2], "rounds": 3, "stats": stats}, "cut")
	r = game.stack.back()
	await create_timer(0.3).timeout
	r._t = 0.0
	var s0: Vector2 = r._stamp(0.0)
	check(is_equal_approx(s0.x, 2.0) and is_equal_approx(s0.y, 0.05), "the stamp starts at scale 2.0 and alpha 0.05 (%s)" % s0)
	r._t = 0.267
	var s1: Vector2 = r._stamp(0.0)
	check(absf(s1.x - 0.95) < 0.005, "the stamp reaches 0.95 at 0.267 s (%s)" % s1)
	r._t = 0.4
	var s2: Vector2 = r._stamp(0.0)
	check(is_equal_approx(s2.x, 1.0) and is_equal_approx(s2.y, 1.0), "the stamp settles at 1.0 by 0.4 s")
	r._t = 0.5
	check(r._menu_k(0) == 0.0, "the menu has not started to move at 0.5 s")
	r._t = 1.6
	check(r._menu_k(0) > 0.99 and r._menu_k(2) > 0.99, "the menu has settled by 1.6 s")
	check(is_equal_approx(r._menu_pos(1).y - r._menu_pos(0).y, 62.0), "menu plates sit 62 px apart")
	check(r._menu_pos(1).x > r._menu_pos(0).x, "menu plates step right with the lean")
	# arcade: clearing the ladder leaves the main menu alone
	game.session.begin("arcade")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	game.session.arcade_stage = 4
	await game.go("result", {"winner": 1, "wins": [2, 0], "rounds": 2, "stats": [{}, {}]}, "cut")
	var ra: Node = game.stack.back()
	check(ra.probe()["items"] == ["Main Menu"] and ra.probe()["arcade_over"], "clearing the ladder shows only the main menu")
	check(ra._header_text() == "ARCADE CLEAR", "the arcade ribbon says ARCADE CLEAR")
	game.session.begin("arcade")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	await game.go("result", {"winner": 2, "wins": [0, 2], "rounds": 2, "stats": [{}, {}]}, "cut")
	var rl: Node = game.stack.back()
	check(rl.probe()["items"] == ["Continue", "Main Menu"] and rl._header_text() == "GAME OVER", "losing an arcade fight offers Continue")
	check(rl._loser_text() == "DEFEATED" and rl._who_text() == "CPU", "the human who lost the arcade fight is tagged DEFEATED")
	# Character Select keeps who is playing: claims and devices stay, picks reset
	game.session.begin("versus2p")
	for i in 2:
		game.session.players[i]["claimed"] = true
		game.session.players[i]["device"] = ["kb2", "kb1"][i]
		game.session.players[i]["fighter"] = [10004, 10005][i]
	await game.go("result", {"winner": 1, "wins": [2, 0], "rounds": 2, "stats": [{}, {}]}, "cut")
	var rs: Node = game.stack.back()
	rs._choose("Character Select")
	var ps: Array = game.session.players
	check(ps[0]["claimed"] and ps[1]["claimed"] and ps[0]["device"] == "kb2" and ps[1]["device"] == "kb1", "Character Select keeps the claimed controllers")
	check(game.session.controls("kb1", 2) and game.session.controls("kb2", 1) and not game.session.controls("kb1", 1), "so the swapped keyboards keep their sides")
	check(ps[0]["fighter"] == -1 and ps[1]["fighter"] == -1 and game.session.mode == "versus2p", "while the picks start over")
	await create_timer(2.0).timeout

func _result_pixels() -> void:
	game.session.begin("versus2p")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	var vp := _viewport(Color.BLACK)
	var scr: Control = RESULT.new()
	vp.add_child(scr)
	scr.enter({"winner": 1, "wins": [2, 1], "rounds": 3, "stats": [{}, {}]}, {})
	scr._art_w.visible = false
	scr._art_l.visible = false
	scr._ink.visible = false
	await create_timer(0.5).timeout
	var img := vp.get_texture().get_image()
	var loser := _px(img, 1200.0, 300.0)
	check(_near(loser, Color("FFE1DA"), 0.06), "the loser's side is #FFE1DA (%s)" % loser.to_html(false))
	var winner := _px(img, 300.0, 100.0)
	check(winner.b > winner.r + 0.04 and winner.b > 0.85, "the winner's side is the cyan side of the pastel field (%s)" % winner.to_html(false))
	var seam_l := _px(img, 735.0, 60.0)
	var seam_r := _px(img, 775.0, 60.0)
	check(seam_l.b > seam_l.r + 0.08 and _near(seam_r, Color("FFE1DA"), 0.06), "the slash runs from x=760 at the top, cyan to its left and pink to its right")
	vp.queue_free()
	# the stat numerals wait for their ribbons: at 0.1 s the rows have not started, so nothing is drawn where they will sit
	var rows_in := {"winner": 1, "wins": [2, 1], "rounds": 3, "stats": [{"damage": 1432.0, "combo": 7, "hits": 31}, {"damage": 904.0, "combo": 4, "hits": 19}]}
	var shots := []
	for hide_ink in [false, true]:
		var vp2 := _viewport(Color.BLACK)
		var early: Control = RESULT.new()
		vp2.add_child(early)
		early.enter(rows_in, {})
		early._art_w.visible = false
		early._art_l.visible = false
		early._ink.visible = not hide_ink
		early.set_process(false)   # both shots are taken at exactly t=0.1: a real-time wait drifted the ribbons between them
		early._process(0.1)
		await process_frame
		await process_frame
		shots.append(vp2.get_texture().get_image())
		check(early._t < 0.5, "the early shot is before the first stat row (t=%.2f)" % early._t)
		vp2.queue_free()
	var bare := 0
	for rect in [Rect2(100, 316, 150, 34), Rect2(1030, 316, 150, 34)]:
		for y in range(int(rect.position.y), int(rect.end.y)):
			for x in range(int(rect.position.x), int(rect.end.x)):
				if not _near(shots[0].get_pixel(x, y), shots[1].get_pixel(x, y), 0.03):
					bare += 1
	check(bare == 0, "no stat numeral is drawn before its row starts (%d px)" % bare)
