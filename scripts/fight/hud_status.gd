extends Control
## One side's row of status pentagons (BA's Combat_Icon_* sprites, 28 px, a 3 px gap), read from the fighter through
## hud_status_table.gd. Up to eight, then an ellipsis. The row starts at the outer edge `origin` and runs toward the centre.
## A new badge pops in over a quarter second (UIAni_Scale_Select), no fade. Fills 1280x720, mouse ignored.

const Table := preload("res://scripts/fight/hud_status_table.gd")
const BADGE := Vector2(28.0, 32.0)
const PITCH := 31.0
const MAX := 8
const GRACE := 0.12     # a badge that drops for a tick or two (a held block between hits) stays up this long

var world: Node
var shown: Array = []     # [{id, icon, kind, count}] on screen now
var _slot := 0
var _origin := Vector2.ZERO
var _left := true
var _born := {}
var _seen := {}     # id -> {badge, t of the last tick it was live}
var _time := 0.0

func setup(w: Node, slot: int, origin: Vector2) -> Control:
	world = w
	_slot = slot
	_origin = origin
	_left = slot == 0
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self

## The pop scale of a badge `age` seconds after it appeared.
static func pop(age: float) -> float:
	if age >= 0.25:
		return 1.0
	if age < 0.067:
		return lerpf(0.8, 0.962, age / 0.067)
	return lerpf(0.962, 1.0, (age - 0.067) / 0.183)

## Where badge k sits (full size), left to right on the left side, right to left on the right side.
func slot_rect(k: int) -> Rect2:
	var x := _origin.x + PITCH * k if _left else _origin.x - BADGE.x - PITCH * k
	return Rect2(x, _origin.y, BADGE.x, BADGE.y)

func _process(delta: float) -> void:
	if world != null and world.get("paused") == true:
		return
	_time += delta
	if world == null or world.fighters.size() <= _slot:
		return
	for b in Table.badges(world.fighters[_slot]):
		_seen[b["id"]] = {"b": b, "t": _time}
	shown = []
	for r in Table.rows():
		var id: String = r["id"]
		if _seen.has(id) and _time - float(_seen[id]["t"]) <= GRACE:
			shown.append(_seen[id]["b"])
			if not _born.has(id):
				_born[id] = _time
		else:
			_seen.erase(id)
			_born.erase(id)
	queue_redraw()

func visible_count() -> int:
	return mini(shown.size(), MAX)

func has_ellipsis() -> bool:
	return shown.size() > MAX

func _draw() -> void:
	for k in visible_count():
		var b: Dictionary = shown[k]
		var r := slot_rect(k)
		var s := pop(_time - float(_born.get(b["id"], -1.0)))
		var box := Rect2(r.get_center() - r.size * s * 0.5, r.size * s)
		BaArt.blit(self, b["icon"], box)
		if int(b["count"]) >= 0:
			BaNumerals.draw(self, str(b["count"]), Vector2(box.end.x + 3.0, box.end.y - 14.0), 14.0, BaNumerals.Tier.MINI, Color.WHITE, 2)
	if has_ellipsis():
		var e := slot_rect(MAX)
		for d in 3:
			BaArt.blit(self, "Combat__Common_Line_Dot", Rect2(e.position.x + 9.0 * d, e.position.y + 20.0, 6.0, 6.0), BaTokens.INK)
