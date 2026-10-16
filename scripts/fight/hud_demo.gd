extends RefCounted
## Screenshot scenarios for the HUD (debug only, inert unless the environment variable HUD_DEMO is set), e.g.
##   HUD_DEMO=lowhp,ex,assist zsh tools/run.sh scripts/fight/tools/shots/hud_facade_lowhp_ex.json
## Applied at the start of every round (after the fighters were reset). Parts: lowhp ex assist wins win1 nearko time10.

static func apply(hud: Control) -> void:
	var s := OS.get_environment("HUD_DEMO")
	if s == "" or not OS.is_debug_build():
		return
	var w: Node = hud.world
	var f1: Fighter = w.f1
	var f2: Fighter = w.f2
	for part in s.split(","):
		match part:
			"lowhp":
				f1.hp = f1.max_hp * 0.18
				f2.hp = f2.max_hp * 0.55
			"ex":
				f1.meter = 100.0
				f2.meter = 62.0
			"assist":
				f1.assist_cd = 0
				f2.assist_cd = 0
			"wins":
				w.wins = [1, 1]
				w.round_no = 3
			"win1":
				w.wins = [1, 0]
			"nearko":
				f2.hp = 4.0
			"bothlow":
				f1.hp = 5.0
				f2.hp = 5.0
			"time10":
				w.timer_frames = 10 * 60 + 30     # half a second before the last ten seconds, so the WARNING fires

## HUD_SHOT=<dir>: the HUD saves a PNG a moment into each banner kind (once per round), for KO / wins / pips shots in CPU-vs-CPU runs.
static var _done := {}
const SNAP_AT := {"ko": 0.5, "win": 0.8, "timeup": 0.5, "round": 0.45, "fight": 0.2}

static func tick(hud: Control) -> void:
	if not OS.is_debug_build():
		return
	var dir := OS.get_environment("HUD_SHOT")
	if dir == "" or not hud._banner.active:
		return
	var k: String = hud._banner.kind
	var age: float = hud._time - float(hud._banner.t0)
	var key := "%s%d" % [k, int(hud.world.round_no)]
	if SNAP_AT.has(k) and age >= float(SNAP_AT[k]) and not _done.has(key):
		_done[key] = true
		_snap(hud, "%s/hud_auto_%s_r%d.png" % [dir, k, int(hud.world.round_no)])

static func _snap(hud: Control, path: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = hud.get_viewport().get_texture().get_image()
	if img.get_width() != 1280:
		img.resize(1280, 720, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("SNAP ", path)
