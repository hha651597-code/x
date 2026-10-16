extends SceneTree
## Sfx engine: manifest and clips, variants, gaps, voice rules, provenance and loudness. Direct calls into Sfx, no fight.
## Run with TEST=res://scripts/models/tests/sound_test.gd tools/sd_test.sh (a real small window).
## It proves routing, timing, file integrity and loudness numbers. It cannot say how anything sounds.

const BASE := "res://assets/audio/ba/"
const CEILING := -1.5
const SILENT_IN_SET := ["swing", "block", "just_guard", "guard_crush", "boom", "jump", "land", "dash", "ko", "fight", "claim", "ult_stamp", "ult_release"]

var checks := 0
var failures: Array = []
var sfx: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("SOUND_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("SOUND_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	sfx = root.get_node("Sfx")
	sfx.volume_sfx = 0.8
	_resolve()
	_sets()
	_fallback()
	_variants()
	_gaps()
	_levels()
	_voices()
	_stop_all()
	await _playback()
	_provenance()
	_loudness()
	print("SOUND_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# helpers
func _fresh() -> void:
	sfx.stop_all()
	sfx.clips_played.clear()
	sfx.voice_log.clear()
	sfx.rng.seed = 7
	sfx.volume_sfx = 0.8

func _sfx_entry(who: String, event: String) -> Variant:
	return sfx.manifest["sets"][who]["sfx"].get(event)

func _gain(rel: String) -> float:
	return float(sfx.manifest["clips"][rel]["gain_db"])

func _shot(who: String, slot: int, tick: int, move := "") -> bool:
	return sfx.play_for(who, slot, tick, "shot", 1.0, 1.0, move)

func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _count(name: String) -> int:
	return int(sfx.played.get(name, 0))

func _all_clip_refs() -> Array:
	var out: Array = []
	for who in sfx.manifest["sets"]:
		for kind in ["sfx", "voice"]:
			for event in sfx.manifest["sets"][who][kind]:
				var e: Variant = sfx.manifest["sets"][who][kind][event]
				if e != null:
					out.append_array(e["clips"])
	return out

# manifest and clips
func _resolve() -> void:
	check(sfx.manifest.has("sets") and sfx.manifest.has("clips"), "the manifest loaded")
	check(sfx.manifest["clips"].size() == 67, "67 clips: 43 sfx and 24 voices (%d)" % sfx.manifest["clips"].size())
	var bad := 0
	for rel in sfx.manifest["clips"]:
		var s: AudioStream = sfx.stream_for(rel)
		if s == null:
			bad += 1
			continue
		if absf(s.get_length() - float(sfx.manifest["clips"][rel]["seconds"])) > 0.05:
			bad += 1
			print("  length differs: ", rel, " ", s.get_length(), " vs ", sfx.manifest["clips"][rel]["seconds"])
	check(bad == 0, "every manifest clip loads and matches its recorded length (%d bad)" % bad)
	check(sfx.missing.is_empty(), "missing is empty (%s)" % str(sfx.missing))
	var dangling := 0
	for rel in _all_clip_refs():
		if not sfx.manifest["clips"].has(rel):
			dangling += 1
	check(dangling == 0, "every event clip is in the clip table")
	check(sfx.stream_for("sfx/not_a_clip.wav") == null and sfx.missing.has("sfx/not_a_clip.wav"), "an unknown clip returns null and lands in missing")
	sfx.missing.clear()

func _sets() -> void:
	var hina: Dictionary = sfx.manifest["sets"]["hina"]
	var hoshino: Dictionary = sfx.manifest["sets"]["hoshino"]
	var ok := true
	for rel in hina["sfx"]["shot"]["clips"]:
		ok = ok and "_HMG_" in rel and not "_SG_" in rel
	check(ok and hina["sfx"]["shot"]["clips"].size() == 5, "Hina's shot is the five HMG clips only")
	ok = true
	for rel in hoshino["sfx"]["shot"]["clips"]:
		ok = ok and "_SG_" in rel and not "_HMG_" in rel
	check(ok and hoshino["sfx"]["shot"]["clips"].size() == 8, "Hoshino's shot is the eight SG clips only")
	check(hina["sfx"]["shot"]["channel"] == "move" and hoshino["sfx"]["shot"]["channel"] == "pool", "Hina's burst is on the move channel, Hoshino's shell in the pool")
	check(hina["sfx"]["shot"]["mute_in"] == ["ex"] and int(hina["sfx"]["shot"]["gap"]) == 36 and int(hoshino["sfx"]["shot"]["gap"]) == 6, "shot gaps 36 and 6, Hina's muted in the ex")
	check(is_equal_approx(float(hina["sfx"]["hit_l"]["scale"]), 1.1) and is_equal_approx(float(hina["sfx"]["hit_h"]["scale"]), 0.9), "impacts keep their fixed pitch scales")
	for who in ["hina", "hoshino"]:
		for event in SILENT_IN_SET:
			check(not sfx.manifest["sets"][who]["sfx"].has(event), "%s.%s stays synthesized" % [who, event])
		var lines := {}
		for event in sfx.manifest["sets"][who]["voice"]:
			for rel in sfx.manifest["sets"][who]["voice"][event]["clips"]:
				lines[rel] = true
				check(rel.begins_with("voice/%s/" % who), "%s voice stays in its own folder (%s)" % [who, rel])
		check(lines.size() == 12, "%s uses 12 voice lines (%d)" % [who, lines.size()])
		check(int(sfx.manifest["sets"][who]["voice"]["ult"]["priority"]) == 5 and int(sfx.manifest["sets"][who]["voice"]["ko"]["priority"]) == 4, who + ": ult 5, ko 4")
	check(not FileAccess.file_exists(BASE + "sfx/SFX_Skill_Hoshino_Ex_Shield_Drop.wav"), "the shield drop clip is not shipped")
	check(String(hoshino["voice"]["ult"]["clips"][1]).ends_with("Hoshino_ExSkill_2.ogg"), "Hoshino keeps her ExSkill_2 line")

# fallback and the old API
func _fallback() -> void:
	_fresh()
	var tick_n := _count("tick")
	sfx.play("tick")
	check(_count("tick") == tick_n + 1, "play() still counts played")
	sfx.play("no_such_sound")
	check(_count("no_such_sound") == 1, "play() counts a name with no sound")
	var shot_n := _count("shot")
	var next: int = sfx._next
	check(not sfx.play_for("kazusa", 0, 10, "shot"), "a fighter with no set plays no clip")
	check(_count("shot") == shot_n + 1 and sfx.clips_played.is_empty(), "a sprite fighter counts played and logs no clip")
	check(sfx._next == (next + 1) % sfx._players.size(), "a fighter with no set plays the synthesized sound")
	var block_n := _count("block")
	next = sfx._next
	check(not sfx.play_for("hina", 0, 10, "block") and _count("block") == block_n + 1 and sfx.clips_played.is_empty(), "an event the set lacks counts played and logs no clip")
	check(sfx._next == (next + 1) % sfx._players.size(), "an event the set lacks plays the synthesized sound")
	shot_n = _count("shot")
	check(_shot("hina", 0, 10), "Hina's shot plays a clip")
	check(_count("shot") == shot_n + 1 and sfx.clips_played.size() == 1, "a clip event counts played once and logs one clip")
	sfx.manifest["sets"]["hina"]["sfx"]["tick"] = null
	next = sfx._next
	var tick_before := _count("tick")
	check(not sfx.play_for("hina", 0, 10, "tick") and sfx._next == next and _count("tick") == tick_before + 1, "a null entry is silent, counted, and does not fall back")
	sfx.manifest["sets"]["hina"]["sfx"].erase("tick")

# variants
func _variants() -> void:
	_fresh()
	for i in 60:
		sfx.play_for("hoshino", 0, i * 10, "shot")
	check(sfx.clips_played.size() == 60, "60 spaced Hoshino shots log 60 clips")
	var repeats := 0
	var distinct := {}
	for i in sfx.clips_played.size():
		distinct[sfx.clips_played[i]["clip"]] = true
		if i > 0 and sfx.clips_played[i]["clip"] == sfx.clips_played[i - 1]["clip"]:
			repeats += 1
	check(repeats == 0, "no SG clip repeats back to back (%d repeats)" % repeats)
	check(distinct.size() == 8, "all 8 SG clips come up in 60 shots (%d)" % distinct.size())
	_fresh()
	for i in 40:
		sfx.play_for("hina", 0, i * 40, "shot")
	repeats = 0
	for i in range(1, sfx.clips_played.size()):
		if sfx.clips_played[i]["clip"] == sfx.clips_played[i - 1]["clip"]:
			repeats += 1
	check(sfx.clips_played.size() == 40 and repeats == 0, "no HMG clip repeats back to back")
	_fresh()
	sfx.play_for("hina", 0, 0, "ult")
	sfx.play_for("hina", 0, 100, "ult")
	check(sfx.clips_played.size() == 2 and sfx.clips_played[0]["clip"] == sfx.clips_played[1]["clip"], "a one-clip event may repeat")
	var runs: Array = []
	for r in 2:
		_fresh()
		sfx.rng.seed = 99
		var seq: Array = []
		for i in 12:
			sfx.play_for("hoshino", 0, i * 10, "shot")
			sfx.play_for("hina", 0, i * 40, "shot")
			seq.append([sfx.clips_played[-2]["clip"], sfx.clips_played[-2]["pitch"], sfx.clips_played[-1]["clip"], sfx.clips_played[-1]["pitch"]])
		runs.append(seq)
	check(runs[0] == runs[1], "a seeded rng gives the same clips and pitches twice")
	check(sfx.rng is RandomNumberGenerator, "Sfx has its own rng")

# gaps, mute_in, channels
func _gaps() -> void:
	_fresh()
	check(_shot("hina", 0, 100), "gap: the first shot plays")
	check(not _shot("hina", 0, 120), "gap: 20 ticks later is dropped")
	check(not _shot("hina", 0, 135), "gap: 35 ticks later is dropped")
	check(_shot("hina", 0, 136), "gap: 36 ticks after the first plays")
	check(_shot("hina", 1, 137), "gap: the other slot has its own gap")
	check(_shot("hina", 0, 5), "gap: a tick that goes backwards is a new round, not a gap")
	check(sfx.clips_played.size() == 4, "gap: 4 clips logged for 6 calls (%d)" % sfx.clips_played.size())
	check(sfx.clips_played[0]["channel"] == "move" and sfx.clips_played[0]["slot"] == 0 and sfx.clips_played[0]["who"] == "hina", "gap: the log says who, slot and channel")
	_fresh()
	check(_shot("hoshino", 0, 0) and not _shot("hoshino", 0, 5) and _shot("hoshino", 0, 6), "gap: Hoshino's shells are 6 ticks apart")
	_fresh()
	var n: int = sfx.clips_played.size()
	check(not _shot("hina", 0, 1000, "ex"), "mute_in: Hina's shot is silent in the ex")
	check(sfx.clips_played.size() == n, "mute_in: nothing is logged")
	check(_shot("hina", 0, 1001, "5L"), "mute_in: a muted call does not use up the gap")
	check(_shot("hoshino", 0, 1002, "ex"), "mute_in: an event with no mute_in plays in the ex")
	_fresh()
	check(sfx.play_for("hina", 0, 0, "cutin") and sfx.clips_played.back()["channel"] == "cut", "channel: the cut-in is on its own channel")
	check(sfx.play_for("hina", 0, 500, "cutin") and sfx.play_for("hina", 0, 560, "cutin"), "gap: no cut-in gap, every freeze gets its clip")
	check(sfx.play_for("hina", 0, 0, "lock_and_load") and not sfx.play_for("hina", 0, 60, "lock_and_load") and sfx.play_for("hina", 0, 120, "lock_and_load"), "gap: one lock and load per 120 ticks")
	check(sfx.clips_played.back()["channel"] == "long", "channel: lock and load is on the long pool")

# volume, pitch, gain
func _levels() -> void:
	_fresh()
	sfx.play_for("hina", 0, 0, "ult")
	var e: Dictionary = sfx.clips_played.back()
	var g := _gain(e["clip"])
	check(absf(float(e["db"]) - (linear_to_db(0.8 * 0.8) + g + sfx.CLIP_TRIM_DB)) < 0.01, "level: slider x entry vol, then gain_db and the clip trim (%.2f)" % float(e["db"]))
	check(g < 0.0, "level: the Hina ult clip carries a negative gain (%.1f)" % g)
	check(sfx.CLIP_TRIM_DB < 0.0, "level: the clips carry a negative trim")
	var limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		var fx := AudioServer.get_bus_effect(0, i)
		limiter = limiter or (fx is AudioEffectLimiter and fx.ceiling_db <= -1.0)
	check(limiter, "level: the master bus has a limiter at -1 dBFS or lower")
	_fresh()
	sfx.play_for("hina", 0, 0, "ult", 1.0, 0.5)
	check(absf(float(sfx.clips_played.back()["db"]) - (linear_to_db(0.8 * 0.8 * 0.5) + g + sfx.CLIP_TRIM_DB)) < 0.01, "level: the caller's vol multiplies")
	_fresh()
	sfx.volume_sfx = 1.0
	sfx.play_for("hina", 0, 0, "ult", 1.0, 10.0)
	check(absf(float(sfx.clips_played.back()["db"]) - (g + sfx.CLIP_TRIM_DB)) < 0.01, "level: the 0 dB clamp comes before gain_db and the trim")
	_fresh()
	sfx.play_for("hina", 0, 0, "hit_l")
	check(is_equal_approx(float(sfx.clips_played.back()["pitch"]), 1.1), "pitch: hit_l is a fixed 1.1")
	sfx.play_for("hina", 0, 0, "hit_h", 2.0)
	check(is_equal_approx(float(sfx.clips_played.back()["pitch"]), 1.8), "pitch: the caller's pitch multiplies the scale")
	_fresh()
	var lo := pow(2.0, -1.0 / 12.0) - 0.0001
	var hi := pow(2.0, 1.0 / 12.0) + 0.0001
	var in_range := true
	var spread := {}
	for i in 30:
		sfx.play_for("hina", 0, i * 40, "shot")
		var p: float = sfx.clips_played.back()["pitch"]
		in_range = in_range and p >= lo and p <= hi
		spread[snappedf(p, 0.001)] = true
	check(in_range, "pitch: Hina's shot stays within -1..1 semitones")
	check(spread.size() > 5, "pitch: the shot pitch varies (%d values)" % spread.size())
	_fresh()
	var fixed := true
	for i in 10:
		sfx.play_for("hoshino", 0, i * 10, "shot")
		var p2: float = sfx.clips_played.back()["pitch"]
		fixed = fixed and p2 >= pow(2.0, -1.0 / 12.0) - 0.0001 and p2 <= 1.0001
	check(fixed, "pitch: Hoshino's shot stays within -1..0 semitones")

# voices
func _voice(who: String, slot: int, tick: int, event: String, frozen := false, max_s := 0.0) -> bool:
	return sfx.voice(who, slot, tick, event, frozen, max_s)

func _voices() -> void:
	# Hina_CommonSkill is 0.91 s, 55 ticks: busy until tick + 55 + 60
	_fresh()
	check(_voice("hina", 0, 0, "skill"), "voice: the first line plays")
	check(not _voice("hina", 0, 30, "skill"), "voice: an equal priority is dropped while one plays")
	check(not _voice("hina", 0, 30, "intro"), "voice: a lower priority is dropped while one plays")
	check(sfx.voice_log.size() == 1, "voice: dropped lines are not logged")
	check(_voice("hina", 0, 30, "ult") and sfx.voice_log.back()["cut"], "voice: a higher priority cuts the current one")
	var e: Dictionary = sfx.voice_log.back()
	check(e["who"] == "hina" and e["slot"] == 0 and e["event"] == "ult" and int(e["priority"]) == 5 and int(e["tick"]) == 30, "voice: the log says who, slot, event, priority and tick")
	check(absf(float(e["db"]) - (linear_to_db(0.8) + _gain(e["clip"]) + sfx.CLIP_TRIM_DB)) < 0.01, "voice: level is slider x vol, then gain_db and the trim")
	_fresh()
	check(_voice("hina", 0, 0, "skill"), "gap: skill plays")
	check(not _voice("hina", 0, 100, "intro"), "gap: 45 ticks after it ended a lower priority is still dropped")
	check(_voice("hina", 0, 115, "intro"), "gap: 60 ticks after it ended the next line plays")
	_fresh()
	check(_voice("hina", 0, 0, "skill") and _voice("hina", 0, 100, "ult"), "gap: a higher priority plays inside the gap")
	check(not sfx.voice_log.back()["cut"], "gap: nothing was playing, so nothing was cut")
	_fresh()
	_voice("hina", 0, 0, "ult")
	check(_voice("hina", 0, 10, "ko") and sfx.voice_log.back()["cut"], "ko: cuts a priority 5 line")
	_fresh()
	_voice("hina", 0, 0, "big_hit")
	check(_voice("hina", 0, 5, "ko") and sfx.voice_log.back()["event"] == "ko", "ko: cuts a damage line")
	_fresh()
	_voice("hina", 0, 0, "ko")
	check(not _voice("hina", 0, 5, "big_hit"), "ko: a damage line cannot cut the retire line")
	_fresh()
	check(not _voice("hina", 0, 0, "skill", true), "freeze: a skill line is dropped")
	check(not _voice("hina", 0, 0, "ko", true) and not _voice("hina", 0, 0, "intro", true), "freeze: ko and intro are dropped")
	check(_voice("hina", 0, 0, "ult", true), "freeze: the ult line passes")
	check(_voice("hina", 0, 600, "skill"), "freeze: the same line plays once the freeze is over")
	_fresh()
	check(_voice("hina", 0, 0, "intro", false, 1.5) and sfx.voice_log.back()["clip"].ends_with("Hina_Battle_In_2.ogg"), "max_s: Hina's intro picks the short line")
	var long_picked := false
	for i in 8:
		sfx.stop_voice(0)
		_voice("hina", 0, 1000 + i * 1000, "intro", false, 1.5)
		long_picked = long_picked or sfx.voice_log.back()["clip"].ends_with("Hina_Battle_In_1.ogg")
	check(not long_picked, "max_s: the long line never plays")
	check(not _voice("hina", 0, 20000, "intro", false, 0.5), "max_s: no line fits, no voice")
	check(not _voice("hoshino", 1, 0, "intro", false, 1.5), "max_s: Hoshino's short intro is 1.77 s, so 1.5 s drops it")
	check(_voice("hoshino", 1, 0, "intro", false, 2.0), "max_s: 2.0 s fits it")
	_fresh()
	check(_voice("hina", 0, 0, "big_hit"), "gap: big hit plays")
	check(not _voice("hina", 0, 170, "big_hit"), "gap: big hit is held for 180 ticks")
	check(_voice("hina", 0, 180, "big_hit"), "gap: big hit plays at 180")
	check(_voice("hina", 0, 0, "skill_auto") and not _voice("hina", 0, 599, "skill_auto") and _voice("hina", 0, 600, "skill_auto"), "gap: the auto skill line is held for 600 ticks")
	_fresh()
	_voice("hina", 0, 0, "skill_auto")
	check(_voice("hina", 0, 150, "skill"), "gap: the manual skill line has no event gap")
	_fresh()
	check(_voice("hina", 0, 0, "skill") and _voice("hoshino", 1, 0, "skill"), "slots: both fighters speak at once")
	check(not _voice("hoshino", 0, 1, "skill") and sfx.voice_log.size() == 2, "slots: the busy time belongs to the slot, whoever speaks")
	_fresh()
	_voice("hina", 0, 5000, "skill")
	check(_voice("hina", 0, 10, "skill"), "round: a tick that goes backwards clears the busy time")
	_fresh()
	_voice("hina", 0, 0, "skill")
	sfx.stop_voice(0)
	check(_voice("hina", 0, 5, "skill"), "stop_voice: frees the channel")
	_fresh()
	var n: int = sfx.voice_log.size()
	check(not _voice("kazusa", 0, 0, "ult") and not _voice("hina", 0, 0, "no_such_line") and sfx.voice_log.size() == n, "a sprite fighter and an unknown line make no voice")
	_fresh()
	var clips := {}
	for i in 30:
		sfx.stop_all()
		_voice("hoshino", 0, 0, "ult")
		clips[sfx.voice_log.back()["clip"]] = true
	check(clips.size() >= 2, "ult line: more than one of ExSkill_1 to 3 comes up (%d)" % clips.size())
	_fresh()
	var prev := ""
	var rep := 0
	for i in 30:
		_voice("hina", 0, i * 1000, "big_hit")
		var c: String = sfx.voice_log.back()["clip"]
		rep += 1 if c == prev else 0
		prev = c
	check(rep == 0, "voice: variants never repeat back to back (%d)" % rep)

func _stop_all() -> void:
	_fresh()
	_voice("hina", 0, 0, "big_hit")
	_shot("hina", 0, 0)
	check(not _voice("hina", 0, 1, "big_hit") and not _shot("hina", 0, 1), "stop_all: the gaps are held before it")
	sfx.stop_all()
	check(_voice("hina", 0, 1, "big_hit") and _shot("hina", 0, 1), "stop_all: clears voice busy time and gap memory")
	sfx.stop_move(0)
	sfx.stop_cut(0, 0.5)
	sfx.stop_voice(1)
	check(true, "stop_move, stop_cut and stop_voice on a quiet channel do not fail")

## Real players and real time: the 5.5 s Hina ult clip is long enough that nothing ends by itself during the waits.
func _playback() -> void:
	_fresh()
	sfx.play_for("hina", 0, 0, "ult")
	var ch: Dictionary = sfx._chan["0.move"]
	var first: AudioStreamPlayer = ch["p"][ch["i"]]
	await create_timer(0.1).timeout
	check(first.playing and first.stream != null, "playback: a move clip plays on its player")
	sfx.play_for("hina", 0, 100, "ult")
	var second: AudioStreamPlayer = ch["p"][ch["i"]]
	check(second != first and second.playing, "playback: the next move clip starts on the other player")
	await create_timer(0.3).timeout
	check(not first.playing, "playback: the cut clip faded out")
	check(second.playing and second.volume_db > -20.0, "playback: the fade did not touch the clip that replaced it")
	sfx.stop_move(0)
	await create_timer(0.3).timeout
	check(not second.playing, "playback: stop_move fades the clip out and stops it")
	_fresh()
	sfx.play_for("hina", 0, 0, "ult")
	var a: AudioStreamPlayer = ch["p"][ch["i"]]
	sfx.play_for("hina", 0, 1, "ult")
	sfx.play_for("hina", 0, 2, "ult")
	check(ch["p"][ch["i"]] == a, "playback: two quick cuts bring the first player back")
	await create_timer(0.3).timeout
	check(a.playing and a.volume_db > -20.0, "playback: a player reused mid-fade is not stopped by the old fade")
	_voice("hoshino", 1, 0, "ult")
	var vp: AudioStreamPlayer = sfx._chan["1.voice"]["p"][sfx._chan["1.voice"]["i"]]
	await create_timer(0.1).timeout
	check(vp.playing, "playback: a voice line plays on its voice player")
	sfx.stop_all()
	await create_timer(0.3).timeout
	check(not vp.playing, "playback: stop_all stops the voice")
	_fresh()
	sfx.play_for("hoshino", 0, 0, "ult")
	var activate: AudioStreamPlayer = sfx._chan["0.move"]["p"][sfx._chan["0.move"]["i"]]
	sfx.play_for("hoshino", 0, 20, "ult_reload")
	await create_timer(0.5).timeout
	check(activate.playing, "playback: Hoshino's ult reload layers over the activate clip instead of cutting it")
	_fresh()
	var lock_player: AudioStreamPlayer = sfx._long[sfx._next_long]
	sfx.play_for("hina", 0, 100, "lock_and_load")
	sfx.play_for("hina", 0, 110, "shot")
	await create_timer(0.4).timeout
	check(lock_player.playing, "playback: a shot does not cut Hina's Lock & Load clip")
	_fresh()

# provenance
func _provenance() -> void:
	var prov := _json(BASE + "PROVENANCE.json")
	check(String(prov.get("scope", "")) == "Local fan project. Redistribution permission is not inferred.", "provenance: the scope line")
	check(prov.has("source") and prov.has("tools") and prov.has("extraction_scripts"), "provenance: source, tools and extraction_scripts")
	var files: Array = prov.get("files", [])
	check(files.size() == 67, "provenance: 67 files (%d)" % files.size())
	var by_path := {}
	for f in files:
		by_path[String(f["runtime_path"])] = f
		check(f is Dictionary and f.has("source_name") and f.has("source") and f.has("seconds") and f.has("lufs") and f.has("gain_db") and f.has("true_peak_db"), "provenance: fields on " + String(f["runtime_path"]))
		check(f["confirmed_by"] is Array and not f["confirmed_by"].is_empty(), "provenance: confirmed_by on " + String(f["runtime_path"]))
	check(by_path.size() == 67, "provenance: runtime paths are unique")
	var bad := 0
	for rel in sfx.manifest["clips"]:
		var path: String = "assets/audio/ba/" + String(rel)
		if not by_path.has(path):
			bad += 1
			print("  no provenance entry: ", path)
			continue
		var f: Dictionary = by_path[path]
		var c: Dictionary = sfx.manifest["clips"][rel]
		if String(f["sha256"]) != String(c["sha256"]) or not is_equal_approx(float(f["gain_db"]), float(c["gain_db"])) or absf(float(f["seconds"]) - float(c["seconds"])) > 0.001:
			bad += 1
			print("  manifest and provenance differ: ", path)
		var res: String = "res://" + path
		if FileAccess.get_sha256(res) != String(f["sha256"]):
			bad += 1
			print("  file differs from its recorded sha256: ", path)
		var fa := FileAccess.open(res, FileAccess.READ)
		if fa == null or fa.get_length() != int(f["bytes"]):
			bad += 1
			print("  size differs: ", path)
	check(bad == 0, "manifest, PROVENANCE.json and the files agree on sha256, bytes, seconds and gain (%d bad)" % bad)
	var on_disk := 0
	var unlisted := 0
	for dir in ["sfx", "voice/hina", "voice/hoshino"]:
		for name in DirAccess.get_files_at(BASE + dir):
			if name.ends_with(".wav") or name.ends_with(".ogg"):
				on_disk += 1
				if not by_path.has("assets/audio/ba/%s/%s" % [dir, name]):
					unlisted += 1
	check(on_disk == 67 and unlisted == 0, "every wav and ogg on disk has a provenance entry (%d files, %d unlisted)" % [on_disk, unlisted])
	var tabled := true
	for path in by_path:
		if "/SFX_Common_HMG_" in path or "/SFX_Common_SG_" in path:
			tabled = tabled and String(by_path[path]["confirmed_by"][0].get("table", "")) == "AudioAnimatorExcel"
	check(tabled, "provenance: every gun clip names its AudioAnimatorExcel row")
	check(by_path["assets/audio/ba/sfx/SFX_Common_SG_01.wav"]["confirmed_by"].size() == 2, "provenance: SG_01 names both its Normal and Stand rows")

# loudness
func _loudness() -> void:
	var prov := _json(BASE + "PROVENANCE.json")
	var over := 0
	var boosted := 0
	var overshoot := 0
	for f in prov.get("files", []):
		var gain := float(f["gain_db"])
		if float(f["true_peak_db"]) + gain > CEILING + 0.0001:
			over += 1
			print("  true peak past the ceiling: ", f["runtime_path"])
		if "/sfx/" in String(f["runtime_path"]) and gain > 0.0:
			boosted += 1
		if "/voice/" in String(f["runtime_path"]):
			if f["lufs"] == null and gain > 0.0:
				overshoot += 1
			elif f["lufs"] != null and float(f["lufs"]) + gain > -16.0 + 0.1001:
				overshoot += 1
	check(over == 0, "no recorded true peak plus gain passes -1.5 dB (%d)" % over)
	check(boosted == 0, "sfx gain never boosts")
	check(overshoot == 0, "voice gain never passes -16 LUFS (%d)" % overshoot)
	var wavs := 0
	var loud := 0
	var understated := 0
	for f in prov.get("files", []):
		var path := String(f["runtime_path"])
		if not path.ends_with(".wav"):
			continue
		var s := load("res://" + path) as AudioStreamWAV
		if s == null or s.format != AudioStreamWAV.FORMAT_16_BITS:
			check(false, "wav loads as 16-bit pcm: " + path)
			continue
		wavs += 1
		var peak := 0
		for i in range(0, s.data.size() - 1, 2):
			peak = maxi(peak, absi(s.data.decode_s16(i)))
		var db := linear_to_db(maxf(float(peak) / 32768.0, 0.000001))
		if db + float(f["gain_db"]) > CEILING + 0.0001:
			loud += 1
			print("  sample peak past the ceiling: ", path, " ", db)
		if db > float(f["true_peak_db"]) + 0.15:
			understated += 1
			print("  recorded true peak is below the sample peak: ", path, " ", db, " vs ", f["true_peak_db"])
	check(wavs == 43, "43 wavs decoded (%d)" % wavs)
	check(loud == 0, "no decoded wav sample peak plus gain passes -1.5 dB (%d)" % loud)
	check(understated == 0, "recorded true peaks are not below the decoded sample peaks (%d)" % understated)
