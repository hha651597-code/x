class_name FxKindsB2
extends RefCounted
## The second set of sprite kinds, from BA's own textures through FxArt: dust, sparkle, heal, boom, ko, swish, slash and the
## impact frame. Same rules as FxKinds: layers are built once, update() moves them with k = age / life, shapes are held poses that
## leave by stepping their size down, a soft glow blob is never the body of a kind. Each kind names its layers in its header.

static func build(fx: Fx) -> void:
	match fx.kind:
		"dust":
			_build_dust(fx)
		"sparkle":
			_build_sparkle(fx)
		"heal":
			_build_heal(fx)
		"boom":
			_build_boom(fx)
		"ko":
			_build_ko(fx)
		"swish", "slash":
			_build_swish(fx)
		"impact":
			_build_impact(fx)

static func update(fx: Fx, k: float) -> void:
	match fx.kind:
		"dust":
			_update_dust(fx, k)
		"sparkle":
			_update_sparkle(fx, k)
		"heal":
			_update_heal(fx, k)
		"boom":
			_update_boom(fx, k)
		"ko":
			_update_ko(fx, k)
		"swish", "slash":
			_update_swish(fx, k)
		"impact":
			_update_impact(fx, k)

static func _rim(c: Color) -> Color:
	return Color(c.r * 0.45, c.g * 0.5, c.b * 0.6, 1.0)

static func _tint(c: Color, a := 1.0) -> Color:
	return Color(c.r, c.g, c.b, a)

# ── dust ──────────────────────────────────────────────────────────────────────
# BA's ground puff: FX_TEX_Smoke_02, white cartoon puffs with a flat grey rim, three held positions and six held sizes (grow,
# hold, shrink out), no alpha fade. The sheet has real alpha, so the tint multiplies a white puff and its grey rim stays a shade
# darker, which is what keeps it readable on snow. Three puffs per node, each smaller than the last; Fx.make's seed picks the side
# (odd seeds go left), the frames and the flips. Layers: one puff each.
const DUST_DIAM := 72.0
const DUST_SIZES := [0.45, 0.8, 1.0, 1.0, 0.7, 0.4]
const DUST_PUFFS := 3

static func _build_dust(fx: Fx) -> void:
	for i in DUST_PUFFS:
		var s := FxKinds._layer(fx, "puff", "mix", false, DUST_DIAM * fx.size * (1.0 - 0.3 * float(i)))
		s.frame = int(Fx.h(float(i), fx.seed_v) * 4.0) % 4
		s.flip_h = Fx.h(float(i) + 7.0, fx.seed_v) > 0.5
		s.set_meta("i", i)

static func _update_dust(fx: Fx, k: float) -> void:
	var side := -1.0 if int(fx.seed_v) % 2 == 1 else 1.0
	var spread := float(fx.data.get("spread", 1.0))
	var drift := float(fx.data.get("drift", 0.0))
	var pose := Fx.pose(k, 6)
	var eo: float = [0.3, 0.6, 1.0][pose / 2]
	for s: Sprite2D in fx.parts:
		var i: int = s.get_meta("i")
		var fi := float(i)
		var spd := (0.55 + 0.45 * Fx.h(fi, fx.seed_v)) * spread
		s.position = Vector2(side * (14.0 + 52.0 * eo * spd) * (1.0 if i % 2 == 0 else -0.6) + drift * eo * 50.0,
			-8.0 - 34.0 * eo * (0.4 + 0.6 * Fx.h(fi + 4.0, fx.seed_v)) * (1.0 - 0.3 * eo))
		FxKinds._scale(s, DUST_SIZES[pose])
		s.modulate = _tint(fx.color)

# ── sparkle ───────────────────────────────────────────────────────────────────
# BA's twinkle: small, big, mid, small over four held poses. The body is Hit_12's fat four-point star tinted with the colour on a
# darker rim a quarter larger (a pale star on snow is invisible), and Flare_05's long thin four-point star on top in white, which
# is BA's own sparkle and gives it the long arms. Layers: 0 rim, 1 body, 2 flare.
const SPARKLE_DIAM := 56.0
const SPARKLE_POSES := [0.35, 1.0, 0.65, 0.3]

