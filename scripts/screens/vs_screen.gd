extends Screen
## VS splash in the shape of BA's stage-start beat (UIAni_StageStart): a dark band opens across the stage plate, the two
## fighters whip in on facet plates with their name plates and BA's VS lettering stamps down. The fight makes the READY and FIGHT
## calls itself. After HANDOFF_AT seconds it hands off to the fight; confirm skips ahead; back returns to the menu.
## params: {hold: true} stops at the end state instead of starting the fight (harness).

const BACKDROP_SHADER := preload("res://shaders/backdrop.gdshader")
const OUTLINE_SHADER := preload("res://shaders/portrait_outline.gdshader")
const Painter := preload("res://scripts/ui/painter.gd")
const Menu := preload("res://scripts/ui/ba_menu.gd")

const FIELD := "UIs__00_Images__Image_Triangle_Pattern_Deco_1"
const RING := "UIs__00_Images__Image_Deco_Circle"
const FLARE := "UIs__00_Images__Ingame_Start_Light"
const HANDOFF_AT := 1.8
const HEAD_PX := 212.0                                  # every head is drawn this wide, whatever size its portrait file is (SelectFrames.HEADS)
const PORTRAIT_CX := [300.0, 980.0]
const HEAD_Y := 125.0
const PLATE_SIZE := Vector2(590.0, 487.0)
const DECO_X := [330.0, 630.0]
const T_PORTRAIT := [0.02, 0.12]
const T_NAME := 0.34
const T_VS := 0.5
const T_STRIP := 0.82
const SIDE_NAME := ["PLAYER 1", "PLAYER 2"]
const FACET_TINT := [Color(1.1, 0.4, 0.44), Color(0.2, 0.82, 1.25)]

static var _rng: RandomNumberGenerator

var _t := 0.0
var _fired := {}
var _handed := false
var _end_hold := false
var _ids := [-1, -1]
var _specials := [-1, -1]
var _hold := false                                      # params {"hold": true}: stop at the end state (harness)

var _world: Control
var _bg: TextureRect
var _band: Control
var _decos: Array = []
var _rings: Array = []
var _plates: Array = []
var _holders: Array = []
var _blocks: Array = []
var _specs: Array = []
var _strip: Control
var _vs: Control
var _vs_flare: Control
var _hint: Control
var _bg_t := 0.0

# enter
func enter(p: Dictionary, _info: Dictionary) -> void:
	_hold = bool(p.get("hold", false))
	_resolve()
	_build()
	Sfx.play("whoosh", 1.0, 0.8)

## Fill in anything the previous screens left open and write it back. Random picks are seeded only in scripted runs.
func _resolve() -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		if Session._persists():
			_rng.randomize()
		else:
			_rng.seed = 91357                            # scripted runs and suites stay reproducible
	var sess: Session = Game.session
	for i in 2:
		var p: Dictionary = sess.players[i]
		var f := _num(p["fighter"])
		if not Game.by_id.has(f):
			var other := _num(sess.players[1 - i]["fighter"])
			var pool: Array = Game.fighters.filter(func(s): return int(s["id"]) != other)
			f = int(pool[_rng.randi_range(0, pool.size() - 1)]["id"]) if not pool.is_empty() else 10005
		p["fighter"] = f
		_ids[i] = f
		var sp := _num(p["special"])
		if not Game.by_id.has(sp) or sp == f:
			var pool2: Array = Game.specials.filter(func(s): return int(s["id"]) != f)
			sp = int(pool2[_rng.randi_range(0, pool2.size() - 1)]["id"]) if not pool2.is_empty() else -1
		p["special"] = sp
		_specials[i] = sp
	if sess.stage.is_empty():
		sess.stage = Stages.LIST[_rng.randi_range(0, Stages.LIST.size() - 1)]

static func _num(v: Variant) -> int:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return int(v)
	return -1

# build
func _painter(parent: Control, rect: Rect2, fn: Callable) -> Control:
	var c: Control = Painter.new().setup(rect.size, fn)
	c.position = rect.position
	parent.add_child(c)
	return c

