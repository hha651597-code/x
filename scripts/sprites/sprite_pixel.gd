class_name SpritePixel
extends RefCounted
## Pixel-art helpers for the fight camera (the screen's camera is scripts/fight/fight_screen.gd → _apply_camera; this
## corrects it per render frame from FighterView, see apply_camera).
##
## A pixel fighter is crisp only when one art pixel (SpriteSet.art_px = 2 world px) covers a WHOLE number of device
## pixels: device px per art px = art_px × camera zoom × screen scale (the canvas_items stretch: 1 at a 1280×720 window,
## 2 on a Retina Mac at 1280×720 points, 1.5 at 1920×1080…). So while a pixel fighter is in the match the camera zoom is
## held on the levels  zoom = n / (art_px × screen scale)  (n = whole device px per art px): at screen scale 2 that is
## 0.75 / 1.0 / 1.25, at 1.5 → 0.667 / 1.0, at 1 → 0.5 / 1.0. The displayed zoom eases between levels (the frame shader
## anti-aliases the pixel seams during the ease) and settles EXACTLY on the level.
## Rules: the level is the largest one at most 15 % tighter than the smooth camera's zoom (that camera keeps ~320 world px
## of air around the fighters, so 15 % tighter still frames them with > 100 px to spare; at screen scale 2 this gives
## 1.0 up to ~830 px between the fighters, 0.75 beyond, and 1.25 for the EX / KO push-ins); it only zooms in again once
## the smooth zoom clears the next level by 0.02 (no flicker at a boundary); levels below 0.7 (stage edges show) are not
## used — when no clean level is near (low-density screens zoomed out) the smooth zoom is used as is and the frame
## shader's sharp-AA path keeps the pixels even. A looser level than the smooth zoom re-clamps the camera centre so the
## view never passes the stage's edge (same bound as the screen: HALF_W + 150).

const MIN_ZOOM := 0.7          # the fight camera's own minimum: wider shows the stage edges
const TOL := 1.15              # a level may be this much tighter than the smooth camera's zoom
const HYST := 0.02             # zoom-in hysteresis (zoom units)
const FIT_PAD := 130.0         # world px kept visible beyond each fighter's centre (a sprite's half width + air)

## Device pixels per reference (1280×720) pixel of the root viewport.
static func screen_scale(vp: Viewport) -> float:
	if vp == null:
		return 1.0
	var vis := vp.get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	if vis.x <= 0.0 or vis.y <= 0.0 or win.x <= 0.0 or win.y <= 0.0:
		return 1.0
	return minf(win.x / vis.x, win.y / vis.y)

## World px per art pixel of the first pixel-art sprite fighter in `fighters` (Fighter nodes), 0 when there is none.
static func art_px_of(fighters: Array) -> float:
	for f in fighters:
		if not is_instance_valid(f):
			continue
		var v: Variant = (f as Object).get("view")
		if not (v is Node):
			continue
		var ss: Variant = (v as Node).get("sset")
		if ss is SpriteSet and bool((v as Node).get("sprite_mode")) and (ss as SpriteSet).pixel:
			return (ss as SpriteSet).art_px
	return 0.0

## The tightest zoom that still shows both fighters with FIT_PAD world px beyond their centres (INF when unknown).
static func fit_zoom(fighters: Array) -> float:
	var lo := INF
	var hi := -INF
	for f in fighters:
		if is_instance_valid(f) and f is Node2D:
			lo = minf(lo, (f as Node2D).position.x)
			hi = maxf(hi, (f as Node2D).position.x)
	if hi < lo:
		return INF
	return 640.0 / ((hi - lo) * 0.5 + FIT_PAD)

## The clean zoom level for a smooth `want` (`unit` = zoom per whole device px of an art pixel), or `want` itself when
## no clean level is near.
static func level(want: float, unit: float, margin := 0.0) -> float:
	var n := floorf((want * TOL - margin) / unit + 0.0001)
	var z := n * unit
	if z < MIN_ZOOM - 0.0001:
		z = (n + 1.0) * unit
		if z > want * 1.1:
			return want
	return z

