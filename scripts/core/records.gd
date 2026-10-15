class_name Records
extends RefCounted
## Persistent play records in user://records.json (matches, wins, best combo, per-fighter W/L, arcade clears).
## Written by FightScreen at the end of every match; read by the Extras screen.

const PATH := "user://records.json"

## Scripted runs (a step file's --script= after --, or a SceneTree test's --script) never write the player's real file.
## A test that needs to write points `path` at a scratch file.
static var path := PATH

static func _writes() -> bool:
	if path != PATH:
		return true
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--script" or a == "-s" or a.begins_with("--script="):
			return false
	return true

static func load_all() -> Dictionary:
	var base := {"matches": 0, "human_wins": 0, "best_combo": 0, "total_damage": 0.0, "arcade_clears": 0, "per_fighter": {}, "by_mode": {}}
	if not FileAccess.file_exists(path):
		return base
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return base
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return base
	for k in base:
		if not data.has(k):
			data[k] = base[k]
	return data

static func save_all(d: Dictionary) -> void:
	if not _writes():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

## Record one finished match. winner_id / loser_id are roster ids; human_won = a human beat the CPU
## (or in versus2p always true); stats = {combo, damage}.
static func add_match(mode: String, winner_id: int, loser_id: int, human_won: bool, stats: Dictionary) -> void:
	var d := load_all()
	d["matches"] = int(d["matches"]) + 1
	if human_won:
		d["human_wins"] = int(d["human_wins"]) + 1
	d["best_combo"] = maxi(int(d["best_combo"]), int(stats.get("combo", 0)))
	d["total_damage"] = float(d["total_damage"]) + float(stats.get("damage", 0.0))
	var pf: Dictionary = d["per_fighter"]
	for pair in [[winner_id, "wins"], [loser_id, "losses"]]:
		var key := str(pair[0])
		var row: Dictionary = pf.get(key, {"wins": 0, "losses": 0})
		row[pair[1]] = int(row[pair[1]]) + 1
		pf[key] = row
	var bm: Dictionary = d["by_mode"]
	bm[mode] = int(bm.get(mode, 0)) + 1
	save_all(d)

static func add_arcade_clear() -> void:
	var d := load_all()
	d["arcade_clears"] = int(d["arcade_clears"]) + 1
	save_all(d)
