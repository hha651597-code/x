extends SceneTree
## Sound hook-ups: which clip, which channel, how many and when Hina and Hoshino sound in a fight, and that the sprite
## fighters play the mapped Blue Archive sounds of assets/audio/ba/ui_map.json. Fighters are driven directly, the cut-in through the fight screen's sim step.
## Routing and timing only: it cannot say how anything sounds.
## Run with TEST=res://scripts/models/tests/sound_hooks_test.gd tools/sd_test.sh (a real small window).
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

var checks := 0
var failures: Array = []
var game: Node
var sfx: Node
var screen: Node
var states: Dictionary
var FI: GDScript
var M: GDScript
var a: Node       # P1
var b: Node       # P2
var base := {}    # Sfx.played at the last _fresh()
var crossed := 0  # clips played for the wrong gun
var scanned := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("HOOKS_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("HOOKS_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	FI = load("res://scripts/fight/fight_input.gd")
	M = load("res://scripts/fight/movesets.gd")
	game = root.get_node("Game")
	sfx = root.get_node("Sfx")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	await _match(10004, 10005)
	_hina_normals()
	_hina_streams()
	_assist_volley()
	_hina_ex()
	_hina_supers()
	_hoshino_normals()
	_hoshino_buckshot()
	_hoshino_ex()
	_hoshino_heal()
	_hits()
	_voices()
	_stop_on_hit()
	_swing()
	await _cutin()
	_round_start()
	_cross_check()
	_clocks()
	_pins()
	_long_clips()
	_stop_all_rules()
	_quit_paths()
	_no_set(true)
	_sprites()
	_sprite_hits_hina()
	_no_set(false)
	print("HOOKS_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# helpers
func _match(p1: int, p2: int) -> void:
	game.session.begin("training")
	game.session.players[0]["fighter"] = p1
	game.session.players[1]["fighter"] = p2
	await game.go("fight", {}, "cut")
	screen = game.stack.back()
	screen.set_physics_process(false)
	screen.phase = "fight"
	states = screen.f1.get_script().S
	a = screen.f1
	b = screen.f2

## Idle fighters, empty logs, no leftover state in Sfx or the screen. Frames keep counting, as they do in a match.
func _fresh() -> void:
	for c in sfx.clips_played:
		scanned += 1
		var clip := String(c["clip"])
		if (c["who"] == "hina" and "_SG_" in clip) or (c["who"] == "hoshino" and "_HMG_" in clip):
			crossed += 1
	sfx.stop_all()
	sfx.clips_played.clear()
	sfx.voice_log.clear()
	sfx.rng.seed = 7
	base = sfx.played.duplicate()
	screen._clear_freeze()
	screen._events.clear()
	for p in screen.projectiles:
		if is_instance_valid(p):
			p.queue_free()
	screen.projectiles.clear()
	screen.phase = "fight"
	screen.slowmo = 0
	screen.wins = [0, 0]
	for f in screen.fighters:
		f.reset_round(f.position.x, f.facing)
		f._set_state(states.IDLE)
		f.input = FI.new()
		f.hitstop = 0
		f.meter = 0.0

func _clips(event: String, who := "") -> Array:
	return sfx.clips_played.filter(func(c: Dictionary) -> bool: return c["event"] == event and (who == "" or c["who"] == who))

func _lines(event: String, slot := 0) -> Array:
	return sfx.voice_log.filter(func(v: Dictionary) -> bool: return v["event"] == event and (slot == 0 or v["slot"] == slot))

## Calls of an event since the last _fresh().
func _played(name: String) -> int:
	return int(sfx.played.get(name, 0)) - int(base.get(name, 0))

func _run_move(f: Node, key: String, max_ticks := 300) -> void:
	f._start_move(key)
	for i in max_ticks:
		f.tick()
		if f.state != states.ATTACK:
			return

func _tick(f: Node, n: int) -> void:
	for i in n:
		f.tick()

## Buckshot or Sustained Burst: the skill button stays down for `hold_ticks` ticks, then the move runs out.
func _hold_skill(f: Node, hold_ticks: int) -> void:
	f._start_move("skill")
	for i in 400:
		f.input = FI.from_held(f.input, 0, 0, ["skill"] if i < hold_ticks else [])
		f.tick()
		if f.state != states.ATTACK:
			return

func _player(slot: int, chan: String) -> AudioStreamPlayer:
	var ch: Dictionary = sfx._chan["%d.%s" % [slot, chan]]
	return ch["p"][ch["i"]]

func _hit(att: Node, def: Node, opts := {}) -> String:
	var h: Dictionary = M.H(Rect2(), 20.0, 12, 10, 4.0, opts.merged({"hitstop": 0}))
	return String(def.receive_hit(att, h, att.position, false))

# Hina: gun normals, streams, EX, supers
func _hina_normals() -> void:
	_fresh()
	var swings := _played("swing")
	_run_move(a, "5H")
	var shots := _clips("shot", "hina")
	check(shots.size() == 1, "hina 5H: one burst clip, not seven (%d)" % shots.size())
	check(shots.size() == 1 and String(shots[0]["clip"]).begins_with("sfx/SFX_Common_HMG_0") and shots[0]["channel"] == "move" and shots[0]["slot"] == 1, "hina 5H: an HMG burst on her move channel")
	check(_played("shot") == 1, "hina 5H: the sfx[] entry calls the shot event once (%d)" % _played("shot"))
	check(_played("swing") == swings, "hina 5H: a gun normal has no swing")
	var spool := _clips("spool", "hina")
	check(spool.size() == 1 and shots.size() == 1 and spool[0]["tick"] < shots[0]["tick"], "hina 5H: the spool comes before the first burst")
	check(_clips("reload", "hina").is_empty() and _clips("hit_l").is_empty(), "hina 5H: no reload, no impact")
	_fresh()
	a._start_move("5L")
	_tick(a, 9)
	a._start_move("5L")
	_tick(a, 20)
	check(_played("shot") == 2 and _clips("shot", "hina").size() == 1, "hina: two 5L inside 36 ticks fire one burst (%d calls, %d clips)" % [_played("shot"), _clips("shot", "hina").size()])
	check(_clips("spool", "hina").size() == 1, "hina: a chained burst has no second spool")
	_tick(a, 60)
	_run_move(a, "5L")
	check(_clips("shot", "hina").size() == 2, "hina: a burst 36 ticks or more later plays")
	check(_clips("spool", "hina").size() == 2, "hina: the spool comes back after 45 idle ticks")
	_fresh()
	_run_move(a, "close_L")
	_run_move(a, "6H")
	check(_played("shot") == 0 and _clips("spool", "hina").is_empty(), "hina: close strikes fire no gun sound")

func _hina_streams() -> void:
	_fresh()
	_hold_skill(a, 60)
	var shots := _clips("shot", "hina")
	check(_played("shot") > 5 and shots.size() >= 1 and shots.size() < _played("shot"), "hina skill hold: the stream reaches the shot event and the gap drops the extras (%d calls, %d clips)" % [_played("shot"), shots.size()])
	var spaced := true
	for i in range(1, shots.size()):
		spaced = spaced and int(shots[i]["tick"]) - int(shots[i - 1]["tick"]) >= 36
	check(spaced, "hina skill hold: bursts are 36 ticks or more apart")
	_fresh()
	_run_move(a, "skill")
	check(_clips("shot", "hina").size() == 1, "hina skill tap: three rounds, one burst clip")

func _assist_volley() -> void:
	_fresh()
	a.assist = M.assist_for({})
	a.assist_cd = 0
	screen.call_assist(a)
	for i in 40:
		screen._run_events()
	check(not screen.projectiles.is_empty() and _clips("shot").is_empty() and _played("shot") == 1, "assist volley: the assist's rounds sound synthesised, not as hina's gun (%d calls, %d clips)" % [_played("shot"), _clips("shot").size()])
	a.assist = {}

func _hina_ex() -> void:
	_fresh()
	_run_move(a, "ex")
	var ult := _clips("ult", "hina")
	check(ult.size() == 1 and ult[0]["channel"] == "move" and ult[0]["slot"] == 1, "hina EX: the ult clip on her move channel")
	check(_played("shot") == 10 and _clips("shot", "hina").is_empty(), "hina EX: ten rounds call shot and every one is muted")
	check(_clips("spool", "hina").is_empty() and _clips("reload", "hina").is_empty(), "hina EX with a full magazine: no spool, no reload")
	check(sfx._fades.has(_player(1, "move")), "hina EX: the ult clip is stopped when the move ends")
	_fresh()
	a.kv["mag"] = 5
	_run_move(a, "ex")
	var reload := _clips("reload", "hina")
	check(reload.size() == 1 and String(reload[0]["clip"]).begins_with("sfx/SFX_Common_HMG_Reload_Hina"), "hina EX that empties the magazine: one reload clip")
	check(_clips("lock_and_load", "hina").is_empty() and _lines("skill_auto").is_empty(), "hina EX that empties the magazine: no Lock & Load")
	sfx.clips_played.clear()
	check(a.state != states.ATTACK and a.move_key == "ex" and a.sfx("shot") and _clips("shot", "hina").size() == 1, "hina after her EX: a shot outside a move is not muted by the last move key")

func _hina_supers() -> void:
	_fresh()
	var locks := _played("lock")
	a._start_move("super")
	var lal := _clips("lock_and_load", "hina")
	check(lal.size() == 1 and lal[0]["channel"] == "long", "hina Lock & Load super: its own clip, on the long pool")
	check(_played("lock") == locks, "hina Lock & Load: the synthesised lock is replaced")
	check(_lines("skill", 1).size() == 1 and _lines("skill_auto").is_empty(), "hina Lock & Load super: the skill voice")
	_fresh()
	a._start_move("super_down")
	check(sfx.voice_log.is_empty() and _clips("lock_and_load").is_empty(), "hina Out-and-Out: the down super has no voice")
	_fresh()
	a.kv["mag"] = 3
	_run_move(a, "5H")
	check(_lines("skill_auto", 1).size() == 1 and _lines("skill").is_empty() and _clips("lock_and_load", "hina").size() == 1, "hina auto Lock & Load: skill_auto voice and the clip")
	a.frame += 300
	screen._vis_frame += 300
	a.kv["mag"] = 3
	_run_move(a, "5H")
	check(_lines("skill_auto").size() == 1, "hina auto Lock & Load: a second trigger 300 ticks later is silent (gap 600)")
	check(_clips("lock_and_load", "hina").size() == 2, "hina auto Lock & Load: the clip itself only waits 120 ticks")
	a.frame += 400
	screen._vis_frame += 400
	a.kv["mag"] = 3
	_run_move(a, "5H")
	check(_lines("skill_auto").size() == 2, "hina auto Lock & Load: speaks again after 600 ticks")

# Hoshino
func _hoshino_normals() -> void:
	_fresh()
	var swings := _played("swing")
	_run_move(b, "5H")
	var shots := _clips("shot", "hoshino")
	check(shots.size() == 2, "hoshino 5H: two SG clips (%d)" % shots.size())
	check(shots.size() == 2 and String(shots[0]["clip"]).begins_with("sfx/SFX_Common_SG_0") and shots[0]["channel"] == "pool", "hoshino 5H: SG shots on the pool")
	check(shots.size() == 2 and int(shots[1]["tick"]) - int(shots[0]["tick"]) == 9, "hoshino 5H: one clip at each shot frame, 9 ticks apart")
	check(_played("shot") == 3, "hoshino 5H: the pellet at frame 11 calls the same event and the gap drops it (%d)" % _played("shot"))
	var pump := _clips("pump", "hoshino")
	check(pump.size() == 1 and shots.size() == 2 and int(pump[0]["tick"]) - int(shots[1]["tick"]) == 12, "hoshino 5H: one pump, 12 ticks after the second shot")
	check(_played("swing") == swings, "hoshino 5H: no swing")
	_fresh()
	_run_move(b, "5L")
	check(_clips("shot", "hoshino").size() == 1 and _clips("pump", "hoshino").size() == 1, "hoshino 5L: one shot, one pump")
	_fresh()
	b._start_move("5L")
	_tick(b, 9)
	b._start_move("5L")
	_tick(b, 30)
	var s2 := _clips("shot", "hoshino")
	var p2 := _clips("pump", "hoshino")
	check(s2.size() == 2 and p2.size() == 1, "hoshino: a pump that a new shot cuts off is dropped (%d shots, %d pumps)" % [s2.size(), p2.size()])
	check(s2.size() == 2 and p2.size() == 1 and int(p2[0]["tick"]) - int(s2[1]["tick"]) == 12, "hoshino: the pump that stays comes 12 ticks after the last shot")
	_fresh()
	_run_move(b, "close_H")
	check(_played("shot") == 0 and _clips("pump", "hoshino").is_empty(), "hoshino: a stock bash fires no gun sound")

func _hoshino_buckshot() -> void:
	_fresh()
	_hold_skill(b, 50)
	check(_played("shot") == 9, "hoshino Buckshot, 3 shells: nine pellets call shot (%d)" % _played("shot"))
	check(_clips("shot", "hoshino").size() == 1, "hoshino Buckshot, 3 shells: one clip (%d)" % _clips("shot", "hoshino").size())
	var reload := _clips("reload", "hoshino")
	check(reload.size() == 1 and String(reload[0]["clip"]).begins_with("sfx/SFX_Common_SG_Reload"), "hoshino Buckshot: one reload per hold")
	_fresh()
	_run_move(b, "skill")
	check(_clips("shot", "hoshino").size() == 1 and _clips("reload", "hoshino").size() == 1, "hoshino Buckshot, one shell: one shot, one reload")
	var shot := _clips("shot", "hoshino")
	var rl := _clips("reload", "hoshino")
	check(shot.size() == 1 and rl.size() == 1 and int(rl[0]["tick"]) > int(shot[0]["tick"]), "hoshino Buckshot: the reload comes after the shell")

func _hoshino_ex() -> void:
	_fresh()
	_run_move(b, "ex")
	var ult := _clips("ult", "hoshino")
	var rl := _clips("ult_reload", "hoshino")
	check(ult.size() == 1 and ult[0]["channel"] == "move", "hoshino EX: the activate clip on her move channel")
	check(rl.size() == 1 and rl[0]["channel"] == "long" and ult.size() == 1 and int(rl[0]["tick"]) - int(ult[0]["tick"]) == 20, "hoshino EX: the reload clip layers on the long pool 20 ticks later")
	check(_clips("reload", "hoshino").is_empty(), "hoshino EX: not the Buckshot reload")

func _hoshino_heal() -> void:
	_fresh()
	var claims := _played("claim")
	b._start_move("super")
	check(_clips("first_aid", "hoshino").size() == 1 and _lines("skill", 2).size() == 1, "hoshino First Aid super: the first aid clip and the skill voice")
	_tick(b, 22)
	check(_clips("heal_tick", "hoshino").size() == 1 and _played("claim") == claims, "hoshino First Aid super: the heal plays heal_tick, not claim")
	_fresh()
	b._start_move("super_down")
	check(sfx.voice_log.is_empty() and _clips("first_aid").is_empty(), "hoshino Expert Suppression: the down super has no voice")
	_fresh()
	b.hp = b.max_hp * 0.2
	_tick(b, 305)
	check(_clips("first_aid", "hoshino").size() == 1, "hoshino auto First Aid: first_aid once (%d)" % _clips("first_aid", "hoshino").size())
	check(_clips("heal_tick", "hoshino").size() == 5, "hoshino auto First Aid: heal_tick on each of the five ticks (%d)" % _clips("heal_tick", "hoshino").size())
	check(_lines("skill_auto", 2).size() == 1 and _lines("skill").is_empty(), "hoshino auto First Aid: the skill_auto voice once")

# hits
func _hits() -> void:
	_fresh()
	var hl := _played("hit_l")
	var booms := _played("boom")
	check(_hit(a, b, {"sfx": "hit_l"}) == "hit", "hit: a light hit lands")
	var imp := _clips("hit_l")
	check(imp.size() == 1 and imp[0]["who"] == "hina" and imp[0]["channel"] == "pool" and _played("hit_l") == hl + 1, "hit: the impact follows the attacker's set (hina)")
	_hit(b, a, {"sfx": "hit_h"})
	check(_clips("hit_h").size() == 1 and _clips("hit_h")[0]["who"] == "hoshino", "hit: and hoshino's, when she hits")
	_hit(a, b, {"sfx": "boom"})
	check(_played("boom") == booms + 1 and _clips("boom").is_empty(), "hit: boom stays synthesised")
	check(a.has_sounds() and b.has_sounds(), "has_sounds: hina and hoshino have a set")

func _voices() -> void:
	_fresh()
	var light := {"sfx": "hit_l"}
	var big := {"sfx": "hit_h", "launch": Vector2(4, -10), "kd": true}
	_hit(a, b, light)
	check(sfx.voice_log.is_empty(), "big hit: a light hit never voices")
	_hit(a, b, big)
	var bh := _lines("big_hit")
	check(bh.size() == 1 and bh[0]["slot"] == 2, "big hit: a launch voices once, from the one who was hit")
	screen._vis_frame += 400
	_hit(a, b, big)
	check(_lines("big_hit").size() == 1, "big hit: once per combo, even 400 ticks and a second launch later")
	b._recover()
	screen._vis_frame += 400
	_hit(a, b, big)
	check(_lines("big_hit").size() == 2, "big hit: the next combo voices again")
	b._recover()
	screen._vis_frame += 10
	_hit(a, b, big)
	check(_lines("big_hit").size() == 2, "big hit: a new combo inside 180 ticks is dropped")
	_fresh()
	b.position.y -= 200.0
	_hit(a, b, light)
	check(sfx.voice_log.is_empty() and b.state == states.AIRHIT, "big hit: being airborne is not enough")
	_fresh()
	b.hp = 5.0
	_hit(a, b, big)
	check(sfx.voice_log.is_empty(), "big hit: the blow that kills does not voice")
	_fresh()
	b.voice("big_hit")
	screen.phase = "fight"
	b._ko()
	var ko := _lines("ko")
	check(ko.size() == 1 and ko[0]["slot"] == 2 and ko[0]["cut"] == true, "ko: the KO line cuts the damage line")
	_fresh()
	a.voice("intro")
	a._ko()
	check(_lines("ko", 1).size() == 1, "ko: it cuts an intro line too")
	_fresh()
	a._ko()
	screen.phase = "ko"
	b._ko()
	check(_lines("ko", 2).is_empty(), "ko: a KO after the round is decided is silent")
	_fresh()
	screen.wins = [0, 0]
	b.hp = 0.0
	screen._end_round()
	check(_lines("victory").is_empty(), "victory: a round win that does not end the match is silent")
	_fresh()
	screen.wins = [1, 0]
	b.hp = 0.0
	screen._end_round()
	var vic := _lines("victory")
	check(vic.size() == 1 and vic[0]["slot"] == 1, "victory: the match winner speaks (%d)" % vic.size())
	_fresh()
	screen.wins = [1, 1]
	a.hp = a.max_hp
	b.hp = b.max_hp
	screen._end_round()
	check(_lines("victory").is_empty(), "victory: a draw is silent")

func _stop_on_hit() -> void:
	for st in ["HIT", "AIRHIT", "BLOCK", "KO"]:
		_fresh()
		a.sfx("ult")
		var p := _player(1, "move")
		check(p.playing and not sfx._fades.has(p), "move clip: playing before the %s" % st)
		a._set_state(states[st])
		check(sfx._fades.has(p), "move clip: %s fades the move channel out" % st)
	_fresh()
	a.sfx("ult")
	var q := _player(1, "move")
	a._set_state(states.JUMP)
	check(not sfx._fades.has(q), "move clip: a jump does not stop it")
	_fresh()
	a._start_move("5H")
	_tick(a, 14)
	var burst := _player(1, "move")
	_hit(b, a, {"sfx": "hit_l"})
	check(sfx._fades.has(burst), "move clip: a hit on hina ends her burst")

func _swing() -> void:
	_fresh()
	var swings := _played("swing")
	a._start_move("close_L")
	check(_played("swing") == swings + 1, "swing: a close strike keeps it")
	a._start_move("6H")
	check(_played("swing") == swings + 2, "swing: a command strike keeps it")
	b._start_move("5L")
	check(_played("swing") == swings + 2, "swing: a gun normal has none")
	var throws := _played("throw")
	a._start_move("throw")
	check(_played("throw") == throws + 1 and _played("swing") == swings + 2, "swing: the throw keeps its own sound")

func _cutin() -> void:
	_fresh()
	var supers := _played("super")
	var rises := _played("ult_rise")
	a.meter = 100.0
	a._start_move("ex")
	screen._sim_step()
	check(screen.time_stop > 0, "cut-in: the EX freezes the world")
	var cut := _clips("cutin", "hina")
	check(cut.size() == 1 and cut[0]["channel"] == "cut" and cut[0]["slot"] == 1, "cut-in: one cut-in clip on the caster's cut channel")
	check(_lines("ult", 1).size() == 1, "cut-in: the ult line at freeze start")
	check(_played("super") == supers and _played("ult_rise") == rises, "cut-in: a set fighter does not also play the synthesised cut-in")
	check(not b.voice("big_hit") and not b.voice("skill") and not b.voice("intro"), "freeze: every voice but ult is dropped")
	check(b.voice("ult") and _lines("ult", 2).size() == 1, "freeze: ult still speaks")
	var cp := _player(1, "cut")
	for i in 72:
		screen._sim_step()
	check(screen.time_stop == 0 and cp.playing and not sfx._fades.has(cp), "cut-in: the clip plays through the resume")
	for i in 29:
		screen._sim_step()
	check(not sfx._fades.has(cp), "cut-in: 29 ticks after the resume it still plays")
	screen._sim_step()
	check(sfx._fades.has(cp), "cut-in: 30 ticks (0.5 s) after the resume it fades")
	check(_clips("cutin", "hina").size() == 1, "cut-in: once per freeze")

func _round_start() -> void:
	_fresh()
	check(a.voice("intro") and not a.voice("intro"), "round start: a line in progress drops the next one")
	screen.restart_round()
	screen.phase = "fight"
	check(a.voice("intro"), "round start: stop_all cleared the voice state")
	var whoosh: AudioStreamPlayer = sfx._players[(sfx._next + sfx._players.size() - 1) % sfx._players.size()]
	check(whoosh.playing and not sfx._fades.has(whoosh), "round start: the round's own whoosh starts after stop_all, so it is not faded")
	var f0: int = a.frame
	screen.restart_round()
	screen.phase = "fight"
	check(a.frame == f0, "round start: fighter frames keep counting through a round")

func _cross_check() -> void:
	_fresh()
	check(scanned > 40 and crossed == 0, "no HMG clip played for Hoshino and no SG clip for Hina (%d of %d)" % [crossed, scanned])


# the voice clock, offsets, long clips, stop_all, quit paths
## An EX freeze stalls Fighter.frame but not the screen's _vis_frame, and a line plays in real time.
func _clocks() -> void:
	_fresh()
	a.meter = 100.0
	a._start_move("ex")
	screen._sim_step()
	check(_lines("ult", 1).size() == 1, "clock: the EX voices its ult line at freeze start")
	var f0: int = a.frame
	var v0: int = screen._vis_frame
	for i in 172:
		screen._sim_step()
	check(a.frame - f0 < 120 and screen._vis_frame - v0 == 172, "clock: the freeze stalled the fighter clock but not the screen's (%d, %d)" % [a.frame - f0, screen._vis_frame - v0])
	check(a.voice("victory"), "clock: a victory line after a freezing EX is not held off by a line that ended long ago")
	_fresh()
	a.meter = 100.0
	a._start_move("ex")
	screen._sim_step()
	for i in 100:
		screen._sim_step()
	check(a.voice("victory") == false, "clock: but one right after the ult line is dropped")
	_fresh()

## Frame offsets inside the move data that the tests above only touch in passing.
func _pins() -> void:
	var ult_at := -1
	for e in a.moves["ex"]["sfx"]:
		if e["name"] == "ult":
			ult_at = int(e["frame"])
	check(ult_at == 8, "pin: hina's ult clip starts on EX frame 8 (%d)" % ult_at)
	var reload_at := -1
	for e in b.moves["skill"]["sfx"]:
		if e["name"] == "reload":
			reload_at = int(e["frame"])
	check(reload_at == 22, "pin: hoshino's Buckshot reload is on frame 22 (%d)" % reload_at)
	# a kd without a launch vector is a big hit too
	_fresh()
	_hit(a, b, {"sfx": "hit_h", "kd": true})
	check(_lines("big_hit", 2).size() == 1, "big hit: a knockdown without a launch voices")
	# a dropped line does not use up the combo's one line
	_fresh()
	check(b.voice("intro"), "big hit: setup, an intro line is playing")
	_hit(a, b, {"sfx": "hit_h", "launch": Vector2(4, -10), "kd": true})
	check(_lines("big_hit").is_empty() and not b.big_voiced, "big hit: dropped while a higher line plays, and not counted as spoken")
	screen._vis_frame += 400
	_hit(a, b, {"sfx": "hit_h", "launch": Vector2(4, -10), "kd": true})
	check(_lines("big_hit").size() == 1, "big hit: the same combo tries again once the line is over")
	# the spool waits 45 ticks after the last round fired, not after the last spool
	_fresh()
	a.kv["fired_t"] = -1000
	for i in 8:
		a._start_move("5L")
		_tick(a, 20)
	check(_clips("spool", "hina").size() == 1, "hina spool: eight bursts 20 ticks apart spool once (%d)" % _clips("spool", "hina").size())
	_fresh()

## Long clips have their own pool, so a flood of impacts never cuts them.
func _long_clips() -> void:
	_fresh()
	check(a.sfx("lock_and_load"), "long pool: lock and load starts")
	var lp: AudioStreamPlayer = sfx._long[(sfx._next_long + sfx._long.size() - 1) % sfx._long.size()]
	for i in 40:
		a.sfx("hit_l")
	check(lp.playing and lp.stream != null and not sfx._fades.has(lp), "long pool: 40 impacts later the lock and load clip still plays")
	_fresh()

func _stop_all_rules() -> void:
	_fresh()
	sfx.play("confirm")
	var ui: AudioStreamPlayer = sfx._players[(sfx._next + sfx._players.size() - 1) % sfx._players.size()]
	a.sfx("hit_l")
	var clip: AudioStreamPlayer = sfx._players[(sfx._next + sfx._players.size() - 1) % sfx._players.size()]
	sfx.stop_all()
	check(ui.playing and not sfx._fades.has(ui), "stop_all: a mapped UI sound started this frame is not faded")
	check(sfx._fades.has(clip), "stop_all: a manifest clip is")
	check(sfx.ui.has("throw") and sfx.ui.has("tech") and sfx.ui.has("grab"), "the throw, the tech and the grab play a mapped Blue Archive clip")
	_fresh()

## The pause menu's quits leave the screen for good, so they stop any long clip: read from the source, because calling them
## changes the screen.
func _quit_paths() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/fight/fight_screen.gd")
	for fn in ["quit_to_menu", "quit_to_select"]:
		var i := src.find("func %s(" % fn)
		var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
		check(i >= 0 and body.contains("Sfx.stop_all()"), fn + " stops every sound")

# fighters with no sound set keep today's sounds
## The fighters stay Hina and Hoshino (only they are simulated) but their key names no set, as a sprite kit's does.
var _keys := []
func _no_set(on: bool) -> void:
	if on:
		_keys = [a.data, b.data]
		a.data = a.data.duplicate()
		b.data = b.data.duplicate()
		a.data["key"] = "zzz_no_set"
		b.data["key"] = "zzz_no_set"
	else:
		a.data = _keys[0]
		b.data = _keys[1]

func _sprites() -> void:
	_fresh()
	check(not a.has_sounds() and not b.has_sounds(), "no set: neither fighter has a set")
	var supers := _played("super")
	var rises := _played("ult_rise")
	a.meter = 100.0
	a._start_move("ex")
	screen._sim_step()
	check(screen.time_stop > 0 and _played("super") == supers + 1 and _played("ult_rise") == rises + 1, "no set, cut-in: super and ult_rise still play")
	check(sfx.clips_played.is_empty() and sfx.voice_log.is_empty(), "no set, cut-in: no clip, no voice")
	for i in 72:
		screen._sim_step()
	check(screen._cut_fade == -1, "no set, cut-in: nothing is scheduled to fade")
	_fresh()
	var claims := _played("claim")
	for i in 3:
		screen.fx_heal(b)
	check(_played("claim") == claims + 3 and sfx.clips_played.is_empty(), "no set, heal: three claim sounds and no clip (%d)" % (_played("claim") - claims))
	_fresh()
	var spec: Dictionary = b.moves["skill"]["spawns"][0]
	var shots := _played("shot")
	screen._frame += 10
	screen.spawn_projectile(a, spec)
	screen.spawn_projectile(b, spec)
	check(_played("shot") == shots + 2, "no set, shot: two fighters firing in the same frame both sound (%d)" % (_played("shot") - shots))
	screen.spawn_projectile(a, spec)
	screen.spawn_projectile(b, spec)
	check(_played("shot") == shots + 2, "no set, shot: each fighter is still throttled to one per 3 frames")
	screen._frame += 3
	screen.spawn_projectile(a, spec)
	check(_played("shot") == shots + 3 and sfx.clips_played.is_empty(), "no set, shot: it sounds again after 3 frames, still no clip")
	_fresh()
	a.meter = 100.0
	var super_calls := _played("super")
	a._start_super(false)
	check(_played("super") == super_calls + 1 and sfx.clips_played.is_empty() and sfx.voice_log.is_empty(), "no set, super: the synthesised super sound, no clip, no voice")
	_fresh()
	var swings := _played("swing")
	a._start_move("close_L")
	check(_played("swing") == swings + 1, "no set: a strike still plays swing")
	var impacts := _played("hit_l")
	_hit(a, b, {"sfx": "hit_l"})
	check(_played("hit_l") == impacts + 1 and sfx.clips_played.is_empty(), "no set, hit: the synthesised hit and no clip")
	check(a.voice("intro") == false and a.voice("ko") == false and a.sfx("shot") == false and sfx.voice_log.is_empty(), "no set: voice and sfx return false and log nothing")

func _sprite_hits_hina() -> void:
	_fresh()
	var hl := _played("hit_l")
	var hh := _played("hit_h")
	_hit(a, b, {"sfx": "hit_l"})
	_hit(a, b, {"sfx": "hit_h"})
	check(_played("hit_l") == hl + 1 and _played("hit_h") == hh + 1 and sfx.clips_played.is_empty(), "a fighter with no set hitting a fighter with one still plays the synthesised hit")
	b.data["key"] = "hoshino"
	_hit(b, a, {"sfx": "hit_l"})
	check(_clips("hit_l", "hoshino").size() == 1, "a fighter with a set hitting one without plays her own impact")
	b.data["key"] = "zzz_no_set"
