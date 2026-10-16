class_name FxKinds
extends RefCounted
## Sprite-based Fx kinds, built from BA's own effect textures (FxArt). build() makes the sprite layers once, in Fx._ready;
## update() moves them every frame with k = age / life. Shapes are held poses that leave in steps, not smooth fades.
## Fx.make and the kind names are unchanged, so every kit keeps working. The kinds of the second set (dust, sparkle, heal, boom, ko,
## swish, slash, impact) are in fx_kinds_art.gd and share this file's _layer, _scale and _steps.

const KINDS := ["spark", "muzzle", "ring", "block", "text", "dust", "sparkle", "heal", "boom", "ko", "swish", "slash", "impact"]    # the last eight are FxKindsB2

static func build(fx: Fx) -> void:
	match fx.kind:
		"spark":
			_build_spark(fx)
		"muzzle":
			_build_muzzle(fx)
		"ring":
			_build_ring(fx)
		"block":
			_build_block(fx)
		"text":
			_build_text(fx)
		_:
			FxKindsB2.build(fx)

static func update(fx: Fx, k: float) -> void:
	match fx.kind:
		"spark":
			_update_spark(fx, k)
		"muzzle":
			_update_muzzle(fx, k)
		"ring":
			_update_ring(fx, k)
		"block":
			_update_block(fx, k)
		"text":
			_update_text(fx, k)
		_:
			FxKindsB2.update(fx, k)

## One sprite layer, added to `fx`, scaled so a flipbook frame is `fit_px` wide.
static func _layer(fx: Fx, sheet: String, blend: String, erode: bool, fit_px: float, mask := "") -> Sprite2D:
	var s := FxArt.sprite(sheet, blend, erode, mask)
	var b := fit_px / FxArt.frame_size(sheet).x
	s.set_meta("base", b)
	s.scale = Vector2.ONE * b
	fx.add_child(s)
	fx.parts.append(s)
	return s

## Scale relative to the layer's fitted size.
static func _scale(s: Sprite2D, sx: float, sy := -1.0) -> void:
	var b: float = s.get_meta("base")
	s.scale = Vector2(b * sx, b * (sx if sy < 0.0 else sy))

## `left` (0..1, the share of a shape that remains) quantised to `steps` steps, so a shape erodes in held steps.
static func _steps(left: float, steps: int) -> float:
	return floorf(clampf(left, 0.0, 1.0) * float(steps) + 0.001) / float(steps)

# spark
# BA's gun hit (FX_Common_Hit_*): FX_TEX_Hit_06's four comic stars played as a flipbook over the life, a white core, a few
# streaks, and on heavy hits a star accent. The star sheet has baked colour (a yellow body, a pale ring and a white centre that
# differ only in blue) and a flat fill, and it leaves by stepping its size down instead of eroding. Cool tints (the ex cyan)
# take their tint through the shader's gray mode; gray mode crushes the three tones to 0.92, 0.97 and 1.0, which on a pale
# tint is a flat khaki star, so warm tints (red well above blue) use the sheet's own colour times the tint. The white core
# only shows in the first fifth of the life. Layers: 0 burst (mix), 1 core (add), 2..1+n streaks (mix), 2+n accent (add,
# size > 1.2 only).
const SPARK_DIAM := 150.0       # px across at size 1.0
const SPARK_POSES := [0.75, 1.0, 1.1, 1.1, 0.8, 0.5]    # six held sizes over the life: grow, hold, shrink out

static func _warm(c: Color) -> bool:
	return c.r - c.b >= 0.3 and c.g >= c.b       # a pink (blue above green) would come out orange through the yellow sheet

static func _spark_streaks(size: float) -> int:
	return 3 + int(2.0 * size)

