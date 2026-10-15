extends SceneTree
## Records: a scripted run never writes the player's real user://records.json, a scratch path does round-trip.
## Run: TEST=res://scripts/ui/tests/records_test.gd zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const SCRATCH := "user://records_test_scratch.json"

var checks := 0
var failures: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("RECORDS_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	var R: GDScript = load("res://scripts/core/records.gd")
	var real: String = R.PATH
	check(R.path == real, "the default path is the real file")
	var before := _stamp(real)
	R.add_match("versus-cpu", 10004, 10005, true, {"combo": 3, "damage": 40.0})
	R.add_arcade_clear()
	R.save_all({"matches": 99})
	check(_stamp(real) == before, "a scripted run leaves the real records file alone")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	R.path = SCRATCH
	R.add_match("versus-cpu", 10004, 10005, true, {"combo": 3, "damage": 40.0})
	R.add_match("versus2p", 10005, 10004, true, {"combo": 7, "damage": 10.0})
	R.add_arcade_clear()
	var d: Dictionary = R.load_all()
	check(int(d["matches"]) == 2 and int(d["human_wins"]) == 2, "a scratch path records matches (%s)" % d.get("matches"))
	check(int(d["best_combo"]) == 7 and int(d["arcade_clears"]) == 1, "best combo and arcade clears")
	check(int(d["per_fighter"]["10004"]["wins"]) == 1 and int(d["per_fighter"]["10004"]["losses"]) == 1, "per fighter rows")
	check(_stamp(real) == before, "the scratch run still leaves the real file alone")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	R.path = real
	print("RECORDS_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

## Content hash of a user:// file (empty when absent): "not written" without reading the player's data into the log.
func _stamp(path: String) -> String:
	return FileAccess.get_md5(path)
