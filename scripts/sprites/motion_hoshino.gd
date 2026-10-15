extends RigMotion
## Hoshino Takanashi (Abydos, Foreclosure Task Force president). Sleepy, unhurried, fiercely protective: she fights
## from behind her shield-case with a shotgun hanging at her side, and would rather be napping.
## Art space: she faces +x (native 1). Bones: hips/spine/chest/head, hairL/hairR, armL (hanging shotgun arm) + gun,
## armR (hand at her chin), case (the big shield on her right hip), legs. Poses are bone offsets in degrees:
## downward-hanging bones (arms, legs, gun, hair, case) swing FORWARD with NEGATIVE rotation; upward bones (spine,
## chest, head) lean forward with POSITIVE rotation.

# her left foot is lifted in the standing art; lower it so both soles sit on the ground
const STAND := {"shinL": [0.0, 0.0, 26.0], "footL": [0.0, 0.0, 36.0]}

func sample(t: float, mff: float) -> Dictionary:
	var S := Fighter.S
	var p := {}
	add(p, STAND)
	var face := "17_boring"
	var rate := 12.0
	var closed := false
	match L.state:
		S.IDLE, S.INTRO:
			add(p, _idle(t))
			face = "17_boring" if sin(t * 0.37) > -0.25 else "01_normal"
		S.WALK:
			add(p, _walk(t))
			face = "00_default"
			rate = 16.0
		S.CROUCH:
			add(p, _crouch(1.0))
			face = "05_serious"
			rate = 20.0
		S.JUMP:
			add(p, _air())
			face = "02_respond"
			rate = 18.0
		S.DASH:
			add(p, {"spine": [16, 0, 0], "chest": [8, 0, 0], "head": [-4, 0, 0], "thighR": [-30, 0, 0], "shinR": [28, 0, 0], "thighL": [24, 0, 0],
				"armL_up": [18, 0, 0], "case": [14, 0, 0], "hairL": [20, 0, 0], "hairR": [-10, 0, 0], "hips": [0, 10, 0]})
			face = "06_shout"
			rate = 24.0
		S.BACKDASH:
			add(p, {"spine": [-10, 0, 0], "head": [-8, 0, 0], "thighR": [20, 0, 0], "thighL": [-14, 0, 0], "armL_up": [-12, 0, 0], "hairL": [-14, 0, 0], "hips": [0, -10, -10]})
			face = "07_difficult 1"
			rate = 24.0
		S.ATTACK:
			var r := _attack(mff)
			add(p, r["pose"])
			face = r.get("face", "06_shout")
			rate = float(r.get("rate", 26.0))
			closed = bool(r.get("closed", false))
		S.HIT:
			add(p, {"spine": [-14, 0, 0], "chest": [-10, 0, 0], "head": [-16, 0, 0], "hips": [0, -14, 2], "armL_up": [12, 0, 0], "gun": [10, 0, 0], "case": [8, 0, 0],
				"hairL": [22, 0, 0], "hairR": [-18, 0, 0], "thighR": [8, 0, 0], "thighL": [-6, 0, 0]})
			face = "13_worry"
			rate = 30.0
		S.AIRHIT:
			add(p, {"armL_up": [34, 0, 0], "armL_lo": [20, 0, 0], "armR_up": [-30, 0, 0], "thighL": [-40, 0, 0], "thighR": [30, 0, 0], "shinL": [30, 0, 0],
				"spine": [-10, 0, 0], "head": [-14, 0, 0], "hairL": [30, 0, 0], "hairR": [-26, 0, 0], "case": [-20, 0, 0]})
			face = "09_difficult 3"
			rate = 26.0
		S.BLOCK:
			add(p, {"case": [-40, 0, 0], "armR_up": [-22, 0, 0], "armR_lo": [-10, 0, 0], "spine": [4, 0, 0], "head": [-4, 0, 0], "hips": [0, -6, 4], "thighR": [-6, 0, 0]})
			face = "05_serious"
			rate = 30.0
		S.DOWN, S.KO:
			add(p, {"armL_up": [20, 0, 0], "armR_up": [-14, 0, 0], "thighL": [-8, 0, 0], "thighR": [10, 0, 0], "hairL": [14, 0, 0], "hairR": [-14, 0, 0], "head": [-10, 0, 0]})
			face = "10_shy 1" if L.state == S.KO else "04_embarrased"
			closed = true
			rate = 14.0
		S.GETUP:
			add(p, {"spine": [8, 0, 0], "head": [10, 0, 0], "armL_up": [-10, 0, 0]})
			face = "01_normal"
		S.WIN:
			var w := sin(t * 6.0)
			add(p, {"armR_up": [-60, 0, 0], "armR_lo": [-20 + 18 * w, 0, 0], "spine": [-3, 0, 0], "head": [-4 + 2 * w, 0, 0], "hairL": [6 * w, 0, 0], "hairR": [-6 * w, 0, 0],
				"hips": [0, 0, -6 * absf(sin(t * 3.0))], "case": [-6, 0, 0]})
			face = "03_smile" if sin(t * 1.1) > -0.3 else "14_ calm smile"
			rate = 14.0
	return {"pose": p, "face": face, "rate": rate, "blink": not closed, "closed": closed}

