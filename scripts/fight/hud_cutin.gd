extends Control
## The EX ult cut-in, played while FightScreen freezes the whole world (see fight_screen.gd, "EX ult freeze").
## It runs on the SIM clock — FightScreen.freeze_age() / release_age(), in seconds — so it can never drift from the freeze,
## it holds while the game is paused, and a queued second cut-in (both players EX on the same frame) restarts it.
##
## Timeline of one cut-in (1.2 s of frozen world). Layers whip in (Motion.whip: 88 percent of the travel in 7 frames, then a
## slow settle, no overshoot) starting 0, 5, 9 and 11 frames apart, as BA's UIExSkillCutin clip does:
##   0.00  white trigger flash + camera punch; the world dims, desaturates and darkens at the edges (veil) while the
##         caster, frozen on her first EX frame, stays bright in a team-colour aura; radial speed lines in her accent
##         colour; rise SFX; the diagonal team band wipes in with triangle shards flying along it
##   0.08  the official art slides in (frame 5), the "EX SKILL" tag (frame 9), the white name plate and its deco bar (frame 11)
##   0.33  the EX skill name STAMPS in (impact SFX, camera kick, a two-frame impact frame on the world)
##   0.86  band + art leave; then the caster alone in the spotlight, rings of light converging on her
##   1.20  the world resumes: second flash + shockwave from the caster, the veil lifts, the ult plays out
## Reduce Flashes (FxFlash): the flashes are capped, the impact frame is skipped and the speed lines hold still.
##
## Layers: this Control (screen space, child of the HUD at z 100: band, art, name, flashes) plus four world-space
## nodes made by attach(): the veil (screen-texture desaturate / dim / vignette / impact frame, z 70, under the caster,
## whom FightScreen raises to z 75), the speed lines (z 71), the aura behind the caster (z 72, additive) and the burst in
## front (z 78, additive).

const Kit := preload("res://scripts/fight/hud_kit.gd")
const Menu := preload("res://scripts/ui/ba_menu.gd")
const PainterScript := preload("res://scripts/ui/painter.gd")
const ACCENT := {10004: Color(0.72, 0.25, 1.0), 10005: Color(0.968, 0.639, 0.549)}    # Hina violet (BA's EX hit tint), Hoshino's light coral (BA's #F7A38C)
const PLATE_W := 241.0          # the real plate is 482 x 70 at 2960 px wide
const PLATE_H := 35.0
const BAR_W := 248.0
const BAR_H := 16.0
const ART_SHADER := preload("res://shaders/hud_cutin_art.gdshader")

const FRAME := 1.0 / 60.0
const ART_T := 5.0 * FRAME      # layer starts, from the real clip
const TAG_T := 9.0 * FRAME
const PLATE_T := 11.0 * FRAME
const STAMP_LEN := 0.1          # the name falls for this long and lands on FightScreen.STAMP_FRAME (impact sound)
const IMPACT_LEN := 2.0 * FRAME # the impact frame on the stamp
const EXIT_T := 0.86
const EXIT_LEN := 0.16
const REL_LEN := 0.45
const BODY_H := 330.0

const VEIL_CODE := """
shader_type canvas_item;
// EX freeze veil: everything drawn under it (stage, opponent, projectiles, effects) is desaturated, dimmed and
// vignetted around the caster. The caster is drawn above it. impact 1 turns the world into a two-tone inverted frame.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
uniform float impact = 0.0;
uniform vec2 focus = vec2(0.5, 0.6);
uniform vec4 tint : source_color = vec4(0.18, 0.26, 0.55, 1.0);
uniform float aspect = 1.7777778;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(c, vec3(l), 0.85 * amount);
	g = mix(g, g * 0.4 + tint.rgb * 0.16, amount);
	vec2 d = (SCREEN_UV - focus) * vec2(aspect, 1.0);
	float r = length(d);
	g *= 1.0 - smoothstep(0.4, 1.35, r) * 0.72 * amount;
	g = mix(g, vec3(1.0 - step(0.5, l)), impact);
	COLOR = vec4(g, 1.0);
}
"""

