class_name Session
extends RefCounted
## The match being set up — one object every screen reads and writes, printed by Dbg and handed to
## the (future) fight as `match_config()`.
##
##   mode    "versus2p" | "versus-cpu" | "arcade" | "training" | ""
##   players [P1, P2]: {slot, device, claimed, cpu, fighter, special, locked}
##             fighter / special are roster ids (int) or "random" before resolution, -1 = none yet
##   stage   {id, name, school, plate} or {} until chosen        (see Stages); a 3D stage also carries time, light (the published form) and light_full (the kit's own)
##   stage_time "day" | "night", the time a 3D stage shows; a stage without that time takes its first
##   bgm     "auto" or a track id                                 (see Stages.BGM)

var mode := ""
var players: Array = [_blank(1), _blank(2)]
var stage_time := "day":
	set(v):
		stage_time = v
		stage = _stage_src
var stage: Dictionary = {}:
	set(v):
		_stage_src = v
		stage = _resolve_stage(v)
var _stage_src: Dictionary = {}
static var _lights := {}
var bgm := "auto"
var arcade_stage := 0
var arcade_ladder: Array = []
var bgm_volume := 0.7
var sfx_volume := 0.8
var reduce_flashes := false
var glyphs := "auto"   # "auto" or one of ControllerGlyphs.OVERRIDES
var jukebox_shuffle := false
var jukebox_repeat := "one"   # "one" keeps looping the track (the files loop for ever), "all" moves on to the next one when it ends

## Options values live in a ConfigFile. Scripted runs (a step file's --script= after --, or a SceneTree test's --script) neither
## read nor write the player's real file, so captures and suites never touch their settings; tests point settings_path at a scratch file.
const REAL_PATH := "user://settings.cfg"
static var settings_path := REAL_PATH

func _init() -> void:
	load_settings()

## A scripted run is a step file (--script= after --) or a SceneTree test (--script / -s).
static func scripted() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--script" or a == "-s" or a.begins_with("--script="):
			return true
	return false

static func _persists() -> bool:
	if settings_path == "":
		return false
	return settings_path != REAL_PATH or not scripted()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if not _persists() or cf.load(settings_path) != OK:
		return
	bgm_volume = _volume(cf.get_value("audio", "bgm", bgm_volume), bgm_volume)
	sfx_volume = _volume(cf.get_value("audio", "sfx", sfx_volume), sfx_volume)
	var flash = cf.get_value("access", "reduce_flashes", false)
	reduce_flashes = flash is bool and flash
	var g = cf.get_value("controls", "glyphs", "auto")
	glyphs = g if g is String and g in ControllerGlyphs.OVERRIDES else "auto"
	var sh = cf.get_value("audio", "shuffle", false)
	jukebox_shuffle = sh is bool and sh
	var rp = cf.get_value("audio", "repeat", "one")
	jukebox_repeat = rp if rp is String and rp in ["one", "all"] else "one"

## A hand-edited file may hold anything; only a finite number is a volume.
static func _volume(v: Variant, fallback: float) -> float:
	return clampf(float(v), 0.0, 1.0) if (v is float or v is int) and is_finite(float(v)) else fallback

