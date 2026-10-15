class_name SpecialPanel
extends Control
## The Special Select panel: a light rounded panel that slides in from the player's
## side after their fighter is locked. Header "Special Select" with a yellow underline, a scrolling 4-column
## grid of the assist/special head icons (a partial row peeks at the bottom), a yellow-bordered highlight and
## a footer strip with the school, the NAME and a cropped face of the highlighted special.
##
##   var p := SpecialPanel.new().setup(slot, Game.specials)   add_child(p)
##   p.open(start_id)    p.on_action(act)    p.close()    p.auto_pick(index)   (CPU roulette)
##   signals: chosen(id)  cancelled  moved(id)
## All rects are 1280x720 reference pixels (P1 panel x 20..398, P2 panel x 880..1258, both y 105..630).

signal chosen(id: int)
signal cancelled
signal moved(id: int)

const SIZE := Vector2(378, 525)
const HOME_Y := 105.0
const HOME_X := [20.0, 880.0]
const COLS := 4
const TILE_SIZE := Vector2(82, 72)
const PITCH := Vector2(84.0, 85.0)
const WELL := Rect2(13, 60, 353, 383)       # the grey list window
const FOOT := Rect2(13, 453, 353, 62)       # footer strip
const PAD := Vector2(13, 13)                # first tile inside the well
const VIEW_ROWS := 4
const FRAME_COL := Color("dde8ec")
const WELL_COL := Color("9fa9ae")
const FOOT_COL := Color("9aa2a7")

var slot := 1
var items: Array = []
var index := 0
var is_open := false
var _t := 0.0                    # seconds since open()
var _closing := false
var _close_t := 0.0
var _shown := false
var _scroll := 0.0               # rows, animated
var _scroll_to := 0
var _tiles: Array = []           # {holder, card, bump}
var _list: Control
var _school: Label
var _name: Label
var _face_cur: TextureRect
var _face_ghost: TextureRect
var _face_t := 1.0
var _ghost_t := 1.0
var _last_dir := 1.0
var _auto := {}
var _shell: Panel

func setup(player_slot: int, list: Array) -> SpecialPanel:
	slot = player_slot
	items = list
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	position = Vector2(_start_x(), HOME_Y)
	return self

func _start_x() -> float:
	return -SIZE.x - 60.0 if slot == 1 else 1280.0 + 60.0

func _home_x() -> float:
	return HOME_X[slot - 1]