## Node2D whose _draw is a Callable (world-space layers of the cut-in).
class Draw2D extends Node2D:
	var cb: Callable
	func _draw() -> void:
		if cb.is_valid():
			cb.call(self)

var f: Fighter
var slot := 1
var skill := ""
var live := false
var world: Node
var _age := 0.0
var _rel := -1.0
var _rel_f: Fighter
var _k := 0.0
var _a := 1.0
var _back: Control
var _art: TextureRect
var _front: Control
var _mat: ShaderMaterial
var _frame := {}
var _consts := {"freeze_s": 1.2, "stamp_s": 0.333, "veil_out_s": 0.233}
var _veil: ColorRect
var _veil_mat: ShaderMaterial
var _rays: Draw2D
var _aura: Draw2D
var _burst: Draw2D

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_back = PainterScript.new().setup(Vector2(1280, 720), _draw_back)
	add_child(_back)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = ART_SHADER
	_art.material = _mat
	add_child(_art)
	_front = PainterScript.new().setup(Vector2(1280, 720), _draw_front)
	add_child(_front)

## Creates the world-space layers (call once, after FightScreen built its world).
func attach(w: Node) -> void:
	world = w
	if w.has_method("freeze_consts"):
		_consts = w.call("freeze_consts")
	var sh := Shader.new()
	sh.code = VEIL_CODE
	_veil_mat = ShaderMaterial.new()
	_veil_mat.shader = sh
	_veil = ColorRect.new()
	_veil.name = "FreezeVeil"
	_veil.color = Color.WHITE
	_veil.material = _veil_mat
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.position = Vector2.ZERO
	_veil.size = Vector2(1280, 720)
	_veil.z_index = 70
	_veil.visible = false
	w.add_child(_veil)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var root: Node = w.get("world_root")
	_rays = Draw2D.new()
	_rays.name = "FreezeRays"
	_rays.cb = _draw_rays
	_rays.z_index = 71
	root.add_child(_rays)
	_aura = Draw2D.new()
	_aura.name = "FreezeAura"
	_aura.cb = _draw_aura
	_aura.z_index = 72
	_aura.material = add
	root.add_child(_aura)
	_burst = Draw2D.new()
	_burst.name = "FreezeBurst"
	_burst.cb = _draw_burst
	_burst.z_index = 78
	_burst.material = add
	root.add_child(_burst)

func start(fighter: Fighter) -> void:
	f = fighter
	slot = fighter.slot
	skill = str(fighter.data.get("exName", "EX Skill"))
	live = true
	visible = true
	_age = 0.0
	var tex: Texture2D = UI.portrait(int(f.data["id"]))
	_art.texture = tex
	var h := SelectFrames.head(int(f.data["id"]), tex)
	var s := 255.0 / float(h[2])
	var ctr := Vector2(float(h[0]) + float(h[2]) * 0.5, float(h[1]) + float(h[2]) * 0.5)
	var anchor := Vector2(300, 262) if slot == 1 else Vector2(980, 262)
	_frame = {"pos": anchor - ctr * s, "size": Vector2(tex.get_size()) * s, "head": anchor, "s": s}
	_art.size = _frame["size"]
	_mat.set_shader_parameter("glow_color", _light())
	_mat.set_shader_parameter("glow_px", 34.0 / s)
	_mat.set_shader_parameter("rim_px", 4.0 / s)
	_update_art()

## Round restart / pause-menu restart mid-freeze: drop everything immediately.
func stop() -> void:
	live = false
	_rel = -1.0
	_rel_f = null
	visible = false
	if _veil != null:
		_veil.visible = false
	if _aura != null:
		_rays.queue_redraw()
		_aura.queue_redraw()
		_burst.queue_redraw()

## 0..1: how strongly the band covers the HUD (the HUD ducks underneath it).
func strength() -> float:
	if not live:
		return 0.0
	return clampf(_age / 0.1, 0.0, 1.0) * (1.0 - _exit_k())

func _exit_k() -> float:
	return clampf((_age - EXIT_T) / EXIT_LEN, 0.0, 1.0)

func _tilt() -> float:
	return -0.085 if slot == 1 else 0.085

