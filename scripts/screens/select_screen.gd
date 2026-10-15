extends Screen
## Character Select. Left/right white->pale-blue side panels with the two
## fighters' art, a teal inverted-trapezoid plate with the roster row of BA student cards (Hina, the "?" random
## tile, Hoshino), P1 red / P2 blue bracket frames, then a Special Select panel per player once their fighter is locked
## (scripts/ui/special_panel.gd). When both players are locked in -> Game.push("stage").
##
##   versus2p   both humans, each on their own device      versus-cpu / training   P2 is auto-picked after P1 locks
## Writes Game.session.players[i].fighter / .special; `.locked` is true once fighter AND special are chosen.

const PLATE_SHADER := preload("res://shaders/select_plate.gdshader")
const BAND_SHADER := preload("res://shaders/select_band.gdshader")
const SpecialPanelScript := preload("res://scripts/ui/special_panel.gd")
const SelectSideScript := preload("res://scripts/ui/select_side.gd")

const FIELD := "UIs__00_Images__Image_Triangle_Pattern_Deco_1"
const RING := "UIs__00_Images__Image_Deco_Circle"
const TILE := 80.0
const PITCH := Vector2(91.3, 91.5)
const GRID_TOP := 43.0
const SIDES_AT := 0.1
const TILES_START := 0.25
const TILE_STEP := 0.05             # the roster closes in from two opposite corners, one band of tiles per step
const POP_FAST := 0.1
const POP_SETTLE := 0.25
const POP_DRIFT := 22.0
const START_FIGHTERS := [10004, 10005]     # Hina / Hoshino
const SEED := 20240607

var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _plate: ColorRect
var _plate_mat: ShaderMaterial
var _band_mat: ShaderMaterial
var _tile_layer: Control
var _tiles: Array = []              # {id, row, col, c, holder, card, delay, bump, popped}
var _row_idx: Array = []            # tile indices per grid row
var _cursors: Array = [null, null]
var _sides: Array = [null, null]
var _panels: Array = [null, null]
var _cur := [0, 0]                  # tile index under each cursor
var _state := ["pick", "pick"]      # pick | roll | special | done
var _roll := [{}, {}]
var _open_at := [-1.0, -1.0]
var _cpu_at := -1.0                 # when P2 (CPU) starts rolling
var _cpu_special_at := -1.0
var _cursors_at := 0.0
var _input_at := 0.0
var _sides_on := false
var _entered := false
var _done_at := -1.0
var _pushed := false
var _rand_t := [0.0, 0.0]
var _rand_id := [-1, -1]
var _leaving := false
var _pending: Array = []            # background portrait loads still in flight
var _hold := false                  # debug: params {"hold": true} stays on this screen after both lock in

func enter(_p: Dictionary, info: Dictionary) -> void:
	if Session._persists():
		_rng.randomize()
	else:
		_rng.seed = SEED                # scripted runs and suites stay reproducible
	_hold = bool(_p.get("hold", false))
	_preload_art()
	_build()
	if info.get("back", false):
		_t = 4.0
	elif info.get("style") == "crest":
		_t = -0.66            # the crest wipe holds black for 0.66 s after it builds this screen

func _start_id(s: int) -> int:
	var f: int = int(Game.session.players[s]["fighter"])
	return f if f >= 0 and Game.by_id.has(f) else START_FIGHTERS[s]

func _preload_art() -> void:
	for s in 2:
		UI.portrait(_start_id(s))
	for f in Game.fighters:
		BaArt.portrait(int(f["id"]))
	for f in Game.fighters:
		var path: String = UI.BA + String(f["portrait"])
		if ResourceLoader.exists(path) and not UI._tex.has(String(f["portrait"])):
			ResourceLoader.load_threaded_request(path)
			_pending.append({"id": int(f["id"]), "rel": String(f["portrait"]), "path": path})

## Collect finished background loads into the shared texture cache, one per frame: a decoded portrait costs about 7 ms.
func _poll_loads() -> void:
	var n := 0
	while not _pending.is_empty() and n < 1:
		var item: Dictionary = _pending[0]
		var st := ResourceLoader.load_threaded_get_status(item["path"])
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			break
		_pending.pop_front()
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(item["path"])   # collect it (frees the loader's bookkeeping)
			UI.tex(item["rel"])
		n += 1

