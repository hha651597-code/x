extends SceneTree
## BA HUD art: provenance both ways, index borders, 9-slice rendering and lean, numerals, words, portraits, warnings.
## Run: TEST=res://scripts/ui/tests/ba_art_test.gd MAXLINES=300 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const HUD_DIR := "res://assets/ba/hud"
const RESULT_DIR := "res://assets/ba/portrait"
const STATES := ["scratched", "hurt", "critical", "flinch", "win", "lose", "ko"]

class Canvas extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(self)

var checks := 0
var failures: Array = []
var ART: GDScript
var NUM: GDScript
var WORDS: GDScript
var roster: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("BAART_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("BAART_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	ART = load("res://scripts/ui/ba_art.gd")
	NUM = load("res://scripts/ui/ba_numerals.gd")
	WORDS = load("res://scripts/ui/ba_words.gd")
	roster = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ba/roster.json"))
	_assets()
	_index()
	await _nine()
	await _additive()
	await _numerals()
	await _words()
	_portraits()
	_expressions()
	_warnings()
	print("BAART_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

## Renders fn(canvas) into a size viewport over bg and returns the image. bg.a = 0 gives a transparent viewport.
func _render(size: Vector2i, fn: Callable, bg := Color(0.5, 0.5, 0.5, 1.0)) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = bg.a < 1.0
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	if bg.a > 0.0:
		var r := ColorRect.new()
		r.color = bg
		r.size = Vector2(size)
		vp.add_child(r)
	var c := Canvas.new()
	c.fn = fn
	vp.add_child(c)
	for i in 3:
		await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img

func _images(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png") or f.ends_with(".webp"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_images(dir.path_join(d), out)

## Every tracked PNG and WebP has a PROVENANCE entry with the right hash, and every entry has its file.
func _assets() -> void:
	var f := FileAccess.open(HUD_DIR + "/PROVENANCE.json", FileAccess.READ)
	check(f != null, "PROVENANCE.json exists")
	if f == null:
		return
	var prov: Dictionary = JSON.parse_string(f.get_as_text())
	var listed := {}
	for e in prov["files"]:
		listed[str(e["runtime_path"])] = e
	var found: Array = []
	_images(HUD_DIR, found)
	check(found.size() >= 250, "at least 250 curated files (%d)" % found.size())
	check(found.size() == listed.size(), "as many files as entries (%d vs %d)" % [found.size(), listed.size()])
	var kinds := {"extracted": 0, "baked": 0}
	for path in found:
		var rel: String = (path as String).trim_prefix("res://")
		check(listed.has(rel), "provenance entry for " + rel)
		if not listed.has(rel):
			continue
		var e: Dictionary = listed[rel]
		check(FileAccess.get_sha256(path) == str(e["sha256"]), "sha256 matches for " + rel)
		check(FileAccess.get_file_as_bytes(path).size() == int(e["bytes"]), "byte count matches for " + rel)
		var k := str(e.get("kind", ""))
		check(kinds.has(k), "kind is extracted or baked for " + rel)
		if k == "extracted":
			check(str(e.get("bundle", "")).ends_with(".bundle") and str(e.get("container", "")) != "", "bundle and container recorded for " + rel)
		elif k == "baked":
			check(str(e.get("derived_from", "")) != "", "derived_from recorded for " + rel)
		kinds[k] = int(kinds.get(k, 0)) + 1
	for rel in listed:
		check(FileAccess.file_exists("res://" + str(rel)), "file exists for entry " + str(rel))
	check(kinds["baked"] >= 18, "the baked words are in provenance (%d)" % kinds["baked"])
	check(FileAccess.file_exists(HUD_DIR + "/README.md"), "README.md exists")

## Sprite sizes and borders in index.json against the files, and every indexed name against provenance.
func _index() -> void:
	var idx: Dictionary = ART.data()
	check(idx.has("sprites") and idx.has("tex") and idx.has("portraits") and idx.has("words") and idx.has("crests"), "index.json sections")
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HUD_DIR + "/PROVENANCE.json"))
	var listed := {}
	for e in prov["files"]:
		listed[str(e["runtime_path"])] = true
	for kind in ["sprites", "tex"]:
		for name in idx[kind]:
			var e: Dictionary = idx[kind][name]
			var path := "%s/%s/%s.png" % [HUD_DIR, kind, name]
			check(listed.has(path.trim_prefix("res://")), "indexed art has provenance: " + name)
			var t: Texture2D = load(path)
			check(t != null and t.get_width() == int(e["w"]) and t.get_height() == int(e["h"]), "index size matches the file: " + name)
			if kind != "sprites":
				continue
			var b: Array = e["borders"]
			check(int(b[0]) + int(b[1]) < int(e["w"]) and int(b[2]) + int(b[3]) < int(e["h"]), "borders leave a centre pixel: " + name)
			if e.has("source_borders"):
				var s: Array = e["source_borders"]
				check(int(s[0]) + int(s[1]) >= int(e["w"]) or int(s[2]) + int(s[3]) >= int(e["h"]), "adjusted borders had a reason: " + name)
				check(str(e.get("note", "")) != "", "adjusted borders carry a note: " + name)
	var hp: Dictionary = ART.info("Combat__Combat_Bg_Hp")
	check(hp["borders"] == [12, 12, 10, 14] and str(hp["note"]) != "", "Combat_Bg_Hp margins are 12/12/10/14")
	check(ART.has("Combat__Combat_Bg_Hp") and not ART.has("Combat__Nope"), "has()")
	ART.info("Combat__Combat_Bg_Hp")
	check(ART.tex("Combat__Combat_Bg_Hp") == ART.tex("Combat__Combat_Bg_Hp"), "textures are cached")
	for k in ["Combat__Combat_CostBg", "UIs__00_Images__Ingame_Start_Light", "Common__Card_Select_Line"]:
		check(ART.tex(k) != null, "tex() loads " + k)
	check(ART.info("UIs__00_Images__Ingame_Start_Light")["blend"] == "add" and ART.info("UIs__00_Images__Formation__UITex_BGBlueLight")["blend"] == "add", "the light textures are additive")
	check(ART.info("Combat__Combat_CostBg")["blend"] == "mix", "everything else mixes")
	check(ART.additive() == ART.additive() and ART.additive().blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "additive() is one shared add material")

## First and last column with a pixel that differs from the ground (or, on a transparent ground, has alpha).
func _ink_cols(img: Image, ground := Color(0.0, 0.0, 0.0, 0.0)) -> Vector2i:
	var x0 := img.get_width()
	var x1 := -1
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if (p.a > 0.02) if ground.a == 0.0 else (not _same(p, ground, 0.02)):
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
	return Vector2i(x0, x1)

func _same(a: Color, b: Color, tol := 0.012) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol

## nine(): the stretched centre has no seam (every row across it, every column down it, is one colour), a rect smaller than
## the borders still has no hole, tint multiplies, and shear leans "/" (the top edge sits right of the bottom edge).
func _nine() -> void:
	var sizes := [Vector2(200, 40), Vector2(25, 26), Vector2(60.5, 30.25), Vector2(10, 10), Vector2(7, 40), Vector2(300, 12)]
	var origin := Vector2(3.37, 2.62)
	for sz in sizes:
		var s: Vector2 = sz
		var canvas := Vector2i(int(s.x) + 12, int(s.y) + 12)
		var hp: Image = await _render(canvas, func(c: Node2D) -> void: ART.nine(c, "Combat__Combat_Bg_Hp", Rect2(origin, s)))
		var b: Array = ART.info("Combat__Combat_Bg_Hp")["borders"]
		var x0 := int(ceil(origin.x)) + int(b[0]) + 1
		var x1 := int(floor(origin.x + s.x)) - int(b[1]) - 1
		var y0 := int(ceil(origin.y)) + int(b[2]) + 1
		var y1 := int(floor(origin.y + s.y)) - int(b[3]) - 1
		var tag := "%dx%d" % [int(s.x), int(s.y)]
		var seams := 0
		if x1 > x0:
			for y in range(int(ceil(origin.y)) + 1, int(floor(origin.y + s.y)) - 1):
				for x in range(x0 + 1, x1 + 1):
					if not _same(hp.get_pixel(x, y), hp.get_pixel(x0, y)):
						seams += 1
		if y1 > y0:
			for x in range(int(ceil(origin.x)) + 1, int(floor(origin.x + s.x)) - 1):
				for y in range(y0 + 1, y1 + 1):
					if not _same(hp.get_pixel(x, y), hp.get_pixel(x, y0)):
						seams += 1
		check(seams == 0, "Combat_Bg_Hp at %s: no seam in the stretched centre (%d odd pixels)" % [tag, seams])
		var sol: Image = await _render(canvas, func(c: Node2D) -> void: ART.nine(c, "Common__Common_Bg_Raius10px", Rect2(origin, s)), Color(1.0, 0.0, 1.0, 1.0))
		var holes := 0
		var ry := mini(5, int(s.y * 0.5) - 1)
		for y in range(int(ceil(origin.y)) + ry, int(floor(origin.y + s.y)) - ry):
			for x in range(int(ceil(origin.x)) + 2, int(floor(origin.x + s.x)) - 2):
				var p := sol.get_pixel(x, y)
				if p.g < 0.9 or p.r < 0.9:
					holes += 1
		check(holes == 0, "Raius10px at %s: no hole or tear inside (%d)" % [tag, holes])
		var ink := _ink_cols(sol, Color(1.0, 0.0, 1.0, 1.0))
		check(ink.x >= int(origin.x) - 1 and ink.y <= int(origin.x + s.x) + 1 and ink.y - ink.x >= int(s.x) - 3, "Raius10px at %s: ink spans the rect (%s)" % [tag, str(ink)])
	# tint
	var tinted: Image = await _render(Vector2i(60, 40), func(c: Node2D) -> void: ART.nine(c, "Common__Common_Bg_Raius10px", Rect2(5, 5, 50, 30), Color(1.0, 0.2, 0.2)), Color(0.0, 0.0, 0.0, 1.0))
	var tp := tinted.get_pixel(30, 20)
	check(tp.r > 0.95 and tp.g < 0.3 and tp.b < 0.3, "nine() multiplies the tint (%s)" % str(tp))
	# lean
	var lean: Image = await _render(Vector2i(200, 90), func(c: Node2D) -> void: ART.nine(c, "Common__Common_Bg_Raius10px", Rect2(40, 10, 100, 60), Color.WHITE, ART.LEAN), Color(0.0, 0.0, 0.0, 0.0))
	var top_x := _row_left(lean, 16)
	var mid_x := _row_left(lean, 40)
	var bot_x := _row_left(lean, 64)
	check(top_x > mid_x and mid_x > bot_x, "nine() leans / : top %d, middle %d, bottom %d" % [top_x, mid_x, bot_x])
	check(absf(float(top_x - bot_x) - ART.LEAN * 48.0) <= 2.0, "the lean is %.4f px per px (%d px over 48 rows)" % [ART.LEAN, top_x - bot_x])
	check(absf(float(mid_x) - 40.0) <= 2.0, "the lean pivots on the centre row (left edge %d, rect left 40)" % mid_x)
	var blit: Image = await _render(Vector2i(200, 90), func(c: Node2D) -> void: ART.blit(c, "Combat__Combat_Time_Icon", Rect2(60, 10, 78, 70), Color.WHITE, ART.LEAN), Color(0.0, 0.0, 0.0, 0.0))
	check(_ink_cols(blit).y > 60, "blit() draws with the lean")
	var plain: Image = await _render(Vector2i(100, 60), func(c: Node2D) -> void: ART.blit(c, "Combat__Combat_Time_Icon", Rect2(10, 10, 39, 43)), Color(0.0, 0.0, 0.0, 0.0))
	var pi := _ink_cols(plain)
	check(pi.x >= 9 and pi.y <= 50 and pi.y - pi.x > 25, "blit() fills its rect (%s)" % str(pi))

## The flare only reads additive: on a mid grey it brightens, mixed it would show its black ground.
func _additive() -> void:
	var add: Image = await _render(Vector2i(120, 120), func(c: Node2D) -> void:
		var n := Canvas.new()
		n.material = ART.additive()
		n.fn = func(f: Node2D) -> void: ART.blit(f, "UIs__00_Images__Ingame_Start_Light", Rect2(0, 0, 120, 120))
		c.add_child(n))
	var mid := add.get_pixel(60, 60)
	check(mid.r > 0.8 and _same(add.get_pixel(2, 2), Color(0.5, 0.5, 0.5, 1.0), 0.02), "additive flare brightens its centre and leaves the corners (%s, %s)" % [str(mid), str(add.get_pixel(2, 2))])

func _row_left(img: Image, y: int) -> int:
	for x in img.get_width():
		if img.get_pixel(x, y).a > 0.5:
			return x
	return -1

func _ink_box(img: Image, a_min := 0.02) -> Rect2i:
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > a_min:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func _ink_count(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n

## Numerals: ten glyphs per tier, boxes inside the sheet and apart, every digit has ink and a shape of its own, and width()
## is the drawn extent.
func _numerals() -> void:
	var glyphs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HUD_DIR + "/numerals/glyphs.json"))
	check(glyphs["tiers"].size() == NUM.KEYS.size(), "a glyph table per tier")
	for tier in NUM.KEYS.size():
		var key: String = NUM.KEYS[tier]
		var t: Dictionary = glyphs["tiers"][key]
		var sheet: Texture2D = load("res://assets/ba/hud/" + str(t["file"]))
		check(sheet != null and t["glyphs"].size() == 10, "%s: ten glyphs" % key)
		var rects: Array = []
		for d in "0123456789":
			var r: Array = t["glyphs"][d]["rect"]
			rects.append(Rect2(r[0], r[1], r[2], r[3]))
			check(Rect2(0, 0, sheet.get_width(), sheet.get_height()).encloses(rects[-1]), "%s: glyph %s inside the sheet" % [key, d])
		var overlap := 0
		for i in 10:
			for j in range(i + 1, 10):
				if (rects[i] as Rect2).intersects(rects[j]):
					overlap += 1
		check(overlap == 0, "%s: glyph boxes do not overlap (%d)" % [key, overlap])
		var shots: Array = []
		for d in "0123456789":
			var img: Image = await _render(Vector2i(80, 90), func(c: Node2D) -> void: NUM.draw(c, d, Vector2(12, 10), 60.0, tier), Color(0.0, 0.0, 0.0, 0.0))
			check(_ink_count(img) > 300, "%s: digit %s has ink (%d)" % [key, d, _ink_count(img)])
			shots.append(img)
		var same := 0
		for i in 10:
			for j in range(i + 1, 10):
				if _images_equal(shots[i], shots[j]):
					same += 1
		check(same == 0, "%s: ten different digits (%d equal pairs)" % [key, same])
	# the string 0123456789 differs per digit cell, and cells line up with width()
	var text := "0123456789"
	var h := 56.0
	var strip: Image = await _render(Vector2i(int(NUM.width(text, h)) + 40, 80), func(c: Node2D) -> void: NUM.draw(c, text, Vector2(20, 8), h, NUM.Tier.NORMAL), Color(0.0, 0.0, 0.0, 0.0))
	var cells: Array = []
	for i in 10:
		var x0 := 20 + (0 if i == 0 else int(NUM.width(text.substr(0, i), h)) + int(round(float(-4) * h / 59.0)))
		var x1 := 20 + int(NUM.width(text.substr(0, i + 1), h))
		cells.append(strip.get_region(Rect2i(x0, 0, x1 - x0, 80)))
	var dup := 0
	for i in 10:
		check(_ink_count(cells[i]) > 300, "'0123456789' cell %d has ink" % i)
		for j in range(i + 1, 10):
			if (cells[i] as Image).get_size() == (cells[j] as Image).get_size() and _images_equal(cells[i], cells[j]):
				dup += 1
	check(dup == 0, "draw('0123456789') differs per digit (%d equal cells)" % dup)
	# width() against the ink, for several tiers, heights and strings
	for tier in [NUM.Tier.NORMAL, NUM.Tier.WHITE, NUM.Tier.MINI, NUM.Tier.RESIST]:
		for hh in [24.0, 40.0, 78.0]:
			for s in ["1234567890", "129", "7"]:
				var w: float = NUM.width(s, hh, tier)
				var img: Image = await _render(Vector2i(int(w) + 40, int(hh) + 30), func(c: Node2D) -> void: NUM.draw(c, s, Vector2(20, 8), hh, tier), Color(0.0, 0.0, 0.0, 0.0))
				var box := _ink_box(img)
				check(absf(float(box.size.x) - w) <= 1.0, "width('%s', %d, %s) = %.1f, drawn %d" % [s, int(hh), NUM.KEYS[tier], w, box.size.x])
				check(absf(float(box.position.x) - 20.0) <= 1.0, "'%s' starts at pos.x (%d)" % [s, box.position.x])
				check(box.size.y >= int(hh * 0.95) and box.size.y <= int(hh * 1.15) + 2, "'%s' at %d px is about that tall (%d)" % [s, int(hh), box.size.y])
	# alignment
	for al in 3:
		var img: Image = await _render(Vector2i(400, 60), func(c: Node2D) -> void: NUM.draw(c, "4096", Vector2(200, 8), 40.0, NUM.Tier.WEAK, Color.WHITE, al), Color(0.0, 0.0, 0.0, 0.0))
		var box := _ink_box(img)
		var w: float = NUM.width("4096", 40.0, NUM.Tier.WEAK)
		var expect: float = [200.0, 200.0 - w * 0.5, 200.0 - w][al]
		check(absf(float(box.position.x) - float(expect)) <= 1.5, "align %d starts at %.1f (drawn %d)" % [al, expect, box.position.x])
	check(NUM.width("", 40.0) == 0.0 and NUM.width("12", 40.0) > NUM.width("1", 40.0), "width() grows with the text")
	check(NUM.width("0123", 80.0) > NUM.width("0123", 40.0) * 1.9, "width() scales with the height")