static func _build_sparkle(fx: Fx) -> void:
	var d := SPARKLE_DIAM * fx.size
	FxKinds._layer(fx, "star4_fat", "mix", false, d)
	FxKinds._layer(fx, "star4_fat", "mix", false, d)
	FxKinds._layer(fx, "star4", "mix", false, d * 1.9)

static func _update_sparkle(fx: Fx, k: float) -> void:
	var p := Fx.pose(k, 4)
	var sc: float = SPARKLE_POSES[p]
	var tilt := 0.0 if p % 2 == 0 else 0.2
	var rim: Sprite2D = fx.parts[0]
	FxKinds._scale(rim, sc * 1.3)
	rim.rotation = tilt
	rim.modulate = _tint(_rim(fx.color))
	var body: Sprite2D = fx.parts[1]
	FxKinds._scale(body, sc)
	body.rotation = tilt
	body.modulate = _tint(fx.color.lightened(0.1))
	var flare: Sprite2D = fx.parts[2]
	FxKinds._scale(flare, sc)
	flare.rotation = tilt
	flare.modulate = Color.WHITE

# ── heal ──────────────────────────────────────────────────────────────────────
# BA's heal: rising plus signs (FX_TEX_Health_01), twinkling Flare_05 stars and a ring on the ground. The plus signs come up
# the body one after another, each held on four poses (small, full, full, small) and gone, with a dark rim under each; the ring is
# the ring kind's circle eroded against Circle_Ring_Wave, flattened to a ground ellipse and stepping out in three radii.
# Colour: mint unless data["color"]. Layers: 0 ring, 1 ring rim (first), then HEAL_PLUS pairs (rim, plus), then HEAL_STARS stars.
const HEAL := Color(0.5, 1.0, 0.72)
const HEAL_PLUS := 7
const HEAL_STARS := 5
const HEAL_PLUS_DIAM := 46.0

static func _heal_color(fx: Fx) -> Color:
	return fx.color if fx.data.has("color") else HEAL

static func _build_heal(fx: Fx) -> void:
	FxKinds._layer(fx, "circle", "mix", true, FxKinds.RING_BASE, "ring_wave")
	var rim := FxKinds._layer(fx, "circle", "mix", true, FxKinds.RING_BASE, "ring_wave")
	fx.move_child(rim, 0)
	for i in HEAL_PLUS:
		var d := HEAL_PLUS_DIAM * (0.7 + 0.5 * Fx.h(float(i) + 3.0, 1.0)) * fx.size
		var r := FxKinds._layer(fx, "plus", "mix", false, d * 1.28)
		var p := FxKinds._layer(fx, "plus", "mix", false, d)
		r.set_meta("i", i)
		p.set_meta("i", i)
	for i in HEAL_STARS:
		var s := FxKinds._layer(fx, "star4", "mix", false, 34.0 * fx.size)
		s.set_meta("i", i)

