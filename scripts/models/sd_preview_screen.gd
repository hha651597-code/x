extends Screen
## SD model preview (screen "sdpreview"): every roster fighter with an sd.json, each with its state anims, kit moves and
## raw source clips, posed only through the actor's pose() (blending off unless toggled). Hurtbox, hit rect, live hit and
## muzzle come from the game's own code: Fighter.hurtbox(), world_rect() of the move's hit, active_hit(),
## FighterView._muzzle_pos(). The held-move timeline, spawn timing and spawn origin are copies of fighter.gd
## _tick_attack and FightScreen.spawn_projectile.
## Fighters are built directly with setup() (not through the fight screen), never ticked, and kept alive for the whole
## run: freeing an SD actor mid-run printed renderer "material is null" errors in the suite.
## Args after "--" (tools/sd_preview.sh passes them): --sd-key=<key> --sd-anim=<anim> preselect; --sd-sheet renders
## filmstrips of key/anim ("all" for every one) to export/sd_preview/<key>/<anim>.png and quits, exit 1 on any failure.

const SD_ACTOR := preload("res://scripts/models/sd_fighter_actor.gd")
const VIEW := preload("res://scripts/fight/fighter_view.gd")
const SPEEDS := [0.25, 0.5, 1.0, 2.0]
const VIEW_FEET := Vector2(820, 650)
const VIEW_SCALE := 0.9
## A sheet cell: the world window around the feet (fight px, room for either facing's reach) and its scale.
const CELL := Rect2(-410, -470, 820, 600)
const CELL_SCALE := 0.4
## Air moves and the jump are drawn this far off the floor line, as in the game, so tucked legs do not read as floating.
const AIR_LIFT := 110.0
const CELL_AT := Vector2(40, 80)
const COLS := 12
const SAMPLES := 16
const HEADER := 52
const HURT := Color("2f6bff")
const HIT := Color("e0314b")
const SHOT := Color("f08c00")
const SPAWN := Color("2b9348")
const MUZZLE := Color("c2255c")
const HELP := "W/S or Up/Down  animation      A/D or Left/Right  step a frame      Q/E or , .  character      Space  play/pause      R or ;  facing\nT or '  overlay      Tab or V  speed      B  blending      C  hold length (held moves)      Esc  quit"

var chars: Array = []         # {key, fighter, actor, entries}; entries are {name, kind: state|move|clip, anim, move}
var cur := 0
var ai := 0
var idx := 0
var timeline: Array = []      # {sf, mf, ch} per sample: the sim's state frame, move frame and charge_t
var playing := true
var face := 1
var show_overlay := true
var blend := false
var speed_i := 2
var hold_len := {}            # move key -> hold length (default the move's hold.max)
var sheet := false
var failures := 0
var _acc := 0.0
var stage: Node2D
var marks: Node2D
var lists: Label
var info: Label
var help: Label
var header: Label

func enter(p: Dictionary, _info: Dictionary) -> void:
	var key := String(p.get("key", ""))
	var anim := String(p.get("anim", ""))
	sheet = bool(p.get("sheet", false))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sd-key="):
			key = a.substr(9)
		elif a.begins_with("--sd-anim="):
			anim = a.substr(10)
		elif a == "--sd-sheet":
			sheet = true
	var bg := ColorRect.new()
	bg.color = UI.ICE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	stage = Node2D.new()
	add_child(stage)
	for entry in Game.fighters:
		if not SD_ACTOR.supports(entry):
			continue
		var f := Fighter.new()
		stage.add_child(f)
		f.set_process(false)    # never ticked or synced: only pose() moves the model
		f.setup(entry, 1, {})
		f.view.back.visible = false
		var actor: Node = f.view.sd_actor
		actor.cfg = actor.cfg.duplicate(true)
		chars.append({"key": String(entry["key"]), "fighter": f, "actor": actor, "entries": _entries(f, actor)})
	marks = VIEW.DrawProxy.new()
	marks.cb = _draw_marks
	marks.z_index = 10
	stage.add_child(marks)
	lists = UI.label("", 17, "label")
	lists.position = Vector2(20, 14)
	add_child(lists)
	info = UI.label("", 19, "label")
	info.position = Vector2(340, 14)
	add_child(info)
	help = UI.label(HELP, 15, "label", Color(UI.INK, 0.75))
	help.position = Vector2(20, 672)
	add_child(help)
	header = UI.label("", 18, "label")
	header.position = Vector2(12, 6)
	header.visible = false
	add_child(header)
	if chars.is_empty():
		info.text = "No roster fighter has assets/ba/sd/<key>/sd.json."
		if sheet:
			print("SD_PREVIEW FAIL no SD fighters")
			get_tree().quit(1)
		return
	if sheet:
		_render_sheets(key if key != "" else "all", anim if anim != "" else "all")
		return
	stage.position = VIEW_FEET
	stage.scale = Vector2.ONE * VIEW_SCALE
	var c := maxi(0, _char_index(key))
	if key != "" and _char_index(key) < 0:
		print("SD_PREVIEW no SD fighter '%s', showing %s" % [key, chars[c]["key"]])
	var a := _anim_index(chars[c], anim)
	if anim != "" and a < 0:
		print("SD_PREVIEW no anim '%s' for %s, showing %s" % [anim, chars[c]["key"], chars[c]["entries"][0]["name"]])
	_select(c, maxi(0, a))
	_apply()

