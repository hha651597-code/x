extends Node
## Every sound is a real Blue Archive clip. play(name) plays the UI and fight sounds of assets/audio/ba/ui_map.json (one or more clips per
## name, cut from the client's audio bundles by tools/sfx_ui_assets.py). Hina and Hoshino also play their own clips from manifest.json
## (look at relevant docs): play_for for effects, voice for lines; an event their set does not name falls back to the map's.
## Safe to call with no audio device. A name the map lacks is silent.

const BASE := "res://assets/audio/ba/"
const POOL := 12
const LONG_POOL := 6        # clips of 0.6 s and more (spool, lock and load, reloads, heal), so a flood of impacts never cuts them
const FADE := 0.06
# not fully functional. set from a recorded demo match, not by ear: without it the real clips mixed to -11.5 LUFS with +2 dBFS peaks
const CLIP_TRIM_DB := -4.0
const VOICE_GAP := 60       # ticks a line keeps equal and lower priorities out after it ends
const FREEZE_VOICE := "ult" # the only line that speaks during an EX freeze
const LOG_MAX := 512

var volume_sfx := 0.8
var played := {}            # every call by event name, whether or not a sound came out
var manifest := {}
var clips_played: Array = []  # {who, slot, tick, event, clip, channel, pitch, db}, newest last, for tests
var voice_log: Array = []     # {who, slot, tick, event, clip, priority, cut, db}
var missing: Array = []       # mapped clips that failed to load
var rng := RandomNumberGenerator.new()  # never the fight's rng
var ui := {}                # sound name -> {clips: [rel], db}, from ui_map.json
var _ui_streams: Array = []   # every stream of the map, so stop_all leaves a menu click or a wipe sound alone
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _long: Array[AudioStreamPlayer] = []
var _next_long := 0
var _streams := {}
var _chan := {}             # "slot.channel" -> {p: two players, i: the one playing}
var _fades := {}            # player -> Tween
var _last := {}             # "slot|who|event" -> tick of the last clip or line
var _picked := {}           # same key -> the last clip, so a variant never repeats back to back
var _speaking := {}         # slot -> {start, end, until, pri}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_load_manifest()
	# Several clips at once can sum past full scale; the limiter keeps the master under -1 dBFS.
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.threshold_db = -3.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), limiter)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in LONG_POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_long.append(p)

func play(sound: String, pitch := 1.0, vol := 1.0) -> void:
	played[sound] = int(played.get(sound, 0)) + 1
	var e: Dictionary = ui.get(sound, {})
	if e.is_empty() or _players.is_empty():
		return
	var stream := stream_for(_pick("ui|" + sound, e["clips"]))
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	_start(p, stream, pitch, linear_to_db(clampf(volume_sfx * vol, 0.0001, 1.0)) + float(e["db"]))

func set_volume(v: float) -> void:
	volume_sfx = clampf(v, 0.0, 1.0)

func _exit_tree() -> void:
	for player in _players + _long:
		player.stop()
		player.stream = null
	for k in _chan:
		for player in _chan[k]["p"]:
			player.stop()
			player.stream = null
	ui.clear()
	_ui_streams.clear()
	_streams.clear()
	OS.delay_msec(60)