func save_settings() -> void:
	if not _persists():
		return
	var cf := ConfigFile.new()
	cf.set_value("audio", "bgm", bgm_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.set_value("access", "reduce_flashes", reduce_flashes)
	cf.set_value("controls", "glyphs", glyphs)
	cf.set_value("audio", "shuffle", jukebox_shuffle)
	cf.set_value("audio", "repeat", jukebox_repeat)
	var err := cf.save(settings_path)
	if err != OK:
		push_warning("settings not saved to %s: %s" % [settings_path, error_string(err)])

static func _blank(slot: int) -> Dictionary:
	return {"slot": slot, "device": "", "claimed": false, "cpu": false, "fighter": -1, "special": -1, "locked": false}

func _resolve_stage(src: Dictionary) -> Dictionary:
	var out := src.duplicate()
	if out.has("map") and not FileAccess.file_exists("res://assets/ba/stages/%s/stage.json" % out["map"]):
		push_warning("stage %s: no 3D assets for map %s, using its plate" % [out.get("id", "?"), out["map"]])
		out.erase("map")
		out.erase("times")
	if out.has("map"):
		var times: Array = out["times"]
		out["time"] = stage_time if stage_time in times else times[0]
		if out["time"] != stage_time:
			push_warning("stage %s has no time %s, using %s" % [out.get("id", "?"), stage_time, out["time"]])
		var full := _light(String(out["map"]), String(out["time"]))
		if full.is_empty():
			push_warning("stage %s: map %s has no usable light json, using its plate" % [out.get("id", "?"), out["map"]])
			out.erase("map")
			out.erase("times")
			out.erase("time")
			return out
		out["light_full"] = full
		out["light"] = _published(full)
	return out

static func _published(full: Dictionary) -> Dictionary:
	var p: Dictionary = full["published"]
	var k: Array = p["key_color"]
	var d: Array = p["key_dir"]
	var f: Array = full["key_dir"]
	var a: Array = p["ambient"]
	return {
		"night": bool(p["night"]),
		"key_color": Color(k[0], k[1], k[2]),
		"key_dir": Vector3(d[0], d[1], d[2]).normalized(),
		"fighter_dir": Vector3(f[0], f[1], f[2]).normalized(),
		"ambient": Color(a[0], a[1], a[2]),
	}

static func _light(map: String, time: String) -> Dictionary:
	var key := map + "/" + time
	if not _lights.has(key):
		var dir := "res://assets/ba/stages/" + map
		var variant: String = StageLoader.read_json(dir + "/stage.json").get("times", {}).get(time, "")
		var doc: Dictionary = StageLoader.read_json("%s/%s.json" % [dir, variant])
		if not doc.has("light"):
			return {}
		_lights[key] = doc["light"]
	return _lights[key].duplicate(true)

## Start a fresh setup for a mode (keeps option values).
func begin(new_mode: String) -> void:
	mode = new_mode
	players = [_blank(1), _blank(2)]
	stage = {}
	bgm = "auto"
	arcade_stage = 0
	arcade_ladder = []
	if new_mode == "versus-cpu" or new_mode == "training" or new_mode == "arcade":
		players[1]["cpu"] = true

## Back to Character Select with the same people: picks, stage and arcade progress reset, claims, devices and CPU flags stay.
func new_picks() -> void:
	for p in players:
		p["fighter"] = -1
		p["special"] = -1
		p["locked"] = false
	stage = {}
	bgm = "auto"
	arcade_stage = 0
	arcade_ladder = []

func reset() -> void:
	begin("")

## Human players that must claim a controller before moving on.
func humans() -> int:
	return 2 if mode == "versus2p" else 1

## The device that controls a slot (claimed device, else the keyboard cluster for that slot).
## A claimed pad that has been unplugged falls back to the keyboard too, so the slot is never dead. The fallback skips a
## cluster the other player has claimed. (No Controls reference: this script compiles before the autoloads exist.)
func device_of(slot: int) -> String:
	var p: Dictionary = players[slot - 1]
	var dev: String = p["device"]
	if p["claimed"] and dev != "" and (not dev.begins_with("pad") or dev.to_int() in Input.get_connected_joypads()):
		return dev
	var o: Dictionary = players[2 - slot]
	var kb := "kb1" if slot == 1 else "kb2"
	if o["claimed"] and o["device"] == kb:
		kb = "kb2" if slot == 1 else "kb1"
	return kb

## True when `dev` may act for `slot` (single-human modes: P1 accepts every device).
func controls(dev: String, slot: int) -> bool:
	if humans() == 1:
		return slot == 1
	return dev == device_of(slot)

func match_config() -> Dictionary:
	var pick := func(p: Dictionary) -> Dictionary:
		return {"slot": p["slot"], "device": p["device"], "cpu": p["cpu"], "fighter": p["fighter"], "special": p["special"]}
	return {"mode": mode, "p1": pick.call(players[0]), "p2": pick.call(players[1]), "stage": stage.duplicate(), "bgm": bgm}
