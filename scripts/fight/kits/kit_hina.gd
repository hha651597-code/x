extends Kit
## HINA (Sorasaki Hina): Gehenna's head prefect. Heavy armour, MG "Destroyer of Denouement", back-line damage dealer.
## Every move names its source in the "source" field; look at relevant docs.
##
## Personality -> style: composed, tired, and ruthless the moment rules are broken. Everything is "so annoying", so she
## spends the least effort that ends it: she never takes cover, plants her feet in the open and lets an oversized machine
## gun do the talking. Her wings and coat never attack, and close in she uses her legs and shoulder, not the gun (adaptation).
## Slow on her feet and sturdy, with the longest reach in the cast and a magazine that rewards
## her for emptying it.
##
##  Stats      sturdy HP, heavy armour, slow walk / dash / jump.
##  5L         Short Burst: a fast 3-round point-blank burst.
##  5H         Full Burst: the full 7-round burst, long reach and heavy pushback; cancels into skill / EX.
##  2L / 2H    Low Burst (low, from a crouch) / Rising Fire (a burst angled up as she rises, anti-air launcher).
##  close_L/H  Shove Kick / Body Check: picked by 5L / 5H when the foe is within 96 px, where her gun zones pass them.
##  6L / 6H    Stride Kick (steps in) / Axe Kick (a slow overhead): forward + light / heavy.
##  throw      Takedown (light + heavy, foe within 120 px): beats block; she lifts the foe one-armed by the collar, holds it a
##             beat overhead and drops it in front of her, a knockdown that lands at the drop. Two throws clash.
##  jL / jH    Air Burst / Heavy Air Burst: level bursts in mid-jump; a machine gun this heavy does not point down.
##  skill      Sustained Burst: a 3-round burst; HOLD to keep a flat, fast stream going. In the air it fires angled down.
##  EX         Denouement: Ishbosheth (the ult, a full meter): grounded, 10 rounds swept across a narrow 30 degree fan.
##             Ends Lock & Load.
##  super      Lock & Load (skill + EX, 50 meter; Basic skill): she reloads on the spot, which starts the damage window,
##             then streams faster and longer than Sustained Burst.
##  super_down Out-and-Out (down + skill + EX, 50 meter; Sub skill): a crouched burst fanned upward that launches and
##             hits airborne foes harder.
##  Wings      Air dash (dash in the air, once a jump, forward or back with the held direction) and a glide (hold up while
##             falling). Movement only: the wings never attack.
##  Passive    Prefect Team Member Judgment (Enhanced skill): her fast stream. Lock & Load still triggers by itself: a
##             49-round magazine, and when it runs dry she reloads instantly with +15 % damage for 4 s. Out-and-Out
##             still adds +5 % against airborne foes.

const MAG := 49                 # her real magazine (look at relevant docs)
# In game the 16 s buff (ATK +21 to 39.9 %) lasts about as long as it takes to empty the gun again, so it is almost
# always up. adaptation: here a full combo spends about 28 rounds, so 4 s at +15 % gives one window per magazine and keeps
# buffed combos near the damage band. It is kit-local (kv dmg_mult), not the engine buff, so it adds no meter gain.
const RELOAD_BUFF := 240
const RELOAD_MULT := 1.15
# fixes bug(hina): side-on, the long gun puts the muzzle past a close foe, so zones that started at the muzzle missed.
const ZONE_BACK := 38.0
const OUT_AND_OUT := 1.05       # in game +2.7 to 5.2 % of ATK per hit against targets not in cover
const STREAM_EVERY := 6         # Sustained Burst hold: one volley every 6 frames...
const STREAM_ANGLES := [-1.5, 1.5]  # ...of two rounds at a small spread, so a round every 3 frames
const LOCK_EVERY := 4           # the Lock & Load super streams a volley every 4 frames
const OUT_AND_OUT_SUPER := 1.3  # the Out-and-Out super against airborne foes, on top of the passive
const DBG_COMBO := false        # dev: prints move starts and the running combo damage (raw, before the defender's `taken`)
const SdSockets := preload("res://scripts/models/sd_sockets.gd")
const DASH_TICKS := 16          # air dash: ticks at DASH_SPEED, no gravity
const DASH_SPEED := 11.0 * Arena.MOVE_SCALE
const DASH_LOCK := 8            # ticks into the dash before an air attack can start
const GLIDE_FALL := 2.5         # glide: fall speed cap
const GLIDE_TICKS := 90         # glide ticks per jump
const SPOOL_IDLE := 45          # ticks since her last round before the gun spools up again

