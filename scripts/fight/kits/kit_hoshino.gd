extends Kit
## HOSHINO (Takanashi Hoshino): Abydos Foreclosure Task Force president. Tank, Heavy armor, semi-auto shotgun (Eye of Horus).
## Research, sources and the move table: look at relevant docs.
##
## Personality -> style: a sleepy "old man" who would rather nap than work, and says so. Once a fight starts she snaps
## into the protective front-liner: she walks up to shotgun range, takes hits on the chin and answers with buckshot.
## No shield moves (the shield stays hidden). Her normals are shots from Eye of Horus; close in she shoulders and stocks
## the shotgun (adaptation).
##
##  Stats      big HP, low damage taken (Foreclosure Task Force President: DEF up).
##  5L         Point-Blank Shot: one semi-auto shot.
##  5H         Double Tap: two shots, one hit of armor in startup, the second shot knocks back.
##  2L / 2H    Low Shot (low) / Upward Shot (anti-air, launches).
##  close_L/H  Shoulder Bump / Stock Bash (one hit of armor): picked by 5L / 5H when the foe is within 96 px.
##  6L / 6H    Muzzle Jab (steps in) / Stock Drop (a slow overhead): forward + light / heavy.
##  throw      Shoulder Toss (light + heavy, foe within 120 px): beats block; she hoists the foe beside her head and heaves it
##             forward with a tumble, a knockdown that lands at the heave. Two throws clash.
##  jL / jH    Air Shot / Downward Blast.
##  skill      Buckshot: HOLD to load more shells (3 pellets each). j.skill fires one shell from the air.
##  EX         Tactical Suppression (the ult, a full meter): advances while firing 5 blasts into a 45 degree fan,
##             armored throughout.
##  super      Emergency First Aid (skill + EX, 50 meter; Basic skill): she stops to heal, armored.
##  super_down Expert Suppression (down + skill + EX, 50 meter; Sub skill): all three Buckshot shells in one armored blast.
##  Passive    Foreclosure Task Force President (Enhanced skill): DEF up. Emergency First Aid still triggers by itself
##             once per round under 30 % HP.
##
## The gun normals are melee rects (a blast zone in front of the muzzle) so they can chain; projectiles are for 5H's first
## shot (a short pellet), the skill and the EX.

const DBG := false   # dev: prints running combo damage (raw, before the defender's `taken`) and First Aid ticks
const AID_EVERY := 60   # in game every 4 s for 20 s; squeezed to fit a 60 s round
const AID_TICKS := 5
const AID_HEAL := 0.018   # fraction of max HP per tick
const SdSockets := preload("res://scripts/models/sd_sockets.gd")
const PUMP_AFTER := 12   # ticks from her last shot frame to the pump

func build_stats() -> Dictionary:
	var s := Movesets.stats_for(data)
	s["taken"] = 0.86   # Foreclosure Task Force President: DEF up
	var hb := SdSockets.hurtbox(String(data["key"]))
	if not hb.is_empty():
		s["hurt_w"] = hb["w"]
		s["hurt_h"] = hb["h"]
		s["hurt_crouch_h"] = hb["crouch_h"]
	var push := SdSockets.push(String(data["key"]))
	if push > 0:
		s["push_w"] = float(push)
	return s

## Gun muzzle relative to the feet, facing right: measured from the 3D model at that move frame, the same for both
## facings (assets/ba/sd/hoshino/sockets.json, tools/sd_measure.sh), else a placeholder. Every shot origin and blast
## zone reads it.
func _muzzle(move_key: String, frame: int) -> Vector2:
	var placeholder := Vector2(78, -151)
	match move_key:
		"2L":
			placeholder = Vector2(84, -80)
		"2H":
			placeholder = Vector2(60, -206)
	return SdSockets.muzzle(String(data["key"]), move_key, frame, placeholder)

## A point-blank blast zone: from her front edge out past the muzzle along `deg` (0 = ahead, + = down), padded by `pad`.
func _zone(key: String, frame: int, deg: float, reach: float, pad: float) -> Rect2:
	var m := _muzzle(key, frame)
	var tip := m + Vector2(reach, 0).rotated(deg_to_rad(deg))
	return Rect2(20, m.y, 0, 0).expand(m).expand(tip).grow_individual(0, pad, pad, pad)