func _idle(t: float) -> Dictionary:
	var b := sin(t * 1.9)
	var sw := sin(t * 0.9)
	return {
		"spine": [0.8 + 1.2 * b, 0, 0], "chest": [1.0 * b, 0, 0], "head": [3.0 + 1.6 * sin(t * 0.7), 0, 0],
		"hairL": [2.6 * sin(t * 1.3 + 1.0), 0, 0], "hairR": [-2.6 * sin(t * 1.1), 0, 0],
		"armL_up": [1.4 * sw, 0, 0], "gun": [1.8 * sin(t * 1.0 + 0.5), 0, 0], "case": [1.2 * sin(t * 0.8), 0, 0],
		"hips": [0, 1.5 * sw, 0.6 * b],
	}

func _walk(t: float) -> Dictionary:
	var dirn := 1.0 if L.vel.x * float(L.facing) >= 0.0 else -1.0
	var ph := t * 7.5 * dirn
	var s := sin(ph)
	var c := cos(ph)
	return {
		"thighR": [-24 * s, 0, 0], "shinR": [34 * maxf(0.0, c), 0, 0], "footR": [-6 * s, 0, 0],
		"thighL": [24 * s, 0, 0], "shinL": [34 * maxf(0.0, -c), 0, 0], "footL": [6 * s, 0, 0],
		"hips": [0, 0, -5.0 * absf(c)], "spine": [3.0, 0, 0], "head": [2.0 - 2.0 * c, 0, 0],
		"armL_up": [10 * s, 0, 0], "gun": [4 * s, 0, 0], "case": [-5 * s, 0, 0],
		"hairL": [8 * s + 6, 0, 0], "hairR": [-8 * s, 0, 0],
	}

func _crouch(k: float) -> Dictionary:
	return {
		"hips": [0, 0, 86 * k], "thighL": [-52 * k, 0, 0], "shinL": [84 * k, 0, 0], "footL": [-34 * k, 0, 0],
		"thighR": [-52 * k, 0, 0], "shinR": [84 * k, 0, 0], "footR": [-34 * k, 0, 0],
		"spine": [10 * k, 0, 0], "chest": [6 * k, 0, 0], "head": [-8 * k, 0, 0],
		"armL_up": [-6 * k, 0, 0], "case": [-8 * k, 0, 0],
	}

func _air() -> Dictionary:
	if L.vel.y < 0.0:
		return {"thighL": [-30, 0, 0], "shinL": [55, 0, 0], "thighR": [-50, 0, 0], "shinR": [70, 0, 0], "footR": [-20, 0, 0],
			"armL_up": [-14, 0, 0], "case": [-12, 0, 0], "spine": [3, 0, 0], "head": [-4, 0, 0], "hairL": [6, 0, 0], "hairR": [-4, 0, 0]}
	return {"thighL": [-8, 0, 0], "thighR": [-20, 0, 0], "shinR": [14, 0, 0], "armL_up": [-22, 0, 0], "case": [-18, 0, 0],
		"hairL": [26, 0, 0], "hairR": [-24, 0, 0], "spine": [2, 0, 0]}