func _images_equal(a: Image, b: Image) -> bool:
	return a.get_data() == b.get_data()

## Words: every one in the index loads and has ink, and draw() puts it where it says.
func _words() -> void:
	var words: Dictionary = ART.data()["words"]
	for w in ["fight", "start", "win", "lose", "vs", "warning", "block", "block_resist", "miss", "immune", "combo", "best_record",
			"round_1", "round_2", "round_3", "final", "ko", "super", "ex_ready", "just_guard", "guard_crush"]:
		check(words.has(w), "word listed: " + w)
		var t: Texture2D = WORDS.tex(w)
		check(t != null, "word loads: " + w)
		if t == null:
			continue
		check(_ink_count(t.get_image()) > 500, "word has ink: " + w)
	check(words.size() == 30, "30 words (%d)" % words.size())
	for w in ["fight", "ko", "block", "ex_ready"]:
		var img: Image = await _render(Vector2i(500, 200), func(c: Node2D) -> void: WORDS.draw(c, w, Vector2(250, 100), 300.0), Color(0.0, 0.0, 0.0, 0.0))
		var box := _ink_box(img, 0.1)
		var tex: Texture2D = WORDS.tex(w)
		var tb := _ink_box(tex.get_image(), 0.1)
		var k := 300.0 / float(tex.get_width())
		var want := Rect2((Vector2(tb.position) - Vector2(tex.get_size()) * 0.5) * k + Vector2(250, 100), Vector2(tb.size) * k)
		check(absf(float(box.position.x) - want.position.x) <= 2.5 and absf(float(box.size.x) - want.size.x) <= 3.0
				and absf(float(box.position.y) - want.position.y) <= 2.5 and absf(float(box.size.y) - want.size.y) <= 3.0,
				"draw(%s) puts the word at %s (ink %s)" % [w, str(want), str(box)])
	check(WORDS.tex("round_2").get_width() >= 400 and WORDS.tex("ko").get_height() >= 200, "baked words are 2x size")

