extends SceneTree
## Weapon-class throw styles, read as data. No match is played: a student with no kit of their own gets their throw from
## Movesets.throw_for and is never simulated, so this audits what throw_for builds (style by weapon, the student's tuning, the
## carry path rules) and that the puppet wind-up and strike differs per style. Hina's and Hoshino's own throws only get the
## generic audit (a valid carry or an explicit snap).
## Run with TEST=res://scripts/models/tests/throw_styles_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const STYLE_OF := {"MG": "SLAM", "RG": "SLAM", "GL": "SLAM", "SG": "HURL", "AR": "TOSS", "SMG": "SWEEP", "HG": "SWEEP", "SR": "SHOVE"}
const SHIFT := {"HeavyArmor": 1, "LightArmor": -1}
const EXTRA := {"Tanker": 4, "Supporter": -2, "Healer": -2}
## Per style: frames [startup, active, recovery], raw damage, launch, release hitstop, shake, grab stop, spin, path [mf, x, y, roll].
const BASE := {
	"SLAM": {"frames": [7, 3, 28], "dmg": 70.0, "launch": Vector2(6, 5), "hitstop": 10, "shake": 7.0, "grab_stop": 4, "spin": 12.0,
		"path": [[10, 65, 0, 0], [13, 55, -26, 0], [16, 42, -48, 0], [21, 45, -53, -8], [22, 56, -34, -8]]},
	"HURL": {"frames": [8, 3, 30], "dmg": 80.0, "launch": Vector2(9.5, -4.5), "hitstop": 6, "shake": 6.0, "grab_stop": 4, "spin": 15.0,
		"path": [[10, 79, -6, 0], [11, 76, -25, 0], [12, 67, -42, 0], [13, 68, -38, 0], [14, 76, -32, -8], [15, 63, -14, 22], [16, 49, -4, 52]]},
	"TOSS": {"frames": [7, 3, 28], "dmg": 72.0, "launch": Vector2(7, -6.5), "hitstop": 8, "shake": 5.0, "grab_stop": 4, "spin": 10.0,
		"path": [[9, 62, 0, 0], [12, 50, -36, 0], [15, 40, -60, -10], [18, 52, -30, 25]]},
	"SWEEP": {"frames": [6, 3, 24], "dmg": 62.0, "launch": Vector2(4.5, -2.5), "hitstop": 6, "shake": 3.0, "grab_stop": 2, "spin": 25.0,
		"path": [[8, 55, 0, 0], [10, 50, -12, 20], [12, 45, -8, 60]]},
	"SHOVE": {"frames": [6, 3, 28], "dmg": 56.0, "launch": Vector2(11, -3), "hitstop": 8, "shake": 4.0, "path": []},
}

var checks := 0
var failures: Array = []
var M: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("THROW_STYLES FAIL ", label)
		failures.append(label)

## The rules of the carry format and of a throw without one. Returns what is wrong, empty when the throw is valid.
func _audit(m: Dictionary) -> Array:
	var bad := []
	var h: Dictionary = m.get("hit", {})
	if not bool(h.get("throw", false)):
		bad.append("hit.throw")
	var c: Dictionary = m.get("carry", {})
	if c.is_empty():
		if float(h.get("snap", 0.0)) <= 0.0:
			bad.append("no carry and no snap")
		return bad
	var path: Array = c.get("path", [])
	if path.size() < 2:
		return bad + ["path needs two keys"]
	if String(c.get("anim", "")) == "" or float(c.get("pivot", 0.0)) <= 0.0 or not c.has("spin") or not c.has("front"):
		bad.append("anim, pivot, spin or front missing")
	if int(c.get("grab_stop", -1)) < 0:
		bad.append("grab_stop below 0")
	for i in path.size():
		var k: Array = path[i]
		if k.size() != 4:
			bad.append("key %d is not [mf, x, y, roll]" % i)
			continue
		if i > 0 and int(k[0]) <= int(path[i - 1][0]):
			bad.append("key %d not after key %d" % [i, i - 1])
		if float(k[2]) > 0.0:
			bad.append("key %d has y above 0 (%s)" % [i, k[2]])
		if absf(float(k[1])) > 160.0:
			bad.append("key %d has |x| over 160 (%s)" % [i, k[1]])
	if int(path[0][0]) <= int(m.get("startup", 0)):
		bad.append("first key not above startup")
	var release := int(c.get("release", 0))
	if release <= int(path[0][0]):
		bad.append("release not above the first key")
	if release >= int(m.get("frames", 0)) - 1:
		bad.append("release not below frames - 1")
	return bad

func _height(e: Dictionary) -> float:
	var h := String(e.get("height", "")).trim_suffix("cm")
	return float(h) if h != "" else 160.0