func build_moves(st: Dictionary) -> Dictionary:
	var dm: float = st["dmg"]
	var col: Color = st["color"]
	var m := {}
	m["5L"] = mv("5L", 6, 3, 12, {
		"hit": hit(_zone("5L", 6, 0, 110, 45), 40 * dm, 16, 11, 4.5, {"meter": 5.0, "sfx": "hit_l"}),
		"cancel": ["light", "heavy", "skill", "ex"], "swish": false, "shots": [6],
		"source": "Normal attack: one semi-auto shot, 3 pellet ticks, range 350 (look at relevant docs); adaptation: the three ticks land as one blast zone ahead of the muzzle so the chain can cancel",
		"pose": {"lunge": 6.0, "recoil": 0.12}})

	# Double Tap: shot 1 is a short pellet, shot 2 the melee blast, so cancels open only after the second shot.
	# not fully functional. 25 px a frame was the slowest pellet that linked off 5L into Hina at the old 74 px spacing; the pair now stands 44 px farther apart, so the first pellet lands about 2 ticks later and kit_hoshino_meas_jumpin drops that link.
	var tap1 := hit(Rect2(), 36 * dm, 20, 12, 2.5, {"meter": 4.0, "hitstop": 6})
	m["5H"] = mv("5H", 20, 3, 20, {
		"hit": hit(_zone("5H", 20, 0, 120, 55), 62 * dm, 26, 16, 8.0, {"meter": 9.0, "hitstop": 11, "spark": "heavy", "sfx": "hit_h", "shake": 5.0}),
		"spawns": [spawn(11, _muzzle("5H", 11), Vector2(25, 0), tap1, {"muzzle_sweep": true, "size": Vector2(30, 22), "color": col, "life": 9, "kind": "pellet"})],
		"armor": {"from": 3, "to": 19, "hits": 1, "dmg": 0.5}, "cancel": ["skill", "ex"], "swish": false, "shots": [11, 20],
		"source": "Normal attack: semi-auto Beretta 1301, one shot per pull, no pump (look at relevant docs); adaptation: two shots on one button where the game fires one per attack cycle, the second a blast zone so it cancels, and one hit of armor in startup for the sturdy front-liner (Tank, Front, DEF passive)",
		"pose": {"lunge": 10.0, "recoil": 0.2}})
	m["2L"] = mv("2L", 7, 3, 13, {
		"crouch": true, "hit": hit(_zone("2L", 7, 12, 110, 36), 30 * dm, 15, 10, 4.0, {"meter": 4.0, "level": "low", "sfx": "hit_l"}),
		"cancel": ["light", "heavy", "skill", "ex"], "swish": false, "shots": [7],
		"source": "adaptation: the normal-attack shot fired crouched at the legs so she has a low (look at relevant docs)",
		"pose": {"lunge": 6.0, "recoil": 0.1}})
	m["2H"] = mv("2H", 9, 4, 24, {
		"crouch": true, "hit": hit(_zone("2H", 9, -60, 150, 50), 64 * dm, 24, 14, 2.0, {"meter": 8.0, "hitstop": 10, "spark": "heavy", "sfx": "hit_h", "launch": Vector2(2, -15), "kd": true, "shake": 4.0}),
		"cancel": ["skill", "ex"], "swish": false, "shots": [9],
		"source": "adaptation: the normal-attack shot angled up as an anti-air; no source gives her one (look at relevant docs)",
		"pose": {"lean": -0.12, "recoil": 0.16}})
	m["jL"] = mv("jL", 6, 6, 8, {
		"air": true, "hit": hit(_zone("jL", 6, 25, 100, 45), 32 * dm, 16, 11, 3.5, {"meter": 4.0, "level": "high", "sfx": "hit_l"}),
		"cancel": ["heavy", "skill"], "swish": false, "shots": [6],
		"source": "no source gives her aerial attacks (look at relevant docs); the move exists because the engine requires the jL, jH and skill_air keys (look at relevant docs); it is her plain normal-attack shot from her plain jump, no flips",
		"pose": {"lean": 0.15, "recoil": 0.1}})
	m["jH"] = mv("jH", 9, 5, 12, {
		"air": true, "hit": hit(_zone("jH", 9, 55, 130, 55), 36 * dm, 26, 14, 5.0, {"meter": 8.0, "hitstop": 9, "level": "high", "spark": "heavy", "sfx": "hit_h", "shake": 3.0}),
		"cancel": ["skill"], "swish": false, "shots": [9],
		"source": "no source gives her aerial attacks (look at relevant docs); the move exists because the engine requires the jL, jH and skill_air keys (look at relevant docs); it is her plain normal-attack shot, fired steeply down from her plain jump, no flips",
		"pose": {"lean": 0.3, "recoil": 0.16}})

	# Close strikes, command normals and the throw. The shotgun is short, so she shoulders and bashes
	# with it. None fires a shell. The shield stays hidden.
	var hip := {"cancel": ["light", "heavy", "skill", "ex"]}
	m["close_L"] = mv("close_L", 5, 3, 12, hip.merged({
		"hit": hit(Rect2(14, -205, 85, 115), 32 * dm, 16, 10, 5.5, {"meter": 4.0, "sfx": "hit_l"}),
		"pose": {"lunge": 8.0, "lean": 0.12},
		"source": "adaptation: no melee in any base clip or skill (look at relevant docs); a shoulder bump for a foe inside her shot zone's reach"}))
	m["close_H"] = mv("close_H", 12, 4, 22, {
		"hit": hit(Rect2(10, -215, 110, 110), 56 * dm, 25, 15, 9.0, {"meter": 9.0, "hitstop": 9, "spark": "heavy", "sfx": "hit_h", "shake": 3.0}),
		"armor": {"from": 3, "to": 11, "hits": 1, "dmg": 0.5}, "cancel": ["skill", "ex"], "pose": {"lunge": 12.0, "lean": 0.2},
		"source": "adaptation: no melee in any base clip or skill (look at relevant docs); a stock bash with one hit of armor for the sturdy front-liner (Tank, DEF passive)"})
	m["6L"] = mv("6L", 9, 3, 14, hip.merged({
		"hit": hit(Rect2(20, -185, 140, 70), 34 * dm, 17, 11, 5.0, {"meter": 5.0, "sfx": "hit_l"}),
		"vx": [{"from": 6, "to": 10, "v": 2.0}], "pose": {"lunge": 14.0, "lean": 0.1},
		"source": "adaptation: no melee in any base clip or skill (look at relevant docs); a muzzle jab that steps in with forward held"}))
	m["6H"] = mv("6H", 22, 4, 26, {
		"hit": hit(Rect2(24, -285, 100, 190), 62 * dm, 26, 16, 4.0, {"meter": 9.0, "hitstop": 9, "level": "high", "spark": "heavy", "sfx": "hit_h", "shake": 3.0}),
		"cancel": ["skill", "ex"], "pose": {"lunge": 6.0, "lean": 0.06},
		"source": "adaptation: no melee in any base clip or skill (look at relevant docs); a slow stock drop from above, an overhead that a crouch block loses to"})
	m["throw"] = mv("throw", 8, 3, 30, {
		"hit": hit(Rect2(0, -200, 105, 170), 80 * dm, 0, 0, 4.0, {"throw": true, "snap": 80.0, "kd": true, "launch": Vector2(11.0, -5.5), "meter": 8.0, "hitstop": 6, "spark": "heavy", "sfx": "slam", "shake": 6.0}),
		"swish": false, "pose": {"lunge": 10.0, "lean": 0.1},
		"carry": {"anim": "carried", "pivot": 76.0, "grab_stop": 4, "release": 16, "spin": 22.0, "front": false,
			"path": [[10, 79, -6, 0], [12, 66, -42, 0], [13, 67, -38, 0], [14, 75, -32, -8], [15, 62, -14, 22], [16, 49, -5, 52]]},
		"sfx": [{"frame": 12, "name": "swing", "pitch": 0.9}, {"frame": 15, "name": "swing", "pitch": 1.2}],
		"source": "adaptation: no melee in any base clip or skill (look at relevant docs); a shoulder toss, the front-liner hoisting the foe beside her head and heaving them clear with a tumble"})

	# Buckshot: HOLD to load shells, 3 pellets each. 0-14 raise the gun, hold at 14 (max 36), then fire.
	var pel := hit(Rect2(), 22 * dm, 17, 12, 7.0, {"meter": 2.5, "hitstop": 5})
	var big := hit(Rect2(), 25 * dm, 20, 14, 10.0, {"meter": 3.0, "hitstop": 6, "spark": "heavy", "launch": Vector2(5, -7), "kd": true})
	var sk := mv("skill", 16, 3, 22, {"hold": {"btn": "skill", "at": 14, "max": 36}, "cancel": [], "fx": [{"frame": 4, "kind": "charge"}],
		# not fully functional. the reload comes 18 ticks after the charge cue (the table's 0.3 s), a guess to tune by ear
		"sfx": [{"frame": 22, "name": "reload"}],
		"source": "Eye of Horus: 8 shells plus a side saddle of spares, 3 pellet ticks per shot (look at relevant docs); adaptation: hold to load up to three shells at once, which no source shows",
		"pose": {"lunge": 8.0, "recoil": 0.22}})
	for k in 3:   # shell k loads after 12 * k held frames; the third is heavy and launches
		for a in [-6.0 - 6.0 * k, 0.0, 6.0 + 6.0 * k]:
			var spec := {"muzzle_sweep": true, "color": col, "kind": "pellet", "min_charge": 12 * k}
			if k < 2:
				spec.merge({"size": Vector2(28, 20), "life": 17, "charge": {"dmg": 0.25, "speed": 0.2}})
			else:
				spec.merge({"size": Vector2(34, 26), "life": 20})
			sk["spawns"].append(spawn(16, _muzzle("skill", 16), Vector2(18.0 if k < 2 else 21.0, 0).rotated(deg_to_rad(a)), pel if k < 2 else big, spec))
	m["skill"] = sk

	var ska := mv("skill_air", 10, 3, 18, {"air": true, "cancel": [],
		"source": "no source gives her aerial attacks (look at relevant docs); the move exists because the engine requires the jL, jH and skill_air keys (look at relevant docs); it is her plain normal-attack shot, one Buckshot shell of 3 pellets, fired down from her plain jump, no flips",
		"pose": {"lean": 0.2, "recoil": 0.2}})
	for a in [12.0, 20.0, 28.0]:
		ska["spawns"].append(spawn(10, _muzzle("skill_air", 10), Vector2(18, 0).rotated(deg_to_rad(a)), pel,
			{"muzzle_sweep": true, "size": Vector2(28, 20), "color": col, "life": 15, "kind": "pellet"}))
	m["skill_air"] = ska

	# Super: Emergency First Aid. She stops to patch herself up behind the Barrier: armor for 2 hits at half damage, and
	# 12 % of max HP over the next 3 s through the heal pool.
	m["super"] = mv("super", 20, 40, 30, {"super": true, "cancel": [], "armor": {"from": -1, "to": 89, "hits": 2, "dmg": 0.5},
		"self": [{"frame": 20, "heal": 0.12}],
		"source": "Basic skill Emergency First Aid: heals herself over time (look at relevant docs); adaptation: the 50-meter super, armored with Expert Suppression's Barrier while she heals"})

	# Down super: Expert Suppression. Every shell at once: Buckshot's full 9-pellet load in one blast at full-charge power,
	# armored through the wind-up.
	var full := hit(Rect2(), 22 * dm * 1.25, 17, 12, 7.0, {"meter": 0.0, "hitstop": 5})
	var vo := mv("super_down", 16, 3, 26, {"super": true, "cancel": [], "armor": {"from": -1, "to": 18, "hits": 2, "dmg": 0.5},
		"fx": [{"frame": 4, "kind": "charge"}], "pose": {"lunge": 10.0, "recoil": 0.3},
		"source": "Sub skill Expert Suppression: the Barrier (look at relevant docs); adaptation: all three Buckshot shells at once behind the Barrier's armor"})
	for k in 3:
		for a in [-6.0 - 6.0 * k, 0.0, 6.0 + 6.0 * k]:
			vo["spawns"].append(spawn(16, _muzzle("super_down", 16), Vector2(21.6, 0).rotated(deg_to_rad(a)), full if k < 2 else big,
				{"muzzle_sweep": true, "color": col, "kind": "pellet", "size": Vector2(34, 24 if k < 2 else 26), "life": 20}))
	m["super_down"] = vo

	# EX: Tactical Suppression. One damaging shot per blast (5 hits, as in game) inside a harmless 45 degree fan.
	# Blasts 1-4 only push, so the foe stays grounded and in hitstun; the fifth launches. Kind "blast" keeps every shot
	# out of the bullet clash (fight_screen.gd), so the harmless ones do not soak up bullets and bullets cannot erase a hit.
	var ex := mv("ex", 10, 60, 28, {"cutin": true, "armor": {"from": 0, "to": 97, "hits": 3, "dmg": 0.35},
		# not fully functional. offsets set by ear: the activate clip at move start, the reload clip 20 ticks later
		"sfx": [{"frame": 0, "name": "ult"}, {"frame": 20, "name": "ult_reload"}],
		"vx": [{"from": 6, "to": 70, "v": 2.8}], "cancel": [],
		"source": "EX: Tactical Suppression, 5 hits in a 45 degree fan of radius 400, knockback on every hit, she advances (look at relevant docs); the armor is Sub skill Expert Suppression's Barrier, only while the EX runs; adaptation: one damaging shot per blast at the centre of the fan, and the fifth blast launches and knocks down in place of the Lv3+ stun so the EX ends the combo",
		"pose": {"recoil": 0.14}})
	for i in 5:
		var fin := i == 4
		var fr := 10 + 14 * i
		var bh := hit(Rect2(), (56 if fin else 40) * dm, 22, 14, 4.5, {"meter": 0.0, "hitstop": 6, "spark": "heavy", "sfx": "hit_h",
			"launch": Vector2(8, -10) if fin else Vector2.ZERO, "kd": fin, "shake": 6.0 if fin else 2.0})
		for a in [-22.5, 0.0, 22.5]:
			ex["spawns"].append(spawn(fr, _muzzle("ex", fr), Vector2(19, 0).rotated(deg_to_rad(a)), bh if a == 0.0 else {},
				{"muzzle_sweep": a == 0.0, "size": Vector2(36, 28), "color": col, "life": 14, "kind": "blast"}))
	m["ex"] = ex
	for k in m:
		var shots: Array = m[k].get("shots", [])
		if shots.is_empty():
			continue
		m[k]["sfx"] = shots.map(func(fr: int) -> Dictionary: return {"frame": fr, "name": "shot"})
		m[k]["sfx"].append({"frame": int(shots[-1]) + PUMP_AFTER, "name": "pump"})
	return m