func personality() -> String:
	return "Composed, tired and ruthless. It's all so annoying, so she ends it fast, standing in the open behind an oversized machine gun."

func build_stats() -> Dictionary:
	var s := Movesets.stats_for(data)
	s["walk"] = 3.4
	s["walk_back"] = 3.0
	s["dash"] = 10.0
	s["jump"] = 16.5
	s["jump_dx"] = 5.5
	s["taken"] = 0.93
	var hb := SdSockets.hurtbox(String(data["key"]))
	if not hb.is_empty():
		s["hurt_w"] = hb["w"]
		s["hurt_h"] = hb["h"]
		s["hurt_crouch_h"] = hb["crouch_h"]
	var push := SdSockets.push(String(data["key"]))
	if push > 0:
		s["push_w"] = float(push)
	return s

## Every gun origin in the kit comes from here: the muzzle measured from the 3D model at that move frame, the same for
## both facings (assets/ba/sd/hina/sockets.json, tools/sd_measure.sh). Without a measurement, placeholders: hip fire
## standing and in the air, lower for the crouching pair.
func _muzzle(move_key: String, frame: int) -> Vector2:
	var placeholder := Vector2(88, -66) if move_key == "2L" or move_key == "2H" else Vector2(95, -110)
	return SdSockets.muzzle(String(data["key"]), move_key, frame, placeholder)