# ── clips ────────────────────────────────────────────────────────────────────
## Plays `event` from `who`'s set (data["key"], "hina"). No set, or an event the set lacks, plays the map's `event`;
## a null entry is silent. `tick` is the fighter's frame, `move` its current move key (for mute_in). True when a clip started.
func play_for(who: String, slot: int, tick: int, event: String, pitch := 1.0, vol := 1.0, move := "") -> bool:
	var events: Dictionary = manifest.get("sets", {}).get(who, {}).get("sfx", {})
	if not events.has(event):
		play(event, pitch, vol)
		return false
	played[event] = int(played.get(event, 0)) + 1
	var e: Variant = events[event]
	if e == null or move in e.get("mute_in", []):
		return false
	var key := "%d|%s|%s" % [slot, who, event]
	if not _gap_ok(key, tick, int(e.get("gap", 0))):
		return false
	var rel := _pick(key, e["clips"])
	var stream := stream_for(rel)
	if stream == null:
		return false
	_last[key] = tick
	# not fully functional. the unit of RandomPitchMin/Max is unverified, semitones assumed
	var semis: Array = e.get("pitch", [0, 0])
	var shift := rng.randf_range(float(semis[0]), float(semis[1])) if float(semis[1]) > float(semis[0]) else float(semis[0])
	var rate := pitch * float(e.get("scale", 1.0)) * pow(2.0, shift / 12.0)
	var db := _db(float(e.get("vol", 1.0)) * vol, rel)
	var channel := String(e.get("channel", "pool"))
	if channel == "pool":
		var p := _players[_next]
		_next = (_next + 1) % _players.size()
		_start(p, stream, rate, db)
	elif channel == "long":
		var p := _long[_next_long]
		_next_long = (_next_long + 1) % _long.size()
		_start(p, stream, rate, db)
	else:
		_on_channel(slot, channel, stream, rate, db)
	_log(clips_played, {"who": who, "slot": slot, "tick": tick, "event": event, "clip": rel, "channel": channel, "pitch": rate, "db": db})
	return true

## A voice line for one fighter slot. One line at a time per slot: a higher priority cuts the current one (60 ms fade),
## an equal or lower one is dropped until the line and VOICE_GAP ticks are over. cuts_all (ko) plays through any of it.
## `frozen` (an EX freeze) lets only FREEZE_VOICE speak. `max_s` drops clips longer than it. True when a line started.
func voice(who: String, slot: int, tick: int, event: String, frozen := false, max_s := 0.0) -> bool:
	var lines: Dictionary = manifest.get("sets", {}).get(who, {}).get("voice", {})
	if not lines.has(event) or (frozen and event != FREEZE_VOICE):
		return false
	var e: Dictionary = lines[event]
	var key := "%d|%s|voice.%s" % [slot, who, event]
	var now: Dictionary = _speaking.get(slot, {})
	if not now.is_empty() and tick < int(now["start"]):
		now = {}
	var pri := int(e["priority"])
	if not bool(e.get("cuts_all", false)):
		if not now.is_empty() and tick < int(now["until"]) and pri <= int(now["pri"]):
			return false
		if not _gap_ok(key, tick, int(e.get("gap", 0))):
			return false
	var clips: Array = e["clips"]
	if max_s > 0.0:
		clips = clips.filter(func(c: String) -> bool: return float(manifest["clips"][c]["seconds"]) <= max_s)
		if clips.is_empty():
			return false
	var rel := _pick(key, clips)
	var stream := stream_for(rel)
	if stream == null:
		return false
	var ticks := ceili(float(manifest["clips"][rel]["seconds"]) * 60.0)
	var cut := not now.is_empty() and tick < int(now["end"])
	var db := _db(float(e.get("vol", 1.0)), rel)
	_speaking[slot] = {"start": tick, "end": tick + ticks, "until": tick + ticks + VOICE_GAP, "pri": pri}
	_last[key] = tick
	_on_channel(slot, "voice", stream, 1.0, db)
	_log(voice_log, {"who": who, "slot": slot, "tick": tick, "event": event, "clip": rel, "priority": pri, "cut": cut, "db": db})
	return true

func stop_move(slot: int) -> void:
	_stop(slot, "move", FADE)

func stop_voice(slot: int) -> void:
	_stop(slot, "voice", FADE)
	_speaking.erase(slot)

func stop_cut(slot: int, fade := FADE) -> void:
	_stop(slot, "cut", fade)

## Everything fades out and the gap, voice and variant memory is cleared. A round or rematch starts here.
func stop_all() -> void:
	for k in _chan:
		for p in _chan[k]["p"]:
			_fade_out(p, FADE)
	for p in _long:
		_fade_out(p, FADE)
	for p in _players:
		if not _ui_streams.has(p.stream):   # a menu click or a wipe sound started this frame is not the fight's to fade
			_fade_out(p, FADE)
	_speaking.clear()
	_last.clear()
	_picked.clear()