func exit() -> void:
	for item in _pending:
		if ResourceLoader.load_threaded_get_status(item["path"]) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(item["path"])
	_pending.clear()

# ── construction ─────────────────────────────────────────────────────────────
func _build() -> void:
	_plate = ColorRect.new()
	_plate.size = Vector2(1280, 720)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_mat = ShaderMaterial.new()
	_plate_mat.shader = PLATE_SHADER
	_plate_mat.set_shader_parameter("sky", UI.tex("bg/BG_View_Kivotos.jpg"))
	_plate.material = _plate_mat
	add_child(_plate)

	var band := ColorRect.new()
	band.size = Vector2(1280, 720)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band_mat = ShaderMaterial.new()
	_band_mat.shader = BAND_SHADER
	_band_mat.set_shader_parameter("field", BaArt.tex(FIELD))
	_band_mat.set_shader_parameter("ring", BaArt.tex(RING))
	_band_mat.set_shader_parameter("tint_l", BaTokens.P1_LIGHT)
	_band_mat.set_shader_parameter("tint_r", BaTokens.P2_LIGHT)
	band.material = _band_mat
	add_child(band)

	for s in 2:
		_sides[s] = SelectSideScript.new().setup(s + 1)
		add_child((_sides[s] as SelectSide).art_layer)

	_tile_layer = Control.new()
	_tile_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tile_layer)
	_build_grid()

	for s in 2:
		var c := SelectCursor.new()
		c.setup(s + 1, BaTokens.side(s + 1))
		_cursors[s] = c
		add_child(c)
	for s in 2:
		add_child((_sides[s] as SelectSide).text_layer)

	for s in 2:
		var p: SpecialPanel = SpecialPanelScript.new().setup(s + 1, Game.specials)
		p.chosen.connect(_on_special_chosen.bind(s))
		p.cancelled.connect(_on_special_cancelled.bind(s))
		_panels[s] = p
		add_child(p)

	# cursor start tiles
	for s in 2:
		_cur[s] = maxi(_tile_of_fighter(_start_id(s)), 0)
		(_cursors[s] as SelectCursor).snap_to(_tiles[_cur[s]]["c"])
	_arrange_cursors()
	var last := 0.0
	for tl in _tiles:
		last = maxf(last, float(tl["delay"]))
	_cursors_at = last + POP_FAST + POP_SETTLE

func _build_grid() -> void:
	var rows := Fighters.build_grid(Game.fighters)
	var bands := []
	for r in rows.size():
		var row: Array = rows[r]
		var idxs := []
		for c in row.size():
			var cell: Variant = row[c]
			var centre := Vector2(640.0 + (float(c) - (row.size() - 1) * 0.5) * PITCH.x, GRID_TOP + TILE * 0.5 + float(r) * PITCH.y)
			var holder := Control.new()
			holder.size = Vector2(TILE, TILE)
			holder.position = centre - Vector2(TILE, TILE) * 0.5
			holder.pivot_offset = Vector2(TILE, TILE) * 0.5
			holder.mouse_filter = Control.MOUSE_FILTER_STOP
			var id := int(cell["id"]) if cell is Dictionary else -1
			var card := SelectTile.new().setup(id)
			card.size = holder.size
			holder.add_child(card)
			_tile_layer.add_child(holder)
			var k := _tiles.size()
			holder.mouse_entered.connect(_on_tile_hover.bind(k))
			holder.gui_input.connect(_on_tile_input.bind(k))
			_tiles.append({"id": id, "row": r, "col": c, "c": centre, "holder": holder, "card": card, "delay": TILES_START, "bump": 0.0, "popped": false})
			bands.append(_corner_band(centre, rows.size()))
			idxs.append(k)
		_row_idx.append(idxs)
	var first: int = bands.min()
	for k in _tiles.size():
		_tiles[k]["delay"] = TILES_START + float(bands[k] - first) * TILE_STEP

## Distance in tiles from the nearer of the grid's top left and bottom right corners: the roster pops in band by band.
static func _corner_band(centre: Vector2, row_count: int) -> int:
	var gx := (centre.x - 640.0) / PITCH.x
	var gy := (centre.y - (GRID_TOP + TILE * 0.5)) / PITCH.y
	var span_x := 2.0
	var span_y := float(row_count - 1)
	return roundi(minf((gx + span_x) + gy, (span_x - gx) + (span_y - gy)))

