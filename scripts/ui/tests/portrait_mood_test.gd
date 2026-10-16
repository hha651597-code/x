extends SceneTree
## HUD portrait faces: the PortraitMood thresholds and hysteresis, hud_top's card per state (hp, flinch, pause, KO, win,
## round reset), the BaArt fallback chain, result-screen faces, and every roster id against assets/ba/hud/portraits/expressions.json.
## Run: TEST=res://scripts/ui/tests/portrait_mood_test.gd MAXLINES=300 zsh tools/sd_test.sh   (a real window, never headless)
## A state the json does not name falls back to the calmer face, and the coverage line
## says how many of the roster's tiles are their own. A json that names a missing file fails; a json that names every
## fighter must give every one of them every state.
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const DT := 1.0 / 60.0
const STATES := ["calm", "scratched", "hurt", "critical", "flinch", "win", "lose", "ko"]
const TILE := {"calm": Color(0.2, 0.9, 0.2), "scratched": Color(0.9, 0.9, 0.2), "hurt": Color(0.9, 0.5, 0.1),
	"critical": Color(0.9, 0.1, 0.1), "flinch": Color(0.1, 0.1, 0.9), "win": Color(0.9, 0.2, 0.9), "lose": Color(0.1, 0.8, 0.8),
	"ko": Color(0.9, 0.2, 0.2)}

class StubFighter extends RefCounted:
	var data := {"id": 10004, "name": "Hina", "school": "Gehenna", "role": "DamageDealer", "bullet": "Explosion"}
	var hp := 1000.0
	var max_hp := 1000.0

class StubWorld extends Node:
	var fighters: Array = []
	var timer_frames := 3600
	var training := false
	var mode := "versus2p"
	var wins := [0, 0]
	var phase := "fight"
	var round_no := 1
	var paused := false