func build_moves(st: Dictionary) -> Dictionary:
	var dm: float = st["dmg"]
	var col := Color(0.82, 0.45, 1.0)     # the purple light from the muzzle's spiral cuts (look at relevant docs)
	var m := {}

	var mz := _muzzle("5L", 7)
	m["5L"] = mv("5L", 7, 3, 12, {
		"hit": hit(Rect2(mz.x - ZONE_BACK, mz.y - 45, 185 + ZONE_BACK, 90), 30 * dm, 18, 9, 4.5, {"meter": 5.0, "sfx": "hit_l"}),
		"cancel": ["light", "heavy", "skill", "ex"], "swish": false, "shots": [7, 8, 9], "pose": {"lunge": 4.0, "recoil": 0.05},
		"source": "Normal attack: 7-round bursts from a 49-round magazine (look at relevant docs); adaptation: a 3-round point-blank burst, and the burst is a melee zone ahead of the muzzle so the chain can cancel"})

	mz = _muzzle("5H", 12)
	m["5H"] = mv("5H", 12, 13, 18, {
		"hit": hit(Rect2(mz.x - ZONE_BACK, mz.y - 65, 290 + ZONE_BACK, 130), 70 * dm, 26, 15, 8.0, {"meter": 9.0, "hitstop": 9, "spark": "heavy", "sfx": "hit_h", "shake": 3.0}),
		"cancel": ["skill", "ex"], "swish": false, "shots": [12, 14, 16, 18, 20, 22, 24], "pose": {"lunge": 6.0, "recoil": 0.08},
		"source": "Normal attack: the full 7-round burst, range 750 (look at relevant docs); adaptation: a melee zone ahead of the muzzle, a little taller for the gun's traverse, so it cancels into skill and EX"})

	mz = _muzzle("2L", 7)
	m["2L"] = mv("2L", 7, 3, 13, {
		"crouch": true, "hit": hit(Rect2(mz.x - ZONE_BACK, mz.y - 20, 175 + ZONE_BACK, 20 - mz.y), 28 * dm, 16, 8, 3.5, {"meter": 4.0, "level": "low", "sfx": "hit_l"}),
		"cancel": ["light", "heavy", "skill", "ex"], "swish": false, "shots": [7, 8, 9], "pose": {"lunge": 4.0, "recoil": 0.04},
		"source": "adaptation: her normal-attack MG burst fired from a crouch so it hits low; no source shows her firing crouched and the model has no kneeling fire clip (look at relevant docs)"})

	mz = _muzzle("2H", 10)
	m["2H"] = mv("2H", 10, 6, 24, {
		"crouch": true, "hit": hit(Rect2(mz.x - 30, mz.y - 270, 150, 270), 64 * dm, 24, 14, 2.0, {"meter": 8.0, "hitstop": 9, "spark": "heavy", "sfx": "hit_h", "launch": Vector2(2.5, -15), "kd": true, "shake": 4.0}),
		"cancel": ["ex"], "swish": false, "shots": [10, 11, 12, 13, 14], "pose": {"lean": -0.1, "recoil": 0.08},
		"source": "adaptation: her normal-attack MG burst angled up as she rises from a crouch, an anti-air launcher; no source shows crouched or upward fire (look at relevant docs)"})

	mz = _muzzle("jL", 6)
	m["jL"] = mv("jL", 6, 6, 8, {
		"air": true, "hit": hit(Rect2(mz.x - ZONE_BACK, mz.y - 45, 175 + ZONE_BACK, 90), 28 * dm, 15, 10, 3.0, {"meter": 4.0, "level": "high", "sfx": "hit_l"}),
		"cancel": ["heavy", "skill"], "swish": false, "shots": [6, 7, 8], "pose": {"recoil": 0.05},
		"source": "Story: she closes on Hoshino from above with MG fire (look at relevant docs); adaptation: a short level burst, since only light guns and shotguns fire down mid-jump"})

	mz = _muzzle("jH", 9)
	m["jH"] = mv("jH", 9, 8, 10, {
		"air": true, "hit": hit(Rect2(mz.x - ZONE_BACK, mz.y - 60, 240 + ZONE_BACK, 120), 42 * dm, 22, 14, 4.5, {"meter": 8.0, "hitstop": 8, "level": "high", "spark": "heavy", "sfx": "hit_h", "shake": 3.0}),
		"swish": false, "shots": [9, 10, 11, 12, 13], "pose": {"recoil": 0.08},
		"source": "Story: she closes on Hoshino from above with MG fire (look at relevant docs); adaptation: a longer, heavier level burst, since only light guns and shotguns fire down mid-jump"})

	# Close strikes, command normals and the throw. Legs and body, never the wings. None fires a round,
	# so none costs magazine. Each key is picked in Fighter._normal_key and the throw by the light + heavy chord.
	var hip := {"cancel": ["light", "heavy", "skill", "ex"]}
	m["close_L"] = mv("close_L", 6, 3, 13, hip.merged({
		"hit": hit(Rect2(20, -150, 95, 75), 26 * dm, 16, 10, 6.0, {"meter": 4.0, "sfx": "hit_l"}),
		"pose": {"lunge": 8.0, "lean": 0.1},
		"source": "adaptation: no source shows Hina striking (look at relevant docs); a shove kick for close range, where her gun zones start 116 px out (they missed Hoshino below 92 px while the push let the pair stand 74 apart) and her gun is about 1.1x her height"}))
	m["close_H"] = mv("close_H", 11, 4, 22, {
		"hit": hit(Rect2(10, -215, 95, 160), 54 * dm, 24, 15, 11.0, {"meter": 9.0, "hitstop": 9, "spark": "heavy", "sfx": "hit_h", "shake": 3.0}),
		"cancel": ["skill", "ex"], "pose": {"lunge": 14.0, "lean": 0.2},
		"source": "adaptation: no source shows Hina striking (look at relevant docs); a body check with the shoulder, the heavy answer to a foe on top of her"})
	m["6L"] = mv("6L", 9, 3, 15, hip.merged({
		"hit": hit(Rect2(24, -150, 150, 75), 30 * dm, 17, 11, 5.0, {"meter": 5.0, "sfx": "hit_l"}),
		"vx": [{"from": 6, "to": 10, "v": 3.0}], "pose": {"lunge": 16.0, "lean": 0.12},
		"source": "adaptation: no source shows Hina striking (look at relevant docs); a kick that steps in with forward held, a longer reach than the close shove"}))
	m["6H"] = mv("6H", 20, 4, 24, {
		"hit": hit(Rect2(28, -285, 105, 190), 60 * dm, 26, 16, 4.0, {"meter": 9.0, "hitstop": 9, "level": "high", "spark": "heavy", "sfx": "hit_h", "shake": 3.0}),
		"cancel": ["skill", "ex"], "pose": {"lunge": 8.0, "lean": 0.05},
		"source": "adaptation: no source shows Hina striking (look at relevant docs); a slow axe kick from above, an overhead that a crouch block loses to"})
	m["throw"] = mv("throw", 7, 3, 28, {
		"hit": hit(Rect2(0, -200, 110, 170), 70 * dm, 0, 0, 4.0, {"throw": true, "snap": 80.0, "kd": true, "launch": Vector2(6.0, 5.0), "meter": 8.0, "hitstop": 10, "spark": "heavy", "sfx": "slam", "shake": 7.0}),
		"swish": false, "pose": {"lunge": 12.0, "lean": 0.12},
		"carry": {"anim": "carried", "pivot": 76.0, "grab_stop": 4, "release": 22, "spin": 7.0, "front": true,
			"path": [[10, 63, -1, 0], [16, 64, -57, -30], [21, 70, -64, -40], [22, 76, -56, -40]]},
		"sfx": [{"frame": 13, "name": "swing", "pitch": 0.8}],
		"source": "adaptation: no source shows Hina throwing (look at relevant docs); a one-armed lift by the collar, a deadpan beat overhead and a drop in front of her, which may echo Ep.30 where Hoshino says they fell together"})

	# Sustained Burst: a 3-round burst on a tap (frames 8, 11, 14); held, it freezes at frame 15 and keeps firing
	# STREAM_ANGLES volleys every STREAM_EVERY frames for up to 36 frames (15 rounds in all; each blocked round also feeds
	# her meter in the engine, so the stream stays short). Projectile moves never cancel, so no cancel list.
	var bullet := hit(Rect2(), 12 * dm, 13, 9, 1.8, {"meter": 0.6, "hitstop": 3, "chip": 0.1})
	var bo := {"size": Vector2(30, 9), "color": col, "life": 60, "muzzle_sweep": true}
	var sk := mv("skill", 8, 8, 18, {"hold": {"btn": "skill", "at": 15, "max": 36, "fire_every": STREAM_EVERY}, "cancel": [],
		"pose": {"recoil": 0.06},
		"source": "Normal attack bursts, sustained, with faster fire from Passive: Prefect Team Member Judgment, ATK SPD +14 to 26.6 % (look at relevant docs); adaptation: hold to keep the stream going"})
	for i in 3:
		sk["spawns"].append(spawn(8 + 3 * i, _muzzle("skill", 8 + 3 * i), Vector2(22, 0.4 * (i - 1)), bullet, bo))
	for a in STREAM_ANGLES:
		var hf: Dictionary = bo.duplicate()
		hf["hold_fire"] = true
		sk["spawns"].append(spawn(15, _muzzle("skill", 15), Vector2(22, 0).rotated(deg_to_rad(a)), bullet, hf))
	m["skill"] = sk

	var sa := mv("skill_air", 8, 13, 13, {"air": true, "cancel": [], "pose": {"recoil": 0.06},
		"source": "Sustained Burst from the air: the skill's sources (look at relevant docs) plus the attack from above; adaptation: a fixed 5-round level burst, since only light guns and shotguns fire down mid-jump"})
	for i in 5:
		var spread := deg_to_rad(2.0 * float(i % 3 - 1))
		sa["spawns"].append(spawn(8 + 3 * i, _muzzle("skill_air", 8 + 3 * i), Vector2(20, 0).rotated(spread), bullet,
			{"size": Vector2(28, 12), "color": col, "life": 45, "kind": "pellet", "muzzle_sweep": true}))
	m["skill_air"] = sa

	# Super: Lock & Load. She reloads on the spot (on_move_start), which starts the damage window at once, then streams
	# faster and longer than Sustained Burst: 3 opening rounds, then two rounds every LOCK_EVERY frames.
	var su := mv("super", 8, 48, 18, {"super": true, "cancel": [], "pose": {"recoil": 0.06},
		"source": "Basic skill Lock & Load: an instant reload and ATK up (look at relevant docs); adaptation: the 50-meter super reloads at once and fires a faster, longer stream than Sustained Burst"})
	for i in 3:
		su["spawns"].append(spawn(8 + 3 * i, _muzzle("super", 8 + 3 * i), Vector2(22, 0.4 * (i - 1)), bullet, bo))
	for fr in range(15, 56, LOCK_EVERY):
		for a in STREAM_ANGLES:
			su["spawns"].append(spawn(fr, _muzzle("super", fr), Vector2(24, 0).rotated(deg_to_rad(a)), bullet, bo))
	m["super"] = su

	# Down super: Out-and-Out. A crouched burst fanned 39 to 44 degrees up, along the aimed barrel (about 35 to 48 across the two facings); the seventh round launches.
	var od := mv("super_down", 10, 20, 24, {"super": true, "crouch": true, "cancel": [], "pose": {"lean": -0.1, "recoil": 0.08},
		"source": "Sub skill Out-and-Out: extra damage against targets out of cover (look at relevant docs); adaptation: an upward anti-air burst, since nobody has cover in mid-air"})
	for i in 7:
		var opts := {"meter": 0.0, "hitstop": 4, "spark": "heavy", "sfx": "hit_h"}
		if i == 6:
			opts.merge({"hitstop": 9, "launch": Vector2(3, -16), "kd": true, "shake": 4.0}, true)
		var up := deg_to_rad(-lerpf(39.0, 44.0, float(i) / 6.0))
		od["spawns"].append(spawn(10 + 3 * i, _muzzle("super_down", 10 + 3 * i), Vector2(24, 0).rotated(up),
			hit(Rect2(), 26 * dm, 20, 12, 2.0, opts), {"size": Vector2(36, 12), "color": col, "life": 40}))
	m["super_down"] = od

	# EX: she stays on the ground and sweeps 10 rounds low to high across the fan, one every 6 frames.
	var ex := mv("ex", 8, 56, 30, {"cutin": true, "cancel": [],
		# not fully functional. the ult clip starts on her first shot frame, a guess to tune by ear
		"sfx": [{"frame": 8, "name": "ult"}],
		"pose": {"recoil": 0.05},
		"source": "EX: Denouement: Ishbosheth, 10 hits in a narrow 30 degree fan, long firing time, grounded, wings spread; firing it as Lock & Load triggers cancels the skill (look at relevant docs); adaptation: the fan is a low-to-high sweep centred a little above level so it lands from hip height in a side view; the 10 rounds come off the magazine (no source shows the EX using ammo) so it feeds Lock & Load, and it ends a running Lock & Load, not only one that triggers with it, so the buff never multiplies the EX"})
	for i in 10:
		var opts := {"meter": 0.0, "hitstop": 3, "spark": "heavy", "sfx": "hit_h"}
		if i == 9:
			opts.merge({"hitstop": 10, "spark": "ex", "sfx": "boom", "launch": Vector2(7, -10), "kd": true, "shake": 6.0}, true)
		var ang := deg_to_rad(lerpf(13.0, -17.0, float(i) / 9.0))
		ex["spawns"].append(spawn(8 + 6 * i, _muzzle("ex", 8 + 6 * i), Vector2(24, 0).rotated(ang), hit(Rect2(), 29 * dm, 18, 12, 2.0, opts),
			{"size": Vector2(40, 12), "color": col, "life": 60, "muzzle_sweep": true}))
	m["ex"] = ex
	for k in m:
		var shots: Array = m[k].get("shots", [])
		if not shots.is_empty():
			m[k]["sfx"] = [{"frame": shots[0], "name": "shot"}]
	return m

