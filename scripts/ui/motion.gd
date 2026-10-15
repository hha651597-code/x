class_name Motion
extends RefCounted
## BA entrance and pulse curves, read from the game's animation clips.
## Nothing here overshoots: the real data has none. `UI.spring` stays for screens that have not been migrated.

## Progress 0..1 after `t` seconds: `share` of the travel in the fast leg, the rest settling out.
static func whip(t: float, fast := BaTokens.WHIP_FAST, settle := BaTokens.WHIP_SETTLE, share := BaTokens.WHIP_SHARE) -> float:
	if t <= 0.0:
		return 0.0
	if t < fast:
		var u := t / fast
		return share * (1.0 - (1.0 - u) * (1.0 - u))
	var s := clampf((t - fast) / settle, 0.0, 1.0)
	return share + (1.0 - share) * (1.0 - (1.0 - s) * (1.0 - s))

## Selection pulse: 1.0 at t=0, `lo` after one half cycle, back to 1.0 after two.
static func pulse(t: float, half := BaTokens.BRACKET_HALF, lo := BaTokens.BRACKET_LO) -> float:
	return lo + (1.0 - lo) * (0.5 + 0.5 * cos(PI * t / half))

## Delay of item `i` in a staggered entrance, in seconds.
static func stagger(i: int, step := BaTokens.STAGGER) -> float:
	return float(i) * step