var checks := 0
var failures: Array = []
var M: GDScript
var TOP: GDScript
var ART: GDScript
var RESULT: GDScript
var game: Node

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("MOOD_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(170.0).timeout.connect(func() -> void:
		print("MOOD_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	M = load("res://scripts/ui/portrait_mood.gd")
	TOP = load("res://scripts/fight/hud_top.gd")
	ART = load("res://scripts/ui/ba_art.gd")
	RESULT = load("res://scripts/screens/result_screen.gd")
	game = root.get_node("Game")
	_levels()
	_hysteresis()
	_precedence()
	_card_states()
	await _card_pixels()
	_chain()
	_roster()
	await _result()
	print("MOOD_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

# the pure state machine
func _levels() -> void:
	check(M.level(0, 1.0) == 0 and M.level(0, 0.80) == 0, "full hp and exactly 0.80 are calm")
	check(M.level(0, 0.7999) == 1 and M.level(1, 0.55) == 1, "below 0.80 scratched, exactly 0.55 still scratched")
	check(M.level(1, 0.5499) == 2 and M.level(2, 0.25) == 2, "below 0.55 hurt, exactly 0.25 still hurt")
	check(M.level(2, 0.2499) == 3 and M.level(3, 0.0) == 3, "below 0.25 critical")
	check(M.CRITICAL_BELOW == TOP.LOW_HP, "critical is hud_top's LOW_HP")
	check(M.level(1, 0.85) == 0 and M.level(1, 0.8499) == 1, "0.85 climbs back to calm and 0.8499 does not")
	check(M.level(2, 0.60) == 1 and M.level(2, 0.5999) == 2, "0.60 climbs back to scratched")
	check(M.level(3, 0.30) == 2 and M.level(3, 0.2999) == 3, "0.30 climbs back to hurt")
	check(M.level(0, 0.10) == 3 and M.level(0, 0.5) == 2 and M.level(1, 0.1) == 3, "several levels drop in one call")
	check(M.level(3, 1.0) == 0 and M.level(3, 0.58) == 2 and M.level(3, 0.9) == 0, "several levels climb in one call, a round reset is calm")
	check(M.level(1, 850.0 / 1000.0) == 0 and M.level(0, 800.0 / 1000.0) == 0 and M.level(0, 799.0 / 1000.0) == 1, "whole hp values land on the edges")

func _hysteresis() -> void:
	for e in 3:
		var down: float = M.DOWN[e]
		var up: float = M.UP[e]
		var l := e
		var flips := 0
		for i in 400:
			var n: int = M.level(l, down + 0.02 * sin(float(i) * 1.7))
			flips += int(n != l)
			l = n
		check(flips <= 1 and l == e + 1, "a flicker around the %.2f edge flips once (%d flips)" % [down, flips])
		l = e + 1
		flips = 0
		for i in 400:
			var n: int = M.level(l, up + 0.02 * sin(float(i) * 1.7))
			flips += int(n != l)
			l = n
		check(flips <= 1 and l == e, "a flicker around the %.2f way back flips once (%d flips)" % [up, flips])
		var r := down - 0.04
		check(M.level(e + 1, r) == e + 1 and M.level(e + 1, up - 0.001) == e + 1 and M.level(e + 1, up) == e, "the band between %.2f and %.2f holds the face" % [down, up])

func _precedence() -> void:
	check(M.state(2, 0.0, 0.2, true) == "ko", "ko beats win and flinch")
	check(M.state(2, 0.4, 0.2, true) == "win", "win beats flinch")
	check(M.state(2, 0.4, 0.2, false) == "flinch", "flinch beats the hp level")
	check(M.state(1, 0.7, 0.0, false) == "scratched" and M.state(0, 1.0, 0.0, false) == "calm" and M.state(3, 0.1, 0.0, false) == "critical", "the hp level otherwise")
	check(M.big_hit(1.0, 0.88) and M.big_hit(0.5, 0.3) and not M.big_hit(1.0, 0.89) and not M.big_hit(0.5, 0.6), "a drop of 0.12 or more is a flinch, a smaller one or a heal is not")
	for s in STATES:
		check(M.CHAIN[s].back() == "calm" and M.CHAIN[s][0] == s, "the chain of %s starts at itself and ends at calm" % s)

# hud_top's card
func _rail() -> Array:
	var a := StubFighter.new()
	var b := StubFighter.new()
	b.data = {"id": 10005, "name": "Hoshino", "school": "Abydos", "role": "Tanker", "bullet": "Pierce"}
	var w := StubWorld.new()
	w.fighters = [a, b]
	root.add_child(w)
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var t: Control = TOP.new().setup(w)
	vp.add_child(t)
	t.set_process(false)
	return [t, w, a, b, vp]

func _step(t: Control, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		t._process(DT)

func _card_states() -> void:
	var rail := _rail()
	var t: Control = rail[0]
	var w: StubWorld = rail[1]
	var a: StubFighter = rail[2]
	var b: StubFighter = rail[3]
	_step(t, 0.1)
	check(t._face == ["calm", "calm"], "full hp, both calm")
	var seen := {}
	for hp in range(1000, -1, -40):
		a.hp = float(hp)
		_step(t, 0.4)
		seen[hp] = t._face[0]
	check(seen[880] == "calm" and seen[800] == "calm" and seen[760] == "scratched" and seen[560] == "scratched", "chip damage: calm to 0.80, scratched to 0.55 (%s, %s)" % [seen[800], seen[760]])
	check(seen[520] == "hurt" and seen[280] == "hurt" and seen[240] == "critical" and seen[40] == "critical", "hurt to 0.25, critical below (%s, %s)" % [seen[280], seen[240]])
	check(seen[0] == "ko" and t._face[1] == "calm", "0 hp is ko and the other side is untouched")
	_step(t, 3.0)
	check(t._face[0] == "ko", "the ko face is held")
	a.hp = 1000.0
	_step(t, DT)
	check(t._face[0] == "calm" and t._lvl[0] == 0, "a new round's full hp is calm at once")
	# heal back up
	a.hp = 500.0
	_step(t, 1.0)
	a.hp = 580.0
	_step(t, 1.0)
	check(t._face[0] == "hurt", "580 of 1000 stays hurt (the edge back is 0.60)")
	a.hp = 600.0
	_step(t, 1.0)
	check(t._face[0] == "scratched", "600 climbs to scratched")
	# one big drop: the flinch face for 0.35 s, then the level it fell to
	a.hp = 1000.0
	_step(t, 0.5)
	a.hp = 850.0
	_step(t, DT)
	check(t._face[0] == "flinch" and absf(float(t._flinch[0]) - M.FLINCH_SECONDS) < 0.001, "a drop of 0.15 shows the flinch face for 0.35 s")
	_step(t, 0.30)
	check(t._face[0] == "flinch", "still flinching at 0.32 s")
	_step(t, 0.07)
	check(t._face[0] == "calm", "and calm at 0.39 s: 0.85 is above the 0.80 edge")
	a.hp = 700.0
	_step(t, DT)
	check(t._face[0] == "flinch", "another 0.15 flinches again")
	_step(t, 0.4)
	check(t._face[0] == "scratched", "and settles on the level it fell to")
	a.hp = 640.0
	_step(t, DT)
	check(t._face[0] == "scratched", "a drop of 0.06 does not flinch")
	# pause: the HUD clock stands still, so does the flinch
	a.hp = 400.0
	_step(t, 0.1)
	var left: float = t._flinch[0]
	w.paused = true
	_step(t, 2.0)
	check(t._face[0] == "flinch" and is_equal_approx(float(t._flinch[0]), left), "a paused HUD keeps the flinch exactly as it was")
	w.paused = false
	_step(t, 0.1)
	check(t._face[0] == "flinch", "and resumes with the time that was left")
	_step(t, 0.4)
	check(t._face[0] == "hurt", "then shows the hurt face")
	# several levels in one frame
	a.hp = 1000.0
	_step(t, 0.5)
	a.hp = 100.0
	_step(t, DT)
	check(t._lvl[0] == 3, "a drop from full to 0.10 skips straight to critical")
	_step(t, 0.5)
	check(t._face[0] == "critical", "and the face follows after the flinch")
	# a ko wins over a flinch and over the win face of the same side
	a.hp = 0.0
	_step(t, DT)
	check(t._face[0] == "ko", "a killing blow is a ko, not a flinch")
	# win
	a.hp = 1000.0
	b.hp = 300.0
	_step(t, 0.5)
	w.phase = "round_end"
	w.wins = [1, 0]
	_step(t, DT)
	check(t._face[0] == "win", "the round's winner shows the win face")
	check(t._face[1] == "hurt", "and the loser keeps their hp face (%s)" % t._face[1])
	_step(t, 5.0)
	check(t._face[0] == "win", "the win face is held through the round_end phase")
	w.phase = "intro"
	_step(t, DT)
	check(t._face[0] == "calm", "the next round's intro takes it off")
	w.phase = "fight"
	w.wins = [1, 1]
	_step(t, DT)
	check(t._face[1] != "win", "a win noticed outside round_end shows no win face")
	w.phase = "round_end"
	b.hp = 0.0
	w.wins = [2, 1]
	_step(t, DT)
	check(t._face == ["win", "ko"], "ko and win on their own sides")
	rail[4].queue_free()
	w.queue_free()

## hud_top draws the tile BaArt gives for the face: flat colour tiles stand in for it.
func _card_pixels() -> void:
	var saved_faces: Dictionary = ART._faces.duplicate()
	var saved_expr: Dictionary = ART._expr.duplicate(true)
	for id in [10004, 10005]:
		for s in STATES:
			if s != "calm":
				ART._faces["%d/%s" % [id, s]] = _flat(TILE[s])
	var rail := _rail()
	var t: Control = rail[0]
	var w: StubWorld = rail[1]
	var a: StubFighter = rail[2]
	var b: StubFighter = rail[3]
	var probe := {}
	for hp in [900.0, 700.0, 450.0, 150.0]:
		a.hp = hp
		b.hp = hp
		_step(t, 0.8)
		probe[hp] = await _faces_px(t)
	var want := {900.0: "calm", 700.0: "scratched", 450.0: "hurt", 150.0: "critical"}
	check(_is_calm(probe[900.0][0]) and _is_calm(probe[900.0][1]), "full-ish hp draws the calm portrait, not a state tile")
	for hp in [700.0, 450.0, 150.0]:
		for side in 2:
			check(_near(probe[hp][side], TILE[want[hp]]), "side %d at %d of 1000 draws the %s tile (%s)" % [side, int(hp), want[hp], probe[hp][side].to_html(false)])
	a.hp = 1000.0
	b.hp = 1000.0
	_step(t, 0.8)
	a.hp = 750.0
	b.hp = 750.0
	t._process(DT)
	var flinch: Array = await _faces_px(t)
	check(_near(flinch[0], TILE["flinch"]) and _near(flinch[1], TILE["flinch"]), "a big drop draws the flinch tile on both sides")
	var edge := {}
	var rect: Rect2 = t.rects(0)["portrait"]
	for k in 8:
		t._process(DT)
		var img: Image = await _snap(t)
		edge[_near(img.get_pixel(int(rect.position.x) + 1, int(rect.get_center().y)), TILE["flinch"])] = true
	check(edge.size() == 2 and M.shake(0.0).x == M.SHAKE_PX and M.shake(1.0 / 30.0).x == -M.SHAKE_PX, "the flinch face shakes 3 px each way: its left edge comes and goes")
	_step(t, 0.8)
	b.hp = 0.0
	_step(t, DT)
	_step(t, 0.8)
	var ko: Color = (await _faces_px(t))[1]
	var spread := maxf(ko.r, maxf(ko.g, ko.b)) - minf(ko.r, minf(ko.g, ko.b))
	check(spread < 0.55 * 0.7 and ko.r > ko.g and ko.r < TILE["ko"].r, "the ko tile is drawn pulled towards grey and dimmed (%s)" % ko.to_html(false))
	a.hp = 1000.0
	b.hp = 1000.0
	w.phase = "round_end"
	w.wins = [1, 0]
	_step(t, 0.3)
	var win := await _faces_px(t)
	check(_near(win[0], TILE["win"]) and _is_calm(win[1]), "the winner draws the win tile")
	rail[4].queue_free()
	w.queue_free()
	ART._faces = saved_faces
	ART._expr = saved_expr

func _flat(c: Color) -> Texture2D:
	var img := Image.create(252, 204, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _snap(t: Control) -> Image:
	t._process(0.0)
	for i in 4:
		await process_frame
	return t.get_viewport().get_texture().get_image()

## The colour at each portrait rect's centre, left side then right.
func _faces_px(t: Control) -> Array:
	var img: Image = await _snap(t)
	var out := []
	for i in 2:
		var c: Vector2 = t.rects(i)["portrait"].get_center()
		out.append(img.get_pixel(int(c.x), int(c.y)))
	return out

func _near(a: Color, b: Color, tol := 0.06) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol

## Not one of the flat state tiles.
func _is_calm(c: Color) -> bool:
	for s in TILE:
		if _near(c, TILE[s], 0.03):
			return false
	return true

# BaArt's fallback chain
func _chain() -> void:
	var saved_faces: Dictionary = ART._faces.duplicate()
	var saved_expr: Dictionary = ART._expr.duplicate(true)
	ART._faces = {}
	ART._expr = {"10004": {"scratched": "ZZZ_missing.png", "hurt": "Student_Portrait_Hoshino.png", "ko": "Student_Portrait_Hihumi.png"}}
	var calm: Texture2D = ART.portrait(10004)
	var hoshino: Texture2D = ART.file("portraits/Student_Portrait_Hoshino.png")
	var hihumi: Texture2D = ART.file("portraits/Student_Portrait_Hihumi.png")
	check(calm != null and ART.portrait(10004, "calm") == calm, "calm is the existing portrait")
	check(ART.portrait(10004, "scratched") == calm, "a named file that is not there falls through to calm")
	check(ART.portrait(10004, "hurt") == hoshino, "a state takes its own file")
	check(ART.portrait(10004, "critical") == hoshino and ART.portrait(10004, "flinch") == hoshino, "critical and flinch fall to hurt")
	check(ART.portrait(10004, "ko") == hihumi, "ko takes its own file")
	check(ART.portrait(10004, "lose") == hoshino, "lose falls through critical to hurt")
	check(ART.portrait(10004, "win") == calm, "win with no file is the calm portrait")
	check(ART.portrait(10005, "hurt") == ART.portrait(10005), "an id with no entry shows its calm portrait in every state")
	check(ART.portrait(10004, "ZZZ_state") == calm and ART.portrait(1, "hurt") == null, "an unknown state is calm, an unknown id is null")
	check(ART.portrait_small(10004) != null and ART.portrait_small(10004) != calm, "portrait_small is unchanged")
	ART._faces = saved_faces
	ART._expr = saved_expr

# the roster against the tiles on disk
func _roster() -> void:
	ART._faces.clear()
	var ex: Dictionary = ART.expressions()
	var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ba/roster.json"))
	var fighters: Array = roster["fighters"]
	var full := true
	for f in fighters:
		full = full and ex.has(str(int(f["id"])))
	var own := 0
	var total := 0
	var bad_files := []
	var missing := []
	var wins := 0
	var result_bad := []
	for f in fighters:
		var id := int(f["id"])
		var e: Dictionary = ex.get(str(id), {})
		var calm: Texture2D = ART.portrait(id)
		for s in STATES:
			total += 1
			var t: Texture2D = ART.portrait(id, s)
			check(t != null and t.get_width() == 252 and t.get_height() == 204, "%s resolves %s at 252x204" % [f["key"], s])
			if s == "calm":
				own += 1
				continue
			var file: String = e.get(s, "")
			if file == "":
				missing.append("%s/%s" % [f["key"], s])
			elif not ResourceLoader.exists(ART.DIR + "portraits/" + file):
				bad_files.append("%s/%s=%s" % [f["key"], s, file])
			else:
				own += 1
				if s != "lose" and t.get_image().get_data() == calm.get_image().get_data():
					bad_files.append("%s/%s is the calm tile" % [f["key"], s])
		for s in ["win", "lose"]:
			var rel := "portrait/%d_%s.webp" % [id, s]
			if ResourceLoader.exists(UI.BA + rel):
				wins += 1
				var plain: Texture2D = UI.portrait(id)
				var face: Texture2D = UI.tex(rel)
				if face.get_size() != plain.get_size():
					result_bad.append("%s %s %s vs %s" % [f["key"], s, face.get_size(), plain.get_size()])
	check(bad_files.is_empty(), "every file expressions.json names exists and differs from calm: %s" % str(bad_files))
	check(result_bad.is_empty(), "every win and lose image is on its portrait's canvas: %s" % str(result_bad))
	if full:
		check(missing.is_empty(), "the json names every fighter, so every state has a file: %s" % str(missing.slice(0, 8)))
		check(wins == fighters.size() * 2, "and every fighter has both result images (%d of %d)" % [wins, fighters.size() * 2])
	print("MOOD_COVERAGE json=%d of %d fighters, own tiles %d of %d, result images %d of %d, %s" % [ex.size(), fighters.size(), own, total,
		wins, fighters.size() * 2, "full set" if full else "partial set, the rest falls back"])

# the result screen
func _result() -> void:
	root.add_child((load("res://scenes/main.tscn") as PackedScene).instantiate())
	await process_frame
	await process_frame
	root.get_node("Dbg").intro_entry = false
	var cases := [["versus2p", 1, 10004, 10005], ["versus2p", 2, 10004, 10005], ["arcade", 2, 10005, 10004], ["arcade", 1, 10004, 10005]]
	for c in cases:
		game.session.begin(c[0])
		game.session.players[0]["fighter"] = c[2]
		game.session.players[1]["fighter"] = c[3]
		await game.go("result", {"winner": c[1], "wins": [2, 1] if c[1] == 1 else [1, 2], "rounds": 3, "stats": [{}, {}]}, "cut")
		var r: Node = game.stack.back()
		var wid: int = c[2] if c[1] == 1 else c[3]
		var lid: int = c[3] if c[1] == 1 else c[2]
		var tag := "%s winner %d" % [c[0], c[1]]
		var win_t: Texture2D = RESULT._face(wid, "win")
		var lose_t: Texture2D = RESULT._face(lid, "lose")
		check(r._art_w.texture == win_t and r._art_l.texture == lose_t, "%s: the winner shows the win face and the loser the lose face" % tag)
		var win_file := ResourceLoader.exists(UI.BA + "portrait/%d_win.webp" % wid)
		var lose_file := ResourceLoader.exists(UI.BA + "portrait/%d_lose.webp" % lid)
		check((win_t != UI.portrait(wid)) == win_file and (lose_t != UI.portrait(lid)) == lose_file, "%s: the face is the image when the install has it and the plain portrait when not" % tag)
		check(win_t.get_size() == UI.portrait(wid).get_size() and lose_t.get_size() == UI.portrait(lid).get_size(), "%s: on the plain portrait's canvas" % tag)
		check(r._frame_w["size"] == Vector2(win_t.get_size()) * float(r._frame_w["scale"]), "%s: SelectFrames.HEADS frames the winner's face" % tag)
		await create_timer(0.3).timeout
		check(is_equal_approx(float(r._mat_l.get_shader_parameter("saturation")), RESULT.LOSER_SAT) and RESULT.LOSER_SAT > 0.3, "%s: the loser keeps colour (saturation %.1f)" % [tag, RESULT.LOSER_SAT])