static func _build_spark(fx: Fx) -> void:
	var d := SPARK_DIAM * fx.size
	var burst := _layer(fx, "hit_star_warm" if _warm(fx.color) else "hit_star", "mix", false, d)
	burst.rotation = (Fx.h(2.0, fx.seed_v) - 0.5) * 0.6
	burst.set_meta("f0", int(Fx.h(1.0, fx.seed_v) * 4.0) % 4)
	_layer(fx, "glow_disc", "add", false, d * 0.8)
	var n := _spark_streaks(fx.size)
	for i in n:
		var s := _layer(fx, "streak", "mix", false, 256.0)
		var ang := TAU * (float(i) + 0.6 * Fx.h(float(i), fx.seed_v)) / float(n) + fx.seed_v
		s.rotation = ang
		s.set_meta("ang", ang)
		s.set_meta("len", d * (0.5 + 0.5 * Fx.h(float(i) + 3.0, fx.seed_v)))
	if fx.size > 1.2:
		var x := _layer(fx, "hit_cross", "add", false, d * 1.1)
		x.rotation = fx.seed_v

static func _update_spark(fx: Fx, k: float) -> void:
	var d := SPARK_DIAM * fx.size
	var c := fx.color
	var burst: Sprite2D = fx.parts[0]
	burst.frame = (int(burst.get_meta("f0")) + Fx.pose(k, 4)) % 4
	var sc: float = SPARK_POSES[Fx.pose(k, SPARK_POSES.size())]
	_scale(burst, sc)
	burst.modulate = Color(c.r, c.g, c.b, 1.0)
	var core: Sprite2D = fx.parts[1]
	core.modulate = Color(1.0, 1.0, 1.0, clampf(1.0 - k / 0.2, 0.0, 1.0))
	_scale(core, 0.6 + 0.6 * k)
	var n := _spark_streaks(fx.size)
	var eo := 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)
	var streak_tint := Color(c.r, c.g, c.b * 0.3) if _warm(c) else c.lightened(0.2)    # a warm star's body colour, as the sheet bakes it
	for i in n:
		var s: Sprite2D = fx.parts[2 + i]
		var ang: float = s.get_meta("ang")
		var ln: float = s.get_meta("len")
		s.position = Vector2.from_angle(ang) * (d * 0.25 + ln * 0.6 * eo)
		_scale(s, ln * (1.0 - 0.7 * k) / 256.0, 0.09)
		s.modulate = Color(streak_tint.r, streak_tint.g, streak_tint.b, 1.0 if k < 0.75 else 0.0)
	if fx.parts.size() > 2 + n:
		var x: Sprite2D = fx.parts[2 + n]
		x.modulate = Color(1.0, 1.0, 1.0, clampf(1.0 - k / 0.5, 0.0, 1.0))
		_scale(x, 0.6 + 0.6 * k)

# muzzle
# BA's muzzle flash: a comic flash from FX_TEX_Muzzle_01, two poses, a small white core, two thin tracer sparks past the flame.
# Frame 0 of the sheet is a round blob; frames 1 and 2 are solid flames and 3 breaks into shards, all pointing along +x, so
# the first pose is one of the two flames and the second is the shards; flip_h turns them for dir -1. The sheet is a flat
# white silhouette, so the flame gets its shape from a darker rim copy under it and a lighter, smaller copy on top (the hot
# centre); a pale tint then still reads as a flame and not as a block. The tracers sit above and below the flame, never on it.
# Layers: 0 flash (mix, erodes), 1 core (add), 2..3 tracers (mix), 4 hot centre, 5 rim (drawn first).
const MUZZLE_DIAM := 130.0

