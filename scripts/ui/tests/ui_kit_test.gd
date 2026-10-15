extends SceneTree
## BA UI kit checks: tokens, display font, motion curves, and two source lints over every UI script: no hex-string colour
## literal, and no banned word or em dash inside a string.
## Run: TEST=res://scripts/ui/tests/ui_kit_test.gd zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

# The BA UI scripts: scripts/ui and scripts/screens, and the HUD and effects scripts in scripts/fight (hud_*, fx_*, fight_hud).
# Each one has no hex-string colour literal (Color("#rrggbb"), Color.html). Color(r, g, b) literals are not checked, so this is
# not proof that every colour comes from BaTokens. A file that may keep hex strings is in EXEMPT with its reason; a file in
# neither list fails.
const LINTED := [
	"res://scripts/ui/assign_panel.gd", "res://scripts/ui/ba_art.gd",
	"res://scripts/ui/ba_menu.gd", "res://scripts/ui/ba_numerals.gd",
	"res://scripts/ui/ba_words.gd", "res://scripts/ui/card.gd",
	"res://scripts/ui/crest_emblem.gd", "res://scripts/ui/crest_icon.gd",
	"res://scripts/ui/controller_glyph.gd", "res://scripts/ui/controller_glyphs.gd",
	"res://scripts/ui/crest_wipe.gd", "res://scripts/ui/gallery_characters.gd",
	"res://scripts/ui/gallery_jukebox.gd", "res://scripts/ui/gallery_plate.gd",
	"res://scripts/ui/gallery_records.gd", "res://scripts/ui/motion.gd",
	"res://scripts/ui/painter.gd", "res://scripts/ui/portrait_mood.gd", "res://scripts/ui/screen_kit.gd",
	"res://scripts/ui/select_cursor.gd", "res://scripts/ui/select_frames.gd",
	"res://scripts/ui/select_side.gd", "res://scripts/ui/select_tile.gd",
	"res://scripts/ui/slam_wipe.gd", "res://scripts/ui/transition.gd",
	"res://scripts/ui/vs_layout.gd", "res://scripts/screens/assign_screen.gd",
	"res://scripts/screens/gallery_screen.gd", "res://scripts/screens/menu_screen.gd",
	"res://scripts/screens/options_screen.gd", "res://scripts/screens/result_screen.gd",
	"res://scripts/screens/screen.gd", "res://scripts/screens/select_screen.gd",
	"res://scripts/screens/title_screen.gd",
	"res://scripts/ui/credits_panel.gd",
	"res://scripts/screens/vs_screen.gd", "res://scripts/fight/fight_hud.gd",
	"res://scripts/fight/fx_art.gd", "res://scripts/fight/fx_digits.gd",
	"res://scripts/fight/fx_flash.gd", "res://scripts/fight/fx_kinds.gd",
	"res://scripts/fight/fx_kinds_art.gd", "res://scripts/fight/fx_particles.gd",
	"res://scripts/fight/hud_banner.gd", "res://scripts/fight/hud_bar.gd",
	"res://scripts/fight/hud_bottom.gd", "res://scripts/fight/hud_cutin.gd",
	"res://scripts/fight/hud_demo.gd", "res://scripts/fight/hud_feed.gd",
	"res://scripts/fight/hud_kit.gd", "res://scripts/fight/hud_pause.gd", "res://scripts/fight/hud_status.gd",
	"res://scripts/fight/hud_status_table.gd", "res://scripts/fight/hud_top.gd",
	"res://scripts/fight/hud_training.gd",
]
const EXEMPT := {
	"res://scripts/ui/ba_tokens.gd": "the token file itself",
	"res://scripts/ui/ui.gd": "the original palette, named constants that the older screens read",
	"res://scripts/ui/special_panel.gd": "the Special Select popup's own palette, read off BA's popup and used once each",
	"res://scripts/ui/gallery_kit.gd": "the per-school facet tints are data keyed by school",
	"res://scripts/screens/stage_screen.gd": "the stage screen keeps its own colours",
}

