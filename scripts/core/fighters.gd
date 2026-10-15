class_name Fighters
extends RefCounted
## Fighter data helpers on top of assets/ba/roster.json (loaded by Game).
##
## Striker Type (the reference shows Standard / Power / Speed / Tricky) is derived from weapon + role:
##   Tanker role, SG, MG, RG, RL -> Power      SMG, HG, FT -> Speed
##   SR, GL, MT -> Tricky                      AR / anything else -> Standard
## Ease Of Use is "Hard" for SR/GL/MT/RG weapons and Healer/Supporter roles, otherwise "Normal".

const NAME_OVERRIDES := {}
const GRID_ROWS := [3]    # Hina, the random tile, Hoshino
const RANDOM_ROW := 0
const RANDOM_COL := 1

static func display_name(s: Dictionary) -> String:
	return NAME_OVERRIDES.get(s["name"], s["name"])

static func striker_type(s: Dictionary) -> String:
	if s["role"] == "Tanker":
		return "Power"
	match s["weapon"]:
		"SG", "MG", "RG", "RL":
			return "Power"
		"SMG", "HG", "FT":
			return "Speed"
		"SR", "GL", "MT":
			return "Tricky"
	return "Standard"

static func ease_of_use(s: Dictionary) -> String:
	if s["weapon"] in ["SR", "GL", "MT", "RG"] or s["role"] in ["Healer", "Supporter"]:
		return "Hard"
	return "Normal"

## The grid as rows: a roster fighter Dictionary, or the String "random" at RANDOM_ROW / RANDOM_COL.
static func build_grid(fighters: Array) -> Array:
	var rows := []
	var i := 0
	for r in GRID_ROWS.size():
		var row := []
		for c in GRID_ROWS[r]:
			if r == RANDOM_ROW and c == RANDOM_COL:
				row.append("random")
			else:
				row.append(fighters[i] if i < fighters.size() else null)
				i += 1
		rows.append(row)
	return rows