static func _update_heal(fx: Fx, k: float) -> void:
	var g := _heal_color(fx)
	var sixth := Fx.pose(k, 6)
	var third := sixth / 2
	var r := 18.0 + 62.0 * float([0.45, 0.8, 1.0][third]) * fx.size
	var ring: Sprite2D = fx.parts[0]
	var rim: Sprite2D = fx.parts[1]
	var a: float = 1.0 - float(FxKinds.RING_POWER[sixth - sixth % 2])    # a thick band: two sixths on each power
	ring.position = Vector2(0.0, -2.0)
	rim.position = ring.position
	FxKinds._scale(ring, 2.0 * r / FxKinds.RING_BASE, 0.5 * r / FxKinds.RING_BASE)
	FxKinds._scale(rim, 2.0 * r / FxKinds.RING_BASE * 1.06, 0.5 * r / FxKinds.RING_BASE * 1.06)
	ring.modulate = _tint(g.lightened(0.2), a)
	rim.modulate = _tint(_rim(g), a)
	var idx := 2
	for i in HEAL_PLUS:
		var fi := float(i)
		var start := 0.04 + 0.42 * Fx.h(fi, 2.0)
		var u := clampf((k - start) / 0.5, 0.0, 1.0)
		var on := k >= start and u < 1.0
		var pose := Fx.pose(u, 4)
		var sc: float = [0.5, 1.0, 1.0, 0.6][pose]
		var ang := TAU * fi / float(HEAL_PLUS) + fx.seed_v
		var pos := Vector2(cos(ang) * 62.0 * (1.0 - u * 0.25), -u * 200.0 * fx.size - sin(ang * 2.0) * 16.0 - 14.0)
		var rim_s: Sprite2D = fx.parts[idx]
		var plus_s: Sprite2D = fx.parts[idx + 1]
		idx += 2
		for sp in [rim_s, plus_s]:
			sp.position = pos
			FxKinds._scale(sp, sc)
		rim_s.modulate = _tint(_rim(g), 1.0 if on else 0.0)
		plus_s.modulate = _tint(g, 1.0 if on else 0.0)
	for i in HEAL_STARS:
		var fi2 := float(i)
		var start2 := 0.1 + 0.5 * Fx.h(fi2, 6.0)
		var u2 := clampf((k - start2) / 0.4, 0.0, 1.0)
		var on2 := k >= start2 and u2 < 1.0
		var s: Sprite2D = fx.parts[idx]
		idx += 1
		s.position = Vector2((Fx.h(fi2, 8.0) - 0.5) * 120.0, -30.0 - u2 * 150.0 - 110.0 * Fx.h(fi2, 9.0))
		FxKinds._scale(s, [0.3, 1.0, 0.6, 0.3][Fx.pose(u2, 4)])
		s.modulate = _tint(Color(1.0, 1.0, 0.95).lerp(g, 0.25), 1.0 if on2 else 0.0)

# ── boom ──────────────────────────────────────────────────────────────────────
# A cel explosion from BA's Boom textures: Boom_02's spiky silhouette is the fireball (a dark rim, the colour, a pale core on
# top), the 16 frames of Boom_01 are the smoke, played every third frame, three puffs behind the fire, and Shock_Wave_06's spikes
# are eroded against their mask for the blast ring. A comic star flashes on the first pose and eight streaks fly out. size =
# radius / 100. Fire sizes are six held poses (grow, hold, shrink out). Layers: 0 ring, 1 ring rim (first), 2..4 smoke, 5 fire
# rim, 6 fire, 7 core, 8 flash star, 9..16 streaks.
const BOOM_FIRE := [0.5, 1.0, 1.12, 1.08, 0.9, 0.55]
const BOOM_STREAKS := 8
const FIRE_CORE := Color(1.0, 0.93, 0.62)
const SMOKE := Color(0.3, 0.27, 0.31)

static func _build_boom(fx: Fx) -> void:
	var R := 100.0 * fx.size
	var ring := FxKinds._layer(fx, "shock", "mix", true, FxKinds.RING_BASE, "shock_mask")
	ring.frame = int(Fx.h(5.0, fx.seed_v) * 4.0) % 4
	ring.rotation = fx.seed_v
	var edge := FxKinds._layer(fx, "shock", "mix", true, FxKinds.RING_BASE, "shock_mask")
	edge.frame = ring.frame
	edge.rotation = fx.seed_v
	fx.move_child(edge, 0)
	for i in 3:
		var s := FxKinds._layer(fx, "boom_puff", "mix", false, R * (1.7 - 0.15 * float(i)))
		s.set_meta("i", i)
	FxKinds._layer(fx, "boom_cloud", "mix", false, R * 2.5)
	FxKinds._layer(fx, "boom_cloud", "mix", false, R * 2.5)
	FxKinds._layer(fx, "boom_cloud", "mix", false, R * 2.5)
	var fl := FxKinds._layer(fx, "hit_star_warm", "mix", false, R * 2.2)
	fl.rotation = fx.seed_v
	for i in BOOM_STREAKS:
		var s2 := FxKinds._layer(fx, "streak", "mix", false, 256.0)
		var ang := TAU * (float(i) + 0.6 * Fx.h(float(i), fx.seed_v)) / float(BOOM_STREAKS)
		s2.rotation = ang
		s2.set_meta("ang", ang)
		s2.set_meta("len", R * (0.8 + 0.7 * Fx.h(float(i) + 3.0, fx.seed_v)))

