extends Screen
## Debug screen for sprite rigs: Game.go("rigtest", {"rig": "hoshino", "pose": {...}, "face": "06_shout", "zoom": 0.7}).
## `pose` is a bone -> [rot, dx, dy] dictionary (see SpriteRig). Used by the .dev/shots/rig_*.json harness files.
## With {"sprite": "<char>", "mode": ...} it opens the frame-by-frame SPRITE test bench instead (scripts/sprites/sprite_test.gd).

var _rig: SpriteRig
var _bench: SpriteTest

func enter(p: Dictionary, _info: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.62, 0.82, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.82, 0.9, 0.97)
	floor_rect.position = Vector2(0, 640)
	floor_rect.size = Vector2(1280, 80)
	add_child(floor_rect)
	if p.has("sprite"):
		floor_rect.visible = false
		_bench = SpriteTest.new()
		add_child(_bench)
		_bench.setup(p)
		return
	_rig = SpriteRig.load_rig(String(p.get("rig", "hoshino")))
	if _rig == null:
		push_error("rig not found")
		return
	var z := float(p.get("zoom", 0.62))
	_rig.scale = Vector2(z * float(p.get("flip", 1)), z)
	_rig.position = Vector2(float(p.get("x", 640)), 640)
	add_child(_rig)
	_rig.set_pose(p.get("pose", {}))
	if p.has("face"):
		_rig.set_face(String(p["face"]))

func probe() -> Dictionary:
	if _bench != null:
		return {"sprite": _bench.sset.key if _bench.sset else "", "mode": _bench.mode, "cells": _bench.cells.size()}
	return {"rig": _rig.rig_name if _rig else "", "face": _rig.face() if _rig else ""}