func _scale(e: Dictionary) -> float:
	return clampf(0.9 + 0.2 * (_height(e) - 142.0) / 37.0, 0.9, 1.1)

## Everything about a style throw that follows from the table and the student, written out here and not read back from Movesets.
func _shape(who: String, e: Dictionary, st: Dictionary, m: Dictionary) -> void:
	var style := String(STYLE_OF.get(String(e["weapon"]), "TOSS"))
	var b: Dictionary = BASE[style]
	var fr: Array = b["frames"]
	var shift := int(SHIFT.get(String(e["armor"]), 0))
	var extra := int(EXTRA.get(String(e["role"]), 0))
	var k := _scale(e)
	var h: Dictionary = m.get("hit", {})
	check(m.get("style", "") == style, "%s: style %s for weapon %s (got %s)" % [who, style, e["weapon"], m.get("style", "")])
	check(int(m.get("startup", -1)) == int(fr[0]) + shift and int(m.get("active", -1)) == int(fr[1]) and int(m.get("recovery", -1)) == int(fr[2]),
		"%s: frames %s with startup %+d (got %s/%s/%s)" % [who, fr, shift, m.get("startup"), m.get("active"), m.get("recovery")])
	check(int(m.get("frames", -1)) == int(fr[0]) + shift + int(fr[1]) + int(fr[2]), who + ": frames is the sum")
	check(is_equal_approx(float(h.get("dmg", 0.0)), float(b["dmg"]) * float(st["dmg"])), "%s: raw damage %s x the kit's dmg" % [who, b["dmg"]])
	var want := Rect2(0, -200, 105.0 * float(st["reach"]), 170)
	check(h.get("rect", Rect2()).is_equal_approx(want), "%s: rect %s (got %s)" % [who, want, h.get("rect")])
	check(h.get("launch", Vector2.ZERO) == b["launch"] and int(h.get("hitstop", -1)) == int(b["hitstop"]) and is_equal_approx(float(h.get("shake", -1)), float(b["shake"])),
		who + ": launch, hitstop and shake follow the style")
	check(bool(h.get("kd", false)) and is_equal_approx(float(h.get("snap", 0.0)), 80.0) and is_equal_approx(float(h.get("meter", 0.0)), 8.0) and String(h.get("sfx", "")) == "slam",
		who + ": a knockdown throw, snap 80, meter 8, slam")
	check(not m.get("swish", true) and (m.get("cancel", [1]) as Array).is_empty() and not m.get("cutin", true) and is_equal_approx(float(m.get("cost", 1.0)), 0.0),
		who + ": no swing arc, cancel or cost")
	check(is_equal_approx(float(m.get("scale", 0.0)), k), "%s: path scale %.4f from %s cm" % [who, k, _height(e)])
	var c: Dictionary = m.get("carry", {})
	var base: Array = b["path"]
	if base.is_empty():
		check(c.is_empty(), who + ": SHOVE has no carry")
		return
	var path: Array = c.get("path", [])
	check(path.size() == base.size(), who + ": the path keeps its keys")
	if path.size() != base.size():
		return
	var first := int(base[0][0])
	var ticks := int(base[-1][0]) - first
	var ok := true
	for i in base.size():
		ok = ok and is_equal_approx(float(path[i][1]), float(base[i][1]) * k) and is_equal_approx(float(path[i][2]), float(base[i][2]) * k) and is_equal_approx(float(path[i][3]), float(base[i][3]))
	check(ok, who + ": every key is the style's, x and y scaled by the height, the roll left alone")
	check(int(path[0][0]) == first + shift, "%s: the path starts with the startup (%d, want %d)" % [who, int(path[0][0]), first + shift])
	var carry := int(path[-1][0]) - int(path[0][0])
	var floor_ticks := base.size() - 1
	check(carry == ticks + extra or (ticks + extra < floor_ticks and carry >= ticks + extra), "%s: carry ticks %d + %d (got %d)" % [who, ticks, extra, carry])
	check(int(c.get("release", -1)) == int(path[-1][0]), who + ": the release is the last key")
	check(c.get("anim", "") == "carried" and is_equal_approx(float(c.get("pivot", 0.0)), 76.0) and bool(c.get("front", false)), who + ": anim carried, pivot 76, front")
	check(int(c.get("grab_stop", -1)) == int(b["grab_stop"]) and is_equal_approx(float(c.get("spin", 0.0)), float(b["spin"])), who + ": grab stop and spin follow the style")

## What the throw looks like to a player, read from the move alone, so a tuning that stops reaching it shows up as a collision.
func _tuple(m: Dictionary) -> String:
	var c: Dictionary = m.get("carry", {})
	var ticks := 0 if c.is_empty() else int(c.get("release", 0)) - int(c["path"][0][0])
	var h: Dictionary = m.get("hit", {})
	return "%s %d %d %.5f %.5f %.6f" % [m.get("style", ""), int(m.get("startup", 0)), ticks, float(h.get("dmg", 0.0)), float(h.get("rect", Rect2()).size.x), float(m.get("scale", 0.0))]