## Every HUD frame: follow the world's freeze clock.
func sync(w: Node) -> void:
	world = w
	var age: float = w.call("freeze_age")
	var caster: Fighter = w.get("freeze_caster")
	if age >= 0.0 and caster != null:
		if caster != f or not live:
			start(caster)
		_age = age
		live = true
	else:
		live = false
	_rel = w.call("release_age")
	var rc: Fighter = w.get("release_caster")
	if _rel >= 0.0 and rc != null:
		_rel_f = rc
	elif _rel < 0.0:
		_rel_f = null
	visible = live or (_rel >= 0.0 and _rel < REL_LEN)
	_update_art()
	_update_veil()
	if _aura != null:
		_rays.queue_redraw()
		_aura.queue_redraw()
		_burst.queue_redraw()

## The side's light tint (slabs, halos, the world-space layers).
func _light(of_slot := 0) -> Color:
	return BaTokens.P1_LIGHT if (of_slot if of_slot > 0 else slot) == 1 else BaTokens.P2_LIGHT

## The caster's own colour for the radial speed lines: BA's tint for Hina (violet) and Hoshino (coral), the attack type's
## colour for everyone else.
static func accent_for(data: Dictionary) -> Color:
	if ACCENT.has(int(data.get("id", 0))):
		return ACCENT[int(data["id"])]
	return BaArt.ATTACK.get(str(data.get("bullet", "")), BaTokens.ATK_PIERCING)

## Font size at which `who` fits the white name plate (a text area of the plate's width less the lean and padding).
static func plate_text_size(who: String) -> int:
	return Menu.fit(who, 24, PLATE_W - 40.0, 12)

## The plate hugs the name: padding either side, never wider than BA's 241 px plate and never a sliver.
static func plate_width(who: String) -> float:
	return clampf(Kit.width(UI.font_ui(700), who, plate_text_size(who)) + 72.0, 128.0, PLATE_W)

func _update_art() -> void:
	_art.visible = live
	if not live:
		_back.queue_redraw()
		_front.queue_redraw()
		return
	_k = Motion.whip(_age - ART_T)
	var ex := _exit_k()
	_a = 1.0 - ex * ex
	var dir := -1.0 if slot == 1 else 1.0
	var slide := (1.0 - _k) * 520.0 * dir
	var drift := _age * 26.0 * -dir      # slow push-in drift while the freeze runs
	var leave := ex * ex * 640.0 * dir    # backs out to its own side
	var p: Vector2 = _frame["pos"]
	_art.position = p + Vector2(slide + drift + leave, 0.0)
	_art.modulate.a = _a
	_mat.set_shader_parameter("flash", FxFlash.flash(clampf(1.0 - _age * 10.0, 0.0, 1.0) * 0.8))
	_mat.set_shader_parameter("brighten", 0.06)
	_mat.set_shader_parameter("glow_amt", 0.8 + (0.0 if FxFlash.reduced() else 0.2 * sin(_age * 22.0)))
	_back.queue_redraw()
	_front.queue_redraw()

## Screen position of a world point (FightScreen.world_root carries the camera).
func _to_screen(wp: Vector2) -> Vector2:
	var root: Node2D = world.get("world_root")
	return root.position + wp * root.scale.x

func _update_veil() -> void:
	if _veil == null:
		return
	var amt := 0.0
	var who: Fighter = null
	var impact := 0.0
	if live:
		amt = clampf(_age / 0.08, 0.0, 1.0)
		who = f
		var land := float(_consts.get("stamp_s", 0.333))
		if _age >= land and _age < land + IMPACT_LEN and not FxFlash.reduced():
			impact = 1.0
	elif _rel >= 0.0:
		amt = 1.0 - clampf(_rel / float(_consts.get("veil_out_s", 0.23)), 0.0, 1.0)
		who = _rel_f
	_veil.visible = amt > 0.001
	if not _veil.visible:
		return
	var fp := Vector2(640, 420)
	if who != null and is_instance_valid(who):
		fp = _to_screen(who.position + Vector2(0, -BODY_H * 0.55))
	_veil_mat.set_shader_parameter("amount", amt)
	_veil_mat.set_shader_parameter("impact", impact)
	_veil_mat.set_shader_parameter("focus", fp / Vector2(1280.0, 720.0))