## State anims first (before the raw clips are added to the actor's own copy of its config), then kit moves, then clips.
func _entries(f: Fighter, actor: Node) -> Array:
	var out: Array = []
	for name in actor.cfg["anims"]:
		out.append({"name": String(name), "kind": "state", "anim": String(name)})
	for key in f.moves:
		out.append({"name": String(key), "kind": "move", "anim": "attack", "move": f.moves[key]})
	for clip in actor.player.get_animation_list():
		actor.cfg["anims"]["clip:" + clip] = {"clip": String(clip), "mode": "hold", "blend": 0}
		out.append({"name": String(clip), "kind": "clip", "anim": "clip:" + clip})
	return out

func _char_index(key: String) -> int:
	for i in chars.size():
		if chars[i]["key"] == key:
			return i
	return -1

func _anim_index(c: Dictionary, name: String) -> int:
	for i in c["entries"].size():
		if c["entries"][i]["name"] == name:
			return i
	return -1

func _select(c: int, a: int) -> void:
	cur = posmod(c, chars.size())
	for i in chars.size():
		chars[i]["fighter"].visible = i == cur
	ai = posmod(a, chars[cur]["entries"].size())
	timeline = _timeline(chars[cur]["actor"], chars[cur]["entries"][ai])
	idx = 0
	_acc = 0.0

## Moves step the sim's way: mf -1 .. frames - 2; a held move parks at mf = hold.at - 1 with charge_t 1..H, then
## carries on from hold.at with charge_t left at H. States and clips step sf over one pass of the descriptor.
## lazy implementation: hand copy of fighter.gd _tick_attack's hold, nothing ties them. will fix when _tick_attack changes.
func _timeline(actor: Node, e: Dictionary) -> Array:
	var out: Array = []
	if e["kind"] == "move":
		var move: Dictionary = e["move"]
		var hold: Dictionary = move.get("hold", {})
		var h := 0 if hold.is_empty() else int(hold_len.get(e["name"], hold["max"]))
		var ch := 0
		for mf in range(-1, int(move["frames"]) - 1):
			if h > 0 and mf == int(hold["at"]):
				for i in h:
					out.append({"sf": 0, "mf": mf - 1, "ch": i + 1})
				ch = h
			out.append({"sf": 0, "mf": mf, "ch": ch})
		return out
	for sf in _span(actor, actor.cfg["anims"][e["anim"]]):
		out.append({"sf": sf, "mf": 0, "ch": 0})
	return out

## Ticks in one pass of a state descriptor: its "frames", else the int "over"s plus each clip window at its speed. A walk, walk back or
## dash with a "stride" is one pass at 1.0x here; in a fight sync() plays it by distance walked.
func _span(actor: Node, d: Dictionary) -> int:
	if d.has("frames"):
		return maxi(1, int(d["frames"]))
	var n := 0.0
	for p in d.get("phases", [d]):
		var over: Variant = p.get("over")
		if over is float or over is int:
			n += float(over)
			continue
		var q: Dictionary = d.merged(p, true)
		var clip := String(q.get("clip", ""))
		var length: float = actor.player.get_animation(clip).length if actor.player.has_animation(clip) else 1.0
		var speed := absf(float(q.get("speed", 1.0)))
		n += (float(q.get("to", length)) - float(q.get("from", 0.0))) * Arena.FPS / speed if speed > 0.0 else Arena.FPS
	return clampi(ceili(n) + 1, 1, 600)

