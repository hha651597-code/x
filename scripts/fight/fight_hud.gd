extends Control
## In-fight HUD facade (1280x720 reference pixels). It builds the sprite modules and routes FightScreen's calls to them. Every
## module ticks itself and reads the world, so the facade keeps only what crosses modules: the banner layer, the flash, the
## ducking under the EX cut-in, the round-start entrance and the pause menu's items. The rails and cards also hide while the stage
## entry's shots play (the world's intro_cover) and whip in when round_intro runs at the wide beat. Nothing else of the HUD is up
## before that: the banner, cut-in, flash and pause layers only draw on request.
##
## Layers (child order = draw order):  top rail · bottom row · feed · training overlay · banner · EX cut-in · flash · pause.
##
## API used by FightScreen: setup · round_intro · banner · on_combo · cutin · cutin_stop · assist_callout · flash · show_pause ·
## refresh · pause_action (+ pause_items / pause_activate for the pause panel).

const PainterScript := preload("res://scripts/ui/painter.gd")
const TopScript := preload("res://scripts/fight/hud_top.gd")
const BottomScript := preload("res://scripts/fight/hud_bottom.gd")
const FeedScript := preload("res://scripts/fight/hud_feed.gd")
const BannerScript := preload("res://scripts/fight/hud_banner.gd")
const CutinScript := preload("res://scripts/fight/hud_cutin.gd")
const PauseScript := preload("res://scripts/fight/hud_pause.gd")
const TrainScript := preload("res://scripts/fight/hud_training.gd")
const DemoScript := preload("res://scripts/fight/hud_demo.gd")

const ENTER_TOP := 170.0       # px the top rail starts above its place
const ENTER_BOTTOM := 150.0    # px the bottom row starts below its place

var world: Node
var _time := 0.0
var _flash_col := Color(1, 1, 1, 0)
var _top: Control
var _bottom: Control
var _feed: Control
var _train: Control
var _banner_layer: Control
var _flash_layer: Control
var _banner := BannerScript.new()
var _cutin: Control
var _pause: Control
var _paused := false
var _guard_bars: Array = []      # hud_top's guard bars; scripts/models/tests/guard_test.gd reads their shader params
var _wins_banner := [0, 0]
var _enter_age := 10.0     # seconds into the match-start entrance; its own clock, so a load hitch does not eat it
var _entered := false      # later rounds and training resets keep the HUD where it is
var _dim_nodes: Array = []

func setup(w: Node) -> void:
	world = w
	DemoScript._done.clear()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100     # above the EX-freeze veil (70) and the raised caster (75): hud_cutin.gd, FREEZE_Z in fight_screen.gd
	_wins_banner = [int(w.wins[0]), int(w.wins[1])]
	_top = TopScript.new().setup(w)
	add_child(_top)
	_guard_bars = _top.guard_bars
	_bottom = BottomScript.new().setup(w)
	add_child(_bottom)
	_feed = FeedScript.new().setup(w)
	add_child(_feed)
	_train = TrainScript.new().setup(self)
	add_child(_train)
	_dim_nodes = [_top, _bottom, _feed, _train]
	_banner_layer = PainterScript.new().setup(Vector2(1280, 720), func(c: Control) -> void: _banner.draw(c, _time))
	add_child(_banner_layer)
	_cutin = CutinScript.new()
	add_child(_cutin)
	_cutin.attach(world)
	_flash_layer = PainterScript.new().setup(Vector2(1280, 720), _draw_flash)
	add_child(_flash_layer)
	_pause = PauseScript.new().setup(self)
	add_child(_pause)

# API used by FightScreen
func round_intro(n: int) -> void:
	DemoScript.apply(self)
	_train.reset()
	_bottom.reset()
	if not _entered:
		_entered = true
		_enter_age = 0.0
	var txt := "ROUND %d" % n
	if world.training:
		txt = "TRAINING"
	elif world.wins[0] == 1 and world.wins[1] == 1:
		txt = "FINAL ROUND"
	banner(txt, "", Color.WHITE, 0.98)

## FightScreen raises wins[] just before it calls this with "<NAME> WINS", so the slot that gained a win is the winner, even in
## a mirror match. Called without a fresh win (a bare banner call), the first fighter with that name takes it.
func banner(text: String, sub: String, color: Color, dur: float) -> void:
	var ws := 0
	if text.ends_with("WINS"):
		for i in 2:
			if int(world.wins[i]) > int(_wins_banner[i]):
				ws = i + 1
		if ws == 0:
			var nm := text.left(text.length() - 5)
			for i in [1, 0]:
				if Fighters.display_name((world.fighters[i] as Fighter).data).to_upper() == nm:
					ws = i + 1
	_wins_banner = [int(world.wins[0]), int(world.wins[1])]
	_banner.start(text, sub, color, dur, _time, ws)

