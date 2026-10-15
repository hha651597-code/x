extends SceneTree
## Weapon aim rules: every kit's air and crouch moves, built as data. No match is played, so this also covers the kits
## that have no SD model (data only).
## Machine guns, snipers and railguns fire level mid-jump and from a crouch; handguns, SMGs, assault rifles, shotguns and
## launchers may fire down.
## Run with TEST=res://scripts/models/tests/aim_rules_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const DOWN_OK := ["HG", "SMG", "AR", "SG", "GL", "RL", "MT"]
const BELOW_MUZZLE := 25.0   # an air move's melee zone may sit at most this far below the muzzle line (centre)
const MUZZLE_Y := -150.0   # non-SD kits have no measured muzzle; their guns sit about here

var checks := 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("AIM_RULE FAIL ", label)
		failures.append(label)

## Grenade launchers fired down: half bounce once and explode, half are duds. Hoshino stands in with her weapon set to GL.
func _launchers(game: Node) -> void:
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("training")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	await game.go("fight", {}, "cut")
	var screen: Node = game.stack.back()
	screen.set_physics_process(false)
	var movesets = load("res://scripts/fight/movesets.gd")
	var f: Node = screen.f2
	var weapon: String = f.data["weapon"]
	var nade := func(vel: Vector2) -> Dictionary:
		return movesets._spawn(0, Vector2(60, -150), vel, movesets.H(Rect2(), 10, 10, 8, 2.0), {"gravity": 0.5, "kind": "grenade",
			"size": Vector2(26, 26), "color": Color.WHITE, "life": 120, "explode": {"radius": 92.0, "hit": movesets.H(Rect2(), 20, 10, 8, 2.0)}})
	var count := func(w: String, vel: Vector2) -> Array:
		f.data["weapon"] = w
		var duds := 0
		var bounces := 0
		for i in 200:
			screen.spawn_projectile(f, nade.call(vel))
			var p = screen.projectiles.back()
			duds += int(p.hit.is_empty() and p.explode.is_empty())
			bounces += p.bounces
		return [duds, bounces]
	var down: Array = count.call("GL", Vector2(7.5, 2.0))
	check(down[0] > 70 and down[0] < 130 and down[0] + down[1] == 200, "a grenade launcher fired down duds about half the time and otherwise bounces (%d duds, %d bounces)" % [down[0], down[1]])
	var up: Array = count.call("GL", Vector2(9.0, -12.5))
	check(up[0] == 0 and up[1] == 0, "a lobbed grenade is never a dud")
	var other: Array = count.call("SG", Vector2(7.5, 2.0))
	check(other[0] == 0 and other[1] == 0, "only grenade launchers have the coin flip")
	f.data["weapon"] = "GL"
	screen.spawn_projectile(f, nade.call(Vector2(7.5, 2.0)))
	var p = screen.projectiles.back()
	p.hit = {"dmg": 1.0}
	p.explode = {"radius": 92.0, "hit": {}}
	p.bounces = 1
	p.gravity = 0.0
	p.age = 5
	p.position = Vector2(0.0, Arena_ground() - 5.0)
	p.vel = Vector2(0.0, 6.0)
	p.tick()
	check(not p.dead and p.vel.y < 0.0 and p.bounces == 0, "a bouncing grenade bounces off the floor instead of exploding on it")
	f.data["weapon"] = weapon
	for q in screen.projectiles:
		q.queue_free()
	screen.projectiles.clear()

func Arena_ground() -> float:
	return load("res://scripts/fight/arena.gd").GROUND

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("AIM_RULES FAIL watchdog timeout")
		quit(3))
	await process_frame
	var game: Node = root.get_node("Game")
	var kits = load("res://scripts/fight/kits.gd")
	var audited := 0
	var level_deg: float = load("res://scripts/fight/arena.gd").LEVEL_DEG
	for e in game.fighters:
		var weapon := String(e["weapon"])
		var kit = kits.make(e)
		var moves: Dictionary = kit.build_moves(kit.build_stats())
		if weapon in DOWN_OK:
			continue
		audited += 1
		for key in moves:
			var m: Dictionary = moves[key]
			var air: bool = bool(m.get("air", false))
			var crouch: bool = bool(m.get("crouch", false))
			if not (air or crouch):
				continue
			for i in m["spawns"].size():
				var v: Vector2 = m["spawns"][i]["vel"]
				if v.x == 0.0 and v.y == 0.0:
					continue
				var down := rad_to_deg(atan2(v.y, absf(v.x)))
				check(down <= level_deg, "%s (%s) %s spawn %d fires %.0f degrees down" % [e["key"], weapon, key, i, down])
			if air and not m["hit"].is_empty() and not m.get("shots", []).is_empty():
				var mz: Vector2 = kit._muzzle(key, int(m["startup"])) if kit.has_method("_muzzle") else Vector2(0.0, MUZZLE_Y)
				var r: Rect2 = m["hit"]["rect"]
				check(r.get_center().y - mz.y <= BELOW_MUZZLE, "%s (%s) %s melee zone sits %.0f below the muzzle" % [e["key"], weapon, key, r.get_center().y - mz.y])
	check(audited > 0, "the roster has kits to audit")
	await _launchers(game)
	print("AIM_RULES ", "PASS" if failures.is_empty() else "FAIL", " kits=", audited, " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
