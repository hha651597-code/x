extends RigMotion
## Sorasaki Hina (Gehenna, head of the Prefect Team). Deadpan, overworked and terrifyingly capable: she keeps her
## machine gun slung and her expression flat, and lets the demon wings do the arguing.
## Art space: the art faces/aims LEFT (native -1), so forward = -x: downward-hanging bones (legs, arms, hair, coat,
## wings at rest) swing forward with POSITIVE rotation, upward bones (spine, chest, head) lean forward NEGATIVE.
## Wings: wingR* hangs to the art's right (the BACK wing), wingL* to the art's left (the FRONT wing). Raising a wing is
## NEGATIVE for wingR*, POSITIVE for wingL*.

# her right boot is lifted in the standing art; lower it so both soles sit on the ground
const STAND := {"shinR": [0.0, 0.0, 30.0], "footR": [0.0, 0.0, 40.0]}

func sample(t: float, mff: float) -> Dictionary:
	var S := Fighter.S
	var p := {}
	add(p, STAND)
	var face := "01_nomal"
	var rate := 12.0
	var closed := false
	match L.state:
		S.IDLE, S.INTRO:
			add(p, _idle(t))
			var cyc := fposmod(t, 9.0)
			face = "05_serious" if cyc > 6.5 and cyc < 7.6 else ("14" if cyc > 3.2 and cyc < 4.0 else "01_nomal")
		S.WALK:
			add(p, _walk(t))
			face = "01_nomal"
			rate = 14.0
		S.CROUCH:
			add(p, _crouch(1.0))
			face = "05_serious"
			rate = 20.0
		S.JUMP:
			add(p, _air())
			face = "16"
			rate = 16.0
		S.DASH:
			add(p, {"spine": [-14, 0, 0], "chest": [-6, 0, 0], "head": [4, 0, 0], "thighL": [28, 0, 0], "shinL": [-26, 0, 0], "thighR": [-22, 0, 0],
				"wingR1": [-6, 0, 0], "wingR2": [-10, 0, 0], "wingR3": [-12, 0, 0], "wingL1": [-8, 0, 0], "wingL2": [-14, 0, 0], "wingL3": [-20, 0, 0],
				"coatR": [-24, 0, 0], "coatL": [-14, 0, 0], "hairR": [-14, 0, 0], "hips": [0, -10, 0]})
			face = "16"
			rate = 22.0
		S.BACKDASH:
			add(p, {"spine": [10, 0, 0], "head": [8, 0, 0], "thighL": [-14, 0, 0], "thighR": [14, 0, 0], "wingR1": [-24, 0, 0], "wingL1": [24, 0, 0], "wingR2": [-18, 0, 0], "wingL2": [18, 0, 0],
				"coatR": [18, 0, 0], "coatL": [-18, 0, 0], "hips": [0, 10, -10]})
			face = "14"
			rate = 22.0
		S.ATTACK:
			var r := _attack(mff)
			add(p, r["pose"])
			face = r.get("face", "05_serious")
			rate = float(r.get("rate", 26.0))
			closed = bool(r.get("closed", false))
		S.HIT:
			add(p, {"spine": [14, 0, 0], "chest": [10, 0, 0], "head": [16, 0, 0], "hips": [0, 14, 2], "wingR1": [16, 0, 0], "wingR2": [14, 0, 0], "wingL1": [-16, 0, 0], "wingL2": [-14, 0, 0],
				"coatR": [-14, 0, 0], "coatL": [14, 0, 0], "hairR": [-20, 0, 0], "armL_lo": [10, 0, 0]})
			face = "13"
			rate = 30.0
		S.AIRHIT:
			add(p, {"wingR1": [-40, 0, 0], "wingR2": [-30, 0, 0], "wingL1": [40, 0, 0], "wingL2": [30, 0, 0], "thighL": [30, 0, 0], "thighR": [-24, 0, 0], "shinL": [-20, 0, 0],
				"spine": [12, 0, 0], "head": [14, 0, 0], "coatR": [-30, 0, 0], "coatL": [30, 0, 0], "hairR": [-26, 0, 0], "armL_lo": [20, 0, 0]})
			face = "09"
			rate = 26.0
		S.BLOCK:
			add(p, {"wingL1": [-6, 0, 0], "wingL2": [-30, 0, 0], "wingL3": [-34, 0, 0], "wingR1": [8, 0, 0], "wingR2": [24, 0, 0], "spine": [-3, 0, 0], "head": [4, 0, 0], "hips": [0, 6, 4],
				"coatL": [10, 0, 0], "armL_lo": [-8, 0, 0]})
			face = "05_serious"
			rate = 30.0
		S.DOWN, S.KO:
			add(p, {"wingR1": [26, 0, 0], "wingR2": [20, 0, 0], "wingR3": [14, 0, 0], "wingL1": [-26, 0, 0], "wingL2": [-20, 0, 0], "wingL3": [-14, 0, 0],
				"armL_lo": [30, 0, 0], "armR_up": [-14, 0, 0], "head": [10, 0, 0], "coatL": [16, 0, 0], "coatR": [-16, 0, 0]})
			face = "10" if L.state == S.KO else "11"
			closed = true
			rate = 14.0
		S.GETUP:
			add(p, {"spine": [-8, 0, 0], "wingR1": [-14, 0, 0], "wingL1": [14, 0, 0]})
			face = "05_serious"
		S.WIN:
			var w := sin(t * 2.4)
			add(p, {"wingR1": [-26 + 6 * w, 0, 0], "wingR2": [-22 + 7 * w, 0, 0], "wingR3": [-18 + 8 * w, 0, 0], "wingL1": [26 - 6 * w, 0, 0], "wingL2": [22 - 7 * w, 0, 0], "wingL3": [18 - 8 * w, 0, 0],
				"coatR": [-10 - 4 * w, 0, 0], "coatL": [10 + 4 * w, 0, 0], "hairR": [8 * w, 0, 0], "armL_lo": [-6 + 8 * w, 0, 0], "hips": [0, 0, -7 * absf(sin(t * 1.6))], "spine": [4, 0, 0], "head": [2, 0, 0]})
			face = "08" if sin(t * 0.9) > 0.0 else "03_smile"
			rate = 14.0
	return {"pose": p, "face": face, "rate": rate, "blink": not closed, "closed": closed}