func _apply() -> void:
	var c: Dictionary = chars[cur]
	var f: Fighter = c["fighter"]
	var actor: Node = c["actor"]
	var e: Dictionary = c["entries"][ai]
	var s: Dictionary = timeline[idx]
	actor.blending = blend
	f.facing = face
	f.move_hit = false
	var want: String = e["anim"]
	var airborne: bool = (e["kind"] == "move" and bool(e["move"].get("air", false))) or want in ["jump", "airhit", "block_air", "dash_air", "dash_air_back", "glide"]
	f.position.y = -AIR_LIFT if airborne else 0.0
	if e["kind"] == "move":
		f.state = Fighter.S.ATTACK
		f.move = e["move"]
		f.move_key = e["name"]
		f.mf = s["mf"]
		f.charge_t = s["ch"]
		actor.pose("attack", 0, e["name"], e["move"], s["mf"], s["ch"], face)
		want = "moves/" + e["name"] if actor.cfg["moves"].has(e["name"]) else "move_default"
	else:
		f.state = maxi(0, Fighter.STATE_NAMES.find(want.trim_suffix("_back").trim_suffix("_low").trim_suffix("_air")))
		f.move = {}
		f.mf = 0
		f.charge_t = 0
		f.sf = s["sf"]
		actor.pose(want, s["sf"], "", {}, 0, 0, face)
	if actor.anim_name != want or (e["kind"] == "clip" and actor.current_clip != e["name"]):
		failures += 1
		print("SD_PREVIEW FAIL %s %s sample %d: posed %s %s, want %s" % [c["key"], e["name"], idx, actor.anim_name, actor.current_clip, want])
	marks.queue_redraw()
	if not sheet:
		_readout()

func _phase(move: Dictionary, s: Dictionary) -> String:
	var hold: Dictionary = move.get("hold", {})
	if s["ch"] > 0 and not hold.is_empty() and s["mf"] == int(hold["at"]) - 1:
		return "held"
	if s["mf"] < int(move["startup"]):
		return "startup"
	return "active" if s["mf"] < int(move["startup"]) + int(move["active"]) else "recovery"

func _is_shot(e: Dictionary, s: Dictionary) -> bool:
	return e["kind"] == "move" and int(s["mf"]) in e["move"].get("shots", []) and _phase(e["move"], s) != "held"

## The spawns the sim fires on this sample (fighter.gd _tick_attack): frame spawns within their charge range, and the
## hold_fire volleys every fire_every held ticks.
## lazy implementation: hand copy of _tick_attack's spawn rules, nothing ties them. will fix when _tick_attack changes.
func _firing(e: Dictionary, s: Dictionary) -> Array:
	var out: Array = []
	if e["kind"] != "move":
		return out
	var move: Dictionary = e["move"]
	var fe := int(move.get("hold", {}).get("fire_every", 0))
	var held := _phase(move, s) == "held"
	for sp in move["spawns"]:
		if held:
			if sp.get("hold_fire", false) and fe > 0 and s["ch"] % fe == 1:
				out.append(sp)
		elif int(sp["frame"]) == s["mf"] and not sp.get("hold_fire", false) and s["ch"] >= int(sp.get("min_charge", 0)) and s["ch"] <= int(sp.get("max_charge", 99999)):
			out.append(sp)
	return out

## Same origin as FightScreen.spawn_projectile; rel_owner matches it while the fighter stands on the floor (y 0 here).
## lazy implementation: hand copy of spawn_projectile's origin, which has no callable helper. will fix when spawn_projectile's origin changes.
func _spawn_pos(f: Fighter, sp: Dictionary) -> Vector2:
	var off: Vector2 = sp.get("offset_left", sp["offset"]) if f.facing < 0 else sp["offset"]
	return f.position + Vector2(off.x * float(f.facing), off.y)

func _frame_text(e: Dictionary, s: Dictionary) -> String:
	if e["kind"] != "move":
		return "sf %d" % s["sf"]
	var t := "mf %d %s" % [s["mf"], _phase(e["move"], s)]
	if s["ch"] > 0:
		t += " ch %d" % s["ch"]
	if _is_shot(e, s):
		t += "  SHOT"
	var n := _firing(e, s).size()
	if n > 0:
		t += "  SPAWN x%d" % n
	return t