func on_move_start(f: Fighter, key: String) -> void:
	if key == "super":
		f.sfx("first_aid")
		f.voice("skill")

func on_tick(f: Fighter) -> void:
	# Emergency First Aid: once per round (kv is wiped every round), under 30 % HP, heal in ticks.
	if f.hp <= 0.0 or f.state == Fighter.S.KO:
		return
	var t := int(f.kv.get("aid_t", -1))
	if t < 0:
		if f.hp < f.max_hp * 0.3 and f.state != Fighter.S.INTRO:
			f.kv["aid_t"] = 0
			f.world.fx_text(f.position + Vector2(0, -330), "EMERGENCY FIRST AID", Color(0.55, 1.0, 0.7))
			f.sfx("first_aid")
			f.voice("skill_auto")
		return
	if t >= AID_EVERY * AID_TICKS:
		return
	if t % AID_EVERY == 0:
		f.hp = minf(f.max_hp, f.hp + f.max_hp * AID_HEAL)
		f.world.fx_heal(f)
		if DBG:
			print("HOSHINO FIRST AID frame ", t, " hp ", snappedf(f.hp, 0.1))
	f.kv["aid_t"] = t + 1

func on_hit_dealt(f: Fighter, def: Fighter, _h: Dictionary, _dmg: float) -> void:
	if DBG:
		print("HOSHINO COMBO ", def.combo_hits, " hits ", snappedf(def.combo_dmg / float(def.stats["taken"]), 0.1), " via ", f.move_key)