# ── construction ─────────────────────────────────────────────────────────────
func _flat(col: Color, r_tl := 0, r_tr := 0, r_br := 0, r_bl := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = r_tl
	sb.corner_radius_top_right = r_tr
	sb.corner_radius_bottom_right = r_br
	sb.corner_radius_bottom_left = r_bl
	sb.anti_aliasing = true
	return sb

func _panel(rect: Rect2, sb: StyleBoxFlat) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", sb)
	return p

func _build() -> void:
	var shell_sb := _flat(FRAME_COL, 10, 10, 10, 10)
	shell_sb.shadow_size = 16
	shell_sb.shadow_color = Color(0.02, 0.06, 0.12, 0.38)
	shell_sb.shadow_offset = Vector2(0, 6)
	shell_sb.border_width_left = 2
	shell_sb.border_width_right = 2
	shell_sb.border_width_bottom = 2
	shell_sb.border_color = Color("eef4f6")
	_shell = _panel(Rect2(Vector2.ZERO, SIZE), shell_sb)
	add_child(_shell)

	var head_sb := _flat(Color("f9f9f9"), 10, 10, 0, 0)
	add_child(_panel(Rect2(0, 0, SIZE.x, 51), head_sb))
	var sep := ColorRect.new()
	sep.color = Color("cfd6d9")
	sep.position = Vector2(0, 50)
	sep.size = Vector2(SIZE.x, 1.5)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)
	var title := UI.label("Special Select", 27, "ui", Color("2b3350"), 800, 0, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(0, 5)
	title.size = Vector2(SIZE.x, 42)
	add_child(title)
	var under := ColorRect.new()
	under.color = Color("f1e24a")
	under.position = Vector2(83, 47)
	under.size = Vector2(213, 3.5)
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(under)

	# list well
	add_child(_panel(WELL, _flat(WELL_COL, 14, 14, 14, 14)))
	_list = Control.new()
	_list.position = WELL.position
	_list.size = WELL.size
	_list.clip_contents = true
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)
	for i in items.size():
		var it: Dictionary = items[i]
		var holder := GalleryKit.Tile.new()
		holder.s = it
		holder.size = TILE_SIZE
		holder.pivot_offset = TILE_SIZE * 0.5
		holder.mouse_filter = Control.MOUSE_FILTER_STOP
		holder.mouse_entered.connect(_on_hover.bind(i))
		holder.gui_input.connect(_on_tile_input.bind(i))
		_list.add_child(holder)
		_tiles.append({"holder": holder, "bump": 0.0})
	# footer
	add_child(_panel(FOOT, _flat(FOOT_COL, 14, 14, 14, 14)))
	var foot := Control.new()
	foot.position = FOOT.position
	foot.size = FOOT.size
	foot.clip_contents = true
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(foot)
	_face_ghost = _face_rect()
	_face_cur = _face_rect()
	foot.add_child(_face_ghost)
	foot.add_child(_face_cur)
	var right := slot == 1   # P1's text sits on the right, face on the left (P2 mirrored)
	var tx := 0.0 if not right else FOOT.size.x - 360.0 - 14.0
	_school = SelectFrames.text("", 11, 3, 800, 1.0, 0, HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT)
	_school.position = Vector2(tx + (0.0 if right else 12.0), 8)
	_school.size = Vector2(360, 16)
	foot.add_child(_school)
	_name = SelectFrames.text("", 34, 6, 900, 1.12, -1, HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT)
	_name.position = Vector2(tx + (0.0 if right else 12.0), 12)
	_name.size = Vector2(360, 48)
	foot.add_child(_name)
	# corner masks (the clipped list/footer have rounded corners in the stills)
	var mask := _CornerMask.new()
	mask.size = SIZE
	mask.rects = [WELL, FOOT]
	mask.radius = 14.0
	mask.color = FRAME_COL
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mask)
	# soft inner shadow on the top of the well
	var shade := _WellShade.new()
	shade.position = WELL.position
	shade.size = WELL.size
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

func _face_rect() -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = Vector2(190, 190)
	r.modulate.a = 0.0
	return r

# ── open / close ─────────────────────────────────────────────────────────────
## Slide in; the highlight starts on `start_id` (or the first special).
func open(start_id := -1) -> void:
	index = 0
	for i in items.size():
		if int(items[i]["id"]) == start_id:
			index = i
	_auto = {}
	_scroll_to = clampi(index / COLS - (VIEW_ROWS - 1), 0, maxi(_rows() - VIEW_ROWS, 0))
	_scroll = float(_scroll_to)
	_t = 0.0
	_closing = false
	is_open = true
	visible = true
	_shown = true
	for i in _tiles.size():
		_mark(i, i == index)
	_set_footer(true)
	position = Vector2(_start_x(), HOME_Y)
	Sfx.play("whoosh")

func close() -> void:
	if not is_open:
		return
	is_open = false
	_closing = true
	_close_t = 0.0
	_auto = {}

func current_id() -> int:
	return int(items[index]["id"]) if index < items.size() else -1

func is_visible_now() -> bool:
	return _shown

## CPU roulette: hop the highlight around, ending on `target` (an index), then emit chosen.
func auto_pick(target: int, hops := 9) -> void:
	_auto = {"target": clampi(target, 0, items.size() - 1), "hops": hops, "wait": 0.0, "n": 0}