## Fight camera hook: the target zoom to ease to. Returns `want` unchanged when no pixel fighter is in the match.
## State (the current level) is kept as meta "pixel_zoom" on `screen`.
static func fight_zoom(screen: Node, want: float) -> float:
	var fl: Variant = screen.get("fighters")
	var art := art_px_of(fl if fl is Array else [])
	if art <= 0.0:
		screen.set_meta("pixel_zoom", 0.0)
		return want
	var unit := 1.0 / maxf(art * screen_scale(screen.get_viewport()), 0.01)
	var cur := float(screen.get_meta("pixel_zoom", 0.0))
	var z := level(want, unit)
	if cur > 0.0 and z > cur + 0.0001 and level(want, unit, HYST) <= cur + 0.0001:
		z = cur
	# never so tight that a fighter leaves the screen: a lower clean level, else the smooth zoom (sharp-AA pixels)
	var fit := fit_zoom(fl if fl is Array else [])
	if z > fit + 0.0001:
		var lower := floorf(fit / unit + 0.0001) * unit
		z = lower if lower >= MIN_ZOOM - 0.0001 else minf(want, fit)
	var clean := absf(z / unit - roundf(z / unit)) < 0.001
	var was_clean := cur > 0.0 and absf(cur / unit - roundf(cur / unit)) < 0.001
	if harness() and absf(z - cur) > 0.0001 and (clean or was_clean):
		var ss := screen_scale(screen.get_viewport())
		print("PIXELCAM level %.3f (camera wants %.3f, fit %.3f) screen scale %.2f -> %.2f device px per art px%s" % [
			z, want, minf(fit, 9.99), ss, z * art * ss, "" if clean else " (no clean level: smooth zoom, sharp-AA pixels)"])
	screen.set_meta("pixel_zoom", z)
	return z

## True while the verification harness runs a step file (scripts/core/dbg.gd): log lines are printed only then.
static func harness() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var d := tree.root.get_node_or_null("Dbg")
	return d != null and String(d.get("_script_path")) != ""

## Camera post-pass, called by FighterView every render frame while it shows a pixel fighter (the fight screen moves its
## camera on sim ticks, views step after them). It re-applies the screen's own camera (world_root transform, stage
## parallax, floor uniforms) at the DISPLAYED zoom: the screen's smooth zoom quantised to a clean level (fight_zoom), eased
## between levels like the screen eases (0.14 out / 0.07 in per tick) and landing exactly on the level. The zoom pivot is
## the screen's: world (cam_x, GROUND - lift) stays where the screen put it. Runs once per screen camera update (the screen
## sets world_root.scale = cam_zoom each tick; a different scale means this pass already ran). Does nothing when a member
## it needs is missing or no pixel fighter is in the match.
static func apply_camera(screen: Node) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	var wr: Variant = screen.get("world_root")
	var zv: Variant = screen.get("cam_zoom")
	if not (wr is Node2D) or not (zv is float):
		return
	var root := wr as Node2D
	var z := float(zv)
	if absf(root.scale.x - z) > 0.000001:
		return                                   # already applied since the screen's last camera update
	var lvl := fight_zoom(screen, z)
	if float(screen.get_meta("pixel_zoom", 0.0)) <= 0.0:
		return
	var last_z := float(screen.get_meta("pixel_cam_z", z))
	var e := float(screen.get_meta("pixel_cam_e", lvl))
	if absf(z - last_z) > 0.08:
		e = lvl                                  # camera reset (new round)
	elif absf(e - lvl) < 0.004:
		e = lvl
	else:
		e = lerpf(e, lvl, 0.14 if lvl < e else 0.07)
	screen.set_meta("pixel_cam_z", z)
	screen.set_meta("pixel_cam_e", e)
	if absf(e - z) < 0.000001:
		return
	var cam_x := float(screen.get("cam_x")) if screen.get("cam_x") is float else 0.0
	var bg: Variant = screen.get("bg_layer")
	var lift := float((bg as Node).get_meta("lift", 0.0)) if bg is Node else 0.0
	# a looser view than the screen planned: keep it inside the stage (the screen's own bound, for this zoom)
	var cx := cam_x
	if e < z:
		var lim := maxf(Arena.HALF_W + 150.0 - 640.0 / e, 0.0)
		cx = clampf(cam_x, -lim, lim)
	var pos := root.position + Vector2(cam_x * z - cx * e, (Arena.GROUND - lift) * (z - e))
	root.scale = Vector2(e, e)
	root.position = pos
	# the stage's camera hooks, with the screen's shake (same formula as FightScreen._apply_camera)
	var sk: Variant = screen.get("_shake")
	var fr: Variant = screen.get("_frame")
	var sh := Vector2.ZERO
	if sk is float and fr is int:
		sh = Vector2(sin(float(fr) * 2.3), cos(float(fr) * 1.9)) * float(sk)
	var horizon_y := pos.y + (Arena.GROUND - 24.0) * e
	if bg is Node and (bg as Node).has_meta("fx"):
		var fx: Object = (bg as Node).get_meta("fx")
		if fx != null and fx.has_method("update_camera"):
			fx.call("update_camera", cx, e, sh, horizon_y)
		var st: Variant = screen.get("stage_node")
		if fx != null and fx.has_method("set_floor_camera") and st is Node and (st as Node).has_meta("floor_mat"):
			fx.call("set_floor_camera", (st as Node).get_meta("floor_mat"), e, horizon_y)