## The imported stream for a manifest clip path ("sfx/SFX_Common_HMG_01.wav"), cached. Null and listed in `missing` on a miss.
func stream_for(rel: String) -> AudioStream:
	if _streams.has(rel):
		return _streams[rel]
	var path := BASE + rel
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	elif rel.ends_with(".ogg") and FileAccess.file_exists(path):
		s = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))   # not imported yet (dev only)
	if s == null:
		if not missing.has(rel):
			missing.append(rel)
			push_warning("Sfx: cannot load " + path)
		return null
	_streams[rel] = s
	return s

func _load_manifest() -> void:
	var f := FileAccess.open(BASE + "manifest.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if parsed is Dictionary:
		manifest = parsed
	else:
		push_warning("Sfx: no readable manifest at %smanifest.json, no mapped sound plays" % BASE)

func _db(vol: float, rel: String) -> float:
	return linear_to_db(clampf(volume_sfx * vol, 0.0001, 1.0)) + float(manifest.get("clips", {}).get(rel, {}).get("gain_db", 0.0)) + CLIP_TRIM_DB

## A tick that goes backwards (a new round) counts as no history.
func _gap_ok(key: String, tick: int, gap: int) -> bool:
	if gap <= 0 or not _last.has(key):
		return true
	var d := tick - int(_last[key])
	return d < 0 or d >= gap

func _pick(key: String, clips: Array) -> String:
	var last := String(_picked.get(key, ""))
	var fresh: Array = clips.filter(func(c: String) -> bool: return c != last) if clips.size() > 1 else clips
	var rel: String = fresh[rng.randi_range(0, fresh.size() - 1)]
	_picked[key] = rel
	return rel

func _log(into: Array, entry: Dictionary) -> void:
	into.append(entry)
	if into.size() > LOG_MAX:
		into.pop_front()

# ── players ──────────────────────────────────────────────────────────────────
## Each slot has a move, a voice and a cut channel of two players: a new clip starts on the idle one while the old fades.
func _on_channel(slot: int, chan: String, stream: AudioStream, pitch: float, db: float) -> void:
	var k := "%d.%s" % [slot, chan]
	if not _chan.has(k):
		var pair: Array[AudioStreamPlayer] = []
		for i in 2:
			var p := AudioStreamPlayer.new()
			add_child(p)
			pair.append(p)
		_chan[k] = {"p": pair, "i": 0}
	var ch: Dictionary = _chan[k]
	_fade_out(ch["p"][ch["i"]], FADE)
	ch["i"] = 1 - int(ch["i"])
	_start(ch["p"][ch["i"]], stream, pitch, db)

func _stop(slot: int, chan: String, secs: float) -> void:
	var k := "%d.%s" % [slot, chan]
	if _chan.has(k):
		for p in _chan[k]["p"]:
			_fade_out(p, secs)

func _start(p: AudioStreamPlayer, stream: AudioStream, pitch: float, db: float) -> void:
	_kill_fade(p)
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = db
	p.play()

## A fade that ends in stop() must never outlive the clip that replaced it, so _start kills it first.
func _fade_out(p: AudioStreamPlayer, secs: float) -> void:
	if not p.playing:
		return
	_kill_fade(p)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, secs)
	tw.tween_callback(func() -> void:
		p.stop()
		_fades.erase(p))
	_fades[p] = tw

func _kill_fade(p: AudioStreamPlayer) -> void:
	if _fades.has(p):
		_fades[p].kill()
		_fades.erase(p)


# ── the sound map ────────────────────────────────────────────────────────────
## Loads ui_map.json and every clip it names, so the first call never waits on a disk read.
func _build() -> void:
	var f := FileAccess.open(BASE + "ui_map.json", FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (parsed is Dictionary and parsed.get("sounds") is Dictionary):
		push_warning("Sfx: no readable %sui_map.json, only the fighters' own clips play" % BASE)
		return
	ui = parsed["sounds"]
	for name in ui:
		for rel in ui[name]["clips"]:
			var stream := stream_for(rel)
			if stream != null:
				_ui_streams.append(stream)