static func _build_muzzle(fx: Fx) -> void:
	var d := MUZZLE_DIAM * fx.size
	var sgn := float(fx.dir)
	var flash := _layer(fx, "muzzle_a", "mix", true, d)
	flash.flip_h = fx.dir < 0
	flash.position = Vector2(sgn * d * 0.35, 0.0)
	flash.set_meta("f0", 1 + int(Fx.h(1.0, fx.seed_v) * 2.0) % 2)
	var core := _layer(fx, "glow_disc", "add", false, d * 0.4)
	core.position = Vector2(sgn * d * 0.1, 0.0)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var s := _layer(fx, "capsule", "mix", false, 256.0)
		s.rotation = (PI if fx.dir < 0 else 0.0) + side * sgn * 0.14
		s.set_meta("len", d * (0.45 + 0.25 * Fx.h(float(i), fx.seed_v)))
		s.set_meta("side", side)
	var hot := _layer(fx, "muzzle_a", "mix", true, d)
	hot.flip_h = fx.dir < 0
	hot.position = flash.position - Vector2(sgn * d * 0.06, 0.0)
	var rim := _layer(fx, "muzzle_a", "mix", true, d)
	rim.flip_h = fx.dir < 0
	rim.position = flash.position
	fx.move_child(rim, 0)

static func _update_muzzle(fx: Fx, k: float) -> void:
	var c := fx.color
	var d := MUZZLE_DIAM * fx.size
	var sgn := float(fx.dir)
	var flash: Sprite2D = fx.parts[0]
	var p := Fx.pose(k, 2)
	var left := _steps(1.0 - clampf((k - 0.5) / 0.5, 0.0, 1.0), 3)
	var frame: int = [int(flash.get_meta("f0")), 3][p]
	var sc := 1.0 if p == 0 else 0.7
	flash.frame = frame
	_scale(flash, sc)
	flash.modulate = Color(c.r, c.g, c.b, left)
	var hot: Sprite2D = fx.parts[4]
	hot.frame = frame
	_scale(hot, 0.3 * sc)
	var hc := c.lightened(0.6)
	hot.modulate = Color(hc.r, hc.g, hc.b, left if p == 0 else 0.0)
	var rim: Sprite2D = fx.parts[5]
	rim.frame = frame
	_scale(rim, 1.15 * sc)
	var dark := c.darkened(0.5)
	rim.modulate = Color(dark.r, dark.g, dark.b, left)
	var core: Sprite2D = fx.parts[1]
	core.modulate = Color(1.0, 1.0, 1.0, clampf(1.0 - k / 0.25, 0.0, 1.0))
	var tracer := c.lightened(0.25)
	for i in 2:
		var s: Sprite2D = fx.parts[2 + i]
		var ln: float = s.get_meta("len")
		var side: float = s.get_meta("side")
		s.position = Vector2(sgn * d * (0.42 + 0.5 * k), side * d * (0.26 + 0.12 * k))
		_scale(s, ln / 256.0 * (1.0 - 0.6 * k), maxf(3.0, 0.035 * d) / 64.0)
		s.modulate = Color(tracer.r, tracer.g, tracer.b, 1.0 if k < 0.7 else 0.0)

# ring
# BA's ring: a solid circle eroded against Circle_Ring_Wave (bright rim, dark centre), so the visible ring thins as it
# expands. The mask's rim only averages 0.2 to 0.45 and is uneven, so past an erode power of about 0.25 it alone leaves broken
# arcs; the sheet's ring_w floors it with a radial ramp, which makes the band thickness (1 - power) * 0.4 of the half width and
# leaves the mask to rag the inner edge. Radius steps through three poses, the band thins in six steps.
# Rings above size 0.45 (heavy and ex hits, explosions) add Shock_Wave_06's spiky shapes eroded against their own mask.
# A darker copy 6 percent larger sits under the ring as a hard rim, so a pale tint still shows on snow.
# A hit's ring (Fx.spark: heavy, ex) takes ring_size_for_star, so its first pose is as wide as the star and it grows past it,
# and Fx.spark draws it a z below the star: the band and the spikes stay behind the star, which keeps the focus.
# Layers: 0 ring, 1 spikes (size > 0.45 only), then the dark rim of the ring and of the spikes (both drawn first).
const RING_BASE := 100.0
const RING_POWER := [0.6, 0.66, 0.72, 0.78, 0.86, 0.93]   # erode power per sixth of the life: lower is thicker
const RING_R0 := 26.0                                      # radius in px at size 0
const RING_REACH := 190.0                                  # px of radius per unit of size at the last radius pose
const RING_STEPS := [0.4, 0.7, 1.0]                        # share of the reach per third of the life
const RING_EDGE := 0.94                                    # drawn outer radius over the formula's: the sheet's circle ends at 0.89 of the frame, the rim adds 6 percent

