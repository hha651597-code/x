class_name Rigs
extends RefCounted
## Registry of students that have a real sprite rig (assets/ba/rig/<name>/, built from the Spine standing sprite plus a joint spec).
## Everyone else is drawn with the soft-body portrait puppet (FighterView's shader path).
##
## native: which way the ART faces. 1 = the art faces/aims to the viewer's right (no flip needed when facing right);
##         -1 = the art faces left (Hina's machine gun points up-LEFT, so she is mirrored to aim forward).

const REGISTRY := {
	10005: {"rig": "hoshino", "native": 1, "motion": "res://scripts/sprites/motion_hoshino.gd"},
	10004: {"rig": "hina", "native": -1, "motion": "res://scripts/sprites/motion_hina.gd"},
}

static func info(roster_id: int) -> Dictionary:
	return REGISTRY.get(roster_id, {})

static func has_rig(roster_id: int) -> bool:
	var i: Dictionary = REGISTRY.get(roster_id, {})
	return not i.is_empty() and SpriteRig.exists(String(i["rig"]))

static func make_motion(roster_id: int) -> RigMotion:
	var i: Dictionary = REGISTRY.get(roster_id, {})
	if i.is_empty():
		return null
	var s: GDScript = load(String(i["motion"]))
	return s.new() if s else null