func on_round_start(f: Fighter) -> void:
	f.kv["mag"] = MAG
	f.kv["held_t"] = 0
	f.kv["lock_t"] = 0
	f.kv["dash_t"] = 0
	f.kv["dash_used"] = false
	f.kv["dash_dir"] = 1
	f.kv["dash_out"] = false
	f.kv["up_free"] = false
	f.kv["glide_t"] = 0
	f.kv["anim"] = ""
	f.kv["anim_t"] = 0

func on_move_start(f: Fighter, key: String) -> void:
	f.kv["held_t"] = 0
	var rounds: int = (f.move.get("shots", []) as Array).size()
	for sp in f.move["spawns"]:
		if not sp.get("hold_fire", false):
			rounds += 1
	if key == "ex":
		f.kv["lock_t"] = 0
	if key == "super":
		f.kv["mag"] = MAG
		_lock_and_load(f)
	if rounds > 0 and key != "ex" and f.frame - int(f.kv.get("fired_t", -1000)) >= SPOOL_IDLE:
		f.sfx("spool")
	_spend(f, rounds, key != "ex")
	if DBG_COMBO:
		print("HINA start ", key, " frame ", f.frame, " mag ", f.kv["mag"], " dist ", snappedf(absf(f.foe.position.x - f.position.x), 1.0))

