extends Screen
## Controller Assign overlay. Pushed by the menu over the (blurred, darkened) menu:
## two white "Player N" panels and two numbered gamepad glyphs between them. Confirm on a device claims
## a slot (first device -> P1, a different device -> P2); the claimed glyph flies into its panel and the panel
## takes BA's yellow bracket. Single-human modes (versus-cpu / training / arcade) need only P1, P2 shows "CPU".
## All humans claimed -> a short beat -> crest wipe into character select.
## Back un-claims the last claim; with nothing claimed it closes the overlay (Game.back()).

const Menu := preload("res://scripts/ui/ba_menu.gd")
const Painter := preload("res://scripts/ui/painter.gd")
const BACKDROP_SHADER := preload("res://shaders/backdrop.gdshader")
const DIM_SHADER := preload("res://shaders/assign_dim.gdshader")
const PANEL_POS := [Vector2(57, 185), Vector2(855, 185)]                 # panel top-lefts
const SLOT_POS := [Vector2(515, 262.5), Vector2(515, 457.5)]             # glyph top-lefts in the middle
const DOCK_POS := [Vector2(123, 262.5), Vector2(906.5, 262.5)]           # glyph top-lefts once claimed
const CREST_BY_MODE := {"versus2p": "red", "versus-cpu": "gold", "training": "sakura"}
const BEAT := 0.6
const CLOSE_AFTER := 0.16
const READY_AT := 0.35
const INTRO_DELAY := 0.05
const HINT_SIZE := 16
const GLYPH_H := 23.0   # the ribbon's own glyph side (Menu.ribbon_parts: 0.76 of its height)

var _t := 0.0
var _mode := "versus2p"
var _humans := 2
var _panels: Array = []          # AssignPanel
var _slots: Array = []           # per glyph, see _make_slot
var _dim: ColorRect
var _dim_mat: ShaderMaterial
var _backdrop: TextureRect
var _bd_mat: ShaderMaterial
var _overlay := true
var _claim_seq := 0
var _finish_t := -1.0
var _finishing := false
var _closing := false            # the overlay slides out, then Game.back() pops it
var _close_t := 0.0
var _plates: Control             # the join hints and the back hint, each on a navy ribbon
var _back_parts: Array = []
var _back_a := 0.0

func enter(p: Dictionary, info: Dictionary) -> void:
	_overlay = info.get("overlay", false)
	_mode = String(p.get("mode", Game.session.mode))
	if _mode == "":
		_mode = "versus2p"
	if Game.session.mode != _mode:
		Game.session.begin(_mode)
	_humans = Game.session.humans()
	_build()
	if info.get("back", false):
		# returning from character select: step back one claim, the earlier ones stay
		_t = 0.6
		for i in 2:
			var pl: Dictionary = Game.session.players[i]
			if pl["claimed"] and pl["device"] != "":
				_slots[i]["claimed"] = true
				_slots[i]["device"] = pl["device"]
				(_slots[i]["glyph"] as ControllerGlyph).device = pl["device"]
				_slots[i]["order"] = _claim_seq
				_claim_seq += 1
				_snap_to_dock(i)
		var last := _last_claimed()
		if last >= 0:
			_unclaim(last, false)
	else:
		for i in 2:
			Game.session.players[i]["claimed"] = false
			Game.session.players[i]["device"] = ""
	_refresh_texts()
	Input.joy_connection_changed.connect(_on_pads)

