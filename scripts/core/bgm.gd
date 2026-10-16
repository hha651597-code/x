extends Node
## Background music (autoload "Bgm"): real Blue Archive Original Soundtrack tracks from assets/audio/bgm/ (titles, composers,
## sources and lengths are listed in assets/audio/bgm/TRACKS.md). Every file is an Ogg Vorbis loop (-18 LUFS) whose last 1.5 s is
## a crossfade back into the intro, so AudioStreamOggVorbis.loop = true with loop_offset = 1.5 repeats without a gap.
##
## The music follows Game.session.bgm ("auto" = the bright main theme on menus / select / results and a stage-dependent battle
## track during a fight) and Game.session.bgm_volume, so screens only have to set those two fields. Tracks crossfade through a
## small pool of AudioStreamPlayers. Everything plays on its own "Music" bus (created here) that carries a spectrum analyser,
## which is what the Extras jukebox reads for its visualiser.
##
## The jukebox drives it with set_paused(b), step(1) / step(-1) (next and previous, random with Session.jukebox_shuffle) and, with
## Session.jukebox_repeat "all", the music hands over to the next track END_LEAD seconds before the file ends.
##
## API: tracks(), track(id), current, paused, play_id(id), position(), length(), length_of(id), spectrum(bands), is_playing(), probe(), stop(),
## set_paused(b), neighbour(from, dir, shuffle, roll), step(dir).

const DIR := "res://assets/audio/bgm/"
const BUS_NAME := "Music"
const SOURCE := "Blue Archive Original Soundtrack"
const SOURCE_URL := "bluearchive.wiki/wiki/Soundtrack"
const MAIN_THEME := "constant-moderato"
const FADE := 1.1                   # seconds of an ordinary crossfade
const FADE_FAST := 0.3              # a track that is already fading out when yet another switch arrives
const END_LEAD := 2.4               # repeat All hands over this long before the end: the fade-out finishes before the file's own 1.5 s loop tail
const HISTORY_MAX := 64
const MAKEUP_DB := 3.0              # the files sit at -18 LUFS; slider 1.0 = +3 dB, the default 0.7 = about 0 dB
const POOL := 3
const LOOP_OFFSET := 1.5            # seconds: where a loop restarts (the tail of the file is already the crossfade into the intro)

## id / name / file / composer / no (OST track number) / role / loop (loop_offset seconds) / len (length of the file in seconds, so the UI never has to load it)
const TRACKS := [
	{"id": "constant-moderato", "name": "Constant Moderato", "file": "constant-moderato.ogg", "composer": "Mitsukiyo", "no": 1, "role": "Main theme", "loop": LOOP_OFFSET, "len": 136.77},
	{"id": "unwelcome-school", "name": "Unwelcome School", "file": "unwelcome-school.ogg", "composer": "Mitsukiyo", "no": 7, "role": "Main theme", "loop": LOOP_OFFSET, "len": 119.75},
	{"id": "pachad", "name": "Pachad", "file": "pachad.ogg", "composer": "Nor", "no": 182, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 110.27},
	{"id": "dark-shadows", "name": "Dark Shadows", "file": "dark-shadows.ogg", "composer": "KARUT", "no": 181, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 113.51},
	{"id": "out-of-control", "name": "Out of Control", "file": "out-of-control.ogg", "composer": "KARUT", "no": 48, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 129.44},
	{"id": "step-of-terror", "name": "Step of Terror", "file": "step-of-terror.ogg", "composer": "KARUT", "no": 157, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 64.47},
	{"id": "mechanical-jungle", "name": "Mechanical JUNGLE", "file": "mechanical-jungle.ogg", "composer": "KARUT", "no": 18, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 121.35},
	{"id": "virtual-storm", "name": "Virtual Storm", "file": "virtual-storm.ogg", "composer": "KARUT", "no": 19, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 123.63},
	{"id": "alert", "name": "Alert", "file": "alert.ogg", "composer": "KARUT", "no": 29, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 116.70},
	{"id": "crossfire", "name": "CrossFire", "file": "crossfire.ogg", "composer": "KARUT", "no": 30, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 109.77},
	{"id": "aoharu", "name": "Aoharu", "file": "aoharu.ogg", "composer": "Nor", "no": 34, "role": "Upbeat theme", "loop": LOOP_OFFSET, "len": 107.00},
	{"id": "signal-of-abydos", "name": "Signal of Abydos", "file": "signal-of-abydos.ogg", "composer": "Nor", "no": 45, "role": "Upbeat theme", "loop": LOOP_OFFSET, "len": 113.46},
	{"id": "final-destination-of-ark", "name": "Final Destination of Ark", "file": "final-destination-of-ark.ogg", "composer": "KARUT", "no": 156, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 122.21},
	{"id": "fury-of-set", "name": "Fury of Set", "file": "fury-of-set.ogg", "composer": "KARUT", "no": 212, "role": "Fight theme", "loop": LOOP_OFFSET, "len": 125.79},
]