func on_tick(f: Fighter) -> void:
	_wings(f)
	# Sustained Burst's hold loop fires a volley each time charge_t lands on a fire frame (fighter.gd, hold).
	if f.charge_t != int(f.kv.get("held_t", 0)):
		f.kv["held_t"] = f.charge_t
		if f.charge_t % STREAM_EVERY == 1:
			_spend(f, STREAM_ANGLES.size())
	var lock_t := maxi(0, int(f.kv.get("lock_t", 0)) - 1)
	f.kv["lock_t"] = lock_t
	# Out-and-Out: nobody has cover in mid-air.
	var mult := OUT_AND_OUT if f.foe != null and not f.foe.is_grounded() else 1.0
	if mult > 1.0 and f.state == Fighter.S.ATTACK and f.move_key == "super_down":
		mult *= OUT_AND_OUT_SUPER
	f.kv["dmg_mult"] = mult * (RELOAD_MULT if lock_t > 0 else 1.0)

## Air dash and glide. The engine adds gravity after on_tick, so the dash sets vel.y to -GRAVITY and the glide caps
## the fall at GLIDE_FALL minus one tick of gravity. kv["anim"] / kv["anim_t"] tell the SD actor which anim to play in JUMP.
func _wings(f: Fighter) -> void:
	var kv := f.kv
	if f.state != Fighter.S.JUMP:
		if int(kv["dash_t"]) > 0 or bool(kv["dash_out"]):
			f.air_ok = true
			if f.state == Fighter.S.ATTACK:
				f.vel.x = float(kv["dash_dir"]) * float(f.stats["jump_dx"])
		kv["dash_t"] = 0
		kv["dash_out"] = false
		kv["anim"] = ""
		if f.is_grounded() and f.state != Fighter.S.ATTACK:
			kv["dash_used"] = false
			kv["up_free"] = false
			kv["glide_t"] = 0
		if f.state == Fighter.S.ATTACK:
			kv["up_free"] = false
		return
	if f.input.y >= 0:
		kv["up_free"] = true
	if bool(kv["dash_out"]):
		kv["dash_out"] = false
		f.vel.x = float(kv["dash_dir"]) * float(f.stats["jump_dx"])
	# fixes bug(hina): a dash on the landing tick zeroed vel.y, so _land never ran and she slid along the floor.
	if int(kv["dash_t"]) == 0 and not bool(kv["dash_used"]) and not f.is_grounded() and f.buffered("dash"):
		f.consume("dash")
		kv["dash_used"] = true
		kv["dash_t"] = DASH_TICKS
		kv["dash_dir"] = f.facing if f.input.x == 0 else f.input.x
		f.world.fx_dust(f.position, 4)
		Sfx.play("dash", 1.2, 0.7)
	if int(kv["dash_t"]) > 0:
		var age := DASH_TICKS - int(kv["dash_t"])
		f.vel.x = float(kv["dash_dir"]) * DASH_SPEED * f.speed_mult()
		f.vel.y = -Arena.GRAVITY
		f.air_ok = age >= DASH_LOCK
		kv["anim"] = "dash_air" if int(kv["dash_dir"]) == f.facing else "dash_air_back"
		kv["anim_t"] = age
		if age % 3 == 0:
			f.world.fx_afterimage(f, 3)
		kv["dash_t"] = int(kv["dash_t"]) - 1
		kv["dash_out"] = int(kv["dash_t"]) == 0
	elif f.input.y < 0 and bool(kv["up_free"]) and int(kv["glide_t"]) < GLIDE_TICKS and f.vel.y > 0.0:
		f.vel.y = minf(f.vel.y, GLIDE_FALL - Arena.GRAVITY)
		kv["anim"] = "glide"
		kv["anim_t"] = int(kv["glide_t"])
		kv["glide_t"] = int(kv["glide_t"]) + 1
	else:
		kv["anim"] = ""