func ai_pick(f: Fighter, foe: Fighter, dist: float, rng: RandomNumberGenerator) -> Dictionary:
	# supers below a full meter (skill and EX on one frame); a full meter keeps the ult
	if f.meter >= Arena.SUPER_COST and f.meter < Arena.EX_COST:
		if f.hp < f.max_hp * 0.5 and dist > 260.0 and rng.randf() < 0.4:
			return {"taps": ["skill+ex"], "t": 100}           # Emergency First Aid
		if dist < 260.0 and rng.randf() < 0.3:
			return {"taps": ["skill+ex"], "y": 1, "t": 50}    # Expert Suppression
	if f.meter >= Arena.EX_COST and dist < 300.0 and rng.randf() < 0.4:
		return {"taps": ["ex"], "t": 100}
	if not foe.is_grounded() and dist < 280.0:
		return {"taps": ["heavy"], "y": 1, "t": 40}   # Upward Shot as an anti-air
	if dist > 160.0 and dist < 420.0 and rng.randf() < 0.5:
		var load := rng.randi_range(0, 30)
		return {"taps": ["skill"], "hold_btn": "skill", "hold": 15 + load, "t": 44 + load}   # Buckshot, loading 0-2 extra shells
	if dist >= 420.0:
		return {"x": 1, "t": roundi(20 / Arena.MOVE_SCALE)}   # walk into shotgun range
	return {}
