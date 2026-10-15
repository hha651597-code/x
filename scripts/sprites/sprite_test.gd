class_name SpriteTest
extends Node2D
## In-game sprite test bench (for sprite authors). Opened through the rig test screen:
##   Game.go("rigtest", {"sprite": "hoshino", "mode": "anims"})
## modes:
##   "frames" — every baked frame at fight scale, with its origin (red cross = the fighter's feet), floor line, halo anchor
##   "anims"  — every animation of anims.json playing live (name + current frame under each)
##   "moves"  — every move of the character's kit played on its real frame data (startup / active / recovery), looping
##   "anim"   — one animation big: {"anim": "walk"} (or a move: {"move": "5H"}), optional {"zoom": 1.6, "flip": true}
## Optional {"t": 37} freezes every clock at tick 37 (deterministic screenshots); {"page": n} pages long grids.
## On open it prints the validator report (SpriteSet.validate) as "SPRITECHECK ..." lines: load problems, unknown frame
## names, state slots / kit moves with no authored animation (and what they fall back to), unused frames.

const FLOOR_COL := Color(0.18, 0.32, 0.55, 0.55)

var sset: SpriteSet
var mode := "anims"
var cells: Array = []          # {actor, kind, name, pos, label}
var kit_moves := {}
var _t := 0.0
var _fixed := -1.0
var _zoom := 1.0
var _font: Font

func setup(p: Dictionary) -> void:
	_font = ThemeDB.fallback_font
	var key := String(p.get("sprite", "hoshino"))
	SpriteSets.clear_cache()
	sset = SpriteSets.get_set(key)
	mode = String(p.get("mode", "anims"))
	_fixed = float(p.get("t", -1.0))
	_zoom = float(p.get("zoom", 1.0))
	kit_moves = _kit_moves(key)
	if bool(p.get("report", true)):
		_report(key)
	if sset == null or sset.frames.is_empty():
		return
	match mode:
		"frames": _layout(sset.frames.keys(), "frame", int(p.get("page", 0)), 0.5)
		"moves": _layout(kit_moves.keys(), "move", int(p.get("page", 0)), 0.55)
		"anim":
			if p.has("move"):
				_add_cell("move", String(p["move"]), Vector2(640, 600), _zoom, bool(p.get("flip", false)))
			else:
				_add_cell("anim", String(p.get("anim", "idle")), Vector2(640, 600), _zoom, bool(p.get("flip", false)))
		_:
			var names: Array = []
			for a in sset.anims:
				names.append(a)
			_layout(names, "anim", int(p.get("page", 0)), 0.55)

func _kit_moves(key: String) -> Dictionary:
	for id in SpriteSets.REGISTRY:
		if String(SpriteSets.REGISTRY[id]) == key and Game.by_id.has(int(id)):
			var k := Kits.make(Game.by_id[int(id)])
			return k.build_moves(k.build_stats())
	return {}

func _report(key: String) -> void:
	if sset == null:
		print("SPRITECHECK %s: no sprite set" % key)
		return
	var lines := sset.validate(kit_moves)
	var errs := 0
	for l in lines:
		if String(l).begins_with("ERROR"):
			errs += 1
		print("SPRITECHECK %s %s" % [key, l])
	print("SPRITECHECK %s: %d frames, %d anims, %d moves authored, world scale %.3f, pixel=%s (art px %.2f world px), %d errors, enabled=%s, fight uses sprites=%s" % [
		key, sset.frames.size(), sset.anims.size(), sset.moves.size(), sset.world_scale, sset.pixel, sset.art_px, errs, sset.enabled,
		SpriteSets.files_exist(key) and sset.enabled])

func _layout(names: Array, kind: String, page: int, z: float) -> void:
	var cols := 6
	var rows := 2
	var per := cols * rows
	var start := page * per
	for i in range(start, mini(names.size(), start + per)):
		var k := i - start
		var c := k % cols
		var r := k / cols
		var pos := Vector2(110.0 + float(c) * 212.0, 330.0 + float(r) * 330.0)
		_add_cell(kind, String(names[i]), pos, z * _zoom, false)

