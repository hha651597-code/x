class_name Movesets
extends RefCounted
## Fighter stats + move lists, derived deterministically from each student's roster data
## (weapon class, striker type, role, armour, bullet type). All frame numbers are 60 fps.
##
## A move is a Dictionary:
##   name, startup, active, recovery            frames (hitbox is live during [startup, startup+active))
##   hit            optional melee hit data (see H()); rect is relative to the feet, facing right
##   spawns[]       projectiles/effects: {frame, offset, vel, gravity, life, size, kind, hit, color, at_foe, explode}
##   vx[]           [{from, to, v}] forward velocity (px/frame, in facing direction) while the move runs
##   cancel[]       buttons that may cancel this move once it has connected (hit or block)
##   air, crouch    move requires being airborne / crouching
##   pose           puppet animation: lunge (px), lean (rad), hop (px), squash, recoil (rad)
##   cost           meter cost (the engine sets the ult and super costs);  cutin  true → super-freeze cinematic before the move starts
##   fx[]           [{frame, kind}] cues: "sight", "charge"

const SdConfig := preload("res://scripts/models/sd_config.gd")
const BULLET_COLORS := {
	"Explosion": Color(1.0, 0.62, 0.22),
	"Pierce": Color(0.62, 0.92, 1.0),
	"Mystic": Color(0.86, 0.55, 1.0),
}
# machine guns, snipers and railguns fire level mid-jump and from a crouch
const LEVEL_ONLY := ["MG", "SR", "RG"]
const REACH := {"SG": 0.92, "SMG": 0.92, "HG": 0.95, "AR": 1.0, "MG": 1.05, "SR": 1.15, "RG": 1.1, "GL": 1.0, "RL": 1.0, "MT": 1.0, "FT": 0.9}

static func stats_for(d: Dictionary) -> Dictionary:
	var st := Fighters.striker_type(d)
	var s := {
		"walk": 4.2, "walk_back": 3.4, "jump": 17.5, "jump_dx": 6.0, "dash": 11.0,
		"dmg": 1.0, "taken": 1.0, "assist_cd": 600.0, "proj_speed": 1.0, "reach": REACH.get(d["weapon"], 1.0),
		"striker": st, "color": BULLET_COLORS.get(d["bullet"], Color(1, 0.9, 0.5)),
	}
	match st:
		"Power":
			s["dmg"] = 1.12
			s["walk"] = 3.8
			s["walk_back"] = 3.1
			s["jump"] = 16.5
		"Speed":
			s["dmg"] = 0.92
			s["walk"] = 5.0
			s["walk_back"] = 4.0
			s["dash"] = 12.5
			s["jump"] = 18.5
		"Tricky":
			s["proj_speed"] = 1.12
			s["jump_dx"] = 6.6
	match d["role"]:
		"Tanker":
			s["walk"] *= 0.95
			s["taken"] = 0.95
		"Supporter":
			s["assist_cd"] = 440.0
	match d["armor"]:
		"HeavyArmor":
			s["taken"] *= 0.93
		"Unarmed":
			s["dmg"] *= 1.04
		"LightArmor":
			s["walk"] *= 1.03
	s.merge(_guard_profile(d, st), true)
	s["intro_run"] = 0   # the stage entry no longer runs in; sd.json keeps intro_run and intro_stop as dormant descriptors
	return s

## Guard by kind of character (lighter is faster with less shield and less attack, tanks the reverse).
static func _guard_profile(d: Dictionary, st: String) -> Dictionary:
	var g := {"guard_max": 100.0, "guard_delay": 60, "guard_refill": 0.5, "guard_crush": 50, "guard_jg": 4, "guard_dealt": 1.0}
	match st:
		"Speed": g.merge({"guard_max": 80.0, "guard_delay": 40, "guard_refill": 0.8, "guard_crush": 40, "guard_jg": 5, "guard_dealt": 0.85}, true)
		"Power": g.merge({"guard_max": 125.0, "guard_delay": 80, "guard_refill": 0.35, "guard_crush": 60, "guard_jg": 3, "guard_dealt": 1.2}, true)
		"Tricky": g.merge({"guard_max": 90.0, "guard_delay": 50, "guard_refill": 0.55, "guard_jg": 5}, true)
	if d["role"] == "Tanker":
		g["guard_max"] *= 1.15
		g["guard_dealt"] *= 1.05
	elif d["role"] == "Healer":
		g["guard_max"] *= 0.9
	match d["armor"]:
		"HeavyArmor": g["guard_max"] += 10.0
		"LightArmor": g["guard_refill"] *= 1.1
	return g

