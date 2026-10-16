class_name Kits
extends RefCounted
## Kit registry: a bespoke kit is simply a file scripts/fight/kits/kit_<roster key>.gd (class extends Kit).
## No registration needed — drop the file in. Students without one get the generic weapon-class Kit.

const DIR := "res://scripts/fight/kits/"

static func path_for(data: Dictionary) -> String:
	return DIR + "kit_" + String(data.get("key", "")).to_lower() + ".gd"

static func make(data: Dictionary) -> Kit:
	var k: Kit
	var p := path_for(data)
	if ResourceLoader.exists(p):
		var s: GDScript = load(p)
		k = s.new() if s else Kit.new()
	else:
		k = Kit.new()
	k.data = data
	return k