# ── moves ────────────────────────────────────────────────────────────────────
func _attack(mff: float) -> Dictionary:
	var ph := phases(mff)
	var w := float(ph["w"])
	var s := float(ph["s"])
	var key := L.move_key
	var wind := {}
	var strike := {}
	var base := {}
	var face := "06_shout"
	var rate := 28.0
	var closed := false
	match key:
		"5L":  # lazy gun sweep: the hanging shotgun swings up and across at knee-to-waist height
			face = "02_respond"
			wind = {"armL_up": [16, 0, 0], "armL_lo": [8, 0, 0], "gun": [6, 0, 0], "spine": [-5, 0, 0], "chest": [-3, 0, 0], "head": [-2, 0, 0], "hips": [0, -6, 0]}
			strike = {"armL_up": [-62, 0, 0], "armL_lo": [-34, 0, 0], "gun": [-18, 0, 0], "spine": [7, 0, 0], "chest": [5, 0, 0], "head": [3, 0, 0], "hips": [0, 14, 0], "hairL": [8, 0, 0]}
		"5H":  # case bash: she throws her whole weight (and the shield) forward
			face = "12_shout 2"
			wind = {"case": [26, 0, 0], "hips": [0, -16, 0], "spine": [-9, 0, 0], "chest": [-6, 0, 0], "armR_up": [10, 0, 0], "head": [-3, 0, 0]}
			strike = {"case": [-58, 0, 0], "armR_up": [-26, 0, 0], "armR_lo": [-22, 0, 0], "spine": [14, 0, 0], "chest": [10, 0, 0], "head": [8, 0, 0], "hips": [0, 34, 4],
				"armL_up": [-10, 0, 0], "hairL": [12, 0, 0], "hairR": [-12, 0, 0], "thighR": [-14, 0, 0], "thighL": [10, 0, 0]}
		"2L":
			face = "07_difficult 1"
			base = _crouch(0.9)
			wind = {"armL_up": [10, 0, 0]}
			strike = {"armL_up": [-52, 0, 0], "armL_lo": [-30, 0, 0], "gun": [-14, 0, 0], "hips": [0, 8, 0]}
		"2H":  # shield rise: from a crouch she heaves the case up and forward (anti-air)
			face = "06_shout"
			base = _crouch(0.8)
			wind = {"case": [14, 0, 0], "hips": [0, 0, 10]}
			strike = {"case": [-118, 0, 0], "armR_up": [-52, 0, 0], "armR_lo": [-30, 0, 0], "spine": [-6, 0, 0], "hips": [0, 6, -80], "thighL": [50, 0, 0], "shinL": [-80, 0, 0], "footL": [34, 0, 0],
				"thighR": [50, 0, 0], "shinR": [-80, 0, 0], "footR": [34, 0, 0]}
		"jL":
			face = "02_respond"
			base = _air()
			wind = {"armL_up": [10, 0, 0]}
			strike = {"armL_up": [-48, 0, 0], "armL_lo": [-24, 0, 0], "gun": [-20, 0, 0], "spine": [5, 0, 0]}
		"jH":
			face = "12_shout 2"
			base = _air()
			wind = {"case": [20, 0, 0], "spine": [-6, 0, 0]}
			strike = {"case": [-62, 0, 0], "spine": [16, 0, 0], "chest": [8, 0, 0], "thighL": [-30, 0, 0], "thighR": [-34, 0, 0], "shinL": [40, 0, 0], "shinR": [40, 0, 0]}
		"skill", "skill_air":  # shotgun blast from the hip: raise, fire, recoil, pump
			face = "06_shout"
			if key == "skill_air":
				base = _air()
			wind = {"armL_up": [-52, 0, 0], "armL_lo": [-24, 0, 0], "gun": [-6, 0, 0], "spine": [5, 0, 0], "chest": [4, 0, 0], "head": [-2, 0, 0]}
			strike = {"armL_up": [-58, 0, 0], "armL_lo": [-26, 0, 0], "gun": [-8, 0, 0], "spine": [-10, 0, 0], "chest": [-6, 0, 0], "head": [-8, 0, 0], "hips": [0, -18, 0],
				"hairL": [18, 0, 0], "hairR": [-12, 0, 0], "thighL": [8, 0, 0], "thighR": [-8, 0, 0]}
			if float(ph["r"]) > 0.0:
				strike["armL_lo"] = [-26 + 12 * sin(mff * 0.9), 0, 0]
		"counter":  # raise the case and wait for the hit
			face = "05_serious"
			base = {"case": [-44, 0, 0], "armR_up": [-24, 0, 0], "armR_lo": [-14, 0, 0], "spine": [3, 0, 0], "head": [-4, 0, 0], "hips": [0, -8, 6]}
		"counter_blast":
			face = "12_shout 2"
			wind = {"case": [-30, 0, 0], "armL_up": [-46, 0, 0], "armL_lo": [-20, 0, 0]}
			strike = {"armL_up": [-60, 0, 0], "armL_lo": [-26, 0, 0], "case": [-56, 0, 0], "spine": [-12, 0, 0], "hips": [0, -22, 0], "head": [-10, 0, 0], "hairL": [22, 0, 0]}
		"nap":  # sits behind the case and dozes, recovering
			face = "17_boring"
			closed = true
			base = _crouch(1.0)
			base["head"] = [34, 0, 0]
			base["spine"] = [18, 0, 0]
			base["case"] = [-30, 0, 0]
			rate = 8.0
		"ex":  # Tactical Suppression: the case flares open, shotgun up, everything forward
			face = "12_shout 2"
			wind = {"armL_up": [-56, 0, 0], "armL_lo": [-22, 0, 0], "case": [-50, 0, 0], "spine": [-4, 0, 0], "head": [-4, 0, 0], "hairL": [26, 0, 0], "hairR": [-26, 0, 0]}
			strike = {"armL_up": [-62, 0, 0], "armL_lo": [-26, 0, 0], "gun": [-8, 0, 0], "case": [-58, 0, 0], "spine": [-14, 0, 0], "chest": [-8, 0, 0], "head": [-10, 0, 0],
				"hips": [0, -24, 0], "hairL": [34, 0, 0], "hairR": [-34, 0, 0]}
			if float(ph["s"]) > 0.5:
				strike["hips"] = [0, -24 + 4.0 * sin(mff * 1.7), 0]
		_:
			face = "06_shout"
			wind = {"spine": [-4, 0, 0]}
			strike = {"spine": [8, 0, 0], "armL_up": [-30, 0, 0]}
	var out := {}
	add(out, base)
	add(out, wind, w)
	add(out, strike, s)
	return {"pose": out, "face": face, "rate": rate, "closed": closed}