# ── screen space: band, shards, halo, speed lines ────────────────────────────
const SPAN := 1800.0          # the band's wipe covers this much of x, so the whip's 88 percent clears the screen

func _draw_back(c: Control) -> void:
	if not live:
		return
	var side := BaTokens.side(slot)
	var light := _light()
	var left := slot == 1
	var dirs := 1.0 if left else -1.0
	var ex := _exit_k()
	var kk := Motion.whip(_age) * (1.0 - 0.35 * ex)
	var on := 1.0 - ex
	# a light navy wash so the band reads (the world itself is already dimmed by the veil)
	c.draw_rect(Rect2(0, 0, 1280, 720), Color(0.01, 0.03, 0.12, 0.3 * clampf(_age / 0.1, 0.0, 1.0) * on))
	# wide diagonal bands (the whole stack is tilted a few degrees): wipe in from the caster's side, wipe out across
	Kit.base = Kit.tilt(Vector2(640, 332), _tilt())
	c.draw_set_transform_matrix(Kit.base)
	var lean := 90.0
	var yc := 332.0
	var hh := 292.0 * kk
	var ein := Motion.whip(_age)
	var eout := ex * ex
	var x0 := -160.0 + SPAN * eout
	var x1 := -160.0 + SPAN * ein
	if not left:
		x0 = 1440.0 - SPAN * ein
		x1 = 1440.0 - SPAN * eout
	if x1 - x0 > 1.0:
		c.draw_colored_polygon(Kit.slab(x0, x1, yc - hh * 0.5 - 40.0, hh + 80.0, lean), BaTokens.alpha(side, 0.35))
		c.draw_colored_polygon(Kit.slab(x0, x1, yc - hh * 0.5 - 58.0, 14.0, lean), Color(1, 1, 1, 0.95))
		c.draw_colored_polygon(Kit.slab(x0, x1, yc + hh * 0.5 + 44.0, 20.0, lean), BaTokens.alpha(BaTokens.CONFIRM, 0.95))
		var top := BaTokens.alpha(side.lerp(Color.WHITE, 0.22), 0.97)
		var bot := BaTokens.alpha(side.darkened(0.2), 0.97)
		c.draw_polygon(Kit.slab(x0, x1, yc - hh * 0.5, hh, lean), PackedColorArray([top, top, bot, bot]))
	# halo behind the head (upright)
	Kit.base = Transform2D.IDENTITY
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	var hp: Vector2 = _frame["head"] + Vector2(_art.position - _frame["pos"])
	Kit.halo(c, hp + Vector2(0, -170.0), 150.0, 38.0, Color(1, 1, 1, 0.95 * _a), 7.0)
	Kit.halo(c, hp + Vector2(0, -170.0), 205.0, 50.0, Color(1, 1, 1, 0.35 * _a), 3.0)
	# speed lines flowing along the slant
	Kit.base = Kit.tilt(Vector2(640, 332), _tilt())
	c.draw_set_transform_matrix(Kit.base)
	var rnd := RandomNumberGenerator.new()
	rnd.seed = 99 + slot
	for i in 30:
		var y := rnd.randf_range(yc - 190.0, yc + 190.0)
		var ln := rnd.randf_range(180.0, 520.0)
		var sp := rnd.randf_range(1800.0, 3200.0)
		var x := fposmod(rnd.randf_range(0.0, 1700.0) + _age * sp * dirs, 1700.0) - 200.0
		if not left:
			x = 1480.0 - (x + 200.0)
		c.draw_line(Vector2(x, y), Vector2(x - ln * dirs, y), Color(1, 1, 1, 0.5 * on), rnd.randf_range(2.0, 5.0), true)
	_draw_shards(c, left, on, yc, hh, light)
	Kit.base = Transform2D.IDENTITY
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

const SHARDS := 40