func _full(parent: Control, fn: Callable) -> Control:
	return _painter(parent, Rect2(0.0, 0.0, 1280.0, 720.0), fn)

func _build() -> void:
	_world = Control.new()
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)

	var stage: Dictionary = Game.session.stage
	var plate_path := String(stage.get("plate", ""))
	_bg = TextureRect.new()
	_bg.texture = UI.tex(plate_path if plate_path != "" else "bg/BG_Abydos_Collection.jpg")
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.position = Vector2(-60, -40)
	_bg.size = Vector2(1400, 800)
	_bg.pivot_offset = _bg.size * 0.5
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = BACKDROP_SHADER
	bm.set_shader_parameter("radius", 0.02)
	bm.set_shader_parameter("tint", Color(0.2, 0.3, 0.6))
	bm.set_shader_parameter("tint_amount", 0.25)
	bm.set_shader_parameter("brightness", 0.9)
	bm.set_shader_parameter("saturation", 1.1)
	bm.set_shader_parameter("darken", 0.0)
	_bg.material = bm
	_world.add_child(_bg)

	_band = _painter(_world, VsLayout.BAND, _draw_band)
	_band.pivot_offset = VsLayout.BAND.size * 0.5
	for i in 2:
		var ring_c := Vector2(PORTRAIT_CX[i], 150.0)
		_rings.append(_painter(_world, Rect2(ring_c - Vector2(230.0, 230.0), Vector2(460.0, 460.0)), _draw_ring))
	for i in 2:
		var pr := Rect2(Vector2(PORTRAIT_CX[i] - PLATE_SIZE.x * 0.5, 96.0), PLATE_SIZE)
		_plates.append(_painter(_world, pr, _draw_plate.bind(i)))
	for i in 2:
		_decos.append(_painter(_world, Rect2(Vector2(DECO_X[i], VsLayout.BAND.get_center().y - 160.0), Vector2(320.0, 320.0)), _draw_deco.bind(i)))
	for i in 2:
		_add_portrait(i)
	for i in 2:
		_blocks.append(_full(_world, _draw_block.bind(i)))
		_specs.append(_full(_world, _draw_special.bind(i)))
	_strip = _full(_world, _draw_stage)

	_vs_flare = _centred(Vector2(560.0, 540.0), VsLayout.VS_C + Vector2(-70.0, 30.0), _draw_flare)
	_vs_flare.material = BaArt.additive()
	_vs = _centred(Vector2(VsLayout.VS_W + 40.0, 130.0), VsLayout.VS_C, _draw_vs)
	_hint = _painter(_world, Rect2(440.0, 14.0, 400.0, 34.0), _draw_hint)
	_hint.modulate.a = 0.0
	_vs_flare.modulate.a = 0.0
	_vs.modulate.a = 0.0

func _centred(sz: Vector2, centre: Vector2, fn: Callable) -> Control:
	return _painter(_world, Rect2(centre - sz * 0.5, sz), fn)

func _add_portrait(i: int) -> void:
	var tex := UI.portrait(_ids[i])
	var w := float(tex.get_width())
	var head := SelectFrames.head(_ids[i], tex)
	var fit := HEAD_PX / float(head[2])
	var head_x := float(head[0]) + float(head[2]) * 0.5
	var centre := Vector2(w - head_x if i == 0 else head_x, float(head[1]) + float(head[2]) * 0.5) * fit   # i == 0 is mirrored
	var sz := Vector2(tex.get_size()) * fit
	var holder := Control.new()
	holder.size = sz
	holder.set_meta("home", Vector2(PORTRAIT_CX[i], HEAD_Y) - centre)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var main := TextureRect.new()
	main.texture = tex
	main.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main.stretch_mode = TextureRect.STRETCH_SCALE
	main.size = sz
	main.flip_h = i == 0                                # both face the middle
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("px_scale", 1.0 / fit)
	m.set_shader_parameter("outline_px", 3.5)
	m.set_shader_parameter("shadow_amt", 0.3)
	main.material = m
	holder.add_child(main)
	holder.modulate.a = 0.0
	_world.add_child(holder)
	_holders.append(holder)

