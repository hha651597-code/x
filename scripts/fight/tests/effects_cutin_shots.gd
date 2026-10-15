extends SceneTree
## Captures for the effects, taken on exact sim ticks instead of by waiting: the fight's physics are off and the freeze
## clock is set by hand, so a frame is the same on every run. Sets (E2_SETS, comma separated, default all):
##   cutin   the ult cut-in for Hina and Hoshino as P1 and Hina as P2, at ticks E2_TICKS (default 6, 30 and 56) of the 72
##   reduce  the EX stamp (tick 20), the trigger flash (tick 1) and an EX hit's flash with Reduce Flashes off and on
##   kinds   dust, sparkle, heal, boom, K.O. burst, the swish and slash and the impact frame at 15, 40 and 70 percent of their life on a bright
##           stage (Gehenna day) and a dark one (Gehenna night)
## Run: zsh tools/effects_cutin_shots.sh [WxH]   ->   E2_OUT (default tmp/e2)/<set>_*.png. A real window, never headless.
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

class StubSession extends Session:
	func _init() -> void:
		super()
		reduce_flashes = true

var game: Node
var screen: Node
var out := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("E2_SHOTS FAIL watchdog timeout")
		quit(3))
	await process_frame
	out = OS.get_environment("E2_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("res://tmp/e2")
	DirAccess.make_dir_recursive_absolute(out)
	var sets := OS.get_environment("E2_SETS")
	var want: Array = (sets if sets != "" else "cutin,reduce,kinds").split(",")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	if "cutin" in want:
		await _cutin("hina", 10004, 10005, 1)
		await _cutin("hoshino", 10005, 10004, 1)
		await _cutin("hina_p2", 10005, 10004, 2)
	if "reduce" in want:
		await _reduce()
	if "kinds" in want:
		await _kinds("day", "bright")
		await _kinds("night", "dark")
	print("E2_SHOTS done ", out)
	quit(0)

## A fight with its physics off. `mode` versus2p keeps both fighters human (P2 can cast).
func _fight(p1: int, p2: int, stage_id := "gehenna-night") -> void:
	game.session.begin("versus2p")
	game.session.players[0]["fighter"] = p1
	game.session.players[1]["fighter"] = p2
	for st in (load("res://scripts/core/stages.gd") as GDScript).LIST:
		if st["id"] == stage_id:
			game.session.stage = st
	root.get_node("Dbg").intro_entry = false     # the 300 tick entry intro would hide the idle picture these checks need
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.phase = "fight"
	for i in 90:
		await process_frame
	screen.set_physics_process(false)

func _snap(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))

## The freeze clock set by hand: `tick` of 72.
func _at(tick: int) -> void:
	screen.freeze_t = tick
	screen.time_stop = 72 - tick

func _cast(slot: int) -> void:
	var f: Object = screen.f1 if slot == 1 else screen.f2
	screen.begin_cutin(f)
	screen._enter_freeze()

func _cutin(name: String, p1: int, p2: int, slot: int) -> void:
	await _fight(p1, p2)
	_cast(slot)
	var ticks := OS.get_environment("E2_TICKS")
	for t in (ticks if ticks != "" else "6,30,56").split(","):
		_at(int(t))
		await _snap("cutin_%s_t%02d" % [name, int(t)])
	screen._clear_freeze()

func _reduce() -> void:
	await _fight(10004, 10005)
	var real: Object = game.session
	var Flash: GDScript = load("res://scripts/fight/fx_flash.gd")
	_cast(1)
	for on in [false, true]:
		game.session = StubSession.new() if on else real
		for t in [1, 20]:
			_at(t)
			await _snap("reduce_%s_stamp_t%02d" % ["on" if on else "off", t])
	game.session = real
	screen._clear_freeze()
	await process_frame
	# an EX hit: the star, its ring and the facade's full-screen flash (hud.flash caps with FxFlash)
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	screen.f1.position = Vector2(-120.0, 560.0)
	screen.f2.position = Vector2(60.0, 560.0)
	for on in [false, true]:
		game.session = StubSession.new() if on else real
		var fx_layer: Node2D = screen.fx_layer
		for c in fx_layer.get_children():
			c.queue_free()
		FX.spark(fx_layer, Vector2(40.0, 400.0), "ex", 1, 1.0)
		screen.hud.flash(Color(1, 1, 1), 0.5)
		for fx in fx_layer.get_children():
			fx.set_process(false)
			fx._process(0.46 * 0.25)
		await _snap("reduce_%s_ex_hit" % ["on" if on else "off"])
	game.session = real

## Two groups so nothing overlaps: the small ones in a row, and the explosion with the K.O. burst. x is spaced from the middle.
const GROUPS := {
	"small": [
		["dust", 0.45, {"seed": 0.0, "size": 1.0}, 556.0],
		["dust", 0.45, {"seed": 1.0, "size": 1.0}, 556.0],
		["sparkle", 0.6, {"color": Color(1.0, 1.0, 1.0), "size": 1.4}, 380.0],
		["sparkle", 0.6, {"color": Color(0.62, 0.93, 1.0), "size": 1.4}, 380.0],
		["heal", 1.1, {"seed": 1.0}, 556.0],
		["swish", 0.3, {"color": Color(0.9, 0.7, 0.4), "dir": 1, "off": Vector2.ZERO, "r": 100.0, "thick": 30.0}, 380.0],
		["slash", 0.35, {"color": Color(1.0, 1.0, 1.0), "dir": 1, "off": Vector2.ZERO}, 380.0],
	],
	"big": [
		["boom", 0.55, {"color": Color(1.0, 0.55, 0.2), "size": 1.0, "seed": 1.0}, 420.0],
		["ko", 1.0, {"color": Color(1.0, 0.45, 0.4), "seed": 1.0}, 420.0],
	],
	"impact": [["impact", 0.05, {"seed": 1.0, "z": 70}, 400.0]],
}

func _kinds(time: String, name: String) -> void:
	game.session.stage_time = time
	await _fight(10004, 10005)
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var Flash: GDScript = load("res://scripts/fight/fx_flash.gd")
	screen.fighters_layer.visible = false
	var layer: Node2D = screen.fx_layer
	for group in GROUPS:
		var list: Array = GROUPS[group]
		for frac in [0.15, 0.4, 0.7]:
			for c in layer.get_children():
				c.free()
			for i in list.size():
				var spec: Array = list[i]
				var x := -450.0 + 150.0 * float(i) if group == "small" else -300.0 + 560.0 * float(i)
				if group == "impact":
					x = 0.0
					Flash.set("_last_impact_ms", -100000)
				var fx: Node2D = FX.make(layer, spec[0], Vector2(x, float(spec[3])), float(spec[1]), spec[2])
				fx.set_process(false)
				fx._process(float(spec[1]) * float(frac))
			await _snap("kinds_%s_%s_%02d" % [name, group, int(frac * 100.0)])