func _draw_marks(ci: Node2D) -> void:
	if chars.is_empty() or timeline.is_empty():
		return
	var c: Dictionary = chars[cur]
	var f: Fighter = c["fighter"]
	var e: Dictionary = c["entries"][ai]
	var s: Dictionary = timeline[idx]
	var px := 1.0 / stage.scale.x
	var font := UI.font_label()
	var fired := _firing(e, s)
	ci.draw_line(Vector2(CELL.position.x, 0), Vector2(CELL.end.x, 0), Color(UI.INK, 0.3), px)
	if sheet:
		var actor: Node = c["actor"]
		ci.draw_string(font, CELL.position + Vector2(8, 20) * px, "%s  %s" % ["R" if face > 0 else "L", _frame_text(e, s)], HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * px), UI.INK)
		ci.draw_string(font, CELL.position + Vector2(8, 38) * px, "%s %.2fs" % [actor.current_clip, actor.current_time], HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * px), Color(UI.INK, 0.7))
		if _is_shot(e, s) or not fired.is_empty():
			ci.draw_rect(CELL.grow(-2.5 * px), SHOT if _is_shot(e, s) else SPAWN, false, 5 * px)
	if not show_overlay:
		return
	var hb := f.hurtbox()
	ci.draw_rect(hb, HURT, false, 2 * px)
	if e["kind"] == "move" and not f.move["hit"].is_empty():
		var r := f.melee_rect(f.move["hit"]["rect"])
		var live := not f.active_hit().is_empty()
		if live:
			ci.draw_rect(r, Color(HIT, 0.28))
		ci.draw_rect(r, Color(HIT, 1.0 if live else 0.4), false, (3.0 if live else 1.5) * px)
	var foe_spawns := 0
	for sp in fired:
		if sp["at_foe"]:
			foe_spawns += 1
			continue
		var p := _spawn_pos(f, sp)
		var v: Vector2 = sp["vel"]
		ci.draw_line(p, p + Vector2(v.x * float(face), v.y).normalized() * 60.0, SPAWN, 2 * px)
		ci.draw_line(p - Vector2(7, 7) * px, p + Vector2(7, 7) * px, SPAWN, 3 * px)
		ci.draw_line(p - Vector2(7, -7) * px, p + Vector2(7, -7) * px, SPAWN, 3 * px)
	if foe_spawns > 0:
		ci.draw_string(font, Vector2(CELL.position.x + 8 * px, -20 * px), "%d spawn(s) at the foe" % foe_spawns, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * px), SPAWN)
	var m: Vector2 = f.view._muzzle_pos()
	ci.draw_circle(m, 5 * px, MUZZLE)
	if _is_shot(e, s):
		ci.draw_arc(m, 17 * px, 0.0, TAU, 28, SHOT, 3 * px)
		ci.draw_string(font, m + Vector2(-16, -24) * px, "SHOT", HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * px), SHOT)
	ci.draw_line(f.position - Vector2(10, 0) * px, f.position + Vector2(10, 0) * px, UI.INK, 2 * px)
	ci.draw_line(f.position - Vector2(0, 10) * px, f.position + Vector2(0, 10) * px, UI.INK, 2 * px)

func _readout() -> void:
	var c: Dictionary = chars[cur]
	var actor: Node = c["actor"]
	var e: Dictionary = c["entries"][ai]
	var s: Dictionary = timeline[idx]
	var over := ""
	for o in actor.sampled.slice(1):
		over += "   + overlay %s %.3f s" % [o[0], o[1]]
	var lines := ["%s   %s %s   descriptor %s" % [c["key"], e["kind"], e["name"], actor.anim_name],
		"clip %s   %.3f s%s" % [actor.current_clip, actor.current_time, over]]
	if e["kind"] == "move":
		var move: Dictionary = e["move"]
		var hold: Dictionary = move.get("hold", {})
		lines.append("%s   startup %d  active %d  recovery %d  last mf %d   charge %s   shots %s" % [_frame_text(e, s),
			int(move["startup"]), int(move["active"]), int(move["recovery"]), int(move["frames"]) - 2,
			"-" if hold.is_empty() else "%d / %d (at %d, max %d)" % [s["ch"], int(hold_len.get(e["name"], hold["max"])), int(hold["at"]), int(hold["max"])],
			str(move.get("shots", "-"))])
	else:
		lines.append("sf %d / %d" % [s["sf"], timeline.size() - 1])
	lines.append("sample %d / %d   facing %s   speed %sx   %s   blending %s   overlay %s" % [idx + 1, timeline.size(),
		"right" if face > 0 else "left", str(SPEEDS[speed_i]), "playing" if playing else "paused",
		"on" if blend else "off", "on" if show_overlay else "off"])
	info.text = "\n".join(lines)
	var entries: Array = c["entries"]
	var t := "CHARACTERS\n"
	for i in chars.size():
		t += ("> " if i == cur else "    ") + String(chars[i]["key"]) + "\n"
	t += "\nANIMATIONS  %d / %d\n" % [ai + 1, entries.size()]
	var top := clampi(ai - 12, 0, maxi(0, entries.size() - 24))
	for i in range(top, mini(entries.size(), top + 24)):
		t += ("> " if i == ai else "    ") + "%s  %s\n" % [entries[i]["kind"], entries[i]["name"]]
	lists.text = t