var checks := 0
var failures: Array = []
var T: GDScript

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("UIKIT_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("UIKIT_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	T = load("res://scripts/ui/ba_tokens.gd")
	_tokens()
	_font()
	_motion()
	_lint()
	print("UIKIT_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _tokens() -> void:
	check(absf(T.SHEAR - tan(deg_to_rad(10.0))) < 0.0005, "shear is tan(10 deg)")
	check(T.P1 != T.P2 and T.side(1) == T.P1 and T.side(2) == T.P2, "sides")
	check(is_equal_approx(T.shear_px(28.0), 28.0 * T.SHEAR), "shear_px")
	check(T.BRACKET_LO < 1.0 and T.WHIP_SHARE > 0.85 and T.WHIP_SHARE < 0.9, "motion constants")
	check(T.alpha(T.P1, 0.5).a == 0.5, "alpha helper")

func _font() -> void:
	var U: GDScript = load("res://scripts/ui/ui.gd")
	var f: Font = U.font_display()
	check(f != null, "display font loads")
	if f == null:
		return
	var w := f.get_string_size("STAGE START 0123456789", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	check(w > 300.0, "display font draws caps and digits (width %.0f)" % w)
	check(f.has_char("0".unicode_at(0)) and f.has_char("K".unicode_at(0)), "digits and caps present")
	check(U.font_display() == f, "display font is cached")

func _motion() -> void:
	var M: GDScript = load("res://scripts/ui/motion.gd")
	check(M.whip(0.0) == 0.0 and M.whip(-1.0) == 0.0, "whip starts at 0")
	check(absf(M.whip(T.WHIP_FAST) - T.WHIP_SHARE) < 0.0001, "whip covers its share in the fast leg")
	check(absf(M.whip(T.WHIP_FAST + T.WHIP_SETTLE) - 1.0) < 0.0001 and M.whip(5.0) == 1.0, "whip ends at 1")
	var prev := 0.0
	var mono := true
	var over := false
	for i in 200:
		var v: float = M.whip(float(i) / 200.0)
		mono = mono and v >= prev - 0.000001
		over = over or v > 1.0
		prev = v
	check(mono and not over, "whip is monotonic and never overshoots")
	check(absf(M.pulse(0.0) - 1.0) < 0.0001 and absf(M.pulse(T.BRACKET_HALF) - T.BRACKET_LO) < 0.0001, "pulse range")
	check(absf(M.pulse(2.0 * T.BRACKET_HALF) - 1.0) < 0.0001, "pulse period")
	check(is_equal_approx(M.stagger(3), 3.0 * T.STAGGER), "stagger")

## Copy a player can read: house rules ban these words and the em dash. Checked in string literals only, so a method named
## unlock() or a dash in a code comment is not copy.
const BANNED := ["delve", "seamless", "elevate", "unlock", "empower", "streamline", "effortless", "supercharge", "lorem ipsum", "—"]

func _copy_lint(path: String) -> void:
	var rx := RegEx.new()
	rx.compile("\"(?:[^\"\\\\\n]|\\\\.)*\"")
	var hits := []
	var n := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		n += 1
		if line.strip_edges().begins_with("#"):
			continue
		for m in rx.search_all(line):
			for w in BANNED:
				if m.get_string().to_lower().contains(w):
					hits.append("line %d '%s'" % [n, w])
	check(hits.is_empty(), "no banned word or em dash in a string of %s %s" % [path.get_file(), hits])

## No Color("hex") literal in the files that are supposed to read tokens.
func _lint() -> void:
	var rx := RegEx.new()
	rx.compile("Color(?:\\.html)?\\(\\s*\"#?[0-9a-fA-F]{3,8}\"")
	for path in LINTED:
		var f := FileAccess.open(path, FileAccess.READ)
		check(f != null, "lint opens " + path)
		if f == null:
			continue
		_copy_lint(path)
		var m := rx.search(f.get_as_text())
		check(m == null, "no hex colour literal in " + path + (" (" + m.get_string() + ")" if m else ""))
	for path in EXEMPT:
		_copy_lint(path)
		check(rx.search(FileAccess.get_file_as_string(path)) != null, "stale exemption, %s has no hex colour left (%s)" % [path, EXEMPT[path]])
	for dir in ["res://scripts/ui", "res://scripts/screens", "res://scripts/fight"]:
		for name in DirAccess.get_files_at(dir):
			if not name.ends_with(".gd") or (dir.ends_with("fight") and not (name.begins_with("hud_") or name.begins_with("fx_") or name == "fight_hud.gd")):
				continue
			var path: String = dir + "/" + name
			check(path in LINTED or EXEMPT.has(path), "the colour lint covers " + path)