## Melee/projectile hit data.
static func H(rect: Rect2, dmg: float, hitstun: int, blockstun: int, push: float, opts := {}) -> Dictionary:
	var h := {
		"rect": rect, "dmg": dmg, "hitstun": hitstun, "blockstun": blockstun, "push": push,
		"launch": Vector2.ZERO, "kd": false, "meter": dmg * 0.12, "hitstop": 6, "level": "mid",
		"spark": "light", "sfx": "hit_l", "shake": 0.0, "pierce": false, "multi": 1, "chip": 0.08,
	}
	h.merge(opts, true)
	return h

static func _move(name: String, startup: int, active: int, recovery: int, opts := {}) -> Dictionary:
	var m := {
		"name": name, "startup": startup, "active": active, "recovery": recovery, "frames": startup + active + recovery,
		"hit": {}, "spawns": [], "vx": [], "cancel": [], "air": false, "crouch": false,
		"pose": {"lunge": 0.0, "lean": 0.0, "hop": 0.0, "squash": 0.0, "recoil": 0.0}, "cost": 0.0, "cutin": false, "fx": [],
	}
	m.merge(opts, true)
	m["frames"] = int(m["startup"]) + int(m["active"]) + int(m["recovery"])
	return m

static func _spawn(frame: int, offset: Vector2, vel: Vector2, hit: Dictionary, opts := {}) -> Dictionary:
	var sp := {
		"frame": frame, "offset": offset, "vel": vel, "gravity": 0.0, "life": 80, "size": Vector2(30, 10),
		"kind": "bullet", "hit": hit, "color": Color(1, 0.9, 0.5), "at_foe": false, "explode": {},
	}
	sp.merge(opts, true)
	return sp

# ── the full move list ───────────────────────────────────────────────────────
static func moves_for(d: Dictionary, st: Dictionary) -> Dictionary:
	var r: float = st["reach"]
	var dm: float = st["dmg"]
	var col: Color = st["color"]
	var mv := {}
	# Normals (shared shape, reach scaled by weapon class)
	mv["5L"] = _move("5L", 5, 3, 9, {
		"hit": H(Rect2(26, -232, 98 * r, 96), 36 * dm, 14, 9, 4.5, {"meter": 5.0, "hitstop": 6, "spark": "light", "sfx": "hit_l"}),
		"cancel": ["light", "heavy", "skill", "ex"], "pose": {"lunge": 16.0, "lean": 0.14, "hop": 0.0, "squash": 0.0, "recoil": 0.0}})
	mv["5H"] = _move("5H", 12, 4, 22, {
		"hit": H(Rect2(26, -255, 138 * r, 130), 82 * dm, 22, 14, 7.0, {"meter": 9.0, "hitstop": 9, "spark": "heavy", "sfx": "hit_h",
			"launch": Vector2(5, -9), "kd": true, "shake": 4.0}),
		"cancel": ["skill", "ex"], "vx": [{"from": 8, "to": 16, "v": 3.0}], "pose": {"lunge": 34.0, "lean": 0.26, "hop": 0.0, "squash": 0.0, "recoil": 0.0}})
	mv["2L"] = _move("2L", 6, 3, 10, {
		"crouch": true,
		"hit": H(Rect2(24, -64, 110 * r, 64), 30 * dm, 13, 8, 3.5, {"meter": 4.0, "level": "low", "spark": "light", "sfx": "hit_l"}),
		"cancel": ["light", "heavy", "skill", "ex"], "pose": {"lunge": 12.0, "lean": 0.1, "hop": 0.0, "squash": 0.0, "recoil": 0.0}})
	mv["2H"] = _move("2H", 10, 4, 24, {
		"crouch": true,
		"hit": H(Rect2(8, -290, 100, 215), 70 * dm, 24, 14, 2.0, {"meter": 8.0, "hitstop": 9, "spark": "heavy", "sfx": "hit_h",
			"launch": Vector2(1.5, -15), "kd": true, "shake": 4.0, "level": "mid"}),
		"cancel": ["ex"], "pose": {"lunge": 8.0, "lean": -0.12, "hop": 20.0, "squash": 0.0, "recoil": 0.0}})
	mv["jL"] = _move("jL", 4, 9, 6, {
		"air": true,
		"hit": H(Rect2(10, -200, 100 * r, 120), 32 * dm, 16, 11, 3.5, {"meter": 4.0, "level": "high", "spark": "light", "sfx": "hit_l"}),
		"cancel": ["heavy", "skill"], "pose": {"lunge": 10.0, "lean": 0.18, "hop": 0.0, "squash": 0.0, "recoil": 0.0}})
	mv["jH"] = _move("jH", 8, 7, 8, {
		"air": true,
		"hit": H(Rect2(14, -215, 132 * r, 150), 68 * dm, 22, 14, 5.0, {"meter": 8.0, "hitstop": 8, "level": "high", "spark": "heavy", "sfx": "hit_h",
			"launch": Vector2(5.5, 7), "kd": true, "shake": 3.0}),
		"cancel": [], "pose": {"lunge": 22.0, "lean": 0.3, "hop": 0.0, "squash": 0.0, "recoil": 0.0}})
	mv["skill"] = _skill(d, st, false)
	mv["skill_air"] = _skill(d, st, true)
	mv["ex"] = _ex(d, st)
	return mv

