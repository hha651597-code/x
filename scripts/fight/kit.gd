class_name Kit
extends RefCounted
## A character's fighting style. The default kit is the generic weapon-class move set (movesets.gd); every student that
## has scripts/fight/kits/kit_<key>.gd (key = roster "key", e.g. kit_hoshino.gd) gets a bespoke kit instead: stats,
## moves, special mechanics, input mappings, passives, written from that student's personality (look at relevant docs).
##
## Override what you need; everything has a sane default. The Fighter calls these hooks (see fighter.gd):
##   build_stats() / build_moves(stats)      once, at setup
##   map_ground_input(f) / map_air_input(f)  before the normal button→move mapping; return a move key (after consuming the
##                                           button with f.consume("skill")) or "" to fall through
##   on_round_start(f)                       reset kit-private state (f.kv is a free Dictionary for it)
##   on_tick(f)                              every simulation frame (passives, timers, stacks, auras)
##   on_move_start(f, key)                   a move begins
##   on_hit_dealt(f, def, h, dmg)            f's attack/projectile connected (hit, not block)
##   on_block_dealt(f, def, h)               f's attack was blocked
##   on_hit_taken(f, att, h, dmg) -> float   f is about to take `dmg`; return the (possibly changed) damage
##   on_ko(f)                                f was KO'd
## Plus data: taunt/idle flavour and which sprite motion to use are handled elsewhere.

var data: Dictionary = {}

# data
func build_stats() -> Dictionary:
	return Movesets.stats_for(data)

func build_moves(stats: Dictionary) -> Dictionary:
	return Movesets.moves_for(data, stats)

# hooks
func map_ground_input(_f: Fighter) -> String:
	return ""

func map_air_input(_f: Fighter) -> String:
	return ""

func on_round_start(_f: Fighter) -> void:
	pass

func on_tick(_f: Fighter) -> void:
	pass

func on_move_start(_f: Fighter, _key: String) -> void:
	pass

func on_hit_dealt(_f: Fighter, _def: Fighter, _h: Dictionary, _dmg: float) -> void:
	pass

func on_block_dealt(_f: Fighter, _def: Fighter, _h: Dictionary) -> void:
	pass

func on_hit_taken(_f: Fighter, _att: Fighter, _h: Dictionary, dmg: float) -> float:
	return dmg

func on_ko(_f: Fighter) -> void:
	pass

## CPU hint: how the AI should use this character's own tools. Called when the AI picks a new plan.
## Return {} to let the generic AI decide, or {"taps": ["skill"], "x": -1, "y": 0, "hold": 0, "t": 24} where taps are buttons to press in
## order, x/y the direction to hold (relative: +1 = toward the foe, -1 = away; y +1 = down), `hold` frames to keep a button held after
## the tap (for hold-to-charge moves) and `t` the plan length in frames.
func ai_pick(_f: Fighter, _foe: Fighter, _dist: float, _rng: RandomNumberGenerator) -> Dictionary:
	return {}

# builders (thin public wrappers so kits don't touch Movesets internals)
## A move. opts keys: hit, spawns, vx, motion, cancel, air, crouch, pose, cost, cutin, fx, sfx, self, inv, armor, counter,
## hold, teleport (look at relevant docs).
static func mv(name: String, startup: int, active: int, recovery: int, opts := {}) -> Dictionary:
	return Movesets._move(name, startup, active, recovery, opts)

## Hit data. rect is relative to the feet, facing right: Rect2(x, y, w, h) with y negative = up.
static func hit(rect: Rect2, dmg: float, hitstun: int, blockstun: int, push: float, opts := {}) -> Dictionary:
	return Movesets.H(rect, dmg, hitstun, blockstun, push, opts)

## A projectile / effect spawn at move frame `frame`.
static func spawn(frame: int, offset: Vector2, vel: Vector2, h: Dictionary, opts := {}) -> Dictionary:
	return Movesets._spawn(frame, offset, vel, h, opts)