func _idle(t: float) -> Dictionary:
	var ph := t * 1.5
	var b := sin(t * 1.8)
	return {
		"wingR1": [-4 + 3 * sin(ph), 0, 0], "wingR2": [3 * sin(ph - 0.5), 0, 0], "wingR3": [4 * sin(ph - 1.0), 0, 0],
		"wingL1": [4 - 3 * sin(ph + 0.3), 0, 0], "wingL2": [-3 * sin(ph - 0.2), 0, 0], "wingL3": [-4 * sin(ph - 0.7), 0, 0],
		"coatL": [2.0 * sin(t * 1.2), 0, 0], "coatR": [-2.0 * sin(t * 1.1 + 1.0), 0, 0], "hairR": [3.0 * sin(t * 1.4), 0, 0],
		"armL_lo": [1.6 * sin(t * 2.1), 0, 0], "armR_up": [1.2 * sin(t * 1.0), 0, 0],
		"spine": [-0.6 + 0.8 * b, 0, 0], "head": [0.6 * sin(t * 0.8), 0, 0], "hips": [0, 0, 0.8 * b],
	}

func _walk(t: float) -> Dictionary:
	var dirn := 1.0 if L.vel.x * float(L.facing) >= 0.0 else -1.0
	var ph := t * 6.5 * dirn
	var s := sin(ph)
	var c := cos(ph)
	var fl2 := sin(t * 3.0)
	return {
		"thighL": [18 * s, 0, 0], "shinL": [-24 * maxf(0.0, c), 0, 0], "footL": [4 * s, 0, 0],
		"thighR": [-18 * s, 0, 0], "shinR": [-24 * maxf(0.0, -c), 0, 0], "footR": [-4 * s, 0, 0],
		"hips": [0, 0, -4.0 * absf(c)], "spine": [-4.0, 0, 0],
		"wingR1": [-8 + 6 * fl2, 0, 0], "wingR2": [-6 + 7 * fl2, 0, 0], "wingR3": [-4 + 8 * fl2, 0, 0],
		"wingL1": [8 - 6 * fl2, 0, 0], "wingL2": [6 - 7 * fl2, 0, 0], "wingL3": [4 - 8 * fl2, 0, 0],
		"coatR": [-10 * s, 0, 0], "coatL": [10 * s, 0, 0], "hairR": [-6 * s - 4, 0, 0],
	}