## Throw styles by weapon class, for every kit without its own throw (Hina and Hoshino define theirs).
## frames: startup, active, recovery. path: the foe's feet as [mf, x, y, roll] from the thrower's feet, facing right, y up negative,
## the last key being the release. No path means the old snap. dmg, launch, hitstop and shake describe the release.
## Numbers are design values; lunge and lean feed the sprite puppet (fighter_view _defs).
const THROW_STYLE_OF := {"MG": "SLAM", "RG": "SLAM", "GL": "SLAM", "SG": "HURL", "AR": "TOSS", "SMG": "SWEEP", "HG": "SWEEP", "SR": "SHOVE"}
const THROW_STYLES := {
	"SLAM": {"frames": [7, 3, 28], "dmg": 70.0, "launch": Vector2(6, 5), "hitstop": 10, "shake": 7.0, "grab_stop": 4, "spin": 12.0, "lunge": 6.0, "lean": 0.1,
		"path": [[10, 65, 0, 0], [13, 55, -26, 0], [16, 42, -48, 0], [21, 45, -53, -8], [22, 56, -34, -8]]},
	"HURL": {"frames": [8, 3, 30], "dmg": 80.0, "launch": Vector2(9.5, -4.5), "hitstop": 6, "shake": 6.0, "grab_stop": 4, "spin": 15.0, "lunge": 18.0, "lean": 0.12,
		"path": [[10, 79, -6, 0], [11, 76, -25, 0], [12, 67, -42, 0], [13, 68, -38, 0], [14, 76, -32, -8], [15, 63, -14, 22], [16, 49, -4, 52]]},
	"TOSS": {"frames": [7, 3, 28], "dmg": 72.0, "launch": Vector2(7, -6.5), "hitstop": 8, "shake": 5.0, "grab_stop": 4, "spin": 10.0, "lunge": 12.0, "lean": 0.1,
		"path": [[9, 62, 0, 0], [12, 50, -36, 0], [15, 40, -60, -10], [18, 52, -30, 25]]},
	"SWEEP": {"frames": [6, 3, 24], "dmg": 62.0, "launch": Vector2(4.5, -2.5), "hitstop": 6, "shake": 3.0, "grab_stop": 2, "spin": 25.0, "lunge": 14.0, "lean": 0.16,
		"path": [[8, 55, 0, 0], [10, 50, -12, 20], [12, 45, -8, 60]]},
	"SHOVE": {"frames": [6, 3, 28], "dmg": 56.0, "launch": Vector2(11, -3), "hitstop": 8, "shake": 4.0, "lunge": 20.0, "lean": 0.08, "path": []},
}

