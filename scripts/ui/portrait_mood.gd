extends RefCounted
## Which face a HUD portrait card shows. The hp level drops at DOWN and climbs back only at the matching UP edge, so a
## heal or a hit hovering on an edge does not flip the face. UP is written out: 0.80 + 0.05 is 0.8500000000000001.
## Precedence: ko, win, flinch, then the hp level.

const CRITICAL_BELOW := 0.25     # hud_top.LOW_HP, the nearly-dead emote's edge
const DOWN := [0.80, 0.55, CRITICAL_BELOW]
const UP := [0.85, 0.60, 0.30]
const BIG_HIT := 0.12            # one drop of this share of max hp shows the flinch face
const FLINCH_SECONDS := 0.35
const SHAKE_PX := 3.0
const KEYS := ["calm", "scratched", "hurt", "critical"]
## The files tried for a state, in order; calm is the existing portrait.
const CHAIN := {
	"calm": ["calm"],
	"scratched": ["scratched", "calm"],
	"hurt": ["hurt", "scratched", "calm"],
	"critical": ["critical", "hurt", "scratched", "calm"],
	"flinch": ["flinch", "hurt", "scratched", "calm"],
	"ko": ["ko", "critical", "hurt", "scratched", "calm"],
	"win": ["win", "calm"],
	"lose": ["lose", "critical", "hurt", "scratched", "calm"],
}

static func level(prev: int, ratio: float) -> int:
	var l := prev
	while l < KEYS.size() - 1 and ratio < float(DOWN[l]):
		l += 1
	while l > 0 and ratio >= float(UP[l - 1]):
		l -= 1
	return l

## A drop from prev to ratio that is a flinch. The margin is the HUD's own 0.0005 hp noise floor.
static func big_hit(prev: float, ratio: float) -> bool:
	return prev - ratio >= BIG_HIT - 0.0005

static func state(lvl: int, ratio: float, flinch_left: float, won: bool) -> String:
	if ratio <= 0.0:
		return "ko"
	if won:
		return "win"
	if flinch_left > 0.0:
		return "flinch"
	return KEYS[lvl]

## Offset of the card's face while it flinches: 3 px left and right every 1/30 s.
static func shake(time: float) -> Vector2:
	return Vector2(SHAKE_PX if int(time * 30.0) % 2 == 0 else -SHAKE_PX, 0.0)