# ── build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	if not _overlay:
		_backdrop = TextureRect.new()
		_backdrop.texture = UI.tex("bg/BG_PracticeRoom_Collection.jpg")
		_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_backdrop.position = Vector2(-50, -30)
		_backdrop.size = Vector2(1380, 780)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bd_mat = ShaderMaterial.new()
		_bd_mat.shader = BACKDROP_SHADER
		_bd_mat.set_shader_parameter("radius", 0.03)
		_bd_mat.set_shader_parameter("tint", Color(0.16, 0.5, 1.0))
		_bd_mat.set_shader_parameter("tint_amount", 0.8)
		_bd_mat.set_shader_parameter("brightness", 0.78)
		_bd_mat.set_shader_parameter("saturation", 1.9)
		_bd_mat.set_shader_parameter("darken", 0.66)
		_backdrop.material = _bd_mat
		add_child(_backdrop)
	if _overlay:
		# blur + darken whatever is below (the menu); the menu also dims itself in set_covered
		_dim = ColorRect.new()
		_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dim_mat = ShaderMaterial.new()
		_dim_mat.shader = DIM_SHADER
		_dim_mat.set_shader_parameter("amount", 0.0)
		_dim.material = _dim_mat
		add_child(_dim)

	for i in 2:
		var panel := AssignPanel.new().setup("Player %d" % (i + 1), BaTokens.P1_LIGHT if i == 0 else BaTokens.P2_LIGHT)
		panel.position = PANEL_POS[i]
		if i >= _humans:
			panel.set_cpu("CPU", "Training dummy" if _mode == "training" else "Computer opponent")
		add_child(panel)
		var chip := UI.label("", 15, "ui", BaTokens.INK, 800, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		chip.position = Vector2(0, 241)
		chip.size = Vector2(AssignPanel.SIZE.x, 22)
		chip.modulate.a = 0.0
		panel.add_child(chip)
		panel.set_meta("chip", chip)
		_panels.append(panel)

	for i in 2:
		_slots.append(_make_slot(i))

	_plates = Painter.new().setup(Vector2(1280, 720), _draw_plates)
	add_child(_plates)

func _make_slot(i: int) -> Dictionary:
	var g := ControllerGlyph.new().set_number(i + 1)
	g.position = SLOT_POS[i]
	g.mouse_filter = Control.MOUSE_FILTER_STOP
	g.mouse_entered.connect(_on_hover.bind(i, true))
	g.mouse_exited.connect(_on_hover.bind(i, false))
	g.gui_input.connect(_on_glyph_input.bind(i))
	add_child(g)
	var slot := {
		"glyph": g, "hint_text": "", "hint_parts": [], "hint_a": 0.0, "claimed": false, "device": "", "order": -1,
		"pos": SLOT_POS[i], "from": SLOT_POS[i], "fly_t": 99.0, "lit": 0.0,
		"shake": 0.0, "hover": 0.0, "hovering": false, "delay": INTRO_DELAY + Motion.stagger(i + 2),
		"active": i < _humans,
	}
	if i >= _humans:
		g.visible = false
	return slot

func _snap_to_dock(i: int) -> void:
	var s: Dictionary = _slots[i]
	s["pos"] = DOCK_POS[i]
	s["from"] = DOCK_POS[i]
	(s["glyph"] as Control).position = DOCK_POS[i]
	s["fly_t"] = 99.0

# ── per-frame motion ─────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_t += delta
	var out := 0.0
	if _closing:
		_close_t += delta
		if _close_t >= CLOSE_AFTER:
			Game.back()
			return
		out = _close_t / CLOSE_AFTER
	modulate.a = 1.0 - out
	var fade := clampf(_t * 3.0, 0.0, 1.0)
	if _dim_mat:
		_dim_mat.set_shader_parameter("amount", smoothstep(0.0, 1.0, fade) * (1.0 - out))   # the shader ignores modulate
	if _bd_mat:
		_bd_mat.set_shader_parameter("darken", lerpf(0.0, 0.66, minf(1.0, _t * 3.0)))
	_back_a = clampf((_t - 0.7) * 2.5, 0.0, 1.0) * (0.0 if _finishing else 1.0)

	# panels slide in from their sides, two frames apart
	for i in 2:
		var panel: AssignPanel = _panels[i]
		var side := -1.0 if i == 0 else 1.0
		panel.position = (PANEL_POS[i] as Vector2) + Vector2(side * ((1.0 - Motion.whip(_t - Motion.stagger(i))) * 460.0 + out * out * 200.0), 0.0)
		panel.set_flash(maxf(0.0, panel._flash - delta * 3.5))
		var chip: Label = panel.get_meta("chip")
		chip.modulate.a = lerpf(chip.modulate.a, 1.0 if _slots[i]["claimed"] else 0.0, 1.0 - exp(-delta * 10.0))

	for i in 2:
		_update_slot(i, delta)
	_plates.queue_redraw()

	if _finish_t > 0.0 and not _finishing:
		_finish_t -= delta
		if _finish_t <= 0.0:
			_finishing = true
			var crest: String = CREST_BY_MODE.get(_mode, "gold")
			Game.go("select", {}, "crest", {"crest": crest})

func _update_slot(i: int, delta: float) -> void:
	var s: Dictionary = _slots[i]
	if not s["active"]:
		return
	var g: ControllerGlyph = s["glyph"]
	var claimed: bool = s["claimed"]
	# intro: the unclaimed glyphs rise into place
	var intro := Motion.whip(_t - float(s["delay"]))
	# flight between the middle slot and the panel
	s["fly_t"] = float(s["fly_t"]) + delta
	var ft: float = s["fly_t"]
	var target: Vector2 = DOCK_POS[i] if claimed else SLOT_POS[i]
	var pos: Vector2 = (s["from"] as Vector2).lerp(target, Motion.whip(ft))
	s["pos"] = pos
	s["hover"] = lerpf(float(s["hover"]), 1.0 if (s["hovering"] and not claimed) else 0.0, 1.0 - exp(-delta * 14.0))
	var shake := 0.0
	if float(s["shake"]) > 0.0:
		s["shake"] = float(s["shake"]) - delta
		shake = sin(_t * 70.0) * 7.0 * clampf(float(s["shake"]) / 0.3, 0.0, 1.0)
	g.position = pos + Vector2(shake, (1.0 - intro) * 90.0 - float(s["hover"]) * 4.0)
	var k := lerpf(0.8, 1.0, intro) * (1.0 + float(s["hover"]) * 0.05)
	g.scale = Vector2(k, k)
	s["lit"] = maxf(0.0, float(s["lit"]) - delta * 4.0)
	g.lit = s["lit"]
	var want := 0.0 if claimed or _finishing else clampf((_t - float(s["delay"]) - 0.35) * 3.0, 0.0, 1.0)
	s["hint_a"] = lerpf(float(s["hint_a"]), want, 1.0 - exp(-delta * 12.0))
	g.z_index = 3 if ft < 0.9 else 1

func _plate(c: Control, parts: Array, centre: Vector2, a: float) -> void:
	if a < 0.02 or parts.is_empty():
		return
	var w := Menu.parts_width(parts, HINT_SIZE, GLYPH_H) + 44.0
	Menu.ribbon_parts(c, Rect2(centre.x - w * 0.5, centre.y - 15.0, w, 30.0), parts, a)

func _draw_plates(c: Control) -> void:
	for i in 2:
		var s: Dictionary = _slots[i]
		if s["active"]:
			_plate(c, s["hint_parts"], Vector2(640.0, (SLOT_POS[i] as Vector2).y + 172.0), float(s["hint_a"]))
	_plate(c, _back_parts, Vector2(640.0, 692.0), _back_a)

## Which panels carry the bracket: a claimed one, and the CPU panel once every human has claimed.
func _refresh_panels() -> void:
	var on := []
	for i in 2:
		on.append(_slots[i]["claimed"] or (i >= _humans and _all_claimed()))
	var any: bool = on[0] or on[1]
	for i in 2:
		(_panels[i] as AssignPanel).set_ready(on[i], any)

# ── claiming ─────────────────────────────────────────────────────────────────
func _claimed_devices() -> Array:
	var out := []
	for s in _slots:
		if s["claimed"]:
			out.append(s["device"])
	return out

func _all_claimed() -> bool:
	for i in _humans:
		if not _slots[i]["claimed"]:
			return false
	return true

func _last_claimed() -> int:
	var best := -1
	var best_order := -1
	for i in 2:
		if _slots[i]["claimed"] and int(_slots[i]["order"]) > best_order:
			best_order = _slots[i]["order"]
			best = i
	return best

func _free_slot() -> int:
	for i in _humans:
		if not _slots[i]["claimed"]:
			return i
	return -1

func _claim(i: int, dev: String) -> void:
	var s: Dictionary = _slots[i]
	var pl: Dictionary = Game.session.players[i]
	pl["claimed"] = true
	pl["device"] = dev
	s["claimed"] = true
	s["device"] = dev
	s["order"] = _claim_seq
	_claim_seq += 1
	(s["glyph"] as ControllerGlyph).device = dev
	s["from"] = (s["glyph"] as ControllerGlyph).position
	s["fly_t"] = 0.0
	s["lit"] = 1.0
	(_panels[i] as AssignPanel).set_flash(1.0)
	if _humans == 1:
		(_panels[1] as AssignPanel).set_flash(0.6)
	Sfx.play("claim")
	_refresh_texts()
	if _all_claimed():
		_finish_t = BEAT

func _unclaim(i: int, sound := true) -> void:
	var s: Dictionary = _slots[i]
	var pl: Dictionary = Game.session.players[i]
	pl["claimed"] = false
	pl["device"] = ""
	s["claimed"] = false
	s["device"] = ""
	(s["glyph"] as ControllerGlyph).device = ""
	s["order"] = -1
	s["from"] = (s["glyph"] as ControllerGlyph).position
	s["fly_t"] = 0.0
	_finish_t = -1.0
	if sound:
		Sfx.play("back")
	_refresh_texts()

func _device_name(dev: String) -> String:
	if dev == "kb1":
		return "KEYBOARD  /  WASD + F"
	if dev == "kb2":
		return "KEYBOARD  /  ARROWS + ENTER"
	if dev == "shared":
		return "KEYBOARD  /  SPACE"
	if dev.begins_with("pad"):
		return "GAMEPAD %d" % (int(dev.substr(3)) + 1)
	return dev.to_upper()

## Who a join hint names: each keyboard still free, the first pad, and Space when one human plays.
func _join_devs() -> Array:
	var out := []
	for d in ["kb1", "kb2"]:
		if d not in _claimed_devices():
			out.append(d)
	out.append("pad0")
	if _humans == 1:
		out.append("shared")
	return out

## A hint line of devices' keys for one action: a picture where there is one, the key's text otherwise.
func _keys_parts(devs: Array, act: String, tail: String) -> Array:
	var parts := []
	for d in devs:
		if not parts.is_empty():
			parts.append("  /  ")
		var g := Controls.glyph_for(d, act)
		parts.append(g if g != null else Controls.label_for(d, act))
	parts.append(tail)
	return parts

func _join_keys() -> String:
	var parts: Array[String] = []
	for d in _join_devs():
		parts.append(Controls.label_for(d, "confirm"))
	return "%s  %s" % ["  /  ".join(parts), "to join" if _humans == 2 else "to start"]

func _refresh_texts() -> void:
	for i in 2:
		var s: Dictionary = _slots[i]
		if not s["claimed"]:
			s["hint_text"] = _join_keys()
			s["hint_parts"] = _keys_parts(_join_devs(), "confirm", "  to join" if _humans == 2 else "  to start")
		var chip: Label = (_panels[i] as AssignPanel).get_meta("chip")
		if s["claimed"]:
			chip.text = _device_name(s["device"])
		elif i >= _humans and _all_claimed():
			chip.text = ""
	_back_parts = _keys_parts(["kb1", "kb2", "pad0"], "back", "   back")
	_refresh_panels()

## A pad came or went: its family may differ, so the pictures and the hints read it again.
func _on_pads(_id: int, _connected: bool) -> void:
	_refresh_texts()
	for s in _slots:
		(s["glyph"] as ControllerGlyph).queue_redraw()

# ── input ────────────────────────────────────────────────────────────────────
func on_action(dev: String, act: String) -> void:
	if _finishing or _closing or _t < READY_AT:
		return
	match act:
		"confirm", "start":
			_press_claim(dev)
		"back":
			_press_back()

func _press_claim(dev: String) -> void:
	if dev in _claimed_devices():
		# this device already owns a slot: nudge it
		for i in 2:
			if _slots[i]["claimed"] and _slots[i]["device"] == dev:
				_slots[i]["shake"] = 0.3
		Sfx.play("error")
		return
	var free := _free_slot()
	if free < 0:
		Sfx.play("error")
		return
	if _humans == 2 and dev == "shared":
		Sfx.play("error")   # Space/Esc only drive single-player screens
		return
	_claim(free, dev)

func _press_back() -> void:
	var last := _last_claimed()
	if last >= 0:
		_unclaim(last)
		return
	Sfx.play("back")
	if _overlay:
		_closing = true
	else:
		Game.back()

func _on_hover(i: int, on: bool) -> void:
	_slots[i]["hovering"] = on and not Game.busy and not _finishing

func _on_glyph_input(ev: InputEvent, i: int) -> void:
	if _finishing or _closing or Game.busy or _t < READY_AT:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if i >= _humans:
			return
		if _slots[i]["claimed"]:
			_unclaim(i)
			return
		var used := _claimed_devices()
		var order := ["kb1", "kb2"] if i == 0 else ["kb2", "kb1"]
		for d in order:
			if d not in used:
				_claim(i, d)
				return
		Sfx.play("error")

func probe() -> Dictionary:
	var out := []
	for i in 2:
		out.append({"claimed": _slots[i]["claimed"], "device": _slots[i]["device"], "bracket": (_panels[i] as AssignPanel).claimed, "glow": 1.0 if (_panels[i] as AssignPanel).claimed else 0.0,
				"hint": _slots[i]["hint_text"], "family": (_slots[i]["glyph"] as ControllerGlyph).picture()})
	return {"mode": _mode, "humans": _humans, "slots": out, "t": snappedf(_t, 0.01), "finishing": _finishing, "beat": snappedf(_finish_t, 0.01)}