static func _update_boom(fx: Fx, k: float) -> void:
	var R := 100.0 * fx.size
	var c := fx.color
	var pose := Fx.pose(k, 6)
	var dark := _rim(c)
	var ring: Sprite2D = fx.parts[0]
	var edge: Sprite2D = fx.parts[1]
	var blade := FxKinds._steps(1.0 - clampf(k / 0.7, 0.0, 1.0), 4)
	var rr := R * (1.0 + 1.6 * float([0.4, 0.7, 1.0][pose / 2]))
	FxKinds._scale(ring, 2.0 * rr / FxKinds.RING_BASE)
	FxKinds._scale(edge, 2.0 * rr / FxKinds.RING_BASE * 1.08)
	ring.modulate = _tint(c.lightened(0.45), blade)
	edge.modulate = _tint(dark, blade)
	var smoke_frame := Fx.pose(k, 6) * 3
	for i in 3:
		var s: Sprite2D = fx.parts[2 + i]
		var a := TAU * float(i) / 3.0 + fx.seed_v
		var eo := 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)
		s.frame = mini(smoke_frame + i % 2, 15)
		s.position = Vector2(cos(a), sin(a) * 0.8) * R * 0.6 * eo + Vector2(0.0, -R * 0.35 * k)
		FxKinds._scale(s, 0.8 + 0.5 * eo)
		s.modulate = _tint(SMOKE, 0.0 if pose == 0 else 1.0)
	var fire: float = BOOM_FIRE[pose]
	var live := 1.0 if k < 0.85 else 0.0
	var fire_rim: Sprite2D = fx.parts[5]
	var fire_s: Sprite2D = fx.parts[6]
	var core: Sprite2D = fx.parts[7]
	FxKinds._scale(fire_rim, fire * 1.1)
	FxKinds._scale(fire_s, fire)
	FxKinds._scale(core, fire * 0.55)
	fire_rim.modulate = _tint(dark, live)
	fire_s.modulate = _tint(c, live)
	core.modulate = _tint(FIRE_CORE, 1.0 if k < 0.55 else 0.0)
	var flash: Sprite2D = fx.parts[8]
	flash.frame = (int(Fx.h(2.0, fx.seed_v) * 4.0) + pose) % 4
	FxKinds._scale(flash, 1.0 if pose == 0 else 0.7)
	flash.modulate = _tint(Color.WHITE, 1.0 if pose < 2 else 0.0)
	var eo2 := 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)
	for i in BOOM_STREAKS:
		var s2: Sprite2D = fx.parts[9 + i]
		var ang: float = s2.get_meta("ang")
		var ln: float = s2.get_meta("len")
		s2.position = Vector2.from_angle(ang) * (R * 0.6 + ln * 0.9 * eo2)
		FxKinds._scale(s2, ln * (1.0 - 0.7 * k) / 256.0, 0.1)
		s2.modulate = _tint(FIRE_CORE.lerp(c, 0.3), 1.0 if k < 0.7 else 0.0)

# ── ko ────────────────────────────────────────────────────────────────────────
# The K.O. burst at the loser's chest. BA's common set has no KO effect, so this is a stand-in built from its parts: Boom_02's
# spike silhouette in white on a coloured rim for the first poses and in the colour after, eight FocusLine bursts radiating, the
# ring kind's spikes and band, and an eight-point star flash. Everything is held on six poses and leaves by stepping down.
# Layers in creation order: 0 band, 1 band rim, 2 spikes, 3 spikes rim (both rims draw first), 4 cloud rim, 5 cloud, 6 star, 7.. focus lines.
const KO_LINES := 8
const KO_CLOUD := [0.6, 1.0, 1.12, 1.12, 0.9, 0.6]