## Auto in a fight: a flavour pairing per stage; anything else hashes into battle.
const STAGE_TRACKS := {"gehenna-night": "out-of-control"}
const BATTLE := ["pachad", "out-of-control", "step-of-terror", "dark-shadows", "mechanical-jungle", "virtual-storm", "alert",
		"crossfire", "final-destination-of-ark", "fury-of-set"]

var current := ""                   # id of the track that is playing (or fading in)
var enabled := true
var paused := false                 # the jukebox's Pause: the players hold their position (stream_paused)

var _bus := -1
var _spec: AudioEffectSpectrumAnalyzerInstance
var _by_id := {}
var _streams := {}
var _pl: Array[AudioStreamPlayer] = []
var _gain := PackedFloat32Array()   # 0..1 crossfade progress per player (the audible gain is sin(gain * PI / 2): equal power)
var _tgt := PackedFloat32Array()
var _rate := PackedFloat32Array()   # progress per second
var _pid: Array[String] = []
var _cur := -1
var _wanted := ""
var _history: Array[String] = []    # tracks left by a step forward, for Previous under shuffle
var _handed_over := ""              # the track that already passed the music on at its end, so it does so once

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for t in TRACKS:
		_by_id[t["id"]] = t
	_setup_bus()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_NAME
		p.volume_db = -80.0
		add_child(p)
		_pl.append(p)
		_gain.append(0.0)
		_tgt.append(0.0)
		_rate.append(1.0 / FADE)
		_pid.append("")
	for st in Stages.BGM:
		if st["id"] != "auto" and not _by_id.has(st["id"]):
			push_warning("Stages.BGM lists '%s' but Bgm has no such track" % st["id"])

func _exit_tree() -> void:
	# release the playbacks and streams so the engine does not report them as leaked at shutdown
	for p in _pl:
		p.stop()
		p.stream = null
	_streams.clear()
	OS.delay_msec(60)   # let the mixer thread drop the stopped playbacks before the engine's leak check

## The "Music" bus with a spectrum analyser (found by name when it already exists, e.g. from a bus layout).
func _setup_bus() -> void:
	_bus = AudioServer.get_bus_index(BUS_NAME)
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, BUS_NAME)
		AudioServer.set_bus_send(_bus, "Master")
	var fx := -1
	for i in AudioServer.get_bus_effect_count(_bus):
		if AudioServer.get_bus_effect(_bus, i) is AudioEffectSpectrumAnalyzer:
			fx = i
	if fx < 0:
		var a := AudioEffectSpectrumAnalyzer.new()
		a.buffer_length = 0.3
		a.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		AudioServer.add_bus_effect(_bus, a)
		fx = AudioServer.get_bus_effect_count(_bus) - 1
	_spec = AudioServer.get_bus_effect_instance(_bus, fx) as AudioEffectSpectrumAnalyzerInstance

# queries
## Every track as {id, name, file, composer, no, role, loop}; the order is the jukebox / stage-select order.
func tracks() -> Array:
	return TRACKS

func has_track(id: String) -> bool:
	return _by_id.has(id)

## One track's dictionary ({} for an unknown id). `title` / `source` are ready-made strings for the UI.
func track(id: String) -> Dictionary:
	if not _by_id.has(id):
		return {}
	var t: Dictionary = (_by_id[id] as Dictionary).duplicate()
	t["source"] = "%s  ·  Track %d" % [SOURCE, int(t["no"])]
	t["url"] = SOURCE_URL
	return t