## Isosceles triangles, 6 to 40 px, white or the side's light tint, flying from the caster's side along the beam. Each one is
## a loop: it leaves fast, slows down as it crosses the screen and is gone before it restarts.
func _draw_shards(c: Control, left: bool, on: float, yc: float, hh: float, light: Color) -> void:
	var dirs := 1.0 if left else -1.0
	for i in SHARDS:
		var fi := float(i)
		var period := 0.55 + 0.5 * Fx.h(fi, 11.0)
		var u := fposmod(_age / period + Fx.h(fi, 12.0), 1.0)
		var travel := 1.0 - pow(1.0 - u, 3.0)
		var size := 6.0 + 34.0 * pow(Fx.h(fi, 13.0), 1.4)
		var y := yc + (Fx.h(fi, 14.0) - 0.5) * (hh + 90.0)
		var x := (-120.0 + 1560.0 * travel) if left else (1400.0 - 1560.0 * travel)
		var a := minf(1.0, u * 8.0) * (1.0 - smoothstep(0.78, 1.0, u)) * on
		var col := Color.WHITE if Fx.h(fi, 15.0) < 0.55 else light
		var len_ := size * 2.1
		var tip := Vector2(x + dirs * len_ * 0.6, y)
		c.draw_colored_polygon(PackedVector2Array([tip, Vector2(x - dirs * len_ * 0.4, y - size * 0.5), Vector2(x - dirs * len_ * 0.4, y + size * 0.5)]), BaTokens.alpha(col, a))

# ── world space (under the caster): radial speed lines in her accent colour ──
const RAYS := 46
const BOLTS := 6

## How strongly the speed lines show: full while the cut-in plays, then with the veil as it lifts.
func _rays_k() -> float:
	if live:
		return 1.0
	if _rel >= 0.0 and _rel_f != null:
		return 1.0 - clampf(_rel / float(_consts.get("veil_out_s", 0.23)), 0.0, 1.0)
	return 0.0

## Hard two-level lines: long wedges in the accent colour, thinner white ones between them, and a few white jagged bolts. The
## pattern redraws every second tick (a held, drawn-on-twos look) and holds still under Reduce Flashes.
func _draw_rays(ci: Node2D) -> void:
	var k := _rays_k()
	var who: Fighter = f if live else _rel_f
	if k <= 0.0 or who == null or not is_instance_valid(who):
		return
	var accent := accent_for(who.data)
	var ctr := who.position + Vector2(0, -BODY_H * 0.55)
	var zoom := maxf((world.get("world_root") as Node2D).scale.x, 0.4)
	var far := 1500.0 / zoom
	var near := 90.0 / zoom
	var st := FxFlash.stepped(_age, 30.0)
	for i in RAYS:
		var fi := float(i)
		if Fx.h(fi, st + 1.7) < 0.38:
			continue
		var ang := TAU * (fi + 0.8 * Fx.h(fi, 2.9 + st)) / float(RAYS)
		var wide := 0.004 + 0.012 * Fx.h(fi, 4.1 + st)
		var r1 := far * (0.55 + 0.45 * Fx.h(fi, 5.3 + st))
		var col := Color.WHITE if Fx.h(fi, 6.1 + st) < 0.3 else accent
		var d := Vector2.from_angle(ang)
		var n := Vector2(-d.y, d.x)
		ci.draw_colored_polygon(PackedVector2Array([ctr + d * near, ctr + d * r1 + n * r1 * wide, ctr + d * r1 - n * r1 * wide]), BaTokens.alpha(col, 0.8 * k))
	for j in BOLTS:
		var fj := float(j)
		var ang2 := TAU * (fj + Fx.h(fj, 8.8 + st)) / float(BOLTS)
		var d2 := Vector2.from_angle(ang2)
		var n2 := Vector2(-d2.y, d2.x)
		var pts := PackedVector2Array()
		for q in 6:
			var t := float(q) / 5.0
			var off := (Fx.h(fj * 7.0 + float(q), 9.4 + st) - 0.5) * 70.0 / zoom * (0.0 if q == 0 else 1.0)
			pts.append(ctr + d2 * lerpf(220.0, far * 0.8, t) / zoom + n2 * off)
		ci.draw_polyline(pts, BaTokens.alpha(accent, 0.8 * k), 9.0 / zoom, true)
		ci.draw_polyline(pts, BaTokens.alpha(Color.WHITE, 0.95 * k), 3.5 / zoom, true)