func on_combo(att: Fighter, def: Fighter, hits: int, h := {}) -> void:
	_feed.on_combo(att, def, hits, h)
	if att.slot == 1 and hits >= 2:
		_train.note_combo(hits, def.combo_dmg, _time)

func cutin(f: Fighter) -> void:
	_cutin.start(f)

func cutin_stop() -> void:
	_cutin.stop()

func assist_callout(f: Fighter) -> void:
	_bottom.callout(f)

func flash(color: Color, alpha: float) -> void:
	_flash_col = Color(color.r, color.g, color.b, FxFlash.flash(alpha))

func show_pause(p: bool) -> void:
	_paused = p
	if p:
		_pause.open()
	else:
		_pause.close()

func refresh() -> void:
	_train.sample(world)

# pause menu
func pause_items() -> Array:
	var items: Array = [
		{"id": "resume", "label": "Resume", "value": ""},
		{"id": "restart", "label": "Reset Positions" if world.training else "Restart Round", "value": ""},
	]
	if world.training:
		items.append({"id": "dummy", "label": "Dummy", "value": str(world.dummy_mode).capitalize()})
		items.append({"id": "boxes", "label": "Hitboxes", "value": "On" if world.debug_boxes else "Off"})
		items.append({"id": "exinf", "label": "Infinite EX", "value": "On" if world.infinite_meter else "Off"})
	items.append({"id": "select", "label": "Character Select", "value": ""})
	items.append({"id": "menu", "label": "Main Menu", "value": ""})
	return items

func pause_activate(i: int, step := 1) -> void:
	var items := pause_items()
	if i < 0 or i >= items.size():
		return
	Sfx.play("confirm")
	match str(items[i]["id"]):
		"resume":
			world.set_paused(false)
		"restart":
			world.restart_round()
		"dummy":
			world.cycle_dummy(step)
		"boxes":
			world.debug_boxes = not world.debug_boxes
		"exinf":
			world.infinite_meter = not world.infinite_meter
		"select":
			world.quit_to_select()
		"menu":
			world.quit_to_menu()

func pause_action(act: String) -> void:
	var items := pause_items()
	match act:
		"up":
			_pause.select(_pause.index - 1)
		"down":
			_pause.select(_pause.index + 1)
		"left", "right":
			var id := str(items[_pause.index]["id"])
			if id in ["dummy", "boxes", "exinf"]:
				pause_activate(_pause.index, 1 if act == "right" else -1)
		"back":
			world.set_paused(false)
		"confirm":
			pause_activate(_pause.index)

## Label for a meter value: SUPER from Arena.SUPER_COST, EX READY from Arena.EX_COST. No HUD piece draws it since the cost
## cells replaced the gauge; super_test.gd pins the thresholds.
static func meter_label(meter: float) -> String:
	if meter >= Arena.EX_COST:
		return "EX READY"
	if meter >= Arena.SUPER_COST:
		return "SUPER"
	return "EX"

# per-frame
func _process(delta: float) -> void:
	if not _paused:
		_time += delta
	_flash_col.a = maxf(0.0, _flash_col.a - delta * 2.4)
	if world == null or world.f1 == null:
		return
	if Game.busy:
		_enter_age = 0.0     # starts once the transition has uncovered the fight
	elif _paused:
		_enter_age = 10.0     # the pause menu opens over a settled rail, never one frozen half way up
	else:
		_enter_age += minf(delta, 1.0 / 30.0)
	_top.position.y = -ENTER_TOP * (1.0 - Motion.whip(_enter_age))
	_bottom.position.y = ENTER_BOTTOM * (1.0 - Motion.whip(_enter_age - Motion.stagger(1)))
	_cutin.sync(world)
	var duck := 1.0 - 0.82 * float(_cutin.strength())     # the HUD ducks under the EX cut-in
	var cover: Variant = world.get("intro_cover")     # the stage entry's shots hide the rails and cards
	var hidden := clampf(float(cover), 0.0, 1.0) if cover is float or cover is int else 0.0
	for n in _dim_nodes:
		(n as Control).modulate.a = duck * (1.0 - hidden)
	DemoScript.tick(self)
	_banner_layer.queue_redraw()
	_flash_layer.queue_redraw()

func _draw_flash(c: Control) -> void:
	if _flash_col.a > 0.01:
		c.draw_rect(Rect2(0, 0, 1280, 720), _flash_col)