func _crouch(k: float) -> Dictionary:
	return {
		"hips": [0, 0, 86 * k], "thighL": [52 * k, 0, 0], "shinL": [-84 * k, 0, 0], "footL": [34 * k, 0, 0],
		"thighR": [52 * k, 0, 0], "shinR": [-84 * k, 0, 0], "footR": [34 * k, 0, 0],
		"spine": [-10 * k, 0, 0], "chest": [-6 * k, 0, 0], "head": [8 * k, 0, 0],
		"coatL": [20 * k, 0, 0], "coatR": [-20 * k, 0, 0], "wingR1": [14 * k, 0, 0], "wingL1": [-14 * k, 0, 0],
	}

func _air() -> Dictionary:
	if L.vel.y < 0.0:
		return {"wingR1": [-30, 0, 0], "wingR2": [-22, 0, 0], "wingR3": [-16, 0, 0], "wingL1": [30, 0, 0], "wingL2": [22, 0, 0], "wingL3": [16, 0, 0],
			"thighL": [26, 0, 0], "shinL": [-40, 0, 0], "thighR": [40, 0, 0], "shinR": [-50, 0, 0], "coatR": [-16, 0, 0], "coatL": [16, 0, 0], "spine": [-3, 0, 0], "hairR": [-10, 0, 0]}
	return {"wingR1": [-22, 0, 0], "wingR2": [-26, 0, 0], "wingR3": [-30, 0, 0], "wingL1": [22, 0, 0], "wingL2": [26, 0, 0], "wingL3": [30, 0, 0],
		"thighL": [8, 0, 0], "thighR": [16, 0, 0], "coatR": [-24, 0, 0], "coatL": [24, 0, 0], "hairR": [-18, 0, 0], "spine": [-2, 0, 0]}