# ── screen space: tag, stamped skill name, caster name plate, flashes ────────
func _draw_front(c: Control) -> void:
	if live:
		_draw_text(c)
		# trigger flash
		var fl := clampf(1.0 - _age / 0.12, 0.0, 1.0)
		if fl > 0.0:
			c.draw_rect(Rect2(0, 0, 1280, 720), Color(1, 1, 1, FxFlash.flash(0.92 * fl * fl)))
	if _rel >= 0.0:
		# release flash: the world snaps back into motion
		var rf := clampf(1.0 - _rel / 0.2, 0.0, 1.0)
		if rf > 0.0:
			c.draw_rect(Rect2(0, 0, 1280, 720), Color(1, 1, 1, FxFlash.flash(0.62 * rf * rf)))

## `r` leans "/" by BA's 10 degrees about its own centre, on top of Kit.base's tilt.
func _lean_matrix(r: Rect2) -> Transform2D:
	return Kit.base * BaArt.lean_xform(BaTokens.SHEAR, r.get_center().y)

## The white sheared name plate with the side-coloured deco bar offset below it, and the caster's name in navy.
func _draw_plate(c: Control, r: Rect2, a: float) -> void:
	var bar := Rect2(r.position + Vector2(9.0, r.size.y - 5.0), Vector2(r.size.x + BAR_W - PLATE_W, BAR_H))
	c.draw_set_transform_matrix(_lean_matrix(bar))
	BaArt.nine(c, "Combat__Common_Bg_Raius5px", bar, BaTokens.alpha(_light(), a))
	c.draw_set_transform_matrix(_lean_matrix(r))
	BaArt.nine(c, "Common__Common_Nonoutline_W_Bg", r, Color(1, 1, 1, a))
	var who := Fighters.display_name(f.data)
	var font := UI.font_ui(700)
	var sz := plate_text_size(who)
	var w := Kit.width(font, who, sz)
	c.draw_string(font, Vector2(r.position.x + (r.size.x - w) * 0.5, r.get_center().y + float(sz) * 0.34 - 2.0), who, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, BaTokens.alpha(BaTokens.INK, a))
	c.draw_set_transform_matrix(Kit.base)