# ── input ────────────────────────────────────────────────────────────────────
func on_action(act: String) -> void:
	if not is_open or _t < 0.2 or not _auto.is_empty():
		return
	match act:
		"left": _goto(index - 1 if index > 0 else items.size() - 1, -1.0)
		"right": _goto(index + 1 if index + 1 < items.size() else 0, 1.0)
		"up": _goto(_vert(-1), 0.0)
		"down": _goto(_vert(1), 0.0)
		"lb": _goto(_vert(-VIEW_ROWS), 0.0)
		"rb": _goto(_vert(VIEW_ROWS), 0.0)
		"confirm": _confirm()
		"back":
			Sfx.play("back")
			cancelled.emit()

func _rows() -> int:
	return (items.size() + COLS - 1) / COLS

func _vert(dr: int) -> int:
	var rows := _rows()
	var r := index / COLS
	var c := index % COLS
	var nr := ((r + dr) % rows + rows) % rows
	return mini(nr * COLS + c, items.size() - 1)

func _goto(i: int, dir: float) -> void:
	i = clampi(i, 0, items.size() - 1)
	if i == index:
		return
	_set_index(i, dir, true)

func _set_index(i: int, dir: float, sound: bool) -> void:
	_mark(index, false)
	index = i
	_mark(index, true)
	_tiles[index]["bump"] = 1.0
	var row := index / COLS
	if row < _scroll_to:
		_scroll_to = row
	elif row > _scroll_to + VIEW_ROWS - 1:
		_scroll_to = row - (VIEW_ROWS - 1)
	_scroll_to = clampi(_scroll_to, 0, maxi(_rows() - VIEW_ROWS, 0))
	_last_dir = dir if dir != 0.0 else _last_dir
	_set_footer(false)
	if sound:
		Sfx.play("tick")
	moved.emit(current_id())

func _mark(i: int, on: bool) -> void:
	var tl: GalleryKit.Tile = _tiles[i]["holder"]
	tl.sel = on
	tl.queue_redraw()

func _confirm() -> void:
	_tiles[index]["bump"] = 1.6
	chosen.emit(current_id())

func _on_hover(i: int) -> void:
	if is_open and _t > 0.4 and _auto.is_empty() and i != index:
		_set_index(i, 0.0, true)

func _on_tile_input(ev: InputEvent, i: int) -> void:
	if not is_open or _t < 0.4 or not _auto.is_empty():
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if i != index:
			_set_index(i, 0.0, false)
		_confirm()

# ── footer ───────────────────────────────────────────────────────────────────
func _set_footer(instant: bool) -> void:
	var it: Dictionary = items[index]
	_school.text = String(it["schoolName"]).to_upper()
	_name.text = Fighters.display_name(it).to_upper()
	var tex := UI.icon(int(it["id"]))
	if not instant and _face_cur.texture != null:
		_face_ghost.texture = _face_cur.texture
		_ghost_t = 0.0
	_face_cur.texture = tex
	_face_t = 1.0 if instant else 0.0

func _place_face(r: TextureRect, off: float) -> void:
	# P1: face on the left edge, P2: face on the right edge; eyes at the strip's middle
	var w := 190.0
	r.size = Vector2(w, w)
	var x := -14.0 + off if slot == 1 else FOOT.size.x + 12.0 - w + off
	r.position = Vector2(x, -52.0)