## The ring size whose first pose is as wide as a star of `star_size` is at its first pose, so the ring leaves at the star's edge.
static func ring_size_for_star(star_size: float) -> float:
	var edge := SPARK_DIAM * star_size * float(SPARK_POSES[0]) * 0.5
	return (edge / RING_EDGE - RING_R0) / (RING_REACH * float(RING_STEPS[0]))

static func _build_ring(fx: Fx) -> void:
	_layer(fx, "circle", "mix", true, RING_BASE, "ring_wave")
	var big := fx.size > 0.45
	if big:
		var sw := _layer(fx, "shock", "mix", true, RING_BASE, "shock_mask")
		sw.frame = int(Fx.h(5.0, fx.seed_v) * 4.0) % 4
		sw.rotation = fx.seed_v
	var rim := _layer(fx, "circle", "mix", true, RING_BASE, "ring_wave")
	fx.move_child(rim, 0)
	if big:
		var edge := _layer(fx, "shock", "mix", true, RING_BASE, "shock_mask")
		edge.frame = (fx.parts[1] as Sprite2D).frame
		edge.rotation = fx.seed_v
		fx.move_child(edge, 0)

static func _update_ring(fx: Fx, k: float) -> void:
	var c := fx.color
	var sixth := Fx.pose(k, 6)
	var step: float = RING_STEPS[sixth / 2]
	var r := RING_R0 + RING_REACH * fx.size * step
	var a: float = 1.0 - float(RING_POWER[sixth])
	var dark := c.darkened(0.5)
	var big := fx.parts.size() > 2
	var ring: Sprite2D = fx.parts[0]
	_scale(ring, 2.0 * r / RING_BASE)
	var lit := c.lightened(0.25)      # paler than a star in front of it, so the two still part where the star's notches show the band
	ring.modulate = Color(lit.r, lit.g, lit.b, a)
	var rim: Sprite2D = fx.parts[2 if big else 1]
	_scale(rim, 2.0 * r / RING_BASE * 1.06)
	rim.modulate = Color(dark.r, dark.g, dark.b, a)
	if big:
		var blade_a := _steps(1.0 - clampf(k / 0.7, 0.0, 1.0), 4)
		var blade := c.lightened(0.45)
		var sw: Sprite2D = fx.parts[1]
		_scale(sw, 2.0 * r / RING_BASE * 0.9)
		sw.modulate = Color(blade.r, blade.g, blade.b, blade_a)
		var edge: Sprite2D = fx.parts[3]
		_scale(edge, 2.0 * r / RING_BASE * 0.9 * 1.08)
		edge.modulate = Color(dark.r, dark.g, dark.b, blade_a)

# block
# BA's shield start: a blue glow disc under a neon shield card, an expanding hex outline, deflected sparks. The generic
# FX_Common_Effect_Shield recipe only: Hoshino's own shield effects stay out of the kit. Everything but the disc is alpha-mix
# so it shows on a bright stage. The card and the hex take a deeper blue than the sparks (their white edge is invisible on
# snow). The card is 102 x 134 px at its start, so the hex starts taller than that and grows outward from there; it is eroded
# against its own glow into a hard line, thinning in steps. The card holds nearly full for most of the life.
# Layers: 0 disc (add), 1 card (mix), 2 hex (mix, erodes), 3..7 sparks (mix).
const SHIELD := Color(0.57, 0.82, 1.0)
const SHIELD_EDGE := Color(0.3, 0.62, 1.0)
const BLOCK_CARD := [1.0, 1.0, 0.85, 0.55]                  # card alpha per quarter of the life
const BLOCK_HEX := [0.6, 0.55, 0.5, 0.45]                   # hex line share left per quarter (1 minus the erode power)