func _draw_text(c: Control) -> void:
	var left := slot == 1
	var font := UI.font_name()
	var ex := _exit_k()
	var out_a := 1.0 - ex
	var exit_dx := ex * ex * 260.0 * (-1.0 if left else 1.0)
	var maxw := 700.0
	var sz := 100
	while sz > 40 and Kit.width(font, skill.to_upper(), sz) > maxw:
		sz -= 4
	var nw := Kit.width(font, skill.to_upper(), sz)
	var xl := (505.0 if left else 800.0 - nw) + exit_dx
	var base := 372.0
	var sgn := 1.0 if left else -1.0
	Kit.base = Kit.tilt(Vector2(640, 332), _tilt())
	# "EX SKILL" tag slides in first
	var kt := Motion.whip(_age - TAG_T)
	var tag_a := clampf((_age - TAG_T) * 10.0, 0.0, 1.0) * out_a
	if tag_a > 0.0:
		Kit.lean(c, Vector2(xl + (1.0 - kt) * 300.0 * sgn, base - float(sz) * 0.9 - 14.0), BaTokens.SHEAR)
		var tag_w := 150.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(0, -34), Vector2(tag_w, -34), Vector2(tag_w - 12, 6), Vector2(-12, 6)]), BaTokens.alpha(BaTokens.CONFIRM, tag_a))
		Kit.text(c, font, Vector2(tag_w * 0.5 - 6.0, -4.0), "EX SKILL", 34, BaTokens.alpha(BaTokens.INK, tag_a), Color(0, 0, 0, 0), 0, 1)
		Kit.unlean(c)
	# the skill name STAMPS in: big and transparent → slammed to size with a white impact plate behind it
	var land := float(_consts.get("stamp_s", 0.333))
	var st := clampf((_age - (land - STAMP_LEN)) / STAMP_LEN, 0.0, 1.0)
	if st > 0.0:
		var e := 1.0 - st
		var sc := 1.0 + 1.25 * e * e
		var na := minf(1.0, st * 1.6) * out_a
		var since := _age - land
		var ctr := Vector2(xl + nw * 0.5, base - float(sz) * 0.35)
		Kit.lean(c, ctr, BaTokens.SHEAR, sc)
		var off := Vector2(-nw * 0.5, float(sz) * 0.35)
		if since > 0.0 and since < 0.22:
			# the impact plate shares the name's transform, so it hugs the glyphs however the band is tilted
			var q := since / 0.22
			var pad := 18.0 + 22.0 * q
			var top := off.y - float(sz) * 0.8 - pad * 0.5
			c.draw_colored_polygon(PackedVector2Array([Vector2(off.x - pad, top), Vector2(off.x + nw + pad, top), Vector2(off.x + nw + pad, off.y + 10.0 + pad * 0.5),
				Vector2(off.x - pad, off.y + 10.0 + pad * 0.5)]), Color(1, 1, 1, FxFlash.flash(0.75 * (1.0 - q) * (1.0 - q) * out_a)))
		Kit.text(c, font, off + Vector2(6, 6), skill.to_upper(), sz, Color(0.02, 0.05, 0.2, 0.55 * na), Color(0, 0, 0, 0), 0)
		Kit.text(c, font, off, skill.to_upper(), sz, BaTokens.alpha(Color.WHITE, na), BaTokens.alpha(BaTokens.LABEL_INK, na), 14)
		Kit.unlean(c)
	# the caster's name on its plate
	var kp := Motion.whip(_age - PLATE_T)
	var plate_a := clampf((_age - PLATE_T) * 14.0, 0.0, 1.0) * out_a
	if plate_a > 0.0:
		var pw := plate_width(Fighters.display_name(f.data))
		var px := (xl + 8.0) if left else (xl + nw - pw - 8.0)
		_draw_plate(c, Rect2(px + (1.0 - kp) * 260.0 * sgn, base + 24.0, pw, PLATE_H), plate_a)
	Kit.base = Transform2D.IDENTITY
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