# ── moves ────────────────────────────────────────────────────────────────────
func _attack(mff: float) -> Dictionary:
	var ph := phases(mff)
	var w := float(ph["w"])
	var s := float(ph["s"])
	var key := L.move_key
	var wind := {}
	var strike := {}
	var base := {}
	var face := "05_serious"
	var rate := 26.0
	var closed := false
	match key:
		"5L":  # wing flick with the front wing
			wind = {"wingL1": [34, 0, 0], "wingL2": [28, 0, 0], "wingL3": [22, 0, 0], "spine": [4, 0, 0], "hips": [0, 6, 0], "coatL": [8, 0, 0]}
			strike = {"wingL1": [-26, 0, 0], "wingL2": [-34, 0, 0], "wingL3": [-40, 0, 0], "spine": [-8, 0, 0], "chest": [-5, 0, 0], "head": [-3, 0, 0], "hips": [0, -12, 0], "wingR1": [8, 0, 0]}
		"5H":  # twin wing slash
			face = "06_shout"
			wind = {"wingL1": [44, 0, 0], "wingL2": [38, 0, 0], "wingL3": [30, 0, 0], "wingR1": [-34, 0, 0], "wingR2": [-28, 0, 0], "wingR3": [-22, 0, 0], "spine": [8, 0, 0], "hips": [0, 14, 0], "head": [4, 0, 0]}
			strike = {"wingL1": [-30, 0, 0], "wingL2": [-40, 0, 0], "wingL3": [-46, 0, 0], "wingR1": [24, 0, 0], "wingR2": [30, 0, 0], "wingR3": [34, 0, 0], "spine": [-14, 0, 0], "chest": [-8, 0, 0],
				"head": [-6, 0, 0], "hips": [0, -30, 0], "coatL": [18, 0, 0], "coatR": [-18, 0, 0], "hairR": [-16, 0, 0]}
		"2L":  # low coat sweep
			base = _crouch(0.9)
			wind = {"coatL": [-10, 0, 0], "wingL1": [10, 0, 0]}
			strike = {"coatL": [56, 0, 0], "coatR": [-30, 0, 0], "wingL1": [-30, 0, 0], "wingL2": [-40, 0, 0], "wingL3": [-50, 0, 0], "spine": [-6, 0, 0]}
		"2H":  # wing uppercut
			face = "06_shout"
			base = _crouch(0.8)
			wind = {"wingL1": [-24, 0, 0], "wingL2": [-30, 0, 0], "wingR1": [20, 0, 0], "hips": [0, 0, 10]}
			strike = {"wingL1": [66, 0, 0], "wingL2": [56, 0, 0], "wingL3": [48, 0, 0], "wingR1": [-56, 0, 0], "wingR2": [-48, 0, 0], "wingR3": [-40, 0, 0], "spine": [6, 0, 0],
				"hips": [0, -4, -80], "thighL": [-50, 0, 0], "shinL": [80, 0, 0], "footL": [-34, 0, 0], "thighR": [-50, 0, 0], "shinR": [80, 0, 0], "footR": [-34, 0, 0], "coatL": [20, 0, 0], "coatR": [-20, 0, 0]}
		"jL":
			base = _air()
			wind = {"wingL1": [30, 0, 0], "wingL2": [24, 0, 0]}
			strike = {"wingL1": [-30, 0, 0], "wingL2": [-36, 0, 0], "wingL3": [-40, 0, 0], "spine": [-6, 0, 0]}
		"jH":  # diving wing slam
			face = "06_shout"
			base = _air()
			wind = {"wingL1": [42, 0, 0], "wingR1": [-40, 0, 0], "spine": [6, 0, 0]}
			strike = {"wingL1": [-40, 0, 0], "wingL2": [-46, 0, 0], "wingL3": [-50, 0, 0], "wingR1": [30, 0, 0], "wingR2": [34, 0, 0], "spine": [-18, 0, 0], "chest": [-8, 0, 0], "thighL": [20, 0, 0], "thighR": [24, 0, 0]}
		"skill", "skill_air":  # Suppression Fire: braced, wings flared, the slung MG chattering
			face = "16"
			if key == "skill_air":
				base = _air()
			wind = {"wingR1": [-20, 0, 0], "wingR2": [-14, 0, 0], "wingL1": [20, 0, 0], "wingL2": [14, 0, 0], "spine": [3, 0, 0], "thighL": [8, 0, 0], "thighR": [-8, 0, 0], "hips": [0, 0, 6], "coatR": [-12, 0, 0], "coatL": [12, 0, 0]}
			strike = {"wingR1": [-26, 0, 0], "wingR2": [-18, 0, 0], "wingL1": [26, 0, 0], "wingL2": [18, 0, 0], "spine": [6, 0, 0], "head": [4, 0, 0], "hips": [0, 8, 4],
				"armL_lo": [3.0 * sin(mff * 2.2), 0, 0], "armL_up": [1.5 * sin(mff * 2.7), 0, 0], "coatR": [-16, 0, 0], "coatL": [16, 0, 0], "hairR": [-12, 0, 0]}
		"halt":  # "Stop right there": a raised glove and a flat stare
			face = "15"
			wind = {"armL_up": [10, 0, 0], "armL_lo": [10, 0, 0], "wingR1": [-14, 0, 0], "wingL1": [14, 0, 0]}
			strike = {"armL_up": [-22, 0, 0], "armL_lo": [-40, 0, 0], "wingR1": [-28, 0, 0], "wingR2": [-20, 0, 0], "wingL1": [28, 0, 0], "wingL2": [20, 0, 0], "spine": [-6, 0, 0], "head": [-3, 0, 0]}
		"ex":  # Denouement: Ishbosheth. She rises, wings wide, face in shadow.
			face = "15"
			wind = {"wingR1": [-30, 0, 0], "wingR2": [-24, 0, 0], "wingL1": [30, 0, 0], "wingL2": [24, 0, 0], "hips": [0, 0, 8], "spine": [3, 0, 0], "hairR": [-10, 0, 0]}
			strike = {"wingR1": [-38, 0, 0], "wingR2": [-34, 0, 0], "wingR3": [-30, 0, 0], "wingL1": [38, 0, 0], "wingL2": [34, 0, 0], "wingL3": [30, 0, 0],
				"hips": [0, 0, -34 - 4.0 * sin(mff * 0.6)], "spine": [4, 0, 0], "head": [6, 0, 0], "coatR": [-34, 0, 0], "coatL": [34, 0, 0], "hairR": [-26, 0, 0],
				"thighL": [4, 0, 0], "thighR": [6, 0, 0], "armL_lo": [2.0 * sin(mff * 2.0), 0, 0]}
		_:
			wind = {"spine": [4, 0, 0]}
			strike = {"spine": [-8, 0, 0], "wingL1": [-20, 0, 0]}
	var out := {}
	add(out, base)
	add(out, wind, w)
	add(out, strike, s)
	return {"pose": out, "face": face, "rate": rate, "closed": closed}