func _tile_of_fighter(id: int) -> int:
	for i in _tiles.size():
		if _tiles[i]["id"] == id:
			return i
	return -1

# ── frame ────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_t += minf(delta, 0.05) if _t < 0.0 else delta   # the crest wipe clamps its clock the same way
	_plate_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_t * 2.1))
	_band_mat.set_shader_parameter("spin", _t * deg_to_rad(3.0))
	for i in _tiles.size():
		var tl: Dictionary = _tiles[i]
		var holder: Control = tl["holder"]
		var ct := _t - float(tl["delay"])
		if ct <= 0.0:
			holder.modulate.a = 0.0
			continue
		if not tl["popped"]:
			tl["popped"] = true
			if i % 3 == 0:
				Sfx.play("pop")
		var k := Motion.whip(ct, POP_FAST, POP_SETTLE)
		tl["bump"] = move_toward(float(tl["bump"]), 0.0, delta * 3.2)
		var bump := sin(float(tl["bump"]) * PI) * 0.09
		holder.scale = Vector2.ONE * (lerpf(0.6, 1.0, k) + bump)
		holder.position = (tl["c"] as Vector2) - holder.size * 0.5 + ((tl["c"] as Vector2) - Vector2(640.0, 360.0)).normalized() * (1.0 - k) * POP_DRIFT
		holder.modulate.a = clampf(k * 3.0, 0.0, 1.0)
		holder.z_index = 1 if (_cur[0] == i or _cur[1] == i) else 0
	if not _sides_on and _t >= SIDES_AT:
		_sides_on = true
		for s in 2:
			_show_tile_art(s)
			(_sides[s] as SelectSide).start()
	if not _entered and _t >= _cursors_at:
		_entered = true
		_input_at = _t + 0.25
		Sfx.play("whoosh")
		for s in 2:
			(_cursors[s] as SelectCursor).appear()
	_poll_loads()
	_process_rolls(delta)
	_process_timers()
	_process_random_cycle(delta)
	for s in 2:                       # after the swaps above: a new texture must not draw one frame in the old art's frame and alpha
		(_cursors[s] as SelectCursor).tick(delta, _t)
		(_sides[s] as SelectSide).process(delta)

func _arrange_cursors() -> void:
	# both cursors on one tile: P2 sits inside P1's ring
	var same: bool = _cur[0] == _cur[1]
	(_cursors[0] as SelectCursor).inset = 0.0
	(_cursors[1] as SelectCursor).inset = 7.0 if same else 0.0
	for s in 2:
		(_cursors[s] as SelectCursor).target = _tiles[_cur[s]]["c"]

func _process_timers() -> void:
	for s in 2:
		if _open_at[s] >= 0.0 and _t >= _open_at[s]:
			_open_at[s] = -1.0
			_open_panel(s)
	if _cpu_at >= 0.0 and _t >= _cpu_at:
		_cpu_at = -1.0
		var f: Dictionary = Game.fighters[_rng.randi() % Game.fighters.size()]
		_start_roll(1, int(f["id"]), true)
	if _cpu_special_at >= 0.0 and _t >= _cpu_special_at:
		_cpu_special_at = -1.0
		(_panels[1] as SpecialPanel).auto_pick(_rng.randi() % Game.specials.size())
	if _done_at >= 0.0 and _t >= _done_at and not _pushed and not covered and not Game.busy and not _hold:
		_pushed = true
		_done_at = -1.0
		Game.push("stage", {})

func _process_random_cycle(delta: float) -> void:
	for s in 2:
		if _state[s] == "pick" and _entered and _tiles[_cur[s]]["id"] == -1:
			_rand_t[s] += delta
			if _rand_t[s] >= 0.5:
				_rand_t[s] = 0.0
				_rand_id[s] = int(Game.fighters[_rng.randi() % Game.fighters.size()]["id"])
				(_sides[s] as SelectSide).show_random(_rand_id[s])

