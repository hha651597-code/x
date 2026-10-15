extends SceneTree
## The real way into a match: the VS screen hands off to the fight on its own, and FIGHT! is called once, by the fight (the VS
## screen stamps no READY? or FIGHT!). Counts the 'fight' sound from the VS screen to control in real time.
## Run with TEST=res://scripts/models/tests/vs_flow_test.gd tools/sd_test.sh (a real small window).

var checks := 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("VS_FLOW_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("VS_FLOW_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	var game: Node = root.get_node("Game")
	var sfx: Node = root.get_node("Sfx")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	game.session.begin("versus2p")
	game.session.players[0]["fighter"] = 10004
	game.session.players[1]["fighter"] = 10005
	game.session.players[0]["special"] = 10017
	game.session.players[1]["special"] = 10017
	var fights0 := int(sfx.played.get("fight", 0))
	await game.go("vs", {}, "cut")
	var vs: Node = game.stack.back()
	check(vs.get_script().resource_path.ends_with("vs_screen.gd"), "setup: the VS screen is up")
	var fight: Node = null
	for i in 100:
		await create_timer(0.1).timeout
		var top: Node = game.stack.back()
		if top != vs and top.get("phase") != null:
			fight = top
			break
	check(fight != null, "the VS screen hands off to the fight on its own")
	if fight != null:
		check(int(sfx.played.get("fight", 0)) == fights0, "the VS screen made no FIGHT! sound (%d)" % (int(sfx.played.get("fight", 0)) - fights0))
		check(fight.get("entry") == true and fight.get("intro_len") == 360, "the match opens with the 360 tick entry")
		for i in 160:
			await create_timer(0.1).timeout
			if fight.get("phase") == "fight":
				break
		check(fight.get("phase") == "fight", "the entry ends in control within 16 s")
		check(int(sfx.played.get("fight", 0)) == fights0 + 1, "FIGHT! sounded once from the VS screen to control (%d)" % (int(sfx.played.get("fight", 0)) - fights0))
	print("VS_FLOW_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
