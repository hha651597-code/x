extends SceneTree
## The Extras screen (gallery). Asset hashes, the numeral and text helpers, tab and focus flow, grid navigation over the fighters
## and 81 specials with scrolling, the longest text of every student, the jukebox (the player box, the track strip, the transport row, the albums), the
## records model with empty and very long data, real pixels, and a copy lint over the Extras files.
## Run: TEST=res://scripts/ui/tests/extras_test.gd MAXLINES=200 zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const OWNED := [
	"res://scripts/screens/gallery_screen.gd", "res://scripts/ui/gallery_kit.gd", "res://scripts/ui/gallery_characters.gd",
	"res://scripts/ui/gallery_jukebox.gd", "res://scripts/ui/gallery_records.gd", "res://scripts/ui/gallery_plate.gd",
	"res://scripts/ui/special_panel.gd",
]
# Files that keep a hex colour on purpose, and why. The colour lint in ui_kit_test.gd carries the same exemptions.
const HEX_EXEMPT := {
	"gallery_kit.gd": "the per-school facet tints are data keyed by school",
	"special_panel.gd": "the Special Select popup's own palette, read off BA's popup and used once each",
}
const BANNED := ["delve", "seamless", "elevate", "unlock", "empower", "streamline", "effortless", "supercharge", "lorem ipsum", "—"]

