class_name SpriteSets
extends RefCounted
## Registry of students drawn with REAL frame-by-frame sprites (assets/ba/sprites/<char>/).
## FighterView asks has_set(id): when true it builds a SpriteActor instead of the SpriteRig / portrait puppet.
##
## A character only switches to sprite playback when BOTH frames.json (baked) and anims.json
## (hand-authored) exist and anims.json does not say "enabled": false — so a half-delivered set (e.g. Hina while only her
## idle sheet exists) keeps the old rig path and the fight stays playable.

const ROOT := "res://assets/ba/sprites/"
const REGISTRY := {10005: "hoshino", 10004: "hina"}

static var _cache := {}

static func key_for(roster_id: int) -> String:
	return String(REGISTRY.get(roster_id, ""))

static func files_exist(key: String) -> bool:
	if key == "":
		return false
	return FileAccess.file_exists(ROOT + key + "/frames.json") and FileAccess.file_exists(ROOT + key + "/anims.json")

static func has_set(roster_id: int) -> bool:
	var k := key_for(roster_id)
	if not files_exist(k):
		return false
	var s := get_set(k)
	return s != null and s.enabled and not s.frames.is_empty()

static func for_id(roster_id: int) -> SpriteSet:
	return get_set(key_for(roster_id))

## Loaded once per process (textures included) and shared by both players / ghosts / the test screen.
static func get_set(key: String) -> SpriteSet:
	if key == "":
		return null
	if _cache.has(key):
		return _cache[key]
	var s := SpriteSet.load_set(key)
	_cache[key] = s
	return s

## Drop the cache (the sprite test screen uses it to pick up reloaded frames / edited anims.json without restarting).
static func clear_cache() -> void:
	_cache.clear()