# drawing
func _draw_band(c: Control) -> void:
	BaArt.nine(c, "Combat__Combat_Gauge_Hp", Rect2(Vector2.ZERO, c.size), Color(BaTokens.GAUGE_EMPTY, 0.9))
	c.draw_rect(Rect2(0.0, 0.0, c.size.x, 1.5), Color(1, 1, 1, 0.45))
	c.draw_rect(Rect2(0.0, c.size.y - 1.5, c.size.x, 1.5), Color(1, 1, 1, 0.45))

func _draw_deco(c: Control, i: int) -> void:
	var flip := Rect2(Vector2.ZERO, c.size)
	if i == 1:
		c.draw_set_transform_matrix(Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(c.size.x, 0.0)))
	BaArt.blit(c, FIELD, flip, Color(1, 1, 1, 0.6))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_ring(c: Control) -> void:
	BaArt.blit(c, RING, Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.3))

func _draw_plate(c: Control, i: int) -> void:
	BaArt.blit(c, "Combat__Combat_CardBg_EX", Rect2(Vector2.ZERO, c.size), FACET_TINT[i])

func _side_tag(i: int) -> String:
	var p: Dictionary = Game.session.players[i]
	return "CPU" if p["cpu"] else SIDE_NAME[i]

func _draw_block(c: Control, i: int) -> void:
	var f: Dictionary = Game.by_id[_ids[i]]
	var school := String(f.get("schoolName", "")).to_upper()
	var crest := CrestIcon.get_icon(String(f.get("school", "")))
	var nm := Fighters.display_name(f).to_upper()
	var b := VsLayout.block(i, school, nm, CrestIcon.fit(String(f.get("school", ""))))
	var right := i == 1
	BaArt.nine(c, "Common__Common_Bg_Raius10px", b["bar"], BaTokens.side(i + 1), BaTokens.SHEAR)
	var bar: Rect2 = b["bar"]
	Menu.label(c, _side_tag(i), Vector2((bar.end.x - 26.0) if right else bar.position.x + 26.0, bar.position.y + 17.0), 13, Color.WHITE, Color(0, 0, 0, 0), 0, 2 if right else 0, 800)
	BaArt.nine(c, "Common__Common_Nonoutline_W_Bg", b["plate"], Color.WHITE, BaTokens.SHEAR)
	if crest != null:
		c.draw_texture_rect(crest, b["crest"], false, BaTokens.INK)
	var sx: float = b["school_x"]
	c.draw_string(UI.font_ui(800), Vector2(sx - (float(b["school_w"]) if right else 0.0), b["school_y"]), school, HORIZONTAL_ALIGNMENT_LEFT, -1, int(b["school_size"]), BaTokens.INK)
	var y: float = b["name_y"]
	var x: float = b["name_x"]
	c.draw_set_transform_matrix(BaArt.lean_xform(BaTokens.SHEAR, y))
	var font := UI.font_name()
	var nsz: int = b["name_size"]
	c.draw_string(font, Vector2(x - (float(b["name_w"]) if right else 0.0), y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nsz, BaTokens.INK)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
	var chip: Rect2 = b["chip"]
	var glyph := BaArt.role_icon(String(f.get("role", "")))
	var chip_bg := BaArt.tex("Common__Card_Role_Bg")
	if glyph != null and chip_bg != null:
		c.draw_texture_rect(chip_bg, chip, false, BaArt.attack_color(String(f.get("bullet", ""))))
		c.draw_texture_rect(glyph, chip.grow(-8.0), false)

func _draw_special(c: Control, i: int) -> void:
	var sp: Dictionary = Game.by_id.get(_specials[i], {})
	if sp.is_empty():
		return
	var nm := String(sp.get("name", "")).to_upper()
	var s := VsLayout.special(i, nm)
	var tint: Color = BaTokens.side(i + 1).lerp(Color.WHITE, 0.55)
	BaArt.blit(c, "Combat__Combat_CardBg_EX", s["card"], Color(tint.r * 1.2, tint.g * 1.2, tint.b * 1.2))
	var face := BaArt.portrait_small(_specials[i])
	if face != null:
		c.draw_texture_rect(face, s["face"], false)
	BaArt.nine(c, "Common__Common_Nonoutline_W_Bg", s["plate"], Color.WHITE, BaTokens.SHEAR)
	Menu.label(c, nm, Vector2(s["text_x"], s["text_y"]), int(s["size"]), BaTokens.INK, Color(0, 0, 0, 0), 0, int(s["align"]), 800)
	Menu.ribbon(c, s["ribbon"], "SPECIAL")

func _draw_stage(c: Control) -> void:
	var stage: Dictionary = Game.session.stage
	var path := String(stage.get("plate", ""))
	var thumb := UI.tex(path) if path != "" else null
	var nm := String(stage.get("name", ""))
	var s := VsLayout.stage(nm, String(stage.get("school", "")), thumb != null)
	var plate: Rect2 = s["plate"]
	BaArt.nine(c, "Common__Common_Nonoutline_W_Bg", plate, Color.WHITE, BaTokens.SHEAR)
	if thumb != null:
		var r: Rect2 = s["thumb"]
		var tsz := Vector2(thumb.get_size())
		var want := r.size.x / r.size.y
		var crop := Vector2(tsz.y * want, tsz.y) if tsz.x / tsz.y > want else Vector2(tsz.x, tsz.x / want)
		var src := Rect2((tsz - crop) * 0.5, crop)
		c.draw_set_transform_matrix(BaArt.lean_xform(BaTokens.SHEAR, plate.get_center().y))
		c.draw_texture_rect_region(thumb, r, src)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
	Menu.label(c, String(stage.get("school", "")), Vector2(s["school_x"], s["school_y"]), int(s["school_size"]), BaTokens.INK.lerp(Color.WHITE, 0.25), Color(0, 0, 0, 0), 0, 0, 700)
	Menu.label(c, nm, Vector2(s["name_x"], s["name_y"]), int(s["name_size"]), BaTokens.INK, Color(0, 0, 0, 0), 0, 0, 800)
	Menu.ribbon(c, Rect2(plate.position.x - 6.0, plate.position.y - 12.0, 64.0, 20.0), "STAGE")

func _draw_vs(c: Control) -> void:
	BaWords.draw(c, "vs", c.size * 0.5, VsLayout.VS_W)

func _draw_flare(c: Control) -> void:
	BaArt.blit(c, FLARE, Rect2(Vector2.ZERO, c.size), Color(1, 1, 1, 0.9))

func _draw_hint(c: Control) -> void:
	Menu.ribbon(c, Rect2(Vector2.ZERO, c.size), "Match would start here. Press back to return.")

# input
func on_action(_dev: String, act: String) -> void:
	match act:
		"confirm", "start":
			if _t > 0.2 and not _handed:
				_skip()
		"back":
			if _t > 0.2:
				Sfx.play("back")
				Game.go("menu", {}, "fade")

func _skip() -> void:
	Sfx.play("confirm")
	if _can_fight() and not _hold:
		_handoff()
	else:
		_t = maxf(_t, HANDOFF_AT)
		for key in ["p1", "p2", "vs"]:
			_fired[key] = true
		_handoff()

func _can_fight() -> bool:
	return ResourceLoader.exists(String(Game.SCREEN_PATHS.get("fight", "")))

func _handoff() -> void:
	if _handed:
		return
	_handed = true
	if _can_fight() and not _hold:
		Game.go("fight", {}, "slam")
	else:
		_end_hold = true

# per-frame animation
func _process(delta: float) -> void:
	_t += delta
	_events()
	_bg_t += delta
	_bg.scale = Vector2.ONE * (1.06 - 0.04 * (1.0 - exp(-_bg_t * 0.8)))
	_update_band()
	_update_portraits()
	_update_blocks()
	_stamp_node(_vs, _vs_flare, _t - T_VS)
	_update_strip()
	if _end_hold:
		_hint.modulate.a = move_toward(_hint.modulate.a, 1.0, delta * 2.5)
	if _t >= HANDOFF_AT and not _handed:
		_handoff()

func _fire(key: String, at: float, fn: Callable) -> void:
	if _t >= at and not _fired.has(key):
		_fired[key] = true
		fn.call()

func _events() -> void:
	_fire("p1", T_PORTRAIT[0] + 0.17, func() -> void: Sfx.play("slam", 1.1, 0.55))
	_fire("p2", T_PORTRAIT[1] + 0.17, func() -> void: Sfx.play("slam", 0.95, 0.55))
	_fire("vs", T_VS + 0.12, func() -> void: Sfx.play("slam", 0.8, 1.0))

func _update_band() -> void:
	var k := VsLayout.band_k(_t)
	_band.scale = Vector2(1.0, maxf(k, 0.001))
	_band.visible = k > 0.0
	var slide := Motion.whip(_t - 0.02, 0.1, 0.28)
	for i in 2:
		var d: Control = _decos[i]
		var home: float = DECO_X[i]
		d.position.x = home + (1.0 - slide) * (-33.0 if i == 0 else 33.0)
		d.pivot_offset = d.size * 0.5
		d.scale = Vector2(1.0, VsLayout.deco_k(_t))
		d.modulate.a = clampf(slide * 2.0, 0.0, 1.0)
		var r: Control = _rings[i]
		r.pivot_offset = r.size * 0.5
		r.rotation = _t * deg_to_rad(3.0 if i == 0 else -3.0)
		r.modulate.a = clampf((_t - T_PORTRAIT[i]) * 4.0, 0.0, 1.0)

func _update_portraits() -> void:
	for i in 2:
		var dir := -1.0 if i == 0 else 1.0
		var t: float = _t - T_PORTRAIT[i]
		var holder: Control = _holders[i]
		var k := Motion.whip(t, 0.117, 0.3)
		holder.position = (holder.get_meta("home") as Vector2) + Vector2((1.0 - k) * 700.0 * dir, 0.0)
		holder.modulate.a = clampf(t * 14.0, 0.0, 1.0)
		var plate: Control = _plates[i]
		var pk := Motion.whip(t + 0.05, 0.117, 0.3)
		plate.position.x = PORTRAIT_CX[i] - PLATE_SIZE.x * 0.5 + (1.0 - pk) * 520.0 * dir
		plate.modulate.a = clampf((t + 0.05) * 14.0, 0.0, 1.0)

func _update_blocks() -> void:
	for i in 2:
		var dir := -1.0 if i == 0 else 1.0
		var t := _t - T_NAME - float(i) * 0.06
		var k := Motion.whip(t, 0.117, 0.3)
		var b: Control = _blocks[i]
		b.position.x = (1.0 - k) * 420.0 * dir
		b.modulate.a = clampf(t * 10.0, 0.0, 1.0)
		var st := _t - T_NAME - 0.14 - float(i) * 0.06
		var s: Control = _specs[i]
		s.position.x = (1.0 - Motion.whip(st, 0.117, 0.3)) * 320.0 * dir
		s.modulate.a = clampf(st * 8.0, 0.0, 1.0)

func _stamp_node(word: Control, flare: Control, t: float) -> void:
	var st := VsLayout.stamp(t)
	word.pivot_offset = word.size * 0.5
	word.scale = Vector2.ONE * st.x
	word.modulate.a = st.y
	var f := VsLayout.flare(t)
	flare.pivot_offset = flare.size * 0.5
	flare.scale = Vector2.ONE * f
	flare.modulate.a = clampf(f, 0.0, 1.0) * st.y

func _update_strip() -> void:
	var k := Motion.whip(_t - T_STRIP, 0.117, 0.3)
	_strip.position.y = (1.0 - k) * 70.0
	_strip.modulate.a = clampf((_t - T_STRIP) * 10.0, 0.0, 1.0)

# debug
func probe() -> Dictionary:
	return {
		"t": snappedf(_t, 0.01),
		"fighters": _ids,
		"specials": _specials,
		"handed_off": _handed,
		"end_hold": _end_hold,
		"fight_available": _can_fight(),
		"match_config": Game.session.match_config(),
		"band": VsLayout.band_k(_t),
		"vs_scale": VsLayout.stamp(_t - T_VS).x,
	}