func _roster(game: Node) -> void:
	var kits = load("res://scripts/fight/kits.gd")
	var seen := {}
	var combos := {}
	var styled := 0
	var own := 0
	for e in game.fighters:
		var who := String(e["key"])
		var kit = kits.make(e)
		var st: Dictionary = kit.build_stats()
		var moves: Dictionary = kit.build_moves(st)
		var has_own: bool = moves.has("throw")
		var m: Dictionary = moves["throw"] if has_own else M.throw_for(e, st)
		var bad := _audit(m)
		check(bad.is_empty(), "%s: the throw %s" % [who, ", ".join(bad)])
		if has_own:
			own += 1
			continue
		styled += 1
		_shape(who, e, st, m)
		var t := _tuple(m)
		check(not seen.has(t), "%s: the throw is its own (same as %s: %s)" % [who, seen.get(t, ""), t])
		seen[t] = who
		combos[" ".join(t.split(" ").slice(0, 3))] = true
	check(styled + own == game.fighters.size(), "every roster entry is audited (%d styled, %d with their own throw)" % [styled, own])
	print("THROW_STYLES roster=%d styled=%d own=%d distinct_tuples=%d style_startup_ticks=%d" % [game.fighters.size(), styled, own, seen.size(), combos.size()])

## Every weapon, role, armor and height a throw can be built for, so a combination no roster entry has still passes the rules.
func _grid() -> void:
	var weapons: Array = STYLE_OF.keys() + ["RL", "MT", "FT"]
	var n := 0
	for w in weapons:
		for role in ["DamageDealer", "Tanker", "Supporter", "Healer"]:
			for armor in ["HeavyArmor", "LightArmor", "Unarmed", "ElasticArmor"]:
				for height in ["142cm", "179cm", ""]:
					var e := {"key": "", "weapon": w, "role": role, "armor": armor, "bullet": "Pierce"}
					if height != "":
						e["height"] = height
					var st: Dictionary = M.stats_for(e)
					var m: Dictionary = M.throw_for(e, st)
					var bad := _audit(m)
					check(bad.is_empty(), "grid %s %s %s %s: %s" % [w, role, armor, height, ", ".join(bad)])
					check(m.get("style", "") == STYLE_OF.get(w, "TOSS"), "grid %s: style (got %s)" % [w, m.get("style", "")])
					n += 1
	check(n == weapons.size() * 48, "the grid built %d throws" % n)

## The puppet's wind-up and strike: five styles, each its own, and a throw with no style keeps the old pair.
func _puppets(game: Node) -> void:
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	await game.go("fight", {}, "cut")
	var screen: Node = game.stack.back()
	screen.set_physics_process(false)
	var f: Node = screen.f1
	var own: Dictionary = f.move
	var seen := {}
	for w in ["MG", "SG", "AR", "SMG", "SR"]:
		var e := {"key": "", "weapon": w, "role": "DamageDealer", "armor": "Unarmed", "bullet": "Pierce"}
		var m: Dictionary = M.throw_for(e, M.stats_for(e))
		f.move = m
		var defs: Array = f.view._defs("throw", m["pose"], false)
		check(defs.size() == 3 and not (defs[1] as Dictionary).is_empty(), "%s (%s): the puppet has a strike" % [w, m.get("style", "")])
		check(not seen.has(var_to_str(defs)), "%s (%s): the puppet pose is its own" % [w, m.get("style", "")])
		seen[var_to_str(defs)] = w
		var plain: Dictionary = m.duplicate()
		plain.erase("style")
		f.move = plain
		check(var_to_str(f.view._defs("throw", m["pose"], false)) != var_to_str(defs), "%s (%s): the style changes the puppet pose" % [w, m.get("style", "")])
	f.move = {"pose": {"lunge": 12.0, "lean": 0.12}}
	var old: Array = f.view._defs("throw", f.move["pose"], false)
	check(not seen.has(var_to_str(old)) and not (old[1] as Dictionary).is_empty(), "a throw with no style keeps its own puppet pair")
	f.move = own

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("THROW_STYLES FAIL watchdog timeout")
		quit(3))
	await process_frame
	M = load("res://scripts/fight/movesets.gd")
	var game: Node = root.get_node("Game")
	var table: Dictionary = M.get_script_constant_map()
	check(table.has("THROW_STYLES") and table.has("THROW_STYLE_OF"), "Movesets has THROW_STYLES and THROW_STYLE_OF")
	_roster(game)
	_grid()
	await _puppets(game)
	print("THROW_STYLES_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