# ── world space (additive): aura behind the caster ───────────────────────────
func _draw_aura(ci: Node2D) -> void:
	if not live or f == null or not is_instance_valid(f):
		return
	var p := f.position
	var team := BaTokens.side(slot)
	var light := _light()
	var freeze_s := float(_consts.get("freeze_s", 1.2))
	var ign := clampf(_age / 0.12, 0.0, 1.0)
	var pulse := 0.86 + 0.14 * sin(_age * 18.0)
	var charge := clampf((_age - EXIT_T) / maxf(0.05, freeze_s - EXIT_T), 0.0, 1.0)
	var inten := ign * pulse * (0.8 + 0.6 * charge)
	# light pillar rising from her feet
	var pw := 120.0 + 40.0 * charge
	var pcol := Color(light.r, light.g, light.b, 0.42 * inten)
	var pclr := Color(light.r, light.g, light.b, 0.0)
	ci.draw_polygon(PackedVector2Array([p + Vector2(-pw, 6), p + Vector2(pw, 6), p + Vector2(pw * 0.5, -700), p + Vector2(-pw * 0.5, -700)]),
		PackedColorArray([pcol, pcol, pclr, pclr]))
	# body glow (soft blobs stretched along the body)
	var mid := p + Vector2(0, -BODY_H * 0.5)
	ci.draw_set_transform(mid, 0.0, Vector2(1.0, 1.8))
	Fx.glow(ci, Vector2.ZERO, 150.0 * (0.92 + 0.16 * inten), Color(light.r, light.g, light.b, 0.6 * inten))
	Fx.glow(ci, Vector2.ZERO, 95.0, Color(team.r, team.g, team.b, 0.55 * inten))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# ground rings rippling out under her feet
	for k in 3:
		var ph := fposmod(_age * 1.5 + float(k) / 3.0, 1.0)
		ci.draw_set_transform(p + Vector2(0, -4), 0.0, Vector2(1.0, 0.26))
		ci.draw_arc(Vector2.ZERO, 46.0 + 200.0 * ph, 0.0, TAU, 56, Color(light.r, light.g, light.b, (1.0 - ph) * 0.85 * ign), 8.0 * (1.0 - ph) + 2.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# light streaks rising around her
	for i in 18:
		var fi := float(i)
		var x := (Fx.h(fi, 1.3) - 0.5) * 240.0
		var sp := 0.55 + 0.6 * Fx.h(fi, 2.1)
		var ph2 := fposmod(Fx.h(fi, 3.3) + _age * sp, 1.0)
		var y := -ph2 * 620.0
		var ln := 50.0 + 100.0 * Fx.h(fi, 4.4)
		var a := sin(ph2 * PI) * 0.85 * ign
		ci.draw_line(p + Vector2(x, y), p + Vector2(x, y - ln), Color(light.r, light.g, light.b, a), 5.0, true)
		ci.draw_line(p + Vector2(x, y - ln * 0.15), p + Vector2(x, y - ln * 0.85), Color(1, 1, 1, a * 0.9), 2.0, true)
	# spotlight before the release: rings of light converging on her
	if charge > 0.0:
		for k in 2:
			var q := clampf(charge * 1.15 - float(k) * 0.25, 0.0, 1.0)
			if q <= 0.0 or q >= 1.0:
				continue
			var r := lerpf(420.0, 36.0, q * q)
			ci.draw_arc(mid, r, 0.0, TAU, 72, Color(1, 1, 1, 0.75 * sin(q * PI)), 6.0, true)

# ── world space (additive): trigger burst + release shockwave in front ───────
func _draw_burst(ci: Node2D) -> void:
	if live and f != null and is_instance_valid(f) and _age < 0.32:
		var q := _age / 0.32
		var e := 1.0 - (1.0 - q) * (1.0 - q)
		var c := f.position + Vector2(0, -BODY_H * 0.55)
		ci.draw_arc(c, 40.0 + 330.0 * e, 0.0, TAU, 72, Color(1, 1, 1, FxFlash.flash(0.95 * (1.0 - q))), 12.0 * (1.0 - q) + 2.0, true)
		var light := _light()
		for i in 16:
			var ang := TAU * float(i) / 16.0 + Fx.h(float(i), 5.0) * 0.3
			var r0 := 70.0 + 240.0 * e
			Fx.shard(ci, c, ang, r0, r0 + 170.0 * (1.0 - q), 14.0 * (1.0 - q) + 2.0, Color(light.r, light.g, light.b, 0.9 * (1.0 - q)))
	if _rel >= 0.0 and _rel < REL_LEN and _rel_f != null and is_instance_valid(_rel_f):
		var q2 := _rel / REL_LEN
		var e2 := 1.0 - pow(1.0 - q2, 3.0)
		var a2 := 1.0 - q2
		var rs := _rel_f.slot
		var light2 := _light(rs)
		var c2 := _rel_f.position + Vector2(0, -BODY_H * 0.5)
		ci.draw_arc(c2, 60.0 + 980.0 * e2, 0.0, TAU, 96, Color(1, 1, 1, 0.95 * a2), 28.0 * a2 + 2.0, true)
		ci.draw_arc(c2, 40.0 + 700.0 * e2, 0.0, TAU, 96, Color(light2.r, light2.g, light2.b, 0.85 * a2), 18.0 * a2 + 2.0, true)
		ci.draw_set_transform(_rel_f.position + Vector2(0, -4), 0.0, Vector2(1.0, 0.22))
		ci.draw_arc(Vector2.ZERO, 90.0 + 1200.0 * e2, 0.0, TAU, 96, Color(1, 1, 1, 0.8 * a2), 22.0 * a2 + 2.0, true)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if q2 < 0.5:
			var qq := q2 / 0.5
			for i in 20:
				var ang2 := TAU * float(i) / 20.0 + Fx.h(float(i), 9.0) * 0.25
				var r1 := 80.0 + 520.0 * qq
				Fx.shard(ci, c2, ang2, r1, r1 + 260.0 * (1.0 - qq), 18.0 * (1.0 - qq) + 2.0, Color(1, 1, 1, 0.9 * (1.0 - qq)))