## Every roster fighter and special resolves to a portrait, MISSING.txt lists exactly the fallbacks, every school has a crest.
func _portraits() -> void:
	var idx: Dictionary = ART.data()["portraits"]
	var people: Array = roster["fighters"] + roster["specials"]
	check(roster["fighters"].size() == 2 and roster["specials"].size() == 81, "2 fighters and 81 specials in the roster")
	var fallback_ids := {}
	for p in people:
		var id: int = int(p["id"])
		check(idx.has(str(id)), "portrait entry for %s (%d)" % [p["name"], id])
		var t: Texture2D = ART.portrait(id)
		check(t != null and t.get_width() == 252 and t.get_height() == 204, "portrait resolves for %s (%d)" % [p["name"], id])
		var s: Texture2D = ART.portrait_small(id)
		check(s != null, "small portrait resolves for %s" % p["name"])
		if idx.has(str(id)):
			if bool(idx[str(id)]["fallback"]):
				fallback_ids[id] = true
			else:
				check(idx[str(id)]["small"] != null and s.get_width() == 182 and s.get_height() == 144, "Small variant for %s is 182x144" % p["name"])
	var listed := {}
	for line in FileAccess.get_file_as_string(HUD_DIR + "/portraits/MISSING.txt").split("\n"):
		if line.strip_edges() != "" and not line.begins_with("#"):
			listed[int(line.split(" ")[0])] = true
	check(listed == fallback_ids, "MISSING.txt matches the fallbacks (%d listed, %d fallbacks)" % [listed.size(), fallback_ids.size()])
	for id in fallback_ids:
		check(str(idx[str(id)]["file"]).ends_with("_fallback.png"), "fallback file name for %d" % id)
	var seen := {}
	for p in people:
		seen[str(idx[str(int(p["id"]))]["file"])] = true
	check(seen.size() == people.size(), "no two ids share a portrait (%d files for %d ids)" % [seen.size(), people.size()])
	var schools := {}
	for p in people:
		schools[p["school"]] = true
	check(schools.size() == 10, "ten schools in the roster (%d)" % schools.size())
	for school in schools:
		var c: Texture2D = ART.school_crest(school)
		check(c != null and c.get_width() == ART.CREST_PX, "crest for %s" % school)
	var white := 0
	var crest: Image = ART.school_crest("Gehenna").get_image()
	for y in crest.get_height():
		for x in crest.get_width():
			var px := crest.get_pixel(x, y)
			if px.a > 0.5:
				white += 1
				check(px.r > 0.99 and px.g > 0.99 and px.b > 0.99, "crest ink is white")
				break
	check(white > 10, "the crest has ink")
	var roles := {}
	var attacks := {}
	for p in people:
		roles[p["role"]] = true
		attacks[p["bullet"]] = true
	for r in roles:
		check(ART.role_icon(r) != null, "role icon: " + r)
	var colours := {}
	for a in attacks:
		colours[ART.attack_color(a)] = true
		check(ART.ATTACK.has(a), "attack colour: " + a)
	check(colours.size() == attacks.size(), "attack colours differ")