# ── frame ────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _shown:
		return
	if is_open:
		_t += delta
	var x := _home_x()
	if _closing:
		_close_t += delta
		var k := clampf(_close_t / 0.26, 0.0, 1.0)
		x = lerpf(_home_x(), _start_x(), k * k)
		if k >= 1.0:
			_closing = false
			_shown = false
			visible = false
			return
	else:
		x = lerpf(_start_x(), _home_x(), Motion.whip(_t, 0.15, 0.3))
	position.x = x
	# auto roulette
	if not _auto.is_empty() and _t > 0.35:
		_auto["wait"] += delta
		var gap := 0.065 + float(_auto["n"]) * 0.012
		if _auto["wait"] >= gap:
			_auto["wait"] = 0.0
			_auto["n"] += 1
			if _auto["n"] > _auto["hops"]:
				var target: int = _auto["target"]
				_auto = {}
				if target != index:
					_set_index(target, 0.0, true)
				_tiles[index]["bump"] = 1.6
				chosen.emit(current_id())
			else:
				var nxt := (index + 7 + int(_auto["n"]) * 3) % items.size()
				_set_index(nxt, 0.0, true)
	# scroll + tiles
	_scroll = lerpf(_scroll, float(_scroll_to), 1.0 - exp(-delta * 14.0))
	if absf(_scroll - float(_scroll_to)) < 0.002:
		_scroll = float(_scroll_to)
	for i in _tiles.size():
		var t: Dictionary = _tiles[i]
		var holder: Control = t["holder"]
		var r := i / COLS
		var c := i % COLS
		var y := PAD.y + (float(r) - _scroll) * PITCH.y
		holder.position = Vector2(PAD.x + c * PITCH.x, y)
		var sc := 1.0
		var shown := true
		if r <= VIEW_ROWS:
			var ct := _t - 0.14 - Motion.stagger(r + c, 0.03)
			sc = lerpf(0.55, 1.0, Motion.whip(ct, 0.12, 0.25))
			shown = ct > 0.0
		t["bump"] = move_toward(float(t["bump"]), 0.0, delta * 4.0)
		var b: float = t["bump"]
		var hl := 1.0 if i == index else 0.0
		var bump := sin(b * PI * 0.5) * 0.06 * hl if b > 0.0 else 0.0
		sc = sc * (1.0 + bump + hl * 0.02)
		holder.scale = Vector2(sc, sc)
		holder.visible = shown
		holder.z_index = 1 if i == index else 0
		var tl: GalleryKit.Tile = holder
		if tl.sel:
			tl.t += delta
			tl.queue_redraw()
	# footer faces
	_face_t = minf(_face_t + delta / 0.2, 1.0)
	_ghost_t = minf(_ghost_t + delta / 0.3, 1.0)
	var inward := 1.0 if slot == 1 else -1.0
	var fe := 1.0 - pow(1.0 - _face_t, 3.0)
	_face_cur.modulate.a = fe if _face_cur.texture else 0.0
	_place_face(_face_cur, -inward * (1.0 - fe) * 26.0 * 1.0)
	_face_ghost.modulate.a = 0.55 * pow(1.0 - _ghost_t, 1.5) if _face_ghost.texture else 0.0
	_place_face(_face_ghost, inward * _ghost_t * 22.0)
	_name.modulate.a = minf(1.0, 0.35 + fe * 0.65)

# ── little drawing helpers ───────────────────────────────────────────────────
class _CornerMask extends Control:
	var rects: Array = []
	var radius := 14.0
	var color := Color.WHITE
	func _draw() -> void:
		for r: Rect2 in rects:
			for corner in 4:
				var cx := r.position.x if corner % 2 == 0 else r.end.x
				var cy := r.position.y if corner < 2 else r.end.y
				var sx := 1.0 if corner % 2 == 0 else -1.0
				var sy := 1.0 if corner < 2 else -1.0
				var centre := Vector2(cx + sx * radius, cy + sy * radius)
				var pts := PackedVector2Array([Vector2(cx, cy)])
				var n := 10
				for k in n + 1:
					var a := PI * 0.5 * float(k) / float(n)
					pts.append(centre + Vector2(-sx * cos(a), -sy * sin(a)) * radius)
				pts.append(Vector2(cx, cy))
				draw_colored_polygon(pts, color)

class _WellShade extends Control:
	func _draw() -> void:
		var h := 12.0
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, h), Vector2(0, h)])
		var cols := PackedColorArray([Color(0, 0, 0, 0.14), Color(0, 0, 0, 0.14), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0)])
		draw_polygon(pts, cols)