func on_hit_dealt(f: Fighter, def: Fighter, _h: Dictionary, _dmg: float) -> void:
	if DBG_COMBO:
		print("HINA COMBO ", def.combo_hits, " hits ", snappedf(def.combo_dmg / float(def.stats["taken"]), 0.1), " via ", f.move_key)

## Lock & Load: rounds come off the 49-round magazine; on empty she reloads at once (the rest of a burst comes from the
## fresh belt) and starts the damage window. An EX that empties the gun only reloads: in game the EX cancels the skill
## when they coincide (look at relevant docs).
func _spend(f: Fighter, rounds: int, buff := true) -> void:
	f.kv["fired_t"] = f.frame
	var left: int = int(f.kv.get("mag", MAG)) - rounds
	if left > 0:
		f.kv["mag"] = left
		return
	f.kv["mag"] = MAG + left
	if buff:
		_lock_and_load(f, true)
	else:
		f.sfx("reload")

func _lock_and_load(f: Fighter, auto := false) -> void:
	f.kv["lock_t"] = RELOAD_BUFF
	f.world.fx_text(f.position + Vector2(0, -330), "LOCK & LOAD", Color(0.85, 0.6, 1.0))
	f.sfx("lock_and_load")
	f.voice("skill_auto" if auto else "skill")

