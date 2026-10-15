extends Control
## The fight's event feed (1280x720 reference pixels): on the attacker's side the combo count with BA's Combo word, the combo's
## damage and the chip that got through a guard; over the defender the hit and guard words (BLOCK, MISS, IMMUNE, JUST GUARD,
## GUARD CRUSH); and the WARNING banner for the last 10 seconds and for a fighter under 25 percent.
## A combo shows from 2 hits, stays 1.7 s after the last one and is cleared by a single hit or reset().
## Block, just guard and guard crush are read by watching world.fighters, so no engine file has to call this. MISS and IMMUNE
## have no source in the game today: they appear only through word(). Likewise the orange (EFFECTIVE) combo tier is reached
## only by a hit dict carrying counter = true, and no engine hit sets it: the engine needs a counter-hit flag first.
## API: setup(world) · on_combo(att, def, hits, h) · word(slot, id, world_pos, chip) · reset().

const BannerScript := preload("res://scripts/fight/hud_banner.gd")

const HOLD := 1.7
const BURST_AT := 10
const BIG := 55.0                 # damage of one hit that counts as a big hit when its spark is unknown
const EDGE := 34.0
const TOP := 172.0
const NUM_H := 78.0
const ROW_Y := 263.0
const WORD_LIFE := 0.9
const WORD_W := {"block": 134.0, "block_resist": 134.0, "miss": 113.0, "immune": 174.0, "just_guard": 190.0, "guard_crush": 240.0}
const WARN_FRAMES := 600
const LOW_HP := 0.25
const WARN_CALM := 0.35           # the WARNING band's gain over a side that has a combo or chip row up

var world: Node
var _time := 0.0
var _combo := [{}, {}]
var _tot := [0.0, 0.0]     # the defender's combo damage as of each attacker's previous hit, so one hit's own damage is a difference
var _chip := [{}, {}]
var _words: Array = []
var _prev := [{}, {}]
var _frames := 1 << 30
var _chip_y := [TOP + 8.0, TOP + 8.0]
var _warn := BannerScript.new()
var _warn_queue: Array = []     # sides waiting for the one WARNING band to be free
var _warned := {}

func setup(w: Node) -> Control:
	world = w
	position = Vector2.ZERO
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn.yc = 238.0
	return self

func reset() -> void:
	_combo = [{}, {}]
	_tot = [0.0, 0.0]
	_chip = [{}, {}]
	_words.clear()
	_warned.clear()
	_warn_queue.clear()
	_warn.active = false
	_frames = 1 << 30

# ── tiers ────────────────────────────────────────────────────────────────────
## BA's numeral colour of one hit: yellow for a big hit or an EX, orange for a hit flagged counter (the engine sets none yet), white otherwise.
static func hit_tier(spark: String, dmg: float, counter := false) -> int:
	if spark == "ex" or spark == "heavy" or dmg >= BIG:
		return BaNumerals.Tier.WEAK
	return BaNumerals.Tier.EFFECTIVE if counter else BaNumerals.Tier.NORMAL

## The tier a combo shows: the loudest one it has had.
static func louder(a: int, b: int) -> int:
	var order := [BaNumerals.Tier.NORMAL, BaNumerals.Tier.EFFECTIVE, BaNumerals.Tier.WEAK]
	return a if order.find(a) >= order.find(b) else b

## Fraction of a combo's display still visible, 1 until the last 0.29 s.
static func fade_of(age: float) -> float:
	return clampf((HOLD - age) * 3.5, 0.0, 1.0)

# ── combo feed ───────────────────────────────────────────────────────────────
func on_combo(att: Object, def: Object, hits: int, h := {}) -> void:
	var idx := int(_val(att, "slot", 0)) - 1
	if idx < 0 or idx > 1:
		return
	var total := float(_val(def, "combo_dmg", 0.0))
	var before := float(_tot[idx])
	_tot[idx] = total
	if hits < 2:
		_combo[idx] = {}
		return
	var prev: Dictionary = _combo[idx]
	var first := _time
	var tier := BaNumerals.Tier.NORMAL
	var cont := not prev.is_empty() and hits > int(prev["hits"])
	if cont:
		first = float(prev["first"])
		tier = int(prev["tier"])
	var spark := str(h.get("spark", ""))
	if spark == "":
		var mv = _val(att, "move", {})
		spark = str((mv.get("hit", {}) as Dictionary).get("spark", "")) if mv is Dictionary else ""
	var last := total - before
	tier = louder(tier, hit_tier(spark, last, bool(h.get("counter", false))))
	_combo[idx] = {"hits": hits, "dmg": total, "t0": _time, "pop": _time, "first": first, "tier": tier}

func _add_chip(att_idx: int, dmg: float) -> void:
	var old: Dictionary = _chip[att_idx]
	var kept := 0.0 if old.is_empty() or _time - float(old["t0"]) > HOLD else float(old["dmg"])
	_chip[att_idx] = {"dmg": kept + dmg, "t0": _time, "pop": _time, "first": _time if kept == 0.0 else float(old["first"])}

