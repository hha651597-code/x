extends RefCounted
## Measured sockets of an SD fighter: assets/ba/sd/<roster key>/sockets.json, written by tools/sd_measure.sh (format in
## scripts/models/tools/sd_measure.gd), cached per key. Static data from the model, so the 60 Hz sim may read it; it must
## never read the live actor.

static var _cache := {}

static func of(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var data: Variant = {}
	var path := "res://assets/ba/sd/%s/sockets.json" % key
	if key != "" and FileAccess.file_exists(path):
		data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			push_error("SD sockets are not a JSON object: " + path)
			data = {}
	_cache[key] = data
	return data

## The symmetric gameplay muzzle (feet-relative, facing right) of `move_key` at `frame`, from the nearest measured frame
## of that move; `fallback` when the fighter or the move has none.
static func muzzle(key: String, move_key: String, frame: int, fallback: Vector2) -> Vector2:
	var best: Dictionary = {}
	for e in of(key).get("muzzle", {}).get(move_key, []):
		if best.is_empty() or absi(int(e["frame"]) - frame) < absi(int(best["frame"]) - frame):
			best = e
	return fallback if best.is_empty() else Vector2(best["sym"][0], best["sym"][1])

## {w, h, crouch_h} in fight px, or {} when the fighter has no sockets.json.
static func hurtbox(key: String) -> Dictionary:
	return of(key).get("hurtbox", {})

## The full width of the fighter's push cylinder in fight px, or 0 when the fighter has none (then Arena.PUSH_W applies).
static func push(key: String) -> int:
	return int(of(key).get("push", 0))