func _process(delta: float) -> void:
	if sheet or chars.is_empty() or not playing:
		return
	_acc += delta * Arena.FPS * float(SPEEDS[speed_i])
	if _acc < 1.0:
		return
	idx = (idx + int(_acc)) % timeline.size()
	_acc = fmod(_acc, 1.0)
	_apply()

func on_action(_dev: String, act: String) -> void:
	if sheet or chars.is_empty():
		return
	match act:
		"up", "down":
			_select(cur, ai + (1 if act == "down" else -1))
		"left", "right":
			playing = false
			idx = posmod(idx + (1 if act == "right" else -1), timeline.size())
		"lb", "rb":
			var name: String = chars[cur]["entries"][ai]["name"]
			var next := posmod(cur + (1 if act == "rb" else -1), chars.size())
			_select(next, maxi(0, _anim_index(chars[next], name)))
		"confirm":
			playing = not playing
		"aux":
			face = -face
		"aux2":
			show_overlay = not show_overlay
		"start":
			speed_i = (speed_i + 1) % SPEEDS.size()
		"back":
			get_tree().quit()
			return
	_apply()

## B and C are not in Controls' keyboard maps, so they never also arrive as actions.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if sheet or chars.is_empty() or not k.pressed or k.echo:
		return
	var e: Dictionary = chars[cur]["entries"][ai]
	if k.physical_keycode == KEY_B:
		blend = not blend
	elif k.physical_keycode == KEY_C and e["kind"] == "move" and e["move"].has("hold"):
		var top := int(e["move"]["hold"]["max"])
		var lengths := [top, 0, top / 2]
		hold_len[e["name"]] = lengths[(lengths.find(int(hold_len.get(e["name"], top))) + 1) % lengths.size()]
		timeline = _timeline(chars[cur]["actor"], e)
		idx = mini(idx, timeline.size() - 1)
	else:
		return
	_apply()

func probe() -> Dictionary:
	if chars.is_empty():
		return {"chars": 0}
	var actor: Node = chars[cur]["actor"]
	var e: Dictionary = chars[cur]["entries"][ai]
	return {"key": chars[cur]["key"], "kind": e["kind"], "anim": e["name"], "sample": idx, "frame": timeline[idx],
		"descriptor": actor.anim_name, "clip": actor.current_clip, "time": actor.current_time, "facing": face,
		"playing": playing, "overlay": show_overlay, "blending": blend, "failures": failures}

# ── sheets ───────────────────────────────────────────────────────────────────

func _render_sheets(key: String, anim: String) -> void:
	lists.visible = false
	info.visible = false
	help.visible = false
	stage.position = CELL_AT - CELL.position * CELL_SCALE
	stage.scale = Vector2.ONE * CELL_SCALE
	var out_dir := ProjectSettings.globalize_path("res://export/sd_preview")
	DirAccess.make_dir_recursive_absolute(out_dir)
	# keep Godot's importer out of the rendered PNGs
	FileAccess.open(out_dir.path_join(".gdignore"), FileAccess.WRITE)
	var saved := 0
	for c in chars.size():
		if key != "all" and chars[c]["key"] != key:
			continue
		_select(c, 0)
		_apply()
		for i in 10:
			await get_tree().process_frame
		if not await _lag_check():
			failures += 1
			print("SD_PREVIEW FAIL %s: a capture does not show the pose set before it" % chars[c]["key"])
		for i in chars[c]["entries"].size():
			if anim == "all" or chars[c]["entries"][i]["name"] == anim:
				if await _sheet(c, i, out_dir.path_join(chars[c]["key"])):
					saved += 1
	if saved == 0:
		failures += 1
		print("SD_PREVIEW FAIL nothing matched fighter '%s' anim '%s'" % [key, anim])
	print("SD_PREVIEW %s sheets=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", saved, failures])
	get_tree().quit(0 if failures == 0 else 1)