static func _build_ko(fx: Fx) -> void:
	var band := FxKinds._layer(fx, "circle", "mix", true, FxKinds.RING_BASE, "ring_wave")
	var band_rim := FxKinds._layer(fx, "circle", "mix", true, FxKinds.RING_BASE, "ring_wave")
	fx.move_child(band_rim, 0)
	var sp := FxKinds._layer(fx, "shock", "mix", true, FxKinds.RING_BASE, "shock_mask")
	sp.frame = int(Fx.h(5.0, fx.seed_v) * 4.0) % 4
	var sp_rim := FxKinds._layer(fx, "shock", "mix", true, FxKinds.RING_BASE, "shock_mask")
	sp_rim.frame = sp.frame
	fx.move_child(sp_rim, 0)
	band.rotation = fx.seed_v
	FxKinds._layer(fx, "boom_cloud", "mix", false, 440.0 * fx.size)
	FxKinds._layer(fx, "boom_cloud", "mix", false, 440.0 * fx.size)
	FxKinds._layer(fx, "star8", "mix", false, 620.0 * fx.size)
	for i in KO_LINES:
		var s := FxKinds._layer(fx, "focus", "mix", false, 256.0)
		var ang := TAU * (float(i) + 0.5 * Fx.h(float(i), fx.seed_v)) / float(KO_LINES)
		s.rotation = ang + PI * 0.5
		s.set_meta("ang", ang)

static func _update_ko(fx: Fx, k: float) -> void:
	var c := fx.color
	var pose := Fx.pose(k, 6)
	var dark := _rim(c)
	var left := FxKinds._steps(1.0 - clampf(k / 0.8, 0.0, 1.0), 5)
	var r := 60.0 + 400.0 * fx.size * float([0.45, 0.7, 1.0][pose / 2])
	var band: Sprite2D = fx.parts[0]
	var band_rim: Sprite2D = fx.parts[1]
	var sp: Sprite2D = fx.parts[2]
	var sp_rim: Sprite2D = fx.parts[3]
	var share: float = 1.0 - float(FxKinds.RING_POWER[pose])    # how much of the band is left: thick first, thin last
	band.modulate = _tint(Color.WHITE.lerp(c, 0.35), share)
	band_rim.modulate = _tint(dark, share)
	FxKinds._scale(band, 2.0 * r / FxKinds.RING_BASE)
	FxKinds._scale(band_rim, 2.0 * r / FxKinds.RING_BASE * 1.06)
	sp.modulate = _tint(Color.WHITE, left)
	sp_rim.modulate = _tint(dark, left)
	FxKinds._scale(sp, 2.0 * r / FxKinds.RING_BASE * 0.9)
	FxKinds._scale(sp_rim, 2.0 * r / FxKinds.RING_BASE * 0.9 * 1.08)
	var cloud_rim: Sprite2D = fx.parts[4]
	var cloud: Sprite2D = fx.parts[5]
	var cs: float = KO_CLOUD[pose]
	FxKinds._scale(cloud_rim, cs * 1.12)
	FxKinds._scale(cloud, cs)
	var hot := 1.0 if k < 0.4 else 0.0
	cloud_rim.modulate = _tint(dark, 1.0 if k < 0.6 else 0.0)
	cloud.modulate = _tint(Color.WHITE if k < 0.22 else c, 1.0 if k < 0.6 else 0.0)
	var star: Sprite2D = fx.parts[6]
	FxKinds._scale(star, 1.0 if pose == 0 else 0.7)
	star.modulate = _tint(Color.WHITE, hot if pose < 2 else 0.0)
	var reach: float = [0.5, 0.9, 1.0, 1.0, 0.8, 0.5][pose]
	for i in KO_LINES:
		var s: Sprite2D = fx.parts[7 + i]
		var ang: float = s.get_meta("ang")
		var ln := 520.0 * fx.size * reach
		s.position = Vector2.from_angle(ang) * (150.0 * fx.size + ln * 0.5)
		FxKinds._scale(s, 0.9, ln / 256.0)
		s.modulate = _tint(c.lightened(0.1), 1.0 if k < 0.7 else 0.0)