## The throw every kit without its own gets (Fighter.setup merges it). The weapon class picks the style (a weapon with no row
## throws as TOSS, the way the skill table treats an unknown gun as an AR). The student tunes it: startup +1 in heavy armor and
## -1 in light armor (the whole path moves with it), carry ticks +4 for a Tanker and -2 for a Supporter or Healer, damage and
## reach from the kit's stats, path size from height (0.9 at 142 cm to 1.1 at 179 cm, kept on the move as `scale`).
static func throw_for(d: Dictionary, st: Dictionary) -> Dictionary:
	var style: String = THROW_STYLE_OF.get(String(d.get("weapon", "")), "TOSS")
	var s: Dictionary = THROW_STYLES[style]
	var shift: int = {"HeavyArmor": 1, "LightArmor": -1}.get(String(d.get("armor", "")), 0)
	var extra: int = {"Tanker": 4, "Supporter": -2, "Healer": -2}.get(String(d.get("role", "")), 0)
	var k := clampf(0.9 + 0.2 * (String(d.get("height", "160cm")).to_float() - 142.0) / 37.0, 0.9, 1.1)
	var fr: Array = s["frames"]
	var m := _move("throw", int(fr[0]) + shift, int(fr[1]), int(fr[2]), {
		"hit": H(Rect2(0, -200, 105 * float(st["reach"]), 170), float(s["dmg"]) * float(st["dmg"]), 0, 0, 4.0, {"throw": true, "snap": 80.0, "kd": true,
			"launch": s["launch"], "meter": 8.0, "hitstop": s["hitstop"], "spark": "heavy", "sfx": "slam", "shake": s["shake"]}),
		"swish": false, "style": style, "scale": k,
		"pose": {"lunge": s["lunge"], "lean": s["lean"], "hop": 0.0, "squash": 0.0, "recoil": 0.0}})
	if not (s["path"] as Array).is_empty():
		var path := _throw_path(s["path"], shift, extra, k)
		m["carry"] = {"anim": "carried", "pivot": 76.0, "grab_stop": s["grab_stop"], "release": path[-1][0], "spin": s["spin"], "front": true, "path": path}
	return m

## The style's keys shifted by the startup change, re-timed so the carry lasts `extra` ticks more, x and y scaled by `k`.
static func _throw_path(base: Array, shift: int, extra: int, k: float) -> Array:
	var first := int(base[0][0])
	var span := int(base[-1][0]) - first
	var path := []
	var prev := -1
	# not fully functional. keys one tick apart cannot shrink, so a Supporter or Healer HURL keeps its length (no roster kit is one)
	for key in base:
		var t :=maxi(first + shift + roundi(float(int(key[0]) - first) * float(span + extra) / float(span)), prev + 1)
		path.append([t, float(key[1]) * k, float(key[2]) * k, float(key[3])])
		prev = t
	return path