# ── cursor movement ──────────────────────────────────────────────────────────
func _neighbour(i: int, dx: int, dy: int) -> int:
	var t: Dictionary = _tiles[i]
	if dx != 0:
		var row: Array = _row_idx[t["row"]]
		return row[(int(t["col"]) + dx + row.size()) % row.size()]
	var nr: int = (int(t["row"]) + dy + _row_idx.size()) % _row_idx.size()
	var best: int = i
	var best_d := INF
	for k in _row_idx[nr]:
		var d := absf((_tiles[k]["c"] as Vector2).x - (t["c"] as Vector2).x)
		if d < best_d:
			best_d = d
			best = k
	return best

func _move_cursor(s: int, to: int, sound := true) -> void:
	if to == _cur[s]:
		return
	_cur[s] = to
	(_cursors[s] as SelectCursor).nudge()
	_arrange_cursors()
	_show_tile_art(s)
	if sound:
		Sfx.play("tick")

func _show_tile_art(s: int) -> void:
	var id: int = _tiles[_cur[s]]["id"]
	var side: SelectSide = _sides[s]
	if id == -1:
		_rand_t[s] = 0.0
		if _rand_id[s] < 0:
			_rand_id[s] = int(Game.fighters[_rng.randi() % Game.fighters.size()]["id"])
		side.show_random(_rand_id[s])
	else:
		side.clear_random()
		side.show_fighter(id)

# ── input ────────────────────────────────────────────────────────────────────
func on_action(dev: String, act: String) -> void:
	if not _entered or _t < _input_at or _leaving:
		return
	for slot in [1, 2]:
		if Game.session.players[slot - 1]["cpu"]:
			continue
		if Game.session.controls(dev, slot):
			_handle(slot - 1, act)
			return

func _handle(s: int, act: String) -> void:
	match _state[s]:
		"pick":
			match act:
				"left": _move_cursor(s, _neighbour(_cur[s], -1, 0))
				"right": _move_cursor(s, _neighbour(_cur[s], 1, 0))
				"up": _move_cursor(s, _neighbour(_cur[s], 0, -1))
				"down": _move_cursor(s, _neighbour(_cur[s], 0, 1))
				"confirm": _confirm_tile(s)
				"back": _back_from_pick(s)
		"special":
			(_panels[s] as SpecialPanel).on_action(act)
		"done":
			if act == "back":
				Sfx.play("back")
				_reopen_special(s)

func _confirm_tile(s: int) -> void:
	var id: int = _tiles[_cur[s]]["id"]
	if id == -1:
		var f: Dictionary = Game.fighters[_rng.randi() % Game.fighters.size()]
		_start_roll(s, int(f["id"]), false)
	else:
		_lock_fighter(s, id)

func _back_from_pick(s: int) -> void:
	# leave only when nobody has locked anything
	for o in 2:
		if o != s and _state[o] != "pick" and not Game.session.players[o]["cpu"]:
			Sfx.play("error")
			return
	if Game.busy:
		return
	_leaving = true
	Sfx.play("back")
	Game.go("menu", {}, "fade")

func _on_tile_hover(k: int) -> void:
	if covered or Game.busy or not _entered or _t < _input_at or _state[0] != "pick":
		return
	_move_cursor(0, k)

func _on_tile_input(ev: InputEvent, k: int) -> void:
	if covered or Game.busy or not _entered or _t < _input_at or _state[0] != "pick":
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_move_cursor(0, k, false)
		_confirm_tile(0)

# ── random roulette ──────────────────────────────────────────────────────────
func _start_roll(s: int, fid: int, cpu: bool) -> void:
	var target := _tile_of_fighter(fid)
	var seq := []
	var last: int = _cur[s]
	for n in 9:
		var k := _rng.randi() % _tiles.size()
		while k == last or _tiles[k]["id"] == -1:
			k = _rng.randi() % _tiles.size()
		seq.append(k)
		last = k
	seq.append(target)
	_state[s] = "roll"
	_roll[s] = {"seq": seq, "k": -1, "wait": 0.0, "fid": fid}

