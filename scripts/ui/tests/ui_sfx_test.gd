extends SceneTree
## The game's own sounds are Blue Archive clips: assets/audio/ba/ui_map.json names a clip (or several) for every sound the code plays, the
## clips exist, load and are sane, their provenance matches, and Sfx.play uses them (the right gain, no variant twice in a row).
## It cannot say how anything sounds: the choice of clip per sound was made from names and measurements, see tools/sfx_ui_assets.py.
## Run: TEST=res://scripts/ui/tests/ui_sfx_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real small window)

const BASE := "res://assets/audio/ba/"
# every sound name the game plays by itself or falls back to (Fighter.sfx events, the HUD, the screens)
const NEEDED := ["tick", "confirm", "back", "whoosh", "pop", "claim", "crest", "error", "lock", "slam", "fight", "hit_l", "hit_h", "block",
	"just_guard", "guard_crush", "shot", "shot_big", "beam", "launch", "boom", "flame", "charge", "super", "ko", "jump", "land", "dash",
	"throw", "tech", "grab", "swing", "ex_ready", "ult_rise", "ult_stamp", "ult_release"]

var checks := 0
var failures: Array = []
var sfx: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("UI_SFX_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		print("UI_SFX_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	sfx = root.get_node("Sfx")
	_map()
	_call_sites()
	_provenance()
	_playing()
	print("UI_SFX_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _map() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "ui_map.json"))["sounds"]
	check(sfx.ui.size() == m.size() and not sfx.ui.is_empty(), "Sfx loaded the map (%d sounds)" % sfx.ui.size())
	for n in NEEDED:
		check(m.has(n), "%s is mapped" % n)
	var used := {}
	for n in m:
		check(NEEDED.has(n), "%s is a sound the game plays" % n)
		var e: Dictionary = m[n]
		check(float(e["db"]) <= 0.0 and float(e["db"]) >= -30.0, "%s: its gain is a sane attenuation (%s dB)" % [n, e["db"]])
		check(not (e["clips"] as Array).is_empty(), "%s has a clip" % n)
		for rel in e["clips"]:
			used[String(rel).get_file()] = true
			var st := load(BASE + rel) as AudioStreamWAV
			check(st != null, "%s loads" % rel)
			if st != null:
				var len := st.get_length()
				check(len >= 0.03 and len <= 2.0, "%s is between 0.03 and 2 s long (%.2f)" % [rel, len])
				check(not st.stereo and st.format == AudioStreamWAV.FORMAT_16_BITS, "%s is mono 16 bit" % rel)
	var on_disk := []
	for f in DirAccess.get_files_at(BASE + "ui"):
		if f.ends_with(".wav"):
			on_disk.append(f)
	check(on_disk.size() == used.size() and on_disk.all(func(f: String) -> bool: return used.has(f)), "every clip file is used and every used clip exists (%d files)" % on_disk.size())
	check(not sfx.has_method("_mix") and sfx.get("_sounds") == null, "the synthesiser is gone")

## Every literal Sfx.play("name") and fighter.sfx("name") in the game's scripts names a mapped sound, or an event of a fighter's own set
## in manifest.json (spool, reload, first_aid ... : those play for Hina and Hoshino and were never a generic sound).
func _call_sites() -> void:
	var rx := RegEx.new()
	rx.compile("(?:Sfx\\.play|[a-z_]*sfx\\.play|\\bsfx)\\(\"([a-z_0-9]+)\"")
	var own := {}
	for who in sfx.manifest.get("sets", {}):
		for ev in sfx.manifest["sets"][who].get("sfx", {}):
			own[ev] = true
	var unmapped := {}
	var n_sites := 0
	for dir in ["res://scripts/ui", "res://scripts/screens", "res://scripts/fight", "res://scripts/core"]:
		for path in _gd_files(dir):
			for m in rx.search_all(FileAccess.get_file_as_string(path)):
				n_sites += 1
				if not sfx.ui.has(m.get_string(1)) and not own.has(m.get_string(1)):
					unmapped[path.get_file() + ":" + m.get_string(1)] = true
	check(n_sites > 60, "the scan found the call sites (%d)" % n_sites)
	check(unmapped.is_empty(), "every played sound name is mapped (unmapped: %s)" % str(unmapped.keys()))

func _gd_files(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and not dir.ends_with("tests"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		if d != "tests" and d != "tools":
			out.append_array(_gd_files(dir + "/" + d))
	return out

func _provenance() -> void:
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "ui/PROVENANCE.json"))
	var files := []
	for f in DirAccess.get_files_at(BASE + "ui"):
		if f.ends_with(".wav"):
			files.append(f)
	check(prov.size() == files.size(), "every clip has a provenance entry (%d)" % prov.size())
	for f in prov:
		check(FileAccess.file_exists(BASE + "ui/" + f) and FileAccess.get_sha256(BASE + "ui/" + f) == prov[f]["sha256"], "%s matches its recorded hash" % f)
		check(String(prov[f]["bundle"]).contains("audio") and String(prov[f]["clip"]) != "", "%s names its client bundle and clip" % f)

func _playing() -> void:
	sfx.set_volume(0.8)
	sfx.stop_all()
	var before: int = sfx.played.get("tick", 0)
	sfx.play("tick")
	check(int(sfx.played.get("tick", 0)) == before + 1, "play counts the call")
	var p: AudioStreamPlayer = sfx._players[(sfx._next + sfx._players.size() - 1) % sfx._players.size()]
	var want_db: float = linear_to_db(0.8) + float(sfx.ui["tick"]["db"])
	check(p.playing and absf(p.volume_db - want_db) < 0.05, "tick plays at the map's gain (%.2f, wanted %.2f)" % [p.volume_db, want_db])
	check(p.stream.resource_path.begins_with(BASE + "ui/tick_"), "and it is the tick clip (%s)" % p.stream.resource_path)
	sfx.play("claim", 1.2, 0.5)
	p = sfx._players[(sfx._next + sfx._players.size() - 1) % sfx._players.size()]
	check(is_equal_approx(p.pitch_scale, 1.2) and absf(p.volume_db - (linear_to_db(0.4) + float(sfx.ui["claim"]["db"]))) < 0.05, "pitch and volume arguments still apply")
	# a sound with several clips never repeats one back to back
	var last := ""
	var repeats := 0
	var seen := {}
	for i in 24:
		sfx.play("hit_l")
		p = sfx._players[(sfx._next + sfx._players.size() - 1) % sfx._players.size()]
		var rp := p.stream.resource_path
		if rp == last:
			repeats += 1
		last = rp
		seen[rp] = true
	check(repeats == 0 and seen.size() >= 3, "hit_l varies and never repeats a clip back to back (%d clips used)" % seen.size())
	sfx.play("not_a_sound")
	check(int(sfx.played.get("not_a_sound", 0)) == 1, "an unmapped name is counted and silent, not an error")
	sfx.set_volume(0.0)
	sfx.play("tick")
	sfx.set_volume(0.8)
	sfx.stop_all()