# ── weapon-class skills (the aux button) ─────────────────────────────────────
static func _skill(d: Dictionary, st: Dictionary, air: bool) -> Dictionary:
	var dm: float = st["dmg"]
	var ps: float = st["proj_speed"]
	var col: Color = st["color"]
	var w: String = d["weapon"]
	var oy := -188.0 if not air else -150.0
	# air shots fire diagonally down, except from guns too heavy to point down mid-jump (MG, SR, RG)
	var tilt := 0.28 if air and w not in LEVEL_ONLY else 0.0
	var m: Dictionary
	match w:
		"SMG":
			m = _move("skill", 8, 22, 14)
			for i in 6:
				var v := Vector2(19.0 * ps, 0.8 * ((i % 3) - 1)).rotated(tilt)
				m["spawns"].append(_spawn(8 + 4 * i, Vector2(72, oy), v, H(Rect2(), 15 * dm, 12, 9, 2.2, {"meter": 2.0, "hitstop": 3, "chip": 0.12}),
					{"size": Vector2(24, 8), "color": col, "life": 70}))
			m["pose"] = {"lunge": 6.0, "lean": 0.05, "hop": 0.0, "squash": 0.0, "recoil": 0.06}
		"HG":
			m = _move("skill", 7, 8, 12)
			for i in 2:
				m["spawns"].append(_spawn(7 + 6 * i, Vector2(66, oy), Vector2(22.0 * ps, 0).rotated(tilt), H(Rect2(), 30 * dm, 15, 10, 3.0, {"meter": 3.0}),
					{"size": Vector2(30, 9), "color": col}))
			m["pose"] = {"lunge": 10.0, "lean": 0.08, "hop": 0.0, "squash": 0.0, "recoil": 0.1}
		"SG":
			m = _move("skill", 14, 3, 24)
			for i in 5:
				var a := deg_to_rad(-12.0 + 6.0 * i) + tilt
				m["spawns"].append(_spawn(14, Vector2(70, oy), Vector2(18.0 * ps, 0).rotated(a), H(Rect2(), 22 * dm, 17, 12, 8.0, {"meter": 2.5, "hitstop": 5}),
					{"size": Vector2(28, 20), "color": col, "life": 17, "kind": "pellet"}))
			m["pose"] = {"lunge": 14.0, "lean": 0.18, "hop": 0.0, "squash": 0.0, "recoil": 0.22}
		"SR":
			m = _move("skill", 26, 2, 26)
			m["spawns"].append(_spawn(26, Vector2(80, oy + 4), Vector2(44.0 * ps, 0).rotated(tilt), H(Rect2(), 105 * dm, 26, 16, 7.0,
				{"meter": 10.0, "hitstop": 10, "spark": "heavy", "sfx": "hit_h", "launch": Vector2(6, -8), "kd": true, "shake": 6.0}),
				{"size": Vector2(86, 12), "color": col, "life": 40, "kind": "snipe"}))
			m["fx"] = [{"frame": 6, "kind": "sight"}]
			m["pose"] = {"lunge": -8.0, "lean": -0.05, "hop": 0.0, "squash": 0.0, "recoil": 0.14}
		"MG":
			m = _move("skill", 12, 32, 22)
			for i in 8:
				m["spawns"].append(_spawn(12 + 4 * i, Vector2(78, oy + 2.0 * ((i % 3) - 1)), Vector2(18.0 * ps, 0.5 * ((i % 4) - 1.5)).rotated(tilt),
					H(Rect2(), 17 * dm, 13, 9, 2.0, {"meter": 2.0, "hitstop": 3}), {"size": Vector2(28, 9), "color": col}))
			m["vx"] = [{"from": 12, "to": 44, "v": 1.0}]
			m["pose"] = {"lunge": 8.0, "lean": 0.1, "hop": 0.0, "squash": 0.0, "recoil": 0.08}
		"GL", "RL":
			m = _move("skill", 18, 2, 24)
			var ex := {"radius": 110.0, "hit": H(Rect2(), 82 * dm, 24, 16, 6.0, {"meter": 9.0, "hitstop": 10, "spark": "heavy", "sfx": "boom",
				"launch": Vector2(5, -10), "kd": true, "shake": 6.0})}
			if w == "GL":
				m["spawns"].append(_spawn(18, Vector2(60, -190), Vector2(9.0 * ps, -12.5), H(Rect2(), 10, 10, 8, 2.0), {"gravity": 0.7, "kind": "grenade", "size": Vector2(26, 26), "color": col, "life": 120, "explode": ex}))
			else:
				m["spawns"].append(_spawn(18, Vector2(70, oy), Vector2(9.0 * ps, 0), H(Rect2(), 10, 10, 8, 2.0), {"kind": "rocket", "size": Vector2(44, 16), "color": col, "life": 120, "explode": ex}))
			m["pose"] = {"lunge": -6.0, "lean": 0.0, "hop": 0.0, "squash": 0.0, "recoil": 0.12}
		"RG":
			m = _move("skill", 28, 2, 28)
			m["spawns"].append(_spawn(28, Vector2(70, oy), Vector2.ZERO, H(Rect2(), 100 * dm, 26, 16, 7.0, {"meter": 10.0, "hitstop": 10, "spark": "heavy", "sfx": "hit_h",
				"launch": Vector2(6, -9), "kd": true, "shake": 7.0}), {"size": Vector2(1100, 44), "kind": "beam", "life": 9, "color": col}))
			m["fx"] = [{"frame": 4, "kind": "charge"}]
			m["pose"] = {"lunge": -10.0, "lean": -0.06, "hop": 0.0, "squash": 0.04, "recoil": 0.16}
		"MT":
			m = _move("skill", 18, 2, 22)
			var ex2 := {"radius": 120.0, "hit": H(Rect2(), 90 * dm, 24, 16, 6.0, {"meter": 9.0, "hitstop": 10, "spark": "heavy", "sfx": "boom", "launch": Vector2(4, -10), "kd": true, "shake": 6.0})}
			m["spawns"].append(_spawn(40, Vector2(0, -760), Vector2(0, 22), H(Rect2(), 10, 10, 8, 2.0), {"kind": "shell", "size": Vector2(24, 40), "color": col, "life": 90, "at_foe": true, "explode": ex2}))
			m["pose"] = {"lunge": -6.0, "lean": 0.0, "hop": 0.0, "squash": 0.0, "recoil": 0.1}
		"FT":
			m = _move("skill", 8, 26, 16)
			for i in 6:
				m["spawns"].append(_spawn(8 + 4 * i, Vector2(80, oy + 20), Vector2(9.0, 0), H(Rect2(), 14 * dm, 11, 8, 1.5, {"meter": 1.5, "hitstop": 2}),
					{"size": Vector2(70, 40), "color": Color(1, 0.55, 0.2), "life": 20, "kind": "flame"}))
			m["pose"] = {"lunge": 8.0, "lean": 0.1, "hop": 0.0, "squash": 0.0, "recoil": 0.05}
		_:  # AR and anything unknown: three-round burst
			m = _move("skill", 12, 10, 16)
			for i in 3:
				m["spawns"].append(_spawn(12 + 4 * i, Vector2(78, oy), Vector2(17.0 * ps, 0).rotated(tilt), H(Rect2(), 26 * dm, 17, 12, 3.0, {"meter": 3.0, "hitstop": 4}),
					{"size": Vector2(34, 10), "color": col, "life": 70}))
			m["pose"] = {"lunge": 8.0, "lean": 0.08, "hop": 0.0, "squash": 0.0, "recoil": 0.1}
	m["air"] = air
	m["frames"] = int(m["startup"]) + int(m["active"]) + int(m["recovery"])
	m["cancel"] = ["ex"]
	return m

