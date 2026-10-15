class_name FxFlash
extends RefCounted
## The Reduce Flashes setting (Game.session.reduce_flashes, saved by Session) read in one place.
## Every full-screen flash, impact frame, strobing pattern and screen shake goes through here. `src` is an object to read the
## setting from instead of the session (tests).

const FLASH_CAP := 0.3      # alpha ceiling of a full-screen flash while reduced
const SHAKE_SCALE := 0.5
const IMPACT_GAP_MS := 340  # at most 3 impact frames a second

static var _last_impact_ms := -100000

static func reduced(src: Object = null) -> bool:
	var s: Object = src if src != null else Game.session
	if s == null:
		return false
	var v: Variant = s.get("reduce_flashes")
	return typeof(v) == TYPE_BOOL and v

static func flash(alpha: float, src: Object = null) -> float:
	return minf(alpha, FLASH_CAP) if reduced(src) else alpha

static func shake(amount: float, src: Object = null) -> float:
	return amount * SHAKE_SCALE if reduced(src) else amount

## `age` in steps of 1 / `hz` seconds, or one fixed step while reduced: a pattern that redraws every few ticks holds still.
static func stepped(age: float, hz: float, src: Object = null) -> float:
	return 0.0 if reduced(src) else floorf(age * hz)

## True when an impact frame may start now: not reduced, and not within IMPACT_GAP_MS of the previous one.
static func impact_ok(src: Object = null) -> bool:
	if reduced(src):
		return false
	var now := Time.get_ticks_msec()
	if now - _last_impact_ms < IMPACT_GAP_MS:
		return false
	_last_impact_ms = now
	return true