func _process_rolls(delta: float) -> void:
	for s in 2:
		if _state[s] != "roll":
			continue
		var r: Dictionary = _roll[s]
		r["wait"] += delta
		var k: int = r["k"]
		var gap := 0.04 if k < 0 else 0.05 + float(k) * 0.011
		if r["wait"] >= gap:
			r["wait"] = 0.0
			k += 1
			r["k"] = k
			var seq: Array = r["seq"]
			if k < seq.size():
				_move_cursor(s, seq[k])
			else:
				_roll[s] = {}
				_lock_fighter(s, int(r["fid"]))

# ── locking ──────────────────────────────────────────────────────────────────
func _lock_fighter(s: int, fid: int) -> void:
	var p: Dictionary = Game.session.players[s]
	p["fighter"] = fid
	p["special"] = -1
	p["locked"] = false
	_state[s] = "special"
	var t := _tile_of_fighter(fid)
	if t >= 0:
		_cur[s] = t
		_arrange_cursors()
		_tiles[t]["bump"] = 1.0
	var side: SelectSide = _sides[s]
	side.clear_random()
	side.show_fighter(fid)
	side.flash()
	(_cursors[s] as SelectCursor).lock()
	Sfx.play("lock")
	_open_at[s] = _t + 0.32
	if s == 0 and Game.session.players[1]["cpu"] and _state[1] == "pick":
		_cpu_at = _t + 0.9

func _open_panel(s: int) -> void:
	if _state[s] != "special":
		return
	var p: Dictionary = Game.session.players[s]
	(_panels[s] as SpecialPanel).open(int(p["special"]))
	(_sides[s] as SelectSide).set_covered(1.0)
	if p["cpu"]:
		_cpu_special_at = _t + 0.75

func _on_special_chosen(sid: int, s: int) -> void:
	if _state[s] != "special":
		return
	var p: Dictionary = Game.session.players[s]
	p["special"] = sid
	p["locked"] = true
	_state[s] = "done"
	(_panels[s] as SpecialPanel).close()
	(_sides[s] as SelectSide).set_covered(0.0)
	(_sides[s] as SelectSide).flash()
	Sfx.play("lock")
	if _state[0] == "done" and _state[1] == "done":
		_done_at = _t + 0.5

func _on_special_cancelled(s: int) -> void:
	if _state[s] != "special":
		return
	_unlock_fighter(s)

func _unlock_fighter(s: int) -> void:
	var p: Dictionary = Game.session.players[s]
	p["fighter"] = -1
	p["special"] = -1
	p["locked"] = false
	_state[s] = "pick"
	_open_at[s] = -1.0
	(_panels[s] as SpecialPanel).close()
	(_sides[s] as SelectSide).set_covered(0.0)
	(_cursors[s] as SelectCursor).unlock()
	_done_at = -1.0
	if s == 0:
		_cpu_cancel()

func _reopen_special(s: int) -> void:
	var p: Dictionary = Game.session.players[s]
	p["locked"] = false
	_state[s] = "special"
	_done_at = -1.0
	_pushed = false
	_open_at[s] = _t + 0.05

func _cpu_cancel() -> void:
	if not Game.session.players[1]["cpu"]:
		return
	_cpu_at = -1.0
	_cpu_special_at = -1.0
	_roll[1] = {}
	var p: Dictionary = Game.session.players[1]
	p["fighter"] = -1
	p["special"] = -1
	p["locked"] = false
	_state[1] = "pick"
	_open_at[1] = -1.0
	(_panels[1] as SpecialPanel).close()
	(_sides[1] as SelectSide).set_covered(0.0)
	(_cursors[1] as SelectCursor).unlock()

## Back from the stage screen: the humans re-open their special panel, the CPU keeps its picks.
func resume() -> void:
	_pushed = false
	_done_at = -1.0
	for s in 2:
		if not Game.session.players[s]["cpu"]:
			_reopen_special(s)

func probe() -> Dictionary:
	var out := {"t": snappedf(_t, 0.01), "state": _state.duplicate(), "entered": _entered, "cursor": [], "panels": []}
	for s in 2:
		var tid: int = _tiles[_cur[s]]["id"]
		out["cursor"].append(tid)
		var pn: SpecialPanel = _panels[s]
		out["panels"].append({"open": pn.is_open, "index": pn.index, "id": pn.current_id()})
	out["players"] = Game.session.players.map(func(p): return {"fighter": p["fighter"], "special": p["special"], "locked": p["locked"]})
	return out