# ── EX skill (the super, aux2) ───────────────────────────────────────────────
static func _ex(d: Dictionary, st: Dictionary) -> Dictionary:
	var dm: float = st["dmg"] * 1.0
	var col: Color = st["color"]
	var w: String = d["weapon"]
	var m: Dictionary
	var big := {"meter": 0.0, "hitstop": 5, "spark": "heavy", "sfx": "hit_h"}
	match w:
		"SR":  # piercing shot
			m = _move("ex", 6, 2, 34, {"cutin": true})
			m["spawns"].append(_spawn(6, Vector2(80, -190), Vector2(60, 0), H(Rect2(), 190 * dm, 30, 20, 8.0,
				{"meter": 0.0, "hitstop": 14, "spark": "ex", "sfx": "boom", "launch": Vector2(8, -10), "kd": true, "shake": 10.0, "pierce": true}),
				{"size": Vector2(1000, 40), "kind": "beam", "life": 12, "color": col}))
		"SG":  # double blast cone
			m = _move("ex", 6, 12, 30, {"cutin": true})
			for k in 2:
				for i in 9:
					var a := deg_to_rad(-20.0 + 5.0 * i)
					m["spawns"].append(_spawn(6 + 8 * k, Vector2(70, -180), Vector2(20, 0).rotated(a), H(Rect2(), 20 * dm, 18, 14, 9.0,
						{"meter": 0.0, "hitstop": 4, "spark": "heavy", "kd": k == 1, "launch": Vector2(7, -9) if k == 1 else Vector2.ZERO}),
						{"size": Vector2(34, 26), "kind": "pellet", "life": 24, "color": col}))
		"RG":  # sustained mega beam
			m = _move("ex", 10, 34, 30, {"cutin": true})
			for i in 5:
				m["spawns"].append(_spawn(10 + 7 * i, Vector2(70, -185), Vector2.ZERO, H(Rect2(), 36 * dm, 20, 16, 4.0,
					{"meter": 0.0, "hitstop": 3, "spark": "heavy", "kd": i == 4, "launch": Vector2(7, -9) if i == 4 else Vector2.ZERO, "shake": 3.0}),
					{"size": Vector2(1200, 80), "kind": "beam", "life": 8, "color": col}))
		"GL", "RL", "MT":  # bombardment: shells rain across the arena
			m = _move("ex", 6, 40, 30, {"cutin": true})
			var ex := {"radius": 130.0, "hit": H(Rect2(), 56 * dm, 22, 16, 6.0, {"meter": 0.0, "hitstop": 6, "spark": "heavy", "sfx": "boom", "launch": Vector2(4, -10), "kd": true, "shake": 5.0})}
			for i in 5:
				m["spawns"].append(_spawn(14 + 9 * i, Vector2(-300 + 150 * i, -760), Vector2(0, 24), H(Rect2(), 5, 5, 5, 1.0),
					{"kind": "shell", "size": Vector2(26, 44), "life": 90, "color": col, "explode": ex, "rel_owner": true}))
			m["spawns"].append(_spawn(6, Vector2(0, -760), Vector2(0, 24), H(Rect2(), 5, 5, 5, 1.0), {"kind": "shell", "size": Vector2(26, 44), "life": 90, "color": col, "explode": ex, "at_foe": true}))
		_:  # barrage (AR / SMG / MG / HG)
			m = _move("ex", 6, 48, 30, {"cutin": true})
			for i in 16:
				m["spawns"].append(_spawn(6 + 3 * i, Vector2(78, -188 + 14.0 * sin(i * 1.7)), Vector2(24, 0.7 * sin(i * 2.3)), H(Rect2(), 24 * dm, 16, 12, 3.5,
					{"meter": 0.0, "hitstop": 3, "kd": i == 15, "launch": Vector2(7, -9) if i == 15 else Vector2.ZERO, "shake": 2.0 if i == 15 else 0.0}),
					{"size": Vector2(40, 12), "color": col, "life": 70}))
	m["pose"] = {"lunge": 0.0, "lean": 0.0, "hop": 0.0, "squash": 0.0, "recoil": 0.08}
	m["cancel"] = []
	m["frames"] = int(m["startup"]) + int(m["active"]) + int(m["recovery"])
	return m

# ── assists (the "Special" student) ──────────────────────────────────────────
## kind: volley | guard | heal | buff | strike.  Returns {kind, name, color, cooldown_scale, spawns[]}
static func assist_for(sp: Dictionary) -> Dictionary:
	var role: String = sp.get("role", "DamageDealer")
	var col: Color = BULLET_COLORS.get(sp.get("bullet", "Pierce"), Color(0.6, 0.9, 1))
	match role:
		"Tanker":
			return {"kind": "guard", "name": "Shield Wall", "color": col}
		"Healer":
			return {"kind": "heal", "name": "First Aid", "color": Color(0.5, 1.0, 0.7)}
		"Supporter":
			return {"kind": "buff", "name": "Tactical Support", "color": Color(1.0, 0.85, 0.35)}
		"Vehicle":
			return {"kind": "strike", "name": "Rolling Strike", "color": col}
		_:
			return {"kind": "volley", "name": "Covering Fire", "color": col}
