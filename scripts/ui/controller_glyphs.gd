class_name ControllerGlyphs
extends RefCounted
## Which glyph family a pad gets and the picture for a logical action. The pictures are Kenney's Input Prompts (CC0) in
## assets/glyphs, white with alpha so a caller tints them. Godot 4.7.2 calls neither XInput nor Steam Input to name a pad: it
## reads SDL, so the family comes from the vendor and product ids (then the name), not from xinput_index or steam_input_index.

const FAMILIES := ["xbox", "playstation", "switch", "steamdeck", "steam"]
## What Options offers. "steam" is the Steam Controller set; the Deck set is only ever detected.
const OVERRIDES := ["auto", "xbox", "playstation", "switch", "steam"]
const ACTIONS := ["confirm", "back", "aux", "aux2", "lb", "rb", "start", "dpad", "stick_l"]
const SONY := 0x054C
const NINTENDO := 0x057E
const MICROSOFT := 0x045E
const VALVE := 0x28DE
const PID_DECK := 0x1205
const PID_STEAM_VIRTUAL := 0x11FF
## Keyboard clusters: action -> glyph file. Enter, Backspace and Space are absent on purpose: their captions are unreadable
## at hint size, so those keys stay text.
const KEYS := {
	"kb1": {"confirm": "f", "back": "g", "aux": "r", "aux2": "t", "up": "w", "down": "s", "left": "a", "right": "d"},
	"kb2": {"aux": "semicolon", "aux2": "apostrophe", "up": "up", "down": "down", "left": "left", "right": "right"},
}

## Test seam: pad id -> {"info": Dictionary, "name": String}. Wins over the real Input singleton.
static var fake := {}
static var _cache := {}
static var _tex := {}

## Pad ids are reused on reconnect, so Controls drops this on every connect and disconnect.
static func forget() -> void:
	_cache.clear()

## The Options choice. Read off the Game node by path: this script is compiled with Session, before the autoloads exist.
static func _choice() -> String:
	var game := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
	return game.session.glyphs if game != null else "auto"

static func family(pad_id: int) -> String:
	var forced := _choice()
	if forced != "auto":
		return forced
	if fake.has(pad_id):
		return classify(fake[pad_id].get("info", {}), fake[pad_id].get("name", ""))
	if not _cache.has(pad_id):
		# get_joy_info logs an engine error for a pad that is not there
		var here := pad_id in Input.get_connected_joypads()
		_cache[pad_id] = classify(Input.get_joy_info(pad_id), Input.get_joy_name(pad_id)) if here else "xbox"
	return _cache[pad_id]

## The family of a "padN" device, "" for a keyboard.
static func family_of(dev: String) -> String:
	return family(int(dev.substr(3))) if dev.begins_with("pad") else ""

## info is Input.get_joy_info: its vendor_id and product_id are Strings in 4.7.2 and ints elsewhere, int() takes both.
static func classify(info: Dictionary, joy_name: String) -> String:
	var vid := int(info.get("vendor_id", 0))
	var pid := int(info.get("product_id", 0))
	match vid:
		SONY:
			return "playstation"
		NINTENDO:
			return "switch"
		VALVE:
			if pid == PID_DECK:
				return "steamdeck"
			if pid == PID_STEAM_VIRTUAL:
				return "xbox"   # Steam's own virtual pad hides the device behind it
			return "steam"
		MICROSOFT:
			return "xbox"
	if info.has("xinput_index"):
		return "xbox"
	var n := (joy_name + " " + str(info.get("raw_name", ""))).to_lower()
	if "steam deck" in n:
		return "steamdeck"
	if "steam" in n and "virtual" not in n:
		return "steam"
	for k in ["playstation", "ps3", "ps4", "ps5", "dualshock", "dualsense"]:
		if k in n:
			return "playstation"
	for k in ["switch", "joy-con", "joycon", "nintendo", "pro controller"]:
		if k in n:
			return "switch"
	return "xbox"

static func _load(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]

static func texture(fam: String, action: String) -> Texture2D:
	return _load("res://assets/glyphs/%s/%s.png" % [fam, action])

static func key(name: String) -> Texture2D:
	return _load("res://assets/glyphs/keyboard/%s.png" % name)

## The key cap on a keyboard device for an action, null when that key has no picture.
static func key_glyph(dev: String, action: String) -> Texture2D:
	var name: String = KEYS.get(dev, {}).get(action, "")
	return key(name) if name != "" else null

## The controller silhouette of a family.
static func body(fam: String) -> Texture2D:
	return _load("res://assets/glyphs/bodies/%s.svg" % fam)