var checks := 0
var failures: Array = []
var game: Node
var K: GDScript
var CH: GDScript
var JB: GDScript
var RC: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("EXTRAS_CHECK FAIL ", label)
		failures.append(label)

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _run() -> void:
	create_timer(480.0).timeout.connect(func() -> void:
		print("EXTRAS_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	AudioServer.set_bus_mute(0, true)
	K = load("res://scripts/ui/gallery_kit.gd")
	CH = load("res://scripts/ui/gallery_characters.gd")
	JB = load("res://scripts/ui/gallery_jukebox.gd")
	RC = load("res://scripts/ui/gallery_records.gd")
	game = root.get_node("Game")
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	_assets()
	_kit()
	_statics()
	await _tabs()
	await _characters()
	await _jukebox()
	await _jukebox_mouse()
	_jukebox_data()
	await _bgm_engine()
	_header_fit()
	await _records()
	_moves_from_kits()
	_armour_chips()
	_plate_clip()
	await _footer_device()
	_bgm_lengths()
	_lint()
	game.session.bgm = "auto"
	print("EXTRAS_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _screen() -> Node:
	return game.stack.back()

func _open(tab: String, extra := {}) -> Node:
	var p := {"tab": tab}
	p.merge(extra)
	await game.go("gallery", p, "cut")
	await _wait(0.6)
	return _screen()

# ── assets ───────────────────────────────────────────────────────────────────
func _assets() -> void:
	var f := FileAccess.open("res://assets/ba/gallery/PROVENANCE.json", FileAccess.READ)
	check(f != null, "gallery PROVENANCE.json opens")
	if f == null:
		return
	var prov: Dictionary = JSON.parse_string(f.get_as_text())
	var files: Array = prov["files"]
	check(files.size() >= 5, "provenance lists the gallery files (%d)" % files.size())
	for e in files:
		var path := "res://" + String(e["runtime_path"])
		check(FileAccess.get_sha256(path) == String(e["sha256"]), "sha256 of " + String(e["runtime_path"]))
		check(FileAccess.get_file_as_bytes(path).size() == int(e["bytes"]), "byte count of " + String(e["runtime_path"]))
		check(String(e["bundle"]) != "" and String(e["container"]) != "", "bundle and container named for " + String(e["runtime_path"]))
		var t: Texture2D = load(path)
		check(t != null and t.get_width() == int(e["width"]) and t.get_height() == int(e["height"]), "size of " + String(e["runtime_path"]))
	for stem in ["Common__Card_Item_Bg_N", "Common__Common_Icon_Formation_Star", "Common__Common_Icon_Formation_Star_Disable", "Common__Common_Deco_DotLine", "UIs__00_Images__Image_Normal_Empty2"]:
		check(K.art(stem) != null, "kit loads " + stem)

# ── helpers ──────────────────────────────────────────────────────────────────
func _kit() -> void:
	var rs: Array = K.runs("83,240")
	check(rs == [["83", true], [",", false], ["240", true]], "runs split a grouped number into digits and a comma")
	check(K.runs("26×3") == [["26", true], ["×", false], ["3", true]], "runs keep the multiplication sign")
	check(K.runs("0:06 / 2:16").size() == 7, "runs keep colons, spaces and the slash")
	var joined := ""
	for r in K.runs("64% 1,234 hits"):
		joined += r[0]
	check(joined == "64% 1,234 hits", "runs lose no character")
	check(K.number_width("83,240", 20.0) > K.number_width("83240", 20.0), "a comma adds width, it is not dropped")
	check(K.number_width("64%", 20.0) > K.number_width("64", 20.0), "a percent sign adds width")
	check(K.number_width("", 20.0) == 0.0, "no text, no width")
	check(K.group(1234567) == "1,234,567" and K.group(0) == "0" and K.group(999) == "999" and K.group(1000) == "1,000" and K.group(-4200) == "-4,200", "group")
	var wide := "Finish a match in any of these modes and your results show up on this page."
	var lines: Array = K.wrap_text(wide, 600, 19, 300.0)
	var ok := lines.size() > 1
	for l in lines:
		ok = ok and (K.Menu.text_width(l, 19, 600) <= 300.0 or " " not in l)
	check(ok, "wrap_text keeps every line inside the width (%d lines)" % lines.size())
	check(K.wrap_text("", 600, 14, 100.0).is_empty(), "wrap_text of nothing")
	check(K.wrap_text("Supercalifragilisticexpialidocious", 600, 14, 40.0).size() == 1, "one long word keeps its own line")
	var fp: Dictionary = K.fit_paragraph("A short line.", 600, 14, 12, 400.0, 2)
	check(fp["fits"] and fp["size"] == 14, "a short paragraph stays at the top size")
	var fp2: Dictionary = K.fit_paragraph(wide + " " + wide + " " + wide, 600, 14, 12, 200.0, 2)
	check(not fp2["fits"] and fp2["size"] == 12, "a paragraph that cannot fit says so after shrinking")
	check(K.fit_number("1,186,442", 34.0, 120.0) < 34.0 and K.number_width("1,186,442", K.fit_number("1,186,442", 34.0, 120.0)) <= 120.0, "fit_number shrinks a long figure into its cell")
	check(K.fit_number("42", 34.0, 120.0) == 34.0, "fit_number leaves a short figure alone")
	for school in K.SCHOOL_TINT:
		check(K.tint_of({"school": school}) != Color.WHITE, "tint for " + school)
	check(K.tint_of({"school": "nowhere"}) == K.tint_of({"school": "abydos"}), "an unknown school falls back")
	var w: Texture2D = K.white_of(BaArt.tex("Common__Common_Attack_Icon"))
	var img := w.get_image()
	var all_white := true
	var any := false
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				any = true
				all_white = all_white and c.r > 0.99 and c.g > 0.99 and c.b > 0.99
	check(any and all_white, "white_of gives a white silhouette")

func _statics() -> void:
	check(JB.fmt_time(136.77) == "2:16" and JB.fmt_time(-3.0) == "0:00" and JB.fmt_time(59.9) == "0:59" and JB.fmt_time(600.0) == "10:00", "fmt_time")
	check(JB.progress(30.0, 120.0, true) == 0.25 and JB.progress(30.0, 120.0, false) == 0.0 and JB.progress(500.0, 120.0, true) == 1.0 and JB.progress(5.0, 0.0, true) == 1.0, "progress is the played share, 0 when the track is not live")
	check(JB.window_for(0, 0.0, 15) == 0.0 and JB.window_for(14, 0.0, 15) == 9.0 and JB.window_for(3, 9.0, 15) == 3.0 and JB.window_for(9, 2.0, 15) == 4.0 and JB.window_for(5, 2.0, 15) == 2.0, "window_for keeps the cursor card in view")
	check(JB.window_for(0, 0.0, 5) == 0.0, "a short strip never scrolls")
	var seen := {}
	for i in 5:
		var br: Rect2 = JB.button_rect(i)
		seen[i] = br
		check(Rect2(Vector2.ZERO, JB.PLAYER.size).encloses(br), "transport button %d sits inside the player box" % i)
	check(not (seen[0] as Rect2).intersects(seen[1]) and not (seen[1] as Rect2).intersects(seen[2]) and not (seen[2] as Rect2).intersects(seen[3]) and not (seen[3] as Rect2).intersects(seen[4]), "the transport buttons do not touch")

# ── tabs and focus ───────────────────────────────────────────────────────────
func _tabs() -> void:
	var scr := await _open("characters")
	check(scr.probe()["tab"] == "characters" and scr.probe()["focus"] == "page", "opens on the Characters page with the page focused")
	scr.on_action("kb1", "rb")
	check(scr.probe()["tab"] == "jukebox", "rb goes to Jukebox")
	scr.on_action("kb1", "rb")
	check(scr.probe()["tab"] == "records", "rb goes to Records")
	scr.on_action("kb1", "rb")
	check(scr.probe()["tab"] == "records", "rb stops at the last tab")
	await _wait(0.5)
	check(is_zero_approx((scr._pages[2] as Control).position.x), "the new page has settled")
	scr.on_action("kb1", "lb")
	scr.on_action("kb1", "lb")
	scr.on_action("kb1", "lb")
	check(scr.probe()["tab"] == "characters", "lb walks back to Characters and stops")
	check((scr._pages[1] as Control).visible == false and (scr._pages[2] as Control).visible == false, "only the current page is visible")
	scr.on_action("kb1", "rb")
	await _wait(0.4)
	scr.on_action("kb1", "up")
	check(scr.probe()["focus"] == "page" and scr.probe()["page"]["zone"] == "ctl", "on the Jukebox the first up moves to the transport row")
	scr.on_action("kb1", "up")
	check(scr.probe()["focus"] == "tabs", "up from the top of a page moves to the tab bar")
	scr.on_action("kb1", "right")
	check(scr.probe()["tab"] == "records", "right on the tab bar switches tab")
	scr.on_action("kb1", "down")
	check(scr.probe()["focus"] == "page", "down returns to the page")
	await _wait(0.2)
	for i in 3:
		check((scr._tabs[i] as GalleryKit.Tab).selected == (i == 2), "tab %d selected flag" % i)
	scr.on_action("kb1", "up")
	await _wait(0.2)
	check((scr._tabs[2] as GalleryKit.Tab).focused, "the selected tab shows its bracket while the tab bar has focus")
	scr.on_action("kb1", "down")

# ── characters ───────────────────────────────────────────────────────────────
func _characters() -> void:
	var scr := await _open("characters")
	var pg: Control = scr._page(0)
	var fighters: Array = game.fighters
	var specials: Array = game.specials
	check(fighters.size() == 2 and specials.size() == 81, "2 fighters and 81 specials (%d, %d)" % [fighters.size(), specials.size()])
	var pr: Dictionary = pg.probe()
	check(pr["index"] == 0 and pr["mode"] == "fighters" and pr["count"] == 2, "starts on the first fighter")
	pg.handle("right")
	check(pg.probe()["index"] == 1, "right reaches the second tile")
	check(pg.handle("up") == false, "up off the top row is not consumed (the screen moves to the tab bar)")
	pg.handle("down")
	check(pg.probe()["index"] == 1, "down on the only row stays put")
	check(pg.handle("left") == true and pg.probe()["index"] == 0, "left is consumed")
	pg.handle("left")
	check(pg.probe()["index"] == 0, "left stops at the first tile")
	pg.handle("right")
	pg.handle("right")
	check(pg.probe()["index"] == 1, "right stops at the last fighter")
	check(pg.probe()["name"] == Fighters.display_name(fighters[1]) and int(pg.probe()["id"]) == int(fighters[1]["id"]), "the probe names the highlighted fighter")
	check(pg._max_scroll() == 0.0, "the two fighters fit the window without scrolling")
	pg.handle("aux")
	await process_frame
	pr = pg.probe()
	check(pr["mode"] == "specials" and pr["count"] == 81 and pr["index"] == 0, "aux switches to 81 specials, first one highlighted")
	for i in 80:
		pg.handle("right")
	pr = pg.probe()
	check(pr["index"] == 80 and int(pr["id"]) == int(specials[80]["id"]), "right x80 reaches the last special")
	check(is_equal_approx(pg._scroll_to, pg._max_scroll()) and pg._max_scroll() > 0.0, "the list is scrolled to its end (%.0f of %.0f px)" % [pg._scroll_to, pg._max_scroll()])
	var row_top: float = pg.TILE_Y0 + float(int(80 / pg.COLS)) * pg.PITCH.y - pg._scroll_to
	check(row_top >= 0.0 and row_top + pg.TILE.y <= pg.VIEW.size.y, "the last tile is inside the window")
	for i in 80:
		pg.handle("left")
	check(pg.probe()["index"] == 0 and is_zero_approx(pg._scroll_to), "left x80 returns to the top and scrolls back")
	for i in 15:
		pg.handle("down")
	check(pg.probe()["index"] == 75, "down x15 reaches row 15")
	pg.handle("right")
	pg.handle("right")
	pg.handle("right")
	check(pg.probe()["index"] == 78, "tile 78 is the last of row 15")
	pg.handle("down")
	check(pg.probe()["index"] == 80, "down from a short last row's column that does not exist goes to the last tile")
	var vis_ok := true
	for i in 81:
		pg._select(i, false, false)
		var top: float = pg.TILE_Y0 + float(int(i / pg.COLS)) * pg.PITCH.y - pg._scroll_to
		vis_ok = vis_ok and top >= -0.01 and top + pg.TILE.y <= pg.VIEW.size.y + 0.01
	check(vis_ok, "every special scrolls into the window when selected")
	pg._select(2, false, false)
	pg.handle("aux")
	check(pg.probe()["mode"] == "fighters" and pg.probe()["index"] == 1, "each mode keeps its own highlight")
	await _characters_fit()
	await _characters_pixels(scr, pg)

## The longest text of every student fits: layout() is the pure function the popup draws from.
func _characters_fit() -> void:
	var worst := {"intro": 0, "name": "", "ex": "", "club": ""}
	var bad := []
	for kind in 2:
		var list: Array = game.specials if kind == 1 else game.fighters
		for s in list:
			var lay: Dictionary = CH.layout(s, kind == 1)
			if not lay["fits"]:
				bad.append(Fighters.display_name(s))
			var intro: Dictionary = lay["intro"]
			check_quiet(intro["fits"] and intro["size"] >= 12, bad, "intro of " + Fighters.display_name(s))
			for line in intro["lines"]:
				check_quiet(K.Menu.text_width(line, intro["size"], 600) <= CH.IW + 2.0, bad, "intro line of " + Fighters.display_name(s))
			var nm: String = lay["name"]
			var font := UI.font_name()
			var fit_px := 48
			while fit_px > 16 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fit_px).x > CH.IW - 140.0:
				fit_px -= 1
			check_quiet(fit_px >= 30, bad, "name size of " + nm)
			if String(s["intro"]).length() > int(worst["intro"]):
				worst["intro"] = String(s["intro"]).length()
			if nm.length() > String(worst["name"]).length():
				worst["name"] = nm
			for f in lay["facts"]:
				var v := String(f[1])
				var sz: int = K.Menu.fit(v, 16, 190.0, 11, 800)
				check_quiet(K.Menu.text_width(v, sz, 800) <= (CH.IW if f[0] == "Club" else 190.0), bad, "fact %s of %s" % [f[0], nm])
			var ex := String(lay["ex"])
			var exs: int = K.Menu.fit(ex, 17, CH.IW - 112.0, 11, 800)
			check_quiet(K.Menu.text_width(ex, exs, 800) <= CH.IW - 112.0, bad, "EX name of " + nm)
			for c in lay["chips"]:
				var cs: int = K.Menu.fit(String(c[1]), 15, CH.CHIP_SIZE.x - 66.0, 10, 800)
				check_quiet(K.Menu.text_width(String(c[1]), cs, 800) <= CH.CHIP_SIZE.x - 66.0, bad, "chip %s of %s" % [c[0], nm])
			if kind == 0:
				for row in lay["rows"]:
					var ds: int = K.Menu.fit(row[1], 12, CH.TABLE_COLS[0] - 56.0, 9, 600)
					check_quiet(K.Menu.text_width(row[1], ds, 600) <= CH.TABLE_COLS[0] - 56.0, bad, "move %s of %s" % [row[0], nm])
				check_quiet((lay["rows"] as Array).size() == 8, bad, "eight move rows for " + nm)
			else:
				check_quiet(float(lay["tab_h"]) >= 112.0, bad, "assist card height for " + nm)
				var nmw: String = Fighters.display_name(s)
				var ns: int = K.Menu.fit(nmw, 12, CH.TILE.x - 28.0, 8, 800)
				check_quiet(ns >= 9 and K.Menu.text_width(nmw, ns, 800) <= CH.TILE.x - 28.0, bad, "tile label of " + nmw)
	check(bad.is_empty(), "every string of all 111 students fits (first failures: %s)" % str(bad.slice(0, 4)))
	print("S3 longest: intro %d chars, name %s" % [worst["intro"], worst["name"]])

func check_quiet(ok: bool, bad: Array, label: String) -> void:
	if not ok:
		bad.append(label)

func _characters_pixels(scr: Node, pg: Control) -> void:
	pg._select(0, false, false)
	await _wait(1.0)
	var img := await _grab()
	var sc := float(img.get_width()) / 1280.0
	var yellow := []
	for k in [0, 3]:
		var at: Vector2 = pg.VIEW.position + Vector2(pg.TILE_X0 + float(k) * pg.PITCH.x, pg.TILE_Y0)
		var n := 0
		for y in range(int(at.y * sc), int((at.y + pg.TILE.y) * sc)):
			for x in range(int(at.x * sc), int((at.x + pg.TILE.x) * sc)):
				var c := img.get_pixel(x, y)
				if c.r > 0.85 and c.g > 0.75 and c.b < 0.45:
					n += 1
		yellow.append(n)
	check(yellow[0] >= 40 and yellow[1] <= 2, "only the selected tile carries the yellow bracket (%d px against %d)" % [yellow[0], yellow[1]])
	var cut := 0
	for y in range(int(pg.VIEW.position.y * sc), int(pg.VIEW.end.y * sc)):
		for x in range(int((pg.VIEW.end.x - 3.0) * sc), int((pg.VIEW.end.x - 1.0) * sc)):
			var c := img.get_pixel(x, y)
			if c.r > 0.7 and c.b < 0.45:
				cut += 1
	check(cut == 0, "the right column of tiles is not cut flat by the window edge (%d warm px on the last two columns)" % cut)
	var plate := img.get_pixel(int((pg.INFO.position.x + pg.IX + 8.0) * sc), int((pg.INFO.position.y + pg.NAME_Y + pg.NAME_H * 0.5) * sc))
	check(plate.b > plate.r and plate.r < 0.25 and plate.b < 0.45, "the name plate is navy (%s)" % str(plate))
	var body := img.get_pixel(int((pg.INFO.position.x + pg.IW - 20.0) * sc), int((pg.INFO.position.y + 330.0) * sc))
	check(body.r > 0.9 and body.g > 0.9, "the popup body is near white (%s)" % str(body))
	var tab := img.get_pixel(int((scr.TAB_X0 + 12.0) * sc), int((scr.TAB_Y + 20.0) * sc))
	check(tab.r > 0.85 and tab.g > 0.8 and tab.b < 0.5, "the selected tab is the yellow plate (%s)" % str(tab))
	var off := img.get_pixel(int((scr.TAB_X0 + scr.TAB_PITCH + 12.0) * sc), int((scr.TAB_Y + 20.0) * sc))
	check(off.b > off.r and off.r < 0.25, "the other tabs are navy (%s)" % str(off))

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

# ── jukebox ──────────────────────────────────────────────────────────────────
func _jukebox() -> void:
	game.session.bgm = "auto"
	game.session.jukebox_shuffle = false
	game.session.jukebox_repeat = "one"
	var bgm: Node = root.get_node("Bgm")
	var scr := await _open("jukebox")
	var pg: Control = scr._page(1)
	var tracks: Array = bgm.tracks()
	check(pg._items.size() == tracks.size() + 1 and pg._items[0]["id"] == "auto", "AUTO plus %d tracks" % tracks.size())
	var pr: Dictionary = pg.probe()
	check(pr["cursor"] == "auto" and pr["playing"] == "auto" and pr["zone"] == "strip", "starts on the playing card (Auto), in the strip")
	check(pg.handle("left") == true and pg.probe()["cursor"] == "auto", "left off the first card stays on it")
	for i in 3:
		pg.handle("right")
	check(pg.probe()["cursor"] == tracks[2]["id"], "right x3 reaches the third track")
	pg.handle("confirm")
	check(game.session.bgm == tracks[2]["id"] and pg.probe()["playing"] == tracks[2]["id"], "confirm plays the track by setting the session bgm")
	await _wait(1.5)
	pr = pg.probe()
	check(pr["live"] and pr["pos"] > 0.5 and pr["len"] > 10.0, "the position runs while it plays (pos %.2f of %.2f)" % [pr["pos"], pr["len"]])
	var frac: float = JB.progress(pr["pos"], pr["len"], pr["live"])
	check(frac > 0.0 and frac < 0.2, "progress is a small share early in the track (%.3f)" % frac)
	pg.handle("right")
	await _wait(0.3)
	check(pg.probe()["live"] == false and pg.probe()["pos"] == 0.0, "another card's gauge stays at zero")
	pg.handle("left")
	await _wait(0.3)
	check(pg.probe()["live"] == true, "back on the playing card it is live again")
	# the box names the composer and the album of the selected track
	for i in 2:
		pg.handle("left")
	check(pg.probe()["cursor"] == tracks[0]["id"] and pg.probe()["composer"] == "Mitsukiyo" and pg.probe()["album"] == "Blue Archive Original Soundtrack Vol.1" and pg.probe()["subtitle"] == "Longing for the Memorable Days", "Constant Moderato shows Mitsukiyo and Vol.1 (%s)" % [pg.probe()["album"]])
	pg.handle("right")
	pg.handle("right")
	check(pg.probe()["cursor"] == "pachad" and pg.probe()["album"] == "Blue Archive Original Soundtrack" and pg.probe()["subtitle"] == "" and pg.probe()["cover"] == "generic.jpg", "PACHAD is on no listed volume: the generic soundtrack card")
	# transport row: up from the strip, play focused first
	check(pg.handle("up") == true and pg.probe()["zone"] == "ctl" and pg.probe()["ctl"] == "play", "up from the strip focuses the transport row on Play")
	pg.handle("confirm")
	check(bgm.paused and pg.probe()["paused"], "Play on the playing track pauses it")
	var held: float = bgm.position()
	await _wait(0.5)
	check(absf(bgm.position() - held) < 0.12, "paused music holds its position (%.2f to %.2f)" % [held, bgm.position()])
	check(pg.button_caption(2) == "PLAY", "the button reads PLAY while paused")
	pg.handle("confirm")
	check(not bgm.paused and pg.button_caption(2) == "PAUSE", "Play again resumes it")
	await _wait(0.3)
	check(bgm.position() > held, "and the position runs on")
	# next and previous follow the track order and the cursor goes with them
	pg.handle("right")
	check(pg.probe()["ctl"] == "next", "right moves to Next")
	pg.handle("confirm")
	check(game.session.bgm == tracks[3]["id"] and pg.probe()["cursor"] == tracks[3]["id"], "Next plays the track after and the cursor follows (%s)" % game.session.bgm)
	pg.handle("left")
	pg.handle("left")
	check(pg.probe()["ctl"] == "prev", "left twice from Next is Previous")
	pg.handle("confirm")
	check(game.session.bgm == tracks[2]["id"] and pg.probe()["cursor"] == tracks[2]["id"], "Previous goes back")
	game.session.bgm = tracks[0]["id"]
	pg.handle("confirm")
	check(game.session.bgm == tracks[-1]["id"], "Previous from the first track wraps to the last")
	pg.handle("right")
	pg.handle("right")
	pg.handle("confirm")
	check(game.session.bgm == tracks[0]["id"], "Next from the last track wraps to the first")
	# shuffle and repeat
	pg.handle("left")
	pg.handle("left")
	pg.handle("left")
	check(pg.probe()["ctl"] == "shuffle" and not game.session.jukebox_shuffle, "shuffle starts off")
	pg.handle("confirm")
	check(game.session.jukebox_shuffle and pg.button_caption(0) == "SHUFFLE ON", "the Shuffle button turns it on")
	var always_other := true
	for i in 12:
		var before: String = game.session.bgm
		bgm.step(1)
		always_other = always_other and game.session.bgm != before and bgm.has_track(game.session.bgm)
	check(always_other, "with shuffle every Next is a different track")
	pg.handle("right")
	pg.handle("right")
	pg.handle("right")
	pg.handle("right")
	check(pg.probe()["ctl"] == "repeat" and game.session.jukebox_repeat == "one" and pg.button_caption(4) == "REPEAT ONE", "repeat starts on One")
	pg.handle("confirm")
	check(game.session.jukebox_repeat == "all" and pg.button_caption(4) == "REPEAT ALL", "the Repeat button switches to All")
	pg.handle("confirm")
	check(game.session.jukebox_repeat == "one", "and back to One")
	check(pg.handle("down") == true and pg.probe()["zone"] == "strip", "down returns to the strip")
	pg.handle("up")
	check(pg.handle("up") == false, "up from the transport row goes on to the tabs")
	pg.handle("down")
	game.session.jukebox_shuffle = false
	# no source line and no volume bar any more
	var src: String = FileAccess.get_file_as_string("res://scripts/ui/gallery_jukebox.gd")
	check(not src.contains("spectrum") and not src.contains("_Viz") and not src.contains("BGM VOLUME") and not src.contains("\"SOURCE\"") and not src.contains("bgm_volume"), "no visualiser, source line or volume bar")
	# pixels: the time readout is dark numerals on the light box, the unplayed gauge the navy track
	game.session.bgm = tracks[2]["id"]
	pg.handle("confirm")
	await _wait(1.0)
	var img := await _grab()
	var s := float(img.get_width()) / 1280.0
	var gx: float = (pg.PLAYER.position.x + pg.GAUGE.position.x + 600.0) * s
	var gy: float = (pg.PLAYER.position.y + pg.GAUGE.position.y + 11.0) * s
	var dark := 0
	var rx: float = (pg.PLAYER.position.x + pg.GAUGE.end.x - 4.0) * s
	for y in range(int((pg.PLAYER.position.y + pg.GAUGE.position.y - 28.0) * s), int((pg.PLAYER.position.y + pg.GAUGE.position.y - 11.0) * s)):
		for x in range(int(rx - 70.0 * s), int(rx)):
			var c := img.get_pixel(x, y)
			if c.r < 0.3 and c.g < 0.35 and c.b < 0.5:
				dark += 1
	check(dark >= 30, "the time readout is dark numerals on the light box (%d dark px)" % dark)
	var g := img.get_pixel(int(gx), int(gy))
	check(g.b > g.r and g.r < 0.2 and g.b < 0.4, "the unplayed part of the gauge is the navy track (%s)" % str(g))
	game.session.bgm = "auto"

## The strip's cards and the box stay on the page, and a click on a card plays it, on a button presses it.
func _jukebox_mouse() -> void:
	game.session.bgm = "auto"
	var bgm: Node = root.get_node("Bgm")
	var scr := await _open("jukebox")
	var pg: Control = scr._page(1)
	await _wait(0.4)
	check(JB.PLAYER.end.y < JB.STRIP.position.y and JB.PLAYER.position.y > 60.0 and JB.STRIP.end.y <= 690.0, "the player box is above the strip and both clear the footer")
	for i in pg._cards.size():
		var cr := Rect2(pg._cards[i]["home"] - Vector2(pg._scroll * JB.PITCH, 0.0), JB.CARD)
		check(Rect2(Vector2.ZERO, JB.STRIP.size + Vector2(JB.PITCH, 0.0)).encloses(cr) or i >= JB.VISIBLE, "card %d starts inside the strip" % i)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	pg._on_card_input(click, 4)
	check(game.session.bgm == bgm.tracks()[3]["id"] and pg.probe()["cursor"] == bgm.tracks()[3]["id"], "a click on a card selects and plays it")
	pg._on_button_input(click, 3)
	check(game.session.bgm == bgm.tracks()[4]["id"] and pg.probe()["zone"] == "ctl", "a click on Next plays the next track")
	pg._on_button_input(click, 2)
	check(bgm.paused, "a click on Play pauses the playing track")
	pg._on_button_input(click, 2)
	check(not bgm.paused, "and a second click resumes it")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	pg._on_card_input(wheel, 0)
	check(pg.probe()["cursor"] == bgm.tracks()[5]["id"], "the wheel over a card steps the selection right")
	# the selection bracket sits under the number disc, not over it
	await _wait(0.6)
	var img := await _grab()
	var k := float(img.get_width()) / 1280.0
	var card: Control = pg._cards[pg._cursor]["node"]
	var xf: Transform2D = card.get_global_transform_with_canvas()
	var dc: Vector2 = xf * JB.disc_rect().get_center()
	var yellow := 0
	for dy in range(-16, 17):
		for dx in range(-16, 17):
			if Vector2(dx, dy).length() > 15.0:
				continue
			var px := img.get_pixel(clampi(int((dc.x + dx) * k), 0, img.get_width() - 1), clampi(int((dc.y + dy) * k), 0, img.get_height() - 1))
			if px.r > 0.9 and px.g > 0.8 and px.b < 0.35:
				yellow += 1
	check(card.sel and yellow == 0, "no bracket yellow inside the selected card's number disc (%d px)" % yellow)
	pg.set_active(false)
	pg._on_button_input(click, 0)
	check(not game.session.jukebox_shuffle, "a hidden page ignores the mouse")
	pg.set_active(true)
	bgm.set_paused(false)
	game.session.bgm = "auto"

## The track to album map, the covers, and the settings the jukebox saves.
func _jukebox_data() -> void:
	var bgm: Node = root.get_node("Bgm")
	var data: Dictionary = JB.albums()
	for t in bgm.tracks():
		check(data["tracks"].has(t["id"]), "%s is in the album map" % t["id"])
		var alb: Dictionary = JB.album_of(t["id"])
		var cv: Texture2D = JB.cover_of(t["id"])
		check(cv != null and cv.get_size() == Vector2(512, 512), "%s has a 512x512 cover (%s)" % [t["id"], alb["cover"]])
	check(JB.album_of("pachad")["cover"] == "generic.jpg" and JB.album_of("nope")["cover"] == "generic.jpg", "a track on no volume and an unknown id get the generic card")
	check(JB.album_of("aoharu")["name"] == "Blue Archive Original Soundtrack Vol.3" and JB.album_of("fury-of-set")["subtitle"] == "Harmonizing for the Hearts of Each", "the wiki's volumes: Aoharu on Vol.3, Fury of Set on Vol.7")
	var prov: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ba/jukebox/PROVENANCE.json"))
	for f in prov:
		check(FileAccess.file_exists("res://assets/ba/jukebox/" + f) and FileAccess.get_sha256("res://assets/ba/jukebox/" + f) == prov[f]["sha256"], "%s matches its recorded hash" % f)
	for id in data["albums"]:
		check(prov.has(data["albums"][id]["cover"]), "%s's cover has a provenance entry" % id)
	# shuffle and repeat survive a restart, and a hand-edited file falls back
	var sess: GDScript = load("res://scripts/core/session.gd")
	var real_path: String = sess.settings_path
	var scratch := "user://zzz_jukebox_settings.cfg"
	sess.settings_path = scratch
	var a = sess.new()
	a.jukebox_shuffle = true
	a.jukebox_repeat = "all"
	a.save_settings()
	var b = sess.new()
	check(b.jukebox_shuffle == true and b.jukebox_repeat == "all", "shuffle and repeat are saved and loaded")
	var cf := ConfigFile.new()
	cf.set_value("audio", "shuffle", "yes")
	cf.set_value("audio", "repeat", "loop")
	cf.save(scratch)
	var c = sess.new()
	check(c.jukebox_shuffle == false and c.jukebox_repeat == "one", "a bad shuffle or repeat value falls back to off and One")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	sess.settings_path = real_path

## Bgm: the order, shuffle's die, the hand over rule, and a hand over that really happens.
func _bgm_engine() -> void:
	var bgm: Node = root.get_node("Bgm")
	var ids: Array = bgm.tracks().map(func(t: Dictionary) -> String: return t["id"])
	check(bgm.neighbour(ids[0], 1, false, 0.0) == ids[1] and bgm.neighbour(ids[-1], 1, false, 0.0) == ids[0], "neighbour goes forward and wraps")
	check(bgm.neighbour(ids[0], -1, false, 0.0) == ids[-1] and bgm.neighbour(ids[5], -1, false, 0.0) == ids[4], "and backward and wraps")
	check(bgm.neighbour("auto", 1, false, 0.0) == ids[0] and bgm.neighbour("auto", -1, false, 0.0) == ids[-1] and bgm.neighbour("", 1, false, 0.0) == ids[0], "from no track it enters the list at an end")
	check(bgm.neighbour(ids[0], 1, true, 0.0) == ids[1] and bgm.neighbour(ids[0], 1, true, 0.999) == ids[-1], "shuffle's die spans every other track")
	var never_same := true
	for i in 101:
		never_same = never_same and bgm.neighbour(ids[3], 1, true, float(i) / 100.0) != ids[3]
	check(never_same, "shuffle never picks the track it is on")
	check(bgm.handover_due(116.7, 119.0) and not bgm.handover_due(100.0, 119.0) and not bgm.handover_due(5.0, 0.0), "the hand over is due END_LEAD before the end")
	# Previous under shuffle returns to the track that was left
	game.session.jukebox_shuffle = true
	game.session.bgm = ids[0]
	await _wait(0.3)
	bgm._history.clear()
	bgm.step(1)
	var second: String = game.session.bgm
	await _wait(0.3)
	bgm.step(-1)
	check(game.session.bgm == ids[0] and second != ids[0], "Previous under shuffle goes back to the track that was left")
	game.session.jukebox_shuffle = false
	# repeat all: near the end the music moves on by itself, repeat one keeps looping
	game.session.bgm = ids[0]
	await _wait(0.8)
	game.session.jukebox_repeat = "one"
	bgm._pl[bgm._cur].seek(bgm.length() - 1.0)
	await _wait(0.2)
	check(game.session.bgm == ids[0], "with repeat One the track is not left at its end")
	game.session.bgm = ids[1]
	await _wait(0.8)
	game.session.jukebox_repeat = "all"
	bgm._pl[bgm._cur].seek(bgm.length() - 1.0)
	await _wait(0.2)
	check(game.session.bgm == ids[2], "with repeat All the music moves on to the next track near the end (%s)" % game.session.bgm)
	game.session.jukebox_repeat = "one"
	game.session.bgm = "auto"
	bgm.set_paused(false)

## The Extras title and its subtitle stay inside the bar's light face, apart from each other.
func _header_fit() -> void:
	var sc: GDScript = load("res://scripts/screens/gallery_screen.gd")
	for tab in 3:
		var rr: Array = sc.head_text_rects(tab)
		var face := Rect2(0.0, 4.0, 1280.0, sc.HEAD_FACE - 4.0 - 4.0)
		check(face.encloses(rr[0]) and face.encloses(rr[1]), "tab %d: the title and the subtitle sit inside the bar's face (%s, %s)" % [tab, rr[0], rr[1]])
		check(rr[0].end.y < rr[1].position.y - 2.0, "tab %d: the subtitle clears the title" % tab)

# ── records ──────────────────────────────────────────────────────────────────
func _records() -> void:
	check(not RC.COUNTED_MODES.has("Training") and RC.COUNTED_MODES.size() == 3, "the empty page lists only the modes whose matches can finish")
	var by_id: Dictionary = game.by_id
	var e: Dictionary = RC.model({}, by_id)
	check(e["empty"] and e["matches"] == 0 and (e["modes"] as Array).is_empty() and e["fighters"] == 0, "no data is the empty state")
	var data := {"matches": 42, "human_wins": 27, "best_combo": 31, "total_damage": 83240.0, "arcade_clears": 3,
			"by_mode": {"versus2p": 18, "versus-cpu": 14, "training": 7, "arcade": 3, "extra": 1},
			"per_fighter": {"10004": {"wins": 9, "losses": 4}, "10005": {"wins": 7, "losses": 6}, "20001": {"wins": 5, "losses": 1},
				"10017": {"wins": 0, "losses": 0}, "99999": {"wins": 3, "losses": 3}}}
	var m: Dictionary = RC.model(data, by_id)
	check(not m["empty"] and m["matches"] == 42 and m["wins"] == 27 and m["losses"] == 15, "totals")
	check(absf(float(m["rate"]) - 64.2857) < 0.01 and m["per_match"] == 1982 and m["damage"] == 83240, "win rate and damage per match")
	check((m["modes"] as Array).size() == 4 and m["modes"][0][0] == "versus2p" and m["modes"][3][0] == "arcade", "modes sorted, four at most")
	check(m["mode_total"] == 43, "percent base counts every mode (%d)" % m["mode_total"])
	check(m["fighters"] == 3, "unknown ids and fighters with no games are skipped (%d)" % m["fighters"])
	check(m["most"][0]["id"] == 10004 and m["most"][1]["id"] == 10005 and m["most"][2]["id"] == 20001, "most played order")
	check(m["best"][0]["id"] == 20001 and m["best"][1]["id"] == 10004 and m["best"][2]["id"] == 10005, "best record order")
	var tie: Dictionary = RC.model({"matches": 4, "per_fighter": {"10005": {"wins": 2, "losses": 0}, "10004": {"wins": 2, "losses": 0}}}, by_id)
	check(tie["most"][0]["id"] == 10004 and tie["best"][0]["id"] == 10004, "ties break by wins then id")
	var scr := await _open("records", {"records": {"matches": 0}})
	var pg: Control = scr._page(2)
	check(pg.probe()["empty"] == true, "the page shows the empty state")
	await _wait(1.2)
	var img := await _grab()
	var s := float(img.get_width()) / 1280.0
	var hit := 0
	var card: Rect2 = RC.EMPTY
	for y in range(int((card.position.y + 160.0) * s), int((card.position.y + 420.0) * s), 4):
		for x in range(int((card.position.x + 60.0) * s), int((card.position.x + 380.0) * s), 4):
			var c := img.get_pixel(x, y)
			if c.r > 0.9 and c.g > 0.9 and c.b > 0.9:
				hit += 1
	check(hit > 200, "Plana is drawn on the empty page (%d light px)" % hit)
	var big := {"matches": 9999999, "human_wins": 7654321, "best_combo": 123456, "total_damage": 9876543210.0, "arcade_clears": 999999,
			"by_mode": {"versus2p": 5000000, "versus-cpu": 4999999}, "per_fighter": {}}
	var bm: Dictionary = RC.model(big, by_id)
	check(bm["damage"] == 987654321 * 10 and bm["per_match"] == 988, "very long figures survive the model")
	var room: float = RC.CELL.x - 30.0
	for v in [K.group(int(bm["matches"])), K.group(int(bm["wins"])), K.group(int(bm["damage"])), K.group(int(bm["best_combo"])) , "100%"]:
		var h: float = K.fit_number(v, RC.STAT_H, room, BaNumerals.Tier.MINI, 16.0)
		check(h >= 16.0 and K.number_width(v, h) <= room, "%s fits its stat cell at %.0f px" % [v, h])
	scr = await _open("records", {"records": big})
	await _wait(2.6)
	check(scr._page(2).probe()["matches"] == 9999999 and scr._page(2).probe()["empty"] == false, "the page renders the long data")
	img = await _grab()
	s = float(img.get_width()) / 1280.0
	var ribbon := img.get_pixel(int((RC.OVERVIEW.position.x + 24.0 + 176.0) * s), int((RC.OVERVIEW.position.y + RC.HEAD_H + 16.0 + 12.0) * s))
	check(ribbon.b > ribbon.r and ribbon.r < 0.25, "a stat label ribbon is navy (%s)" % str(ribbon))
	var ink := 0
	var num := Rect2((RC.OVERVIEW.position + Vector2(34.0, RC.HEAD_H + 16.0 + 32.0)) * s, Vector2(210.0, 34.0) * s)
	for y in range(int(num.position.y), int(num.end.y), 2):
		for x in range(int(num.position.x), int(num.end.x), 2):
			var c := img.get_pixel(x, y)
			if c.b > 0.5 and c.r < 0.35 and c.g < 0.6:
				ink += 1
	check(ink > 20, "the first figure is drawn in D_Font blue (%d px)" % ink)

# ── fixes ────────────────────────────────────────────────────────────────────
## The move table reads each fighter's own kit, and a kit move with no damage or decorative spawns cannot break it.
func _moves_from_kits() -> void:
	var kits: GDScript = load("res://scripts/fight/kits.gd")
	var bad := []
	for s in game.fighters:
		var kit = kits.make(s)
		var mv: Dictionary = kit.build_moves(kit.build_stats())
		var rows: Array = CH.move_rows(s)
		check_quiet(rows.size() == 8, bad, "%s has 8 rows" % s["key"])
		for r in rows:
			var m: Dictionary = mv[r[6]]
			check_quiet([r[3], r[4], r[5]] == [int(m["startup"]), int(m["active"]), int(m["recovery"])], bad, "%s %s frames" % [s["key"], r[6]])
	check(bad.is_empty(), "the move table shows every fighter's own kit frames (first failures: %s)" % str(bad.slice(0, 4)))
	check(CH._damage_of({}) == [0, 1], "a move with nothing in it shows 0")
	check(CH._damage_of({"hit": {}, "spawns": [{"hit": {}, "explode": {}}]}) == [0, 1], "a decorative spawn is not a shot")
	check(CH._damage_of({"hit": {"dmg": 66.0}, "spawns": [{"hit": {}, "explode": {}}]}) == [66, 1], "the move's own damage stands when its spawns deal none")
	check(CH._damage_of({"hit": {}, "spawns": [{"hit": {}}, {"hit": {"dmg": 44.8}}, {"hit": {"dmg": 44.8}}]}) == [45, 2], "only the spawns that deal damage count as shots")
	check(CH._damage_of({"spawns": [{"hit": {"dmg": 5.0}, "explode": {"hit": {"dmg": 30.0}}}]}) == [30, 1], "a shot that explodes shows its blast")
	var src := FileAccess.get_file_as_string("res://scripts/ui/gallery_characters.gd")
	check(not src.contains("about 10 s"), "the assist card states no recharge time that depends on who calls it")

func _armour_chips() -> void:
	var map: Dictionary = K.ARMOR_AS_BULLET
	check(map["LightArmor"] == "Explosion" and map["HeavyArmor"] == "Pierce" and map["ElasticArmor"] == "Sonic" and map["Unarmed"] == "Mystic", "armour chips take the colour of the attack type that beats the armour")
	check(BaArt.attack_color(map[game.by_id[10004]["armor"]]) == BaArt.attack_color("Pierce"), "Hina's heavy armour is coloured Pierce")

## Art that rises above the card is not cut along the card's slant, the slant still cuts the card itself.
func _plate_clip() -> void:
	var plate: Control = load("res://scripts/ui/gallery_plate.gd").new().setup(CH.PLATE_BOX.size)
	plate.set_plate(CH.FIGHTER_CARD, CH.FIGHTER_CARD.position.y - 8.0)
	var poly: PackedVector2Array = plate.clip_polygon()
	var top: float = CH.FIGHTER_CARD.position.y
	check(Geometry2D.is_point_in_polygon(Vector2(CH.PLATE_BOX.size.x - 6.0, top - 24.0), poly), "hair and arms above the card run to the plate's right edge")
	check(Geometry2D.is_point_in_polygon(CH.FIGHTER_CARD.get_center(), poly), "the card itself is inside")
	check(not Geometry2D.is_point_in_polygon(Vector2(CH.PLATE_BOX.size.x - 6.0, CH.FIGHTER_CARD.end.y - 24.0), poly), "below its top edge the card's slant still cuts the art")
	plate.free()

## Space and Esc are shared keys: they never turn the footer's Q / E prompts into raw action names.
func _footer_device() -> void:
	var scr := await _open("characters")
	scr.on_action("kb2", "right")
	scr.on_action("shared", "confirm")
	check(scr._last_dev == "kb2" and root.get_node("Controls").label_for(scr._last_dev, "lb") != "lb", "a shared key does not change the prompts' device")

## Track lengths are data: the jukebox never loads a track to print its time.
func _bgm_lengths() -> void:
	var bgm: Node = root.get_node("Bgm")
	var off := []
	for trk in bgm.tracks():
		var real: float = bgm._stream_for(trk["id"]).get_length()
		if absf(real - float(trk.get("len", -1.0))) > 0.05:
			off.append(trk["id"])
	check(off.is_empty(), "every track's len is its file's length (%s)" % str(off))
	var id: String = bgm.tracks()[-1]["id"]
	bgm._streams.erase(id)
	var loaded: int = bgm._streams.size()
	check(is_equal_approx(bgm.length_of(id), float(bgm.track(id)["len"])) and bgm._streams.size() == loaded, "length_of reads the table and loads nothing")
	check(bgm.length_of("nope") == 0.0, "an unknown track has no length")

# ── copy and colours ─────────────────────────────────────────────────────────
func _lint() -> void:
	var rx := RegEx.new()
	rx.compile("Color\\(\\s*\"#?[0-9a-fA-F]{3,8}\"")
	for path in OWNED:
		var src := FileAccess.get_file_as_string(path).to_lower()
		for w in BANNED:
			check(not src.contains(w), "%s has no %s" % [path.get_file(), w])
		var hex := rx.search(FileAccess.get_file_as_string(path))
		if HEX_EXEMPT.has(path.get_file()):
			check(hex != null, "%s has no hex colour left, so drop its HEX_EXEMPT entry (%s)" % [path.get_file(), HEX_EXEMPT[path.get_file()]])
		else:
			check(hex == null, "%s keeps its colours in BaTokens" % path.get_file())
