extends SceneTree
## Controller glyphs: the family decision table, the fake seam and the Options override, every picture file and its PROVENANCE
## hash, buttons mapped by position, the assign screen's body picture per claim, the glyph chips that must fit their ribbons,
## and the cache dropped on a connection change.
## Run: TEST=res://scripts/ui/tests/glyph_test.gd MAXLINES=120 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const SCRATCH := "user://glyph_test_settings.cfg"
const ACTIONS := ["confirm", "back", "aux", "aux2", "lb", "rb", "start", "dpad", "stick_l"]
const ARCHIVE_SHA := "ac2fcf599080b0f3ba2d174c9474db6df1a0e96ff0662580e2da79a122ab78a1"
const BG := Color(1, 1, 1)

class PadSession extends Session:
	func device_of(slot: int) -> String:
		return "pad0" if slot == 1 else "kb2"

var checks := 0
var failures: Array = []
var CG: GDScript
var Menu: GDScript
var game: Node
var controls: Node
var real_path := ""

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("GLYPH_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("GLYPH_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	CG = load("res://scripts/ui/controller_glyphs.gd")
	Menu = load("res://scripts/ui/ba_menu.gd")
	var sess: GDScript = load("res://scripts/core/session.gd")
	real_path = sess.settings_path
	sess.settings_path = SCRATCH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	game = root.get_node("Game")
	controls = root.get_node("Controls")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	_classify()
	_seam()
	_files()
	_provenance()
	_by_position()
	_settings(sess)
	_cache()
	await _options()
	await _assign()
	await _hud()
	_chips()
	sess.settings_path = real_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	print("GLYPH_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _fake(info: Dictionary, name: String, id := 0) -> void:
	CG.fake = {id: {"info": info, "name": name}}

# the decision table
func _classify() -> void:
	# label, info as Godot 4.7.2 builds it (Strings), joy name, expected family
	var cases := [
		["xbox series wired (mac)", {"vendor_id": "1118", "product_id": "2834", "raw_name": "Xbox Wireless Controller"}, "Xbox Wireless Controller", "xbox"],
		["xbox 360 on windows", {"vendor_id": "1118", "product_id": "654", "xinput_index": "0"}, "XInput Gamepad", "xbox"],
		["xinput clone, unknown vid", {"vendor_id": "11720", "product_id": "12345", "xinput_index": "1"}, "XInput Gamepad", "xbox"],
		["dualsense", {"vendor_id": "1356", "product_id": "3302", "raw_name": "DualSense Wireless Controller"}, "PS5 Controller", "playstation"],
		["dualshock 4", {"vendor_id": "1356", "product_id": "1476"}, "PS4 Controller", "playstation"],
		["hori ps4 fightpad (name only)", {"vendor_id": "3853", "product_id": "102"}, "Horipad 4 PS4", "playstation"],
		["switch pro", {"vendor_id": "1406", "product_id": "8201"}, "Nintendo Switch Pro Controller", "switch"],
		["joycon pair", {"vendor_id": "1406", "product_id": "8210"}, "Nintendo Switch Joy-Con (L/R)", "switch"],
		["steam deck builtin", {"vendor_id": "10462", "product_id": "4613"}, "Steam Deck", "steamdeck"],
		["steam deck under steam input", {"vendor_id": "10462", "product_id": "4613", "steam_input_index": "3"}, "Steam Deck", "steamdeck"],
		["steam controller wired", {"vendor_id": "10462", "product_id": "4354"}, "Steam Controller", "steam"],
		["steam virtual pad, real unknown", {"vendor_id": "10462", "product_id": "4607", "steam_input_index": "1"}, "Steam Virtual Gamepad", "xbox"],
		["8bitdo, no hints", {"vendor_id": "11720", "product_id": "24576"}, "8BitDo SN30 Pro", "xbox"],
		["no info (android/web)", {}, "", "xbox"],
		["no info, name says switch", {}, "Nintendo Switch Pro Controller", "switch"],
		["ints instead of strings", {"vendor_id": 1356, "product_id": 3302}, "Wireless Controller", "playstation"],
		["vendor beats the name", {"vendor_id": "1356", "product_id": "1"}, "Xbox Controller", "playstation"],
		["vendor beats xinput_index", {"vendor_id": "1406", "product_id": "8201", "xinput_index": "0"}, "XInput Gamepad", "switch"],
		["name only: steam deck", {}, "Steam Deck", "steamdeck"],
		["name only: steam, no vendor", {}, "Steam Controller", "steam"],
		["name only: virtual steam is not a Steam pad", {}, "Steam Virtual Gamepad", "xbox"],
		["name only: dualsense", {}, "DualSense Wireless Controller", "playstation"],
		["name only: ps3 clone", {}, "PS3 Controller", "playstation"],
		["raw_name carries it", {"raw_name": "Nintendo Switch Pro Controller"}, "Generic Gamepad", "switch"],
		["a Valve pad with another product id", {"vendor_id": "10462", "product_id": "4352"}, "Controller", "steam"],
		["microsoft by vendor, odd name", {"vendor_id": "1118", "product_id": "1"}, "PS4 Controller", "xbox"],
	]
	for c in cases:
		check(CG.classify(c[1], c[2]) == c[3], "%s: got %s want %s" % [c[0], CG.classify(c[1], c[2]), c[3]])

func _seam() -> void:
	CG.fake = {0: {"info": {"vendor_id": "1356", "product_id": "3302"}, "name": "PS5 Controller"},
			1: {"info": {"vendor_id": "1406", "product_id": "8201"}, "name": "Pro Controller"}}
	check(CG.family(0) == "playstation" and CG.family(1) == "switch", "the fake seam names each pad")
	check(CG.family_of("pad1") == "switch" and CG.family_of("kb1") == "", "family_of reads a pad device, not a keyboard")
	check(CG.family(2) == "xbox", "a pad with no fake and no hardware falls to Xbox")
	game.session.glyphs = "steam"
	check(CG.family(0) == "steam" and CG.family(1) == "steam" and CG.family(2) == "steam", "the Options choice wins over detection")
	game.session.glyphs = "auto"
	check(CG.family(0) == "playstation", "Auto goes back to detection")
	CG.fake = {}
	CG.forget()

# the pictures
func _files() -> void:
	for fam in CG.FAMILIES:
		for a in ACTIONS:
			var t: Texture2D = CG.texture(fam, a)
			check(t != null and t.get_width() == 128 and t.get_height() == 128, "%s/%s is a 128 px picture" % [fam, a])
		var b: Texture2D = CG.body(fam)
		check(b != null and b.get_width() > 150 and b.get_width() <= 300 and b.get_height() > 100, "%s body is imported large enough for the panel (%s)" % [fam, b.get_size() if b else "null"])
	for dev in CG.KEYS:
		for a in CG.KEYS[dev]:
			check(CG.key_glyph(dev, a) != null, "%s %s has a key picture" % [dev, a])
	var glyph_script: GDScript = load("res://scripts/ui/controller_glyph.gd")
	for dev in glyph_script.CLUSTERS:
		for cl in glyph_script.CLUSTERS[dev]:
			for row in cl:
				for k in row:
					check(CG.key(k) != null, "key picture " + k)
	check(CG.texture("xbox", "nope") == null and CG.texture("nope", "confirm") == null, "an unknown picture is null, not an error")

func _provenance() -> void:
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/glyphs/PROVENANCE.json"))
	check(prov.get("archive_sha256") == ARCHIVE_SHA, "the archive the pictures came from is recorded")
	check(str(prov.get("source_url", "")).begins_with("https://kenney.nl/") and "CC0" in str(prov.get("licence", "")), "source URL and CC0 licence are recorded")
	check(FileAccess.get_file_as_string("res://assets/glyphs/LICENSE.txt").contains("Creative Commons Zero, CC0"), "the licence text ships with the pictures")
	var listed := {}
	for f: Dictionary in prov["files"]:
		var path := "res://" + str(f["runtime_path"])
		listed[path] = true
		check(FileAccess.file_exists(path) and FileAccess.get_sha256(path) == f["sha256"], "sha256 of " + path)
		check(FileAccess.get_file_as_bytes(path).size() == int(f["bytes"]), "byte count of " + path)
		if path.ends_with(".svg"):
			var head := RegEx.create_from_string("<svg width=\"([0-9.]+)\" height=\"([0-9.]+)\"").search(FileAccess.get_file_as_string(path))
			var tex: Texture2D = load(path)
			check(head != null and absf(float(head.get_string(1)) - float(f["width"])) < 0.01 and absf(float(head.get_string(2)) - float(f["height"])) < 0.01, "svg size of " + path)
			check(absf(tex.get_width() - float(f["width"])) <= 1.0 and absf(tex.get_height() - float(f["height"])) <= 1.0, "%s imports at its recorded size (%s)" % [path, tex.get_size()])
		if path.ends_with(".png"):
			var img := Image.new()
			check(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK and img.get_width() == int(f["width"]) and img.get_height() == int(f["height"]), "dimensions of " + path)
	var on_disk := _png_and_svg("res://assets/glyphs")
	for p in on_disk:
		check(listed.has(p), "%s is in PROVENANCE" % p)
	check(on_disk.size() == listed.size(), "PROVENANCE lists every picture (%d on disk, %d listed)" % [on_disk.size(), listed.size()])

func _png_and_svg(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png") or f.ends_with(".svg"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_png_and_svg(dir + "/" + d))
	return out

## Godot's JOY_BUTTON_A is the south button everywhere, so "confirm" must show the picture at that position: Cross, B.
func _by_position() -> void:
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/glyphs/PROVENANCE.json"))
	var src := {}
	for f: Dictionary in prov["files"]:
		src[f["runtime_path"]] = f["source_path"]
	for pair in [["xbox", "button_a"], ["playstation", "button_cross"], ["switch", "button_b"], ["steamdeck", "button_a"], ["steam", "button_a"]]:
		check(str(src["assets/glyphs/%s/confirm.png" % pair[0]]).ends_with("_%s.png" % pair[1]), "%s confirm is the south button (%s)" % pair)
	check(str(src["assets/glyphs/switch/back.png"]).ends_with("button_a.png"), "Switch back is the east button, printed A")
	var a: Image = CG.texture("playstation", "confirm").get_image()
	var b: Image = CG.texture("xbox", "confirm").get_image()
	check(a.get_data() != b.get_data(), "the PlayStation and Xbox confirm pictures differ")
	_fake({"vendor_id": "1356", "product_id": "3302"}, "PS5 Controller")
	check(controls.glyph_for("pad0", "confirm") == CG.texture("playstation", "confirm"), "Controls.glyph_for gives the pad's own family")
	check(controls.glyph_for("kb1", "confirm") == CG.key("f") and controls.glyph_for("kb1", "up") == CG.key("w"), "a keyboard cluster gives its key caps")
	check(controls.glyph_for("kb2", "confirm") == null and controls.glyph_for("shared", "confirm") == null, "Enter and Space have no cap picture: the text stays")
	check(controls.glyph_for("pad0", "up") == null, "an action with no picture is null")
	check(controls.label_for("pad0", "confirm") == "A" and controls.label_for("pad0", "dpad") == "D-pad", "label_for stays the text fallback")
	CG.fake = {}
	CG.forget()

# settings
func _settings(sess: GDScript) -> void:
	var s: Session = sess.new()
	check(s.glyphs == "auto", "Glyphs defaults to Auto")
	s.glyphs = "playstation"
	s.save_settings()
	check(sess.new().glyphs == "playstation", "the Glyphs choice survives a reload")
	var cf := ConfigFile.new()
	cf.load(SCRATCH)
	cf.set_value("controls", "glyphs", "dreamcast")
	cf.save(SCRATCH)
	check(sess.new().glyphs == "auto", "a hand-edited value outside the list is Auto")
	cf.set_value("controls", "glyphs", 7)
	cf.save(SCRATCH)
	check(sess.new().glyphs == "auto", "a value that is not text is Auto")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))

func _cache() -> void:
	CG.fake = {}
	CG.forget()
	CG.family(5)
	check(CG._cache.has(5), "a real pad's family is cached")
	Input.joy_connection_changed.emit(5, true)
	check(CG._cache.is_empty(), "a pad connecting drops the cache (ids are reused)")
	CG.family(5)
	Input.joy_connection_changed.emit(5, false)
	check(CG._cache.is_empty(), "a pad leaving drops the cache")
	CG._cache[5] = "playstation"
	controls._on_joy_connection(5, true)
	check(CG.family(5) == "xbox", "the next lookup reads the pad again")
	CG.forget()

func _options() -> void:
	game.session.glyphs = "auto"
	game.push("options", {})
	await create_timer(0.6).timeout
	var o: Node = game.stack.back()
	check(o.IDS == ["bgm", "sfx", "flashes", "glyphs", "controls"], "Options has a Glyphs row before Controls")
	o._set_focus(3)
	var seen := []
	for i in 5:
		o.on_action("kb1", "right")
		seen.append(game.session.glyphs)
	check(seen == ["xbox", "playstation", "switch", "steam", "auto"], "Right steps Auto, Xbox, PlayStation, Switch, Steam and wraps: %s" % [seen])
	o.on_action("kb1", "left")
	check(game.session.glyphs == "steam" and o.probe()["glyphs"] == "steam", "Left steps back and wraps")
	o.on_action("kb1", "confirm")
	check(game.session.glyphs == "auto", "Confirm steps forward")
	o.on_action("kb1", "right")
	o.on_action("kb1", "right")
	check(game.session.glyphs == "playstation", "the row is set to PlayStation")
	o._set_focus(4)
	o.on_action("kb1", "confirm")
	await create_timer(0.3).timeout
	check(o.probe()["page"] == "controls", "the Controls row still opens the Controls page")
	var widest := 0.0
	for row in o.CONTROL_ROWS:
		var w := 0.0
		for k in o.pad_keys(row):
			check(k is Texture2D, "the gamepad column shows %s as a picture" % [row["label"]])
			w += o.token_width(k) + 6.0
		widest = maxf(widest, w - 6.0)
	check(widest <= o.COL_W[3], "the gamepad column fits its glyphs (%.0f of %.0f)" % [widest, o.COL_W[3]])
	var ps_pause: Array = o.pad_keys({"pad": ["start"]})
	check(ps_pause[0] == CG.texture("playstation", "start"), "the Pause row shows the family's start picture")
	var cap: Rect2 = o.cap_rect(3)
	var room: float = cap.position.x - 14.0 - (o.PREVIEW_H + 4.0) * 4.0 - (o.row_rect(3).position.x + 14.0)
	check(Menu.text_width("Button pictures for your gamepad", 14, 600) < room, "the Glyphs note clears the four preview pictures (%.0f px of room)" % room)
	for word in o.GLYPH_NAMES.values():
		check(Menu.fit(word, 16, cap.size.x - 20.0, 11, 800) >= 13 and Menu.text_width(word, 16, 800) < 140.0, "%s fits the Glyphs capsule at a readable size" % word)
	o.on_action("kb1", "back")
	o.on_action("kb1", "back")
	await create_timer(0.4).timeout
	game.session.glyphs = "auto"
	check(not (game.stack.back() == o), "Options closes")

# the assign screen
func _assign() -> void:
	_fake({"vendor_id": "1356", "product_id": "3302", "raw_name": "DualSense Wireless Controller"}, "PS5 Controller")
	game.session.reset()
	game.session.begin("versus2p")
	game.push("assign", {"mode": "versus2p"})
	await create_timer(0.6).timeout
	var a: Node = game.stack.back()
	var g0: Control = a._slots[0]["glyph"]
	check(g0.picture() == "playstation", "an unclaimed glyph shows the first pad's family")
	check(a._slots[0]["hint_parts"].has(CG.texture("playstation", "confirm")), "the join hint shows the PlayStation confirm picture")
	check(a._slots[0]["hint_text"] == "F  /  Enter  /  A  to join", "the join hint keeps its text for the probe: " + a._slots[0]["hint_text"])
	controls.inject("pad0", "confirm")
	await create_timer(0.5).timeout
	var pr: Dictionary = a.probe()
	check(game.session.players[0]["device"] == "pad0" and pr["slots"][0]["claimed"], "pad0 claims Player 1")
	check(g0.picture() == "playstation" and pr["slots"][0]["family"] == "playstation", "the claim shows the PlayStation body and the probe says so")
	check(g0.picture() != "xbox" and CG.body("playstation") != CG.body("xbox"), "the PlayStation body is not the Xbox one")
	var ps := await _paint(g0)
	_fake({"vendor_id": "1118", "product_id": "2834"}, "Xbox Wireless Controller")
	var xb := await _paint(g0)
	check(g0.picture() == "xbox" and ps.get_data() != xb.get_data(), "the drawn pixels change with the family")
	check(_ink(ps) > 2500 and _ink(xb) > 2500, "the body draws in BA ink (%d, %d px)" % [_ink(ps), _ink(xb)])
	# a pad that reconnects as another model: the screen reads the family again
	Input.joy_connection_changed.emit(0, true)
	check(a._slots[1]["hint_parts"].has(CG.texture("xbox", "confirm")), "after a connection change the hint shows the new family's picture")
	_fake({"vendor_id": "1406", "product_id": "8201"}, "Nintendo Switch Pro Controller")
	Input.joy_connection_changed.emit(0, true)
	check(a._slots[1]["hint_parts"].has(CG.texture("switch", "confirm")) and g0.picture() == "switch", "and so does the claimed body")
	controls.inject("kb1", "confirm")
	await create_timer(0.3).timeout
	check(a._slots[1]["device"] == "kb1" and a._slots[1]["glyph"].picture() == "kb1", "a keyboard claim shows the keyboard picture, not a pad")
	var kb := await _paint(a._slots[1]["glyph"])
	check(_ink(kb) > 800, "the key caps draw (%d px)" % _ink(kb))
	controls.inject("kb1", "back")
	await create_timer(0.3).timeout
	check(a._slots[1]["glyph"].picture() == "switch", "unclaiming puts the pad body back")
	await game.go("menu", {}, "cut")
	CG.fake = {}
	CG.forget()

func _paint(g: Control) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(300, 200)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(300, 200)
	vp.add_child(bg)
	var c: Control = load("res://scripts/ui/controller_glyph.gd").new()
	c.device = g.device
	c.number = g.number
	c.position = Vector2(24, 20)
	vp.add_child(c)
	for i in 3:
		await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img

## Pixels that are close to BA ink: the picture, not the white card or the disc's navy.
func _ink(img: Image) -> int:
	var n := 0
	var ink: Color = (load("res://scripts/ui/ba_tokens.gd") as GDScript).INK
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if absf(c.r - ink.r) < 0.04 and absf(c.g - ink.g) < 0.04 and absf(c.b - ink.b) < 0.04:
				n += 1
	return n

# the HUD
func _hud() -> void:
	var Bottom: GDScript = load("res://scripts/fight/hud_bottom.gd")
	var Training: GDScript = load("res://scripts/fight/hud_training.gd")
	var real: Session = game.session
	game.session = PadSession.new()
	_fake({"vendor_id": "1356", "product_id": "3302"}, "PS5 Controller")
	var b: Control = Bottom.new()
	check(b.key_glyph(0) == CG.texture("playstation", "lb"), "the assist key shows the pad's L1 picture")
	check(b.key_label(0) == "LB", "key_label stays the text fallback (%s)" % b.key_label(0))
	check(b.key_glyph(1) == null and b.key_label(1) == ",", "a keyboard device keeps its letter")
	b.free()
	var sizes := []
	var painter: Control = (load("res://scripts/ui/painter.gd") as GDScript).new().setup(Vector2(400, 300), func(c: Control) -> void:
		sizes.append(Training.draw_tip(c, Vector2.ZERO)))
	root.add_child(painter)
	await process_frame
	await process_frame
	painter.queue_free()
	check(not sizes.is_empty() and sizes[0].x > 100 and sizes[0].y > 100, "the tip bubble draws with glyph chips (%s)" % [sizes])
	game.session = real
	CG.fake = {}
	CG.forget()

## A glyph chip must sit inside its ribbon, and the long hint lines must still fit theirs.
func _chips() -> void:
	for fam in CG.FAMILIES:
		for a in ["confirm", "lb", "dpad"]:
			var t: Texture2D = CG.texture(fam, a)
			var ribbon := Rect2(0, 0, Training_chip_w(), 24.0)
			var gh := ribbon.size.y * 0.84
			check(gh <= ribbon.size.y - 2.0 and Menu.parts_width([t], 11, gh) <= ribbon.size.x - 8.0, "%s %s chip fits its training ribbon" % [fam, a])
	var join: Array = []
	for d in ["kb1", "kb2", "pad0", "shared"]:
		var g: Texture2D = controls.glyph_for(d, "confirm")
		join.append_array([g if g != null else controls.label_for(d, "confirm"), "  /  "])
	join.append("  to start")
	var screen: GDScript = load("res://scripts/screens/assign_screen.gd")
	check(Menu.parts_width(join, 16, screen.GLYPH_H) + 44.0 <= 560.0, "the longest join hint fits its ribbon (%.0f)" % (Menu.parts_width(join, 16, screen.GLYPH_H) + 44.0))
	check(absf(screen.GLYPH_H - 30.0 * 0.76) < 0.5, "the assign ribbon's glyph side matches ribbon_parts")
	var tip: Array = [CG.texture("xbox", "dpad"), "  Browse", "        ", CG.texture("xbox", "aux"), "  Fighters / Specials", "        ", CG.texture("xbox", "lb"), " / ", CG.texture("xbox", "rb"), "  Switch tab", "        ", CG.texture("xbox", "back"), "  Back"]
	check(Menu.parts_width(tip, 14, 22.0) + 60.0 < 1232.0, "the gallery hint line fits")

func Training_chip_w() -> float:
	return (load("res://scripts/fight/hud_training.gd") as GDScript)._chip_w(CG.texture("xbox", "confirm"))