## Expression art (tools/hud_expressions.py): all eight HUD states per fighter on the calm card's parallelogram, a win and a lose
## result image on the canvas of the plain one, provenance for each, and every state really differs from its base.
func _expressions() -> void:
	var dir := HUD_DIR + "/portraits"
	var ex: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/expressions.json"))
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RESULT_DIR + "/PROVENANCE.json"))
	var listed := {}
	for e in prov["files"]:
		listed[str(e["runtime_path"])] = e
	var found: Array = []
	for f in DirAccess.get_files_at(RESULT_DIR):
		if f.ends_with("_win.webp") or f.ends_with("_lose.webp"):
			found.append(RESULT_DIR.path_join(f))
	check(found.size() == 4 and listed.size() == 4, "4 result images with 4 provenance entries (%d, %d)" % [found.size(), listed.size()])
	for path in found:
		var rel: String = (path as String).trim_prefix("res://")
		check(listed.has(rel) and FileAccess.get_sha256(path) == str(listed[rel]["sha256"]), "result image hash matches provenance: " + rel)
		check(listed.has(rel) and str(listed[rel]["derived_from"]).begins_with("tools/hud_expressions.py"), "result image names its tool: " + rel)
	var ids := {}
	for p in roster["fighters"]:
		var id := str(int(p["id"]))
		ids[id] = true
		check(ex.has(id), "expressions.json has %s" % p["name"])
		if not ex.has(id):
			continue
		var calm := _img(dir.path_join(ex[id]["calm"]))
		check(calm.get_width() == 252 and calm.get_height() == 204, "calm is 252x204 for %s" % p["name"])
		for st in STATES:
			var fn: String = str(ex[id].get(st, ""))
			check(fn != "" and FileAccess.file_exists(dir.path_join(fn)), "%s has a %s tile" % [p["name"], st])
			if fn == "":
				continue
			var im := _img(dir.path_join(fn))
			check(im.get_size() == calm.get_size(), "%s %s tile is 252x204" % [p["name"], st])
			var moved := 0
			var shape := 0
			for y in range(0, 204, 2):
				for x in range(0, 252, 2):
					var a := calm.get_pixel(x, y)
					var b := im.get_pixel(x, y)
					if a.a > 0.9 and absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
						moved += 1
					if absf(a.a - b.a) > 0.25:
						shape += 1
			check(moved >= 20, "%s %s tile differs from calm (%d px)" % [p["name"], st, moved])
			check(shape < 100, "%s %s tile keeps the parallelogram (%d px off)" % [p["name"], st, shape])
		var base := _img("%s/%s.webp" % [RESULT_DIR, id])
		for st in ["win", "lose"]:
			var im := _img("%s/%s_%s.webp" % [RESULT_DIR, id, st])
			check(im.get_size() == base.get_size(), "%s %s image has the portrait's canvas" % [p["name"], st])
			var moved := 0
			for y in range(0, base.get_height(), 4):
				for x in range(0, base.get_width(), 4):
					var a := base.get_pixel(x, y)
					var b := im.get_pixel(x, y)
					if a.a > 0.9 and absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
						moved += 1
			check(moved >= 20, "%s %s image differs from the portrait (%d px)" % [p["name"], st, moved])
	for id in ex.get("_overlays", {}):
		check(ids.has(id), "overlay entry %s is a roster id" % id)
		for st in ex["_overlays"][id]:
			check(STATES.has(st) and not (ex["_overlays"][id][st] as Array).is_empty(), "overlay entry %s %s names a state and an overlay" % [id, st])

func _img(path: String) -> Image:
	return (load(path) as Texture2D).get_image()

## Nothing above warned; a missing name gives null and exactly one warning, however often it is asked for.
func _warnings() -> void:
	check(ART.warnings().is_empty(), "no runtime warning from our files: %s" % str(ART.warnings()))
	check(ART.tex("ZZZ_missing") == null and ART.tex("ZZZ_missing") == null, "a missing name is null")
	check(WORDS.tex("ZZZ_word") == null and ART.portrait(1) == null and ART.school_crest("ZZZ_school") == null, "missing words, ids and schools are null")
	check(ART.info("ZZZ_missing").is_empty(), "info() of a missing name is empty")
	check(ART.warnings().size() == 4, "one warning per missing name: %s" % str(ART.warnings()))