# ── swish and slash ───────────────────────────────────────────────────────────
# A melee swing. BA's common set has no melee effect, so this is a stand-in from its blade shape: Stretch_Line's diamond with long
# points (frame 2 of the blade sheet) is bent along the swing's arc as a textured strip, in three layers (a dark rim, the colour, a
# white core), with a four-point star on the head. The arc is data["r"], ["a0"], ["a1"], ["thick"], ["squash"], ["off"] (swish)
# or a default one (slash); a facing left mirrors the angles. The blade is always a whole diamond between its head and its tail:
# the head advances in four steps, then the tail follows in four, so the shape is held between steps and leaves from behind.
# Fx._draw calls draw_swish; the head star is a pair of sprites. Layers (sprites): 0 star rim, 1 star.
const SWISH_SEGS := 14
const SWISH_V := [0.504, 0.746]     # frame 2 of the four rows
const SWISH_WIDTHS := [1.55, 1.15, 0.55]   # rim, colour, core, as shares of the blade's thickness
const SWISH_FILL := 0.8             # share of the strip's width the diamond fills at its middle

static func _swing(fx: Fx) -> Dictionary:
	var d := float(fx.dir)
	var a0: float = fx.data.get("a0", -1.1)
	var a1: float = fx.data.get("a1", 0.6)
	var b0 := a0
	var b1 := a1
	if fx.dir < 0:
		b0 = PI - a0
		b1 = PI - a1
	var slash := fx.kind == "slash"
	var rad := float(fx.data.get("r", 130.0 * fx.size if slash else 100.0))
	var thick := float(fx.data.get("thick", 26.0 * fx.size if slash else 30.0))
	var off: Vector2 = fx.data.get("off", Vector2(-20.0, 0.0) if slash else Vector2(30.0, -170.0))
	return {"b0": b0, "b1": b1, "rad": rad, "thick": thick, "sq": float(fx.data.get("squash", 1.0)), "ctr": Vector2(off.x * d, off.y)}

## The visible part of the arc at `k`: [tail, head] as shares of the whole, in quarters.
static func _window(k: float) -> Vector2:
	var prog := 1.0 - pow(1.0 - clampf(k / 0.6, 0.0, 1.0), 2.0)
	var head := maxf(ceilf(prog * 4.0 - 0.001) / 4.0, 0.25)
	var tail := minf(floorf(clampf((k - 0.45) / 0.55, 0.0, 1.0) * 4.0) / 4.0, head - 0.25)
	return Vector2(maxf(tail, 0.0), head)

static func _arc_point(sw: Dictionary, f: float) -> Vector2:
	var th := lerpf(float(sw["b0"]), float(sw["b1"]), f)
	return (sw["ctr"] as Vector2) + Vector2(cos(th) * float(sw["rad"]), sin(th) * float(sw["rad"]) * float(sw["sq"]))

static func _build_swish(fx: Fx) -> void:
	fx.material = FxArt.material("mix", true, false)
	FxKinds._layer(fx, "star4", "mix", false, 70.0)
	FxKinds._layer(fx, "star4", "mix", false, 70.0)

## Share of the strip's width that keeps its inner edge from folding: half the widest layer must stay under the arc's tightest
## curvature radius, rad * squash^2 (a flat 2L arc is tight).
static func _fit(sw: Dictionary) -> float:
	var sq := float(sw["sq"])
	return minf(1.0, 1.9 * float(sw["rad"]) * sq * sq * SWISH_FILL / (float(sw["thick"]) * float(SWISH_WIDTHS[0])))