func _row_x(left: bool, w: float, slide: float) -> float:
	return (EDGE + slide) if left else (1280.0 - EDGE - w + slide)

func _draw_icon_row(i: int, icon: String, text_value: String, tier: int, y: float, a: float, slide: float) -> void:
	var w := 42.0 + BaNumerals.width(text_value, 28.0, tier)
	var x := _row_x(i == 0, w, slide)
	BaArt.blit(self, icon, Rect2(x, y, 43, 44), Color(1, 1, 1, a))
	BaNumerals.draw(self, text_value, Vector2(x + 42.0, y + 3.0), 28.0, tier, Color(1, 1, 1, a))

func _slide(i: int, first: float) -> float:
	return (1.0 - Motion.whip(_time - first)) * 260.0 * (-1.0 if i == 0 else 1.0)

func _draw_combo(i: int) -> void:
	var cb: Dictionary = _combo[i]
	if cb.is_empty():
		return
	var a := fade_of(_time - float(cb["t0"]))
	var slide := _slide(i, float(cb["first"]))
	var hits := int(cb["hits"])
	var nstr := str(hits)
	var tier := int(cb["tier"])
	var word := BaWords.tex("combo")
	var word_w := 132.0
	var word_h := word_w * float(word.get_height()) / float(word.get_width()) if word != null else 0.0
	var nw := BaNumerals.width(nstr, NUM_H, tier)
	var x := _row_x(i == 0, nw + 12.0 + word_w, slide)
	var base := TOP + NUM_H
	var pop := 1.0 + 0.3 * pow(1.0 - minf((_time - float(cb["pop"])) / 0.25, 1.0), 2.0)
	if hits >= BURST_AT:
		var bw := nw + 110.0
		var bx := clampf(x + nw * 0.5 - bw * 0.5, 4.0, 1276.0 - bw)
		BaArt.blit(self, "Floater__Imagefont_Cri_Bg", Rect2(Vector2(bx, base - NUM_H * 0.5 - bw * 0.226), Vector2(bw, bw * 0.452)), Color(1, 1, 1, a))
	BaNumerals.draw(self, nstr, Vector2(x, base - NUM_H * pop), NUM_H * pop, tier, Color(1, 1, 1, a))
	if word != null:
		draw_texture_rect(word, Rect2(x + nw + 12.0, base - 34.0 - word_h * 0.5, word_w, word_h), false, Color(1, 1, 1, a))
	_draw_icon_row(i, "Common__Common_Attack_Icon", "%d" % int(round(float(cb["dmg"]))), BaNumerals.Tier.NORMAL, ROW_Y, a, slide)

func _draw_chip(i: int) -> void:
	var ch: Dictionary = _chip[i]
	if ch.is_empty():
		return
	_draw_icon_row(i, "Common__Common_Defense_Icon", "%d" % int(round(float(ch["dmg"]))), BaNumerals.Tier.RESIST, float(_chip_y[i]), fade_of(_time - float(ch["t0"])), _slide(i, float(ch["first"])))

# ── hit and guard words ──────────────────────────────────────────────────────
func _screen(world_pos: Vector2) -> Vector2:
	var root = world.get("world_root") if world != null else null
	if root == null:
		return world_pos
	var p: Vector2 = get_global_transform().affine_inverse() * ((root as Node2D).get_global_transform() * world_pos)
	return p.clamp(Vector2(90, 200), Vector2(1190, 650))

## A word over the defender in slot 1 or 2 at a world position (the same space as Fx floaters). A repeat restarts the word, so a
## stream of blocks does not stack. chip is the damage that got through a guard, shown beside BLOCK and kept in the feed.
func word(slot: int, id: String, world_pos: Vector2, chip := 0.0) -> void:
	if not WORD_W.has(id):
		return
	for k in range(_words.size() - 1, -1, -1):
		if _words[k]["slot"] == slot and _words[k]["id"] == id:
			_words.remove_at(k)
	_words.append({"slot": slot, "id": id, "p": _screen(world_pos), "t0": _time, "chip": int(round(chip))})
	if chip > 0.5 and (slot == 1 or slot == 2):
		_add_chip(2 - slot, chip)

func _draw_word(w: Dictionary) -> void:
	var age := _time - float(w["t0"])
	var k := age / WORD_LIFE
	var t := BaWords.tex(str(w["id"]))
	if k >= 1.0 or t == null:
		return
	var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - k * 8.0)
	var a := 1.0 if k < 0.6 else (1.0 - k) / 0.4
	var width := float(WORD_W[w["id"]]) * pop
	var size := Vector2(width, width * float(t.get_height()) / float(t.get_width()))
	var centre: Vector2 = w["p"] + Vector2(0.0, -40.0 * Motion.whip(age, 0.12, 0.6))
	draw_texture_rect(t, Rect2(centre - size * 0.5, size), false, Color(1, 1, 1, a))
	if int(w["chip"]) > 0:
		BaNumerals.draw(self, "%d" % int(w["chip"]), Vector2(centre.x + size.x * 0.5 + 6.0, centre.y - 15.0), 29.0 * pop, BaNumerals.Tier.RESIST, Color(1, 1, 1, a))

