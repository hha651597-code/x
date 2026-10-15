extends SceneTree
## Captures of every place a controller glyph shows, one pad family at a time through the fake joy seam (no pad needed).
## Run: zsh tools/glyph_shots.sh OUTDIR [WIDTHxHEIGHT]. Game scripts are load()ed inside _run().

const PADS := {
	"xbox": [{"vendor_id": "1118", "product_id": "2834"}, "Xbox Wireless Controller"],
	"playstation": [{"vendor_id": "1356", "product_id": "3302"}, "PS5 Controller"],
	"switch": [{"vendor_id": "1406", "product_id": "8201"}, "Nintendo Switch Pro Controller"],
	"steamdeck": [{"vendor_id": "10462", "product_id": "4613"}, "Steam Deck"],
	"steam": [{"vendor_id": "10462", "product_id": "4354"}, "Steam Controller"],
}

class PadSession extends Session:
	func device_of(slot: int) -> String:
		return "pad0" if slot == 1 else "kb2"

var out := "/tmp/ba-bld-out/cg"
var game: Node
var CG: GDScript

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(600.0).timeout.connect(func() -> void:
		print("GLYPH_SHOTS FAIL watchdog timeout")
		quit(3))
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var size := Vector2i(1280, 720)
	if args.size() > 1:
		size = Vector2i(int(args[1].get_slice("x", 0)), int(args[1].get_slice("x", 1)))
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	CG = load("res://scripts/ui/controller_glyphs.gd")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	root.get_window().size = size
	await _frames(3)
	var tag := "" if size.x == 1280 else "_%d" % size.x
	for fam in PADS:
		_fake(fam)
		await _assign(fam, tag)
	await _keyboards(tag)
	for fam in PADS:
		_fake(fam)
		await _options(fam, tag)
	await _gallery(tag)
	await _hud(tag)
	print("GLYPH_SHOTS done")
	quit(0)

func _fake(fam: String) -> void:
	CG.fake = {0: {"info": PADS[fam][0], "name": PADS[fam][1]}, 1: {"info": PADS[fam][0], "name": PADS[fam][1]}}

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _save(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	print("saved ", name, " ", img.get_size(), " ", error_string(img.save_png("%s/%s.png" % [out, name])))

func _assign(fam: String, tag: String) -> void:
	game.session.reset()
	game.session.begin("versus2p")
	game.push("assign", {"mode": "versus2p"})
	await create_timer(2.2).timeout
	_save("assign_%s_0%s" % [fam, tag])
	root.get_node("Controls").inject("pad0", "confirm")
	await create_timer(1.3).timeout
	_save("assign_%s_1%s" % [fam, tag])
	root.get_node("Controls").inject("pad1", "confirm")
	game.stack.back()._finish_t = 99.0
	await create_timer(1.3).timeout
	_save("assign_%s_2%s" % [fam, tag])
	await game.go("menu", {}, "cut")
	await create_timer(0.8).timeout

func _keyboards(tag: String) -> void:
	_fake("playstation")
	for pair in [["kb1", "kb2", "kbs"], ["kb2", "pad0", "kb_pad"]]:
		game.session.reset()
		game.session.begin("versus2p")
		game.push("assign", {"mode": "versus2p"})
		await create_timer(2.2).timeout
		root.get_node("Controls").inject(pair[0], "confirm")
		await create_timer(0.6).timeout
		root.get_node("Controls").inject(pair[1], "confirm")
		game.stack.back()._finish_t = 99.0
		await create_timer(1.3).timeout
		_save("assign_%s%s" % [pair[2], tag])
		await game.go("menu", {}, "cut")
		await create_timer(0.8).timeout

func _options(fam: String, tag: String) -> void:
	game.session.glyphs = "auto"
	game.push("options", {})
	await create_timer(0.8).timeout
	var o: Node = game.stack.back()
	o._focus = 3
	await _frames(4)
	_save("options_%s%s" % [fam, tag])
	o._set_page("controls")
	await create_timer(0.4).timeout
	_save("options_controls_%s%s" % [fam, tag])
	game.pop()
	await create_timer(0.4).timeout

func _gallery(tag: String) -> void:
	_fake("playstation")
	await game.go("gallery", {}, "cut")
	await create_timer(1.2).timeout
	var g: Node = game.stack.back()
	g._last_dev = "pad0"
	g._refresh_hint()
	await _frames(4)
	_save("gallery_pad%s" % tag)
	g._last_dev = "kb1"
	g._refresh_hint()
	await _frames(4)
	_save("gallery_kb%s" % tag)

func _hud(tag: String) -> void:
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	game.session.players[0]["special"] = 20001
	game.session.players[1]["special"] = 23005
	root.get_node("Dbg").intro_entry = false
	var real: Session = game.session
	for fam in ["xbox", "playstation", "switch"]:
		_fake(fam)
		game.session = PadSession.new()
		game.session.begin("training")
		game.session.players[0]["fighter"] = 10004
		game.session.players[1]["fighter"] = 10005
		game.session.players[0]["special"] = 20001
		game.session.players[1]["special"] = 23005
		await game.go("fight", {}, "cut")
		await create_timer(2.0).timeout
		_save("hud_%s%s" % [fam, tag])
		var fs: Node = game.stack.back()
		fs.hud.show_pause(true)
		await create_timer(1.0).timeout
		_save("hud_pause_%s%s" % [fam, tag])