func is_playing() -> bool:
	return _cur >= 0 and _pl[_cur].playing

## Playback position (s) of the current track inside its file (loops return to LOOP_OFFSET).
func position() -> float:
	if not is_playing():
		return 0.0
	return maxf(_pl[_cur].get_playback_position() + AudioServer.get_time_since_last_mix(), 0.0)

## Length (s) of the current track's file.
func length() -> float:
	if _cur < 0 or _pl[_cur].stream == null:
		return 0.0
	return _pl[_cur].stream.get_length()

## Length (s) of any track's file, whether or not it is playing (0 for an unknown id).
func length_of(id: String) -> float:
	return float(_by_id[id]["len"]) if _by_id.has(id) else 0.0

## `bands` log-spaced magnitudes (0..1) from the Music bus's analyser, f_lo..f_hi Hz. Real FFT of what is playing.
func spectrum(bands: int, f_lo := 40.0, f_hi := 14000.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(bands)
	if _spec == null or bands <= 0:
		return out
	var ratio := pow(f_hi / f_lo, 1.0 / float(bands))
	var lo := f_lo
	for i in bands:
		var hi := lo * ratio
		var m: Vector2 = _spec.get_magnitude_for_frequency_range(lo, hi, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
		var db := linear_to_db(maxf(maxf(m.x, m.y), 0.0000001))
		# the analyser sees the bus before its volume; music rolls off ~4.5 dB/oct, so tilt the display up with frequency
		var tilt := 4.5 * log(sqrt(lo * hi) / 100.0) / log(2.0)
		out[i] = pow(clampf((db + 64.0 + tilt) / 46.0, 0.0, 1.0), 1.5)   # -64..-18 dB -> 0..1, a little contrast
		lo = hi
	return out

func probe() -> Dictionary:
	return {"spec8": Array(spectrum(8)).map(func(v): return snappedf(v, 0.01)), "current": current, "wanted": _wanted, "playing": is_playing(), "pos": snappedf(position(), 0.01), "len": snappedf(length(), 0.01),
			"session": Game.session.bgm, "paused": paused, "shuffle": Game.session.jukebox_shuffle, "repeat": Game.session.jukebox_repeat,
			"volume": snappedf(Game.session.bgm_volume, 0.01), "bus": _bus, "bus_db": snappedf(AudioServer.get_bus_volume_db(_bus), 0.1),
			"players": _pid.duplicate(), "gains": Array(_gain).map(func(g): return snappedf(g, 0.01))}

# playback
func _process(delta: float) -> void:
	if enabled:
		var want := _desired()
		if want != _wanted:
			_wanted = want
			play_id(want)
	if not paused:
		_fade(delta)
		_hand_over()
	var v := clampf(float(Game.session.bgm_volume), 0.0, 1.0)
	AudioServer.set_bus_mute(_bus, v <= 0.001)
	AudioServer.set_bus_volume_db(_bus, linear_to_db(maxf(v, 0.001)) + MAKEUP_DB)

## What the session asks for right now: its track id, or the auto pick.
func _desired() -> String:
	var id := String(Game.session.bgm)
	if id == "auto" or not _by_id.has(id):
		return _auto_track()
	return id

## Auto: the bright main theme on menus / select / results; a stage-dependent battle track during a fight.
func _auto_track() -> String:
	if Game.current_name() == "fight":
		var key := str(Game.session.stage.get("id", "x"))
		if STAGE_TRACKS.has(key):
			return STAGE_TRACKS[key]
		return BATTLE[absi(key.hash()) % BATTLE.size()]
	return MAIN_THEME

## Crossfade to a track now (the session-following code calls this whenever the wanted id changes).
func play_id(id: String) -> bool:
	if not _by_id.has(id):
		push_warning("Bgm.play_id: unknown track '%s'" % id)
		return false
	enabled = true
	if id == current and _cur >= 0 and _pl[_cur].playing and _tgt[_cur] > 0.0:
		return true
	set_paused(false)
	_handed_over = ""
	var stream := _stream_for(id)
	if stream == null:
		return false
	# whatever is sounding fades out (quickly when several are already on their way out)
	var audible := 0
	for i in POOL:
		if i != _cur and _pl[i].playing:
			audible += 1
	for i in POOL:
		_tgt[i] = 0.0
		_rate[i] = 1.0 / (FADE_FAST if (i != _cur and audible > 0) else FADE)
	var slot := _free_slot()
	var p := _pl[slot]
	p.stop()
	p.stream = stream
	_gain[slot] = 0.0
	_tgt[slot] = 1.0
	_rate[slot] = 1.0 / FADE
	_pid[slot] = id
	p.volume_db = -80.0
	p.play()
	_cur = slot
	current = id
	return true

func _free_slot() -> int:
	var best := -1
	for i in POOL:
		if i == _cur:
			continue
		if not _pl[i].playing:
			return i
		if best < 0 or _gain[i] < _gain[best]:
			best = i
	return best

func _fade(delta: float) -> void:
	for i in POOL:
		var p := _pl[i]
		if not p.playing:
			continue
		_gain[i] = move_toward(_gain[i], _tgt[i], _rate[i] * delta)
		if _gain[i] <= 0.0 and _tgt[i] <= 0.0:
			p.stop()
			p.stream = null
			_pid[i] = ""
			if i == _cur:
				_cur = -1
				current = ""
			continue
		p.volume_db = linear_to_db(maxf(sin(_gain[i] * PI * 0.5), 0.0001))

func _stream_for(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var path: String = DIR + String(_by_id[id]["file"])
	var s: AudioStreamOggVorbis = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStreamOggVorbis
	elif FileAccess.file_exists(path):
		s = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))   # not imported yet (dev only)
	if s == null:
		push_warning("Bgm: cannot load " + path)
		return null
	s.loop = true
	s.loop_offset = float(_by_id[id]["loop"])
	_streams[id] = s
	return s

## Hold every player where it is (true) or let them run on (false). A new track always starts unpaused.
func set_paused(b: bool) -> void:
	paused = b
	for p in _pl:
		p.stream_paused = b

## The track after (dir 1) or before (-1) `from` in the jukebox order, wrapping; with shuffle a random other track going forward
## (roll is a 0..1 die, passed in so a test can pick). From a `from` that is no track (AUTO) it enters the list at an end.
func neighbour(from: String, dir: int, shuffle: bool, roll: float) -> String:
	var ids: Array = TRACKS.map(func(t: Dictionary) -> String: return t["id"])
	var i := ids.find(from)
	if shuffle and dir > 0:
		var pool := ids.filter(func(x: String) -> bool: return x != from)
		return pool[mini(int(roll * float(pool.size())), pool.size() - 1)]
	if i < 0:
		return ids[0] if dir > 0 else ids[ids.size() - 1]
	return ids[posmod(i + dir, ids.size())]

## Next (1) and Previous (-1): the session plays the neighbour of what is playing now. Previous under shuffle returns to the track
## that was left, if any.
func step(dir: int) -> void:
	var from := String(Game.session.bgm)   # the session's pick leads: `current` follows it a frame later
	if not _by_id.has(from):
		from = current
	var target := ""
	if dir < 0 and Game.session.jukebox_shuffle and not _history.is_empty():
		target = _history.pop_back()
	else:
		if dir > 0 and from != "":
			_history.append(from)
			if _history.size() > HISTORY_MAX:
				_history.pop_front()
		target = neighbour(from, dir, Game.session.jukebox_shuffle, randf())
	Game.session.bgm = target
	set_paused(false)

## Repeat All: when the picked track is within END_LEAD of its end, go on to the next one (once per track).
func _hand_over() -> void:
	if Game.session.jukebox_repeat != "all" or String(Game.session.bgm) == "auto" or _cur < 0 or _pid[_cur] == _handed_over:
		return
	if is_playing() and handover_due(position(), length()):
		_handed_over = _pid[_cur]
		step(1)

## Whether a track at `pos` of `len` seconds is within END_LEAD of its end.
static func handover_due(pos: float, len: float) -> bool:
	return len > 0.0 and pos >= len - END_LEAD

## Fade everything out and stop following the session until play_id().
func stop() -> void:
	enabled = false
	for i in POOL:
		_tgt[i] = 0.0
		_rate[i] = 1.0 / FADE_FAST