static func draw_swish(fx: Fx, k: float) -> void:
	var sw := _swing(fx)
	var win := _window(k)
	if win.y - win.x < 0.2:
		return
	var tex := FxArt.tex("blade")
	if tex == null:
		return
	var thin: float = [1.0, 1.0, 0.8, 0.6][mini(int(k * 4.0), 3)]
	var c := fx.color
	var tints := [_rim(c), c, Color.WHITE]
	var fit := _fit(sw)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var fwd := float(sw["b1"]) >= float(sw["b0"])      # the quad's split follows the swing's winding, so a mirrored swing is an exact mirror
	for layer in 3:
		var w := float(sw["thick"]) * thin * float(SWISH_WIDTHS[layer]) / SWISH_FILL * fit
		var base := pts.size()
		for j in SWISH_SEGS + 1:
			var f := lerpf(win.x, win.y, float(j) / float(SWISH_SEGS))
			var p := _arc_point(sw, f)
			var th := lerpf(float(sw["b0"]), float(sw["b1"]), f)
			var n := Vector2(cos(th) * float(sw["sq"]), sin(th)).normalized() * w * 0.5
			var u := float(j) / float(SWISH_SEGS)
			pts.append_array([p - n, p + n])
			uvs.append_array([Vector2(u, SWISH_V[0]), Vector2(u, SWISH_V[1])])
			cols.append_array([tints[layer], tints[layer]])
			if j > 0:
				var i := base + 2 * j
				idx.append_array([i - 2, i - 1, i, i - 1, i + 1, i] if fwd else [i - 2, i - 1, i + 1, i - 2, i + 1, i])
	RenderingServer.canvas_item_add_triangle_array(fx.get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())

static func _update_swish(fx: Fx, k: float) -> void:
	var sw := _swing(fx)
	var win := _window(k)
	var hp := _arc_point(sw, win.y)
	var ss: float = 0.0 if (k > 0.55 or win.y - win.x < 0.2) else [1.0, 0.7, 0.4][mini(int(k / 0.2), 2)]
	var rim: Sprite2D = fx.parts[0]
	var star: Sprite2D = fx.parts[1]
	rim.position = hp
	star.position = hp
	FxKinds._scale(rim, ss * 1.3)
	FxKinds._scale(star, ss)
	rim.modulate = _tint(_rim(fx.color), 1.0 if ss > 0.0 else 0.0)
	star.modulate = _tint(Color.WHITE, 1.0 if ss > 0.0 else 0.0)

## Half the width and height of what Fx._draw puts on screen for this kind (the swing's strip, the impact's ink field), around the
## node's origin, for the contact sheets: the sprites report their own size.
static func drawn_reach(fx: Fx) -> Vector2:
	match fx.kind:
		"swish", "slash":
			var sw := _swing(fx)
			var r := Vector2.ZERO
			for j in 21:
				var p := _arc_point(sw, float(j) / 20.0)
				r = Vector2(maxf(r.x, absf(p.x)), maxf(r.y, absf(p.y)))
			return r + Vector2.ONE * float(sw["thick"]) * 1.3
		"impact":
			return Vector2.ONE * maxf(float(fx.data.get("field", 6000.0)), 1160.0 * fx.size)
	return Vector2.ZERO

# ── impact ────────────────────────────────────────────────────────────────────
# An impact frame: for two or three ticks the world goes to a flat ink field with a white spike burst and white focus lines. It is
# a flat overlay, so it reads no screen texture. Only the K.O. and EX stamp ask for it; with Reduce Flashes on, or inside 340 ms
# of the last one (FxFlash), it is not built at all. Layers: 0 burst, 1..n focus lines.
const IMPACT_LINES := 12

static func _build_impact(fx: Fx) -> void:
	if not FxFlash.impact_ok():
		fx.visible = false
		return
	var burst := FxKinds._layer(fx, "boom_cloud", "mix", false, 700.0 * fx.size)
	burst.rotation = fx.seed_v
	for i in IMPACT_LINES:
		var s := FxKinds._layer(fx, "focus", "mix", false, 256.0)
		var ang := TAU * (float(i) + Fx.h(float(i), fx.seed_v)) / float(IMPACT_LINES)
		s.rotation = ang + PI * 0.5
		s.set_meta("ang", ang)

static func _update_impact(fx: Fx, k: float) -> void:
	var burst: Sprite2D = fx.parts[0]
	var pose := Fx.pose(k, 2)
	FxKinds._scale(burst, [0.8, 1.1][pose])
	burst.modulate = Color.WHITE
	for i in IMPACT_LINES:
		var s: Sprite2D = fx.parts[1 + i]
		var ang: float = s.get_meta("ang")
		var ln: float = [700.0, 900.0][pose] * fx.size
		s.position = Vector2.from_angle(ang) * (260.0 * fx.size + ln * 0.5)
		FxKinds._scale(s, 0.9, ln / 256.0)
		s.modulate = Color.WHITE