## Poses A, B, A: the two A captures must match and differ from B, or captures lag the pose by a frame.
func _lag_check() -> bool:
	var shots: Array = []
	var moves: Array = chars[cur]["entries"].filter(func(e): return e["kind"] == "move")
	for pick in [0, chars[cur]["entries"].find(moves[0]) if not moves.is_empty() else 1, 0]:
		_select(cur, pick)
		idx = timeline.size() / 2
		_apply()
		await RenderingServer.frame_post_draw
		shots.append(_grab(Rect2(CELL_AT, CELL.size * CELL_SCALE)).get_data())
	return shots[0] == shots[2] and shots[0] != shots[1]

func _sheet(c: int, i: int, dir: String) -> bool:
	_select(c, i)
	var e: Dictionary = chars[c]["entries"][i]
	var samples: Array = range(timeline.size())
	if e["kind"] != "move" and timeline.size() > SAMPLES:
		samples = range(SAMPLES).map(func(k): return roundi(float(k) * float(timeline.size() - 1) / float(SAMPLES - 1)))
	var cols := mini(COLS, samples.size())
	var bands := ceili(float(samples.size()) / float(cols))
	var size := Vector2i(CELL.size * CELL_SCALE)
	var img := Image.create(cols * size.x, HEADER + bands * 2 * size.y, false, Image.FORMAT_RGBA8)
	img.fill(UI.ICE)
	var text := "%s  %s  (%s)" % [chars[c]["key"], e["name"], e["kind"]]
	if e["kind"] == "move":
		var move: Dictionary = e["move"]
		text += "  %d frames: startup %d, active %d, recovery %d" % [int(move["frames"]), int(move["startup"]), int(move["active"]), int(move["recovery"])]
		if move.has("hold"):
			text += ", held %d at mf %d" % [int(move["hold"]["max"]), int(move["hold"]["at"]) - 1]
		text += "  shots %s  every move frame" % str(move.get("shots", "-"))
	else:
		text += "  %d of %d frames" % [samples.size(), timeline.size()]
	header.text = text + "\nrows: facing right, facing left   orange frame: shot   green frame/x: spawn   red: hit rect (filled when live)   blue: hurtbox   pink dot: muzzle   +: feet"
	header.visible = true
	marks.visible = false
	for fighter in chars:
		fighter["fighter"].visible = false
	await RenderingServer.frame_post_draw
	img.blit_rect(_grab(Rect2(0, 0, 1280, HEADER)), Rect2i(0, 0, mini(1280, img.get_width()), HEADER), Vector2i.ZERO)
	header.visible = false
	marks.visible = true
	chars[c]["fighter"].visible = true
	for row in 2:
		face = 1 if row == 0 else -1
		for k in samples.size():
			idx = samples[k]
			_apply()
			await RenderingServer.frame_post_draw
			img.blit_rect(_grab(Rect2(CELL_AT, Vector2(size))), Rect2i(Vector2i.ZERO, size), Vector2i((k % cols) * size.x, HEADER + ((k / cols) * 2 + row) * size.y))
	face = 1
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(e["name"] + ".png")
	if img.save_png(path) != OK:
		failures += 1
		print("SD_PREVIEW FAIL cannot write ", path)
		return false
	print("SD_PREVIEW sheet %s %dx%d cells=%d" % [path, img.get_width(), img.get_height(), samples.size() * 2])
	return true

## A region of the window in 1280x720 units; the window may render at a higher pixel density.
func _grab(r: Rect2) -> Image:
	var shot := get_viewport().get_texture().get_image()
	var k := float(shot.get_width()) / 1280.0
	var part := shot.get_region(Rect2i(Vector2i((r.position * k).round()), Vector2i((r.size * k).round())))
	if part.get_width() != int(r.size.x):
		part.resize(int(r.size.x), int(r.size.y), Image.INTERPOLATE_LANCZOS)
	part.convert(Image.FORMAT_RGBA8)
	return part