func ai_pick(f: Fighter, foe: Fighter, dist: float, rng: RandomNumberGenerator) -> Dictionary:
	# supers below a full meter (skill and EX on one frame); a full meter keeps the ult
	if f.meter >= Arena.SUPER_COST and f.meter < Arena.EX_COST:
		if not foe.is_grounded() and dist < 300.0 and rng.randf() < 0.35:
			return {"taps": ["skill+ex"], "y": 1, "t": 60}    # Out-and-Out
		if dist > 200.0 and foe.is_grounded() and rng.randf() < 0.25:
			return {"taps": ["skill+ex"], "t": 80}            # Lock & Load
	# the EX fan lands best inside about 450 px
	if f.meter >= Arena.EX_COST and dist > 150.0 and dist < 440.0 and foe.is_grounded() and rng.randf() < 0.3:
		return {"taps": ["ex"], "t": 100}
	if not foe.is_grounded() and dist < 260.0:
		return {"taps": ["heavy"], "y": 1, "t": 42}     # Rising Fire
	# at range: hold Sustained Burst. The stream only starts after 15 frames held, so the shortest hold is 20.
	if dist > 330.0 and foe.is_grounded():
		var held := 20 + rng.randi_range(0, 32)
		return {"taps": ["skill"], "hold_btn": "skill", "hold": held, "t": held + 30}
	return {}