static func _build_block(fx: Fx) -> void:
	var o := Vector2(float(fx.dir) * 30.0, 0.0)
	var glow := _layer(fx, "glow_disc", "add", false, 170.0)
	glow.position = o
	var shield := _layer(fx, "shield", "mix", false, 200.0)
	shield.position = o
	var hex := _layer(fx, "hex", "mix", true, 130.0)
	hex.position = o
	for i in 5:
		var s := _layer(fx, "streak", "mix", false, 256.0)
		var a := (Fx.h(float(i), 1.7) - 0.5) * 2.2 + (PI if fx.dir < 0 else 0.0)
		s.rotation = a
		s.set_meta("ang", a)
		s.set_meta("len", 40.0 + 90.0 * (0.5 + Fx.h(float(i) + 2.0, 1.1)))

static func _update_block(fx: Fx, k: float) -> void:
	var o := Vector2(float(fx.dir) * 30.0, 0.0)
	var quarter := Fx.pose(k, 4)
	var eo := 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)
	(fx.parts[0] as Sprite2D).modulate = Color(SHIELD.r, SHIELD.g, SHIELD.b, clampf(1.0 - k / 0.6, 0.0, 1.0))
	var shield: Sprite2D = fx.parts[1]
	var sc: float = [0.85, 1.0, 1.06][Fx.pose(k, 3)]
	_scale(shield, sc)
	shield.modulate = Color(SHIELD_EDGE.r, SHIELD_EDGE.g, SHIELD_EDGE.b, BLOCK_CARD[quarter])
	var hex: Sprite2D = fx.parts[2]
	_scale(hex, 1.3 + 0.9 * eo)
	hex.modulate = Color(SHIELD_EDGE.r, SHIELD_EDGE.g, SHIELD_EDGE.b, BLOCK_HEX[quarter])
	for i in 5:
		var s: Sprite2D = fx.parts[3 + i]
		var ang: float = s.get_meta("ang")
		var ln: float = s.get_meta("len")
		s.position = o + Vector2.from_angle(ang) * (ln * 0.3 + ln * 0.9 * eo)
		_scale(s, ln * (1.0 - 0.5 * k) / 256.0, 0.06)
		s.modulate = Color(SHIELD.r, SHIELD.g, SHIELD.b, 1.0 if k < 0.7 else 0.0)

# text (damage numbers)
# A text Fx that opts in with data["digits"] and holds only digits draws BA's bitmap numerals: the "weak" set (yellow, red
# outline) for big hits (fsize >= 44), "normal" otherwise. Every other text (move names, labels) keeps Fx._d_text in the
# display face. fight_screen's damage numbers pass "digits": true.
static func _is_digits(s: String) -> bool:
	return s.length() > 0 and s.is_valid_int() and s.unicode_at(0) >= 48

static func _build_text(fx: Fx) -> void:
	if not bool(fx.data.get("digits", false)) or not _is_digits(fx.text):
		return
	var fsize := float(fx.data.get("fsize", 34))
	var digits := FxDigits.build(fx, fx.text, "weak" if fsize >= 44.0 else "normal", fsize * 1.5)
	for d in digits:
		fx.parts.append(d)

static func _update_text(fx: Fx, k: float) -> void:
	fx.scale = Vector2.ONE * (1.0 + 0.35 * maxf(0.0, 1.0 - k * 8.0))
	var rise := -40.0 * Motion.whip(fx.age, 0.12, 0.6)
	var a := 1.0 if k < 0.6 else (1.0 - k) / 0.4
	for p in fx.parts:
		var sp := p as Sprite2D
		sp.position.y = rise - float(sp.region_rect.size.y) * sp.scale.y * 0.5
		sp.modulate.a = a