# ── watching the fighters ────────────────────────────────────────────────────
static func _val(f: Object, name: String, fallback: Variant) -> Variant:
	var v = f.get(name)
	return fallback if v == null else v

static func _read(f: Object) -> Dictionary:
	return {"state": int(_val(f, "state", -1)), "hitstop": int(_val(f, "hitstop", 0)), "hp": float(_val(f, "hp", 0.0)),
		"max_hp": float(_val(f, "max_hp", 1.0)), "crush": int(_val(f, "crush_t", 0)), "jg": bool(_val(f, "last_block_jg", false))}

## What a fighter's change between two reads means: an array of [word id, chip damage]. A block is a new BLOCK state or a rise of
## hitstop inside it (every block sets hitstop, and a just guard halves blockstun, so blockstun cannot be the mark); a crush is
## crush_t going from nothing to something. Fields a build lacks read as 0 and false.
static func guard_events(prev: Dictionary, cur: Dictionary) -> Array:
	var out: Array = []
	var block_state := int(Fighter.S.BLOCK)
	if cur["state"] == block_state and (prev["state"] != block_state or cur["hitstop"] > prev["hitstop"]):
		if cur["jg"]:
			out.append(["just_guard", 0.0])
		else:
			out.append(["block", maxf(0.0, float(prev["hp"]) - float(cur["hp"]))])
	if cur["crush"] > 0 and prev["crush"] == 0:
		out.append(["guard_crush", 0.0])
	return out

## Where a word sits over its fighter: the block at the spark's height, the others where the guard branch floats its text.
static func word_offset(id: String, facing: float) -> Vector2:
	match id:
		"just_guard": return Vector2(0.0, -300.0)
		"guard_crush": return Vector2(0.0, -330.0)
	return Vector2(-facing * 50.0, -250.0)

func _watch(i: int) -> void:
	var f: Object = world.fighters[i]
	var cur := _read(f)
	var prev: Dictionary = _prev[i]
	_prev[i] = cur
	if prev.is_empty():
		return
	var at: Vector2 = _val(f, "position", Vector2.ZERO)
	for ev in guard_events(prev, cur):
		word(i + 1, str(ev[0]), at + word_offset(str(ev[0]), float(_val(f, "facing", 1))), float(ev[1]))
	var was := float(prev["hp"]) / maxf(float(prev["max_hp"]), 1.0)
	var now := float(cur["hp"]) / maxf(float(cur["max_hp"]), 1.0)
	if str(world.get("phase")) == "fight" and was >= LOW_HP and now < LOW_HP and now > 0.0 and not _warned.has("low%d" % i):
		_warned["low%d" % i] = true
		_warn_queue.append(i + 1)

## The WARNING band steps back over a side where a combo or chip row is up, so the two never read as one smear.
func _warn_gain(delta: float) -> float:
	var busy := false
	for i in 2:
		if _warn.side in [0, i + 1] and not ((_combo[i] as Dictionary).is_empty() and (_chip[i] as Dictionary).is_empty()):
			busy = true
	return move_toward(_warn.gain, WARN_CALM if busy else 1.0, delta * 4.0)

func _process(delta: float) -> void:
	if world != null and world.get("paused") == true:
		return
	_time += delta
	if world == null or world.get("fighters") == null:
		return
	var phase := str(world.get("phase"))
	if phase == "intro":
		reset()
	elif phase != "fight":
		_warn.active = false     # the K.O. and win banners own the middle of the screen
	for i in 2:
		if not (_combo[i] as Dictionary).is_empty() and _time - float(_combo[i]["t0"]) > HOLD:
			_combo[i] = {}
		if not (_chip[i] as Dictionary).is_empty() and _time - float(_chip[i]["t0"]) > HOLD:
			_chip[i] = {}
		_watch(i)
		var rest := ROW_Y + 52.0 if not (_combo[i] as Dictionary).is_empty() else TOP + 8.0
		_chip_y[i] = rest if (_chip[i] as Dictionary).is_empty() else lerpf(float(_chip_y[i]), rest, 1.0 - exp(-delta * 20.0))
	_words = _words.filter(func(w: Dictionary) -> bool: return _time - float(w["t0"]) < WORD_LIFE)
	var frames := int(_val(world, "timer_frames", 1 << 30))
	if phase == "fight" and not bool(_val(world, "training", false)) and _frames > WARN_FRAMES and frames <= WARN_FRAMES and not _warned.has("time"):
		_warned["time"] = true
		_warn_queue.append(0)
	_frames = frames
	if phase == "fight" and not _warn.active and not _warn_queue.is_empty():
		_warn.side = _warn_queue.pop_front()
		_warn.start("WARNING", "", Color.WHITE, 2.0, _time)
	_warn.gain = _warn_gain(delta)
	queue_redraw()

func _draw() -> void:
	_warn.draw(self, _time)
	for i in 2:
		_draw_combo(i)
		_draw_chip(i)
	for w in _words:
		_draw_word(w)