func _add_cell(kind: String, nm: String, pos: Vector2, z: float, flip: bool) -> void:
	if sset.pixel:
		z = maxf(0.5, snappedf(z, 0.5))      # pixel art: an art pixel = a whole number of screen px (2 world px x 0.5 steps)
	var holder := Node2D.new()
	holder.position = pos
	holder.scale = Vector2(-z if flip else z, z)
	add_child(holder)
	var a := SpriteActor.new()
	a.setup(sset, Color(1, 1, 1, 0.95), float(cells.size()))
	holder.add_child(a)
	cells.append({"actor": a, "kind": kind, "name": nm, "pos": pos, "z": z, "frame": ""})

func _process(delta: float) -> void:
	_t += delta
	var ticks := _fixed if _fixed >= 0.0 else _t * 60.0
	for c in cells:
		var a: SpriteActor = c["actor"]
		var fr := ""
		var o := {}
		var extra := ""
		match String(c["kind"]):
			"frame":
				fr = String(c["name"])
			"anim":
				var an: Dictionary = sset.anims.get(String(c["name"]), {})
				if not an.is_empty():
					var r := sset.anim_at(an, ticks)
					fr = String(r[0][0])
					o = SpriteSet.merge(an.get("opts", {}), r[0][2])
			"move":
				var m: Dictionary = kit_moves.get(String(c["name"]), {})
				if m.is_empty():
					m = {"startup": 6, "active": 3, "recovery": 12, "frames": 21}
				var total := int(m.get("frames", 20)) + 20
				var mf := int(ticks) % total
				if mf >= int(m.get("frames", 20)):
					fr = ""
					extra = "(rest)"
				else:
					var ms := sset.move_spec(String(c["name"]), m)
					var pose := sset.move_pose(ms["spec"], m, mf)
					fr = String(pose["frame"])
					o = pose["opts"]
					extra = "%s %d%s" % [pose["phase"], mf, "" if bool(ms["authored"]) else " (fallback " + String(ms["via"]) + ")"]
		if fr == "" and String(c["kind"]) == "move":
			var idle := sset.resolve_slot("idle")
			var ia: Dictionary = sset.anims.get(String(idle["anim"]), {})
			if not ia.is_empty():
				fr = String(ia["frames"][0][0])
		if fr != "":
			a.show_frame(fr, o)
			a.update_fx(delta, 0.0, 1.0)
		c["frame"] = fr + ("  " + extra if extra != "" else "")
	queue_redraw()

func _draw() -> void:
	if sset == null:
		draw_string(_font, Vector2(40, 60), "no sprite set", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.RED)
		return
	draw_string(_font, Vector2(20, 26), "SPRITE TEST  %s  mode=%s  scale=%.3f%s  frames=%d anims=%d" % [sset.key, mode, sset.world_scale,
		"  PIXEL" if sset.pixel else "", sset.frames.size(), sset.anims.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.1, 0.15, 0.3))
	for c in cells:
		var p: Vector2 = c["pos"]
		var z := float(c["z"])
		draw_line(p + Vector2(-100, 0), p + Vector2(100, 0), FLOOR_COL, 2.0)
		draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), Color.RED, 2.0)
		draw_line(p + Vector2(0, -8), p + Vector2(0, 8), Color.RED, 2.0)
		# height guide: Arena.SPRITE_H above the floor (portrait fighters are this tall)
		draw_line(p + Vector2(-30, -Arena.SPRITE_H * z), p + Vector2(30, -Arena.SPRITE_H * z), Color(1, 1, 1, 0.5), 1.0)
		var a: SpriteActor = c["actor"]
		if String(c["kind"]) == "frame" and not a.rec.is_empty():
			var hp: Vector2 = p + a.head_local() * z
			draw_circle(hp, 3.0, Color(1.0, 0.9, 0.1))
		draw_string(_font, p + Vector2(-100, 18), String(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, 200, 14, Color(0.05, 0.1, 0.25))
		draw_string(_font, p + Vector2(-100, 34), String(c["frame"]), HORIZONTAL_ALIGNMENT_LEFT, 200, 12, Color(0.2, 0.25, 0.4))
