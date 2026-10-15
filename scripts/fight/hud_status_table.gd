extends RefCounted
## Which status badges a fighter shows. One row per badge: its Combat_Icon_* sprite, its place in BA's colour grammar
## (buff red, cc purple, debuff blue, special yellow: the sprite carries the colour) and a test on the fighter. A kit gets
## a badge by adding a row; a field the fighter lacks means no badge, never an error.
## A guard crush has no row: the guard disc already turns into the stunned badge (hud_top.gd).

const ICON := "Combat__Combat_Icon_"

static var _rows: Array = []

## o.get(name), or fallback when the object has no such field.
static func field(o: Object, name: String, fallback: Variant) -> Variant:
	var v: Variant = o.get(name)
	return fallback if v == null else v

static func rows() -> Array:
	if _rows.is_empty():
		_rows = [
			{"id": "armor", "icon": "Buff_DEF", "kind": "buff", "when": _armored},
			{"id": "power", "icon": "Buff_ATK", "kind": "buff", "when": _powered},
			{"id": "block", "icon": "Buff_BlockRate", "kind": "buff", "when": _blocking},
			{"id": "ammo", "icon": "Buff_AmmoCount", "kind": "buff", "when": _has_mag, "count": _mag},
			{"id": "lock", "icon": "Special_Fury", "kind": "special", "when": _locked},
		]
	return _rows

## The badges f shows now: {id, icon (BaArt name), kind, count (-1 for none)}, in row order.
static func badges(f: Object) -> Array:
	var out: Array = []
	for r in rows():
		if r["when"].call(f):
			out.append({"id": r["id"], "icon": ICON + str(r["icon"]), "kind": r["kind"], "count": int(r["count"].call(f)) if r.has("count") else -1})
	return out

## A super's armor is up: the move's armor window, or the generic super's one hit before its skill goes active.
static func _armored(f: Object) -> bool:
	if int(field(f, "state", -1)) != Fighter.S.ATTACK or int(field(f, "armor_hits_left", 0)) <= 0:
		return false
	if bool(field(f, "powered", false)):
		return true
	var ar: Dictionary = field(f, "move", {}).get("armor", {})
	var mf := int(field(f, "mf", -1))
	return not ar.is_empty() and mf >= int(ar["from"]) and mf <= int(ar["to"])

static func _powered(f: Object) -> bool:
	return bool(field(f, "powered", false))

static func _blocking(f: Object) -> bool:
	return int(field(f, "state", -1)) == Fighter.S.BLOCK

static func _has_mag(f: Object) -> bool:
	return field(f, "kv", {}).has("mag")

static func _mag(f: Object) -> int:
	return int(field(f, "kv", {}).get("mag", 0))

static func _locked(f: Object) -> bool:
	return int(field(f, "kv", {}).get("lock_t", 0)) > 0
