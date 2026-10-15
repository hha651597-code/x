extends SceneTree
## BA HUD art contact sheets, 1280x720 each, to look at: bars and frames at several sizes, tints and with the lean; cards,
## plates, chips and badges; the COST disc with ten cells and every numeral tier; every word; a portrait wall of the
## fighters and one of the 81 specials. A fake pale sky stands behind, like the stages do.
## The last page rebuilds a reference HUD mockup from the API alone, to see that it can.
## Run: zsh tools/ba_art_sheet.sh   ->   tmp/ba_art_sheet_<0..6>.png

class Page extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(self)

const INK := Color("2D4664")
const SLOT := Color("182442")
const RED := Color("D63636")
const CYAN := Color("00A0FF")
const CELL := Color("00AEFF")
const LEAN := 0.1763

var ART: GDScript
var NUM: GDScript
var WORDS: GDScript
var roster: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(3))
	await process_frame
	ART = load("res://scripts/ui/ba_art.gd")
	NUM = load("res://scripts/ui/ba_numerals.gd")
	WORDS = load("res://scripts/ui/ba_words.gd")
	roster = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ba/roster.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	var pages := [_frames, _cards, _meter, _words, _fighters, _specials, _mock]
	for i in pages.size():
		var p := Page.new()
		p.fn = pages[i]
		root.add_child(p)
		for f in 4:
			await process_frame
		root.get_texture().get_image().save_png("res://tmp/ba_art_sheet_%d.png" % i)
		p.queue_free()
		await process_frame
	var warned: Array = ART.warnings()
	print("ba_art_sheet: ", pages.size(), " pages, ", warned.size(), " warnings ", warned)
	quit(1 if not warned.is_empty() else 0)

func _sky(c: Node2D, top := Color("9CD2F6"), bottom := Color("E8F4FE")) -> void:
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)]),
			PackedColorArray([top, top, bottom, bottom]))

func _cap(c: Node2D, pos: Vector2, text: String, col := INK) -> void:
	c.draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

## A framed navy track with a flat fill: BA's HP bar recipe at any size.
func _bar(c: Node2D, r: Rect2, frac: float, fill: Color, shear := LEAN, from_right := false) -> void:
	ART.nine(c, "Combat__Common_Bg_Raius5px", r.grow_individual(-2, -1, -2, -1), BaTokens.NAVY, shear)
	var inner := Rect2(r.position + Vector2(6, 5), r.size - Vector2(12, 10))
	var w := inner.size.x * frac
	var f := Rect2(inner.position.x + (inner.size.x - w if from_right else 0.0), inner.position.y, w, inner.size.y)
	ART.nine(c, "Combat__Combat_Bg_Hp", r, Color.WHITE, shear)
	if w > 1.0:
		ART.nine(c, "Combat__Combat_Gauge_Hp", f, fill, shear)

func _frames(c: Node2D) -> void:
	_sky(c)
	_cap(c, Vector2(24, 16), "Combat_Bg_Hp + Raius5px track + Gauge_Hp fill, leaned, 480x42")
	_bar(c, Rect2(24, 24, 480, 42), 0.72, RED)
	_bar(c, Rect2(776, 24, 480, 42), 0.45, CYAN, LEAN, true)
	ART.nine(c, "Common__Common_Bg_Raius10px", Rect2(558, 16, 164, 72), Color("062D51"), LEAN)
	ART.nine(c, "Combat__Combat_Bg_Hp", Rect2(558, 16, 164, 72), Color.WHITE, LEAN)
	ART.blit(c, "Combat__Combat_Time_Icon", Rect2(578, 38, 26, 29))
	NUM.draw(c, "60", Vector2(664, 30), 40.0, NUM.Tier.WHITE, Color.WHITE, 1)
	_cap(c, Vector2(24, 92), "guard bar 250x12, same frame; yellow under 30 percent, crushed")
	_bar(c, Rect2(24, 100, 250, 12), 0.8, Color("EAF6FF"))
	_bar(c, Rect2(300, 100, 250, 12), 0.25, Color("FEE600"))
	_bar(c, Rect2(576, 100, 250, 12), 0.0, Color("EAF6FF"))
	_cap(c, Vector2(24, 140), "Combat_Bg_Hp at widths 400, 200, 100, 50, 25, 12, 6, upright and leaned (borders shrink, no tear)")
	var x := 24.0
	for w in [400.0, 200.0, 100.0, 50.0, 25.0, 12.0, 6.0]:
		ART.nine(c, "Combat__Combat_Bg_Hp", Rect2(x, 150, w, 42), Color.WHITE)
		ART.nine(c, "Combat__Combat_Bg_Hp", Rect2(x, 206, w, 42), Color.WHITE, LEAN)
		x += w + 28.0
	_cap(c, Vector2(24, 268), "Common_Bg_Raius10px tinted: ink, side red, side cyan, yellow; 120x60, 60x30, 30x15, 14x7")
	var tints := [INK, RED, CYAN, Color("FEE600")]
	for i in 4:
		var s := Vector2(120, 60) / pow(2.0, float(i))
		ART.nine(c, "Common__Common_Bg_Raius10px", Rect2(24.0 + 150.0 * i, 280, s.x, s.y), tints[i])
		ART.nine(c, "Common__Common_Bg_Raius10px", Rect2(24.0 + 150.0 * i, 350, s.x, s.y), tints[i], LEAN)
	_cap(c, Vector2(660, 268), "Combat_Title_Bg ribbon 28px borders, 200x30 / 120x22 / 60x22 / 40x22")
	var rx := 660.0
	for s in [Vector2(200, 30), Vector2(120, 22), Vector2(60, 22), Vector2(40, 22)]:
		ART.nine(c, "Combat__Combat_Title_Bg", Rect2(rx, 280, s.x, s.y), Color.WHITE, LEAN)
		rx += s.x + 24.0
	_cap(c, Vector2(24, 430), "Common_Popup_Bg 118x215, borders 48/48/145/65, at 300x200 and 150x150; Top_Menu_Bg header; Card_Select_Line at 3 sizes (FEE600, FEE600, untinted: the sprite is yellow already)")
	ART.nine(c, "Common__Common_Popup_Bg", Rect2(24, 440, 300, 240))
	ART.nine(c, "Common__Common_Top_Menu_Bg", Rect2(24, 440, 300, 40))
	ART.nine(c, "Common__Common_Popup_Bg", Rect2(350, 440, 150, 150))
	ART.nine(c, "Common__Card_Select_Line", Rect2(540, 440, 164, 136), Color("FEE600"))
	ART.nine(c, "Common__Card_Select_Line", Rect2(730, 440, 90, 60), Color("FEE600"))
	ART.nine(c, "Common__Card_Select_Line", Rect2(850, 440, 50, 120))
	ART.nine(c, "Common__Common_Nonoutline_W_Bg", Rect2(540, 600, 160, 24), Color.WHITE, LEAN)
	ART.nine(c, "Common__Common_Nonoutline_W_Bg", Rect2(720, 600, 80, 24), Color.WHITE, LEAN)
	ART.nine(c, "Combat__Ingame_Operater_Text_Bg", Rect2(930, 440, 220, 100), Color.WHITE)
	ART.nine(c, "Combat__Ingame_Operater_Text_Bg", Rect2(1170, 440, 80, 140), Color.WHITE)

func _cards(c: Node2D) -> void:
	_sky(c)
	_cap(c, Vector2(24, 16), "Student_Portrait over Combat_CardBg_EX (tint FFC4CB / B9E2FF), Card_Select_Line bracket, cost-tag disc")
	var hina := 10004
	var hoshino := 10005
	for k in 2:
		var o := Vector2(30.0 + 220.0 * k, 30)
		ART.blit(c, "Combat__Combat_CardBg_EX", Rect2(o + Vector2(0, 4), Vector2(160, 129)), Color("FFC4CB") if k == 0 else Color("B9E2FF"))
		c.draw_texture_rect(ART.portrait(hina if k == 0 else hoshino), Rect2(o + Vector2(4, 0), Vector2(150, 121)), false)
		ART.blit(c, "Combat__Combat_CardBg_EX_CostTag", Rect2(o + Vector2(-8, -8), Vector2(40, 40)))
		NUM.draw(c, "5", o + Vector2(2, -2), 18.0, NUM.Tier.MINI, Color.WHITE, 0)
	ART.nine(c, "Common__Card_Select_Line", Rect2(466, 26, 164, 136), Color("FEE600"))
	c.draw_texture_rect(ART.portrait(10005), Rect2(472, 30, 150, 121), false)
	_cap(c, Vector2(660, 16), "Common_Btn_BG tints + Btn_Normal facet overlay: idle, primary, confirm, disabled")
	var plates := [[Color.WHITE, ""], [Color("77DEFF"), "Common__Common_Btn_Normal_B_S_Pt"], [Color("FEE600"), "Common__Common_Btn_Normal_Y_S_Pt"], [Color(0.84, 0.84, 0.84, 0.9), ""]]
	for i in 4:
		var r := Rect2(660.0 + 150.0 * (i % 2), 30.0 + 60.0 * (i / 2), 136, 49)
		ART.nine(c, "Combat__Common_Btn_BG", r, plates[i][0], LEAN)
		if plates[i][1] != "":
			ART.blit(c, plates[i][1], r.grow(2.0))
	WORDS.draw(c, "super", Vector2(878, 54), 90.0)
	WORDS.draw(c, "ex_ready", Vector2(728, 114), 100.0)
	_cap(c, Vector2(24, 190), "role chips: Card_Role_Bg tinted by attack type + white Common_Icon_<role>; status pentagons; school crests (white from alpha, tinted navy)")
	var roles := ["DamageDealer", "Tanker", "Healer", "Supporter", "Vehicle"]
	var atk := ["Explosion", "Pierce", "Mystic", "Sonic", "Explosion"]
	for i in 5:
		var r := Rect2(30.0 + 50.0 * i, 205, 36, 34)
		ART.blit(c, "Common__Card_Role_Bg", r, ART.attack_color(atk[i]))
		c.draw_texture_rect(ART.role_icon(roles[i]), r.grow(-6.0), false)
	var badges := ["Combat__Combat_Icon_Buff_ATK", "Combat__Combat_Icon_Buff_DEF", "Combat__Combat_Icon_Buff_Shield", "Combat__Combat_Icon_Buff_AmmoCount",
			"Combat__Combat_Icon_Buff_BlockRate", "Combat__Combat_Icon_Debuff_ATK", "Combat__Combat_Icon_CC_Stunned", "Combat__Combat_Icon_Special_Fury"]
	for i in badges.size():
		ART.blit(c, badges[i], Rect2(320.0 + 34.0 * i, 205, 28, 32))
	var schools := ["Abydos", "Arius", "Gehenna", "Hyakkiyako", "Millennium", "RedWinter", "Shanhaijing", "SRT", "Trinity", "Valkyrie"]
	for i in schools.size():
		c.draw_rect(Rect2(24.0 + 60.0 * i, 250, 54, 54), Color("F4FAFF"))
		var t: Texture2D = ART.school_crest(schools[i])
		c.draw_texture_rect(t, Rect2(26.0 + 60.0 * i, 252, 50, 50), false, INK)
	for i in 4:
		c.draw_rect(Rect2(640.0 + 60.0 * i, 250, 54, 54), INK)
		c.draw_texture_rect(ART.school_crest(schools[i * 2]), Rect2(642.0 + 60.0 * i, 252, 50, 50), false)
	_cap(c, Vector2(24, 330), "crest at HUD size 34 px and 22 px (navy plate, white)")
	for i in 5:
		c.draw_rect(Rect2(24.0 + 80.0 * i, 340, 70, 40), Color("2D4664"))
		c.draw_texture_rect(ART.school_crest(schools[i]), Rect2(30.0 + 80.0 * i, 343, 34, 31), false)
		c.draw_texture_rect(ART.school_crest(schools[i]), Rect2(70.0 + 80.0 * i - 4.0, 351, 22, 20), false)
	_cap(c, Vector2(24, 410), "assist call-out: Combat_Balloon_Sup 69x95 (borders 46/20/0/0) with Student_Portrait_Small; Cri_Bg starburst; Twinkle; NearlyDead; hazard strips; BestRecord")
	ART.nine(c, "Combat__Combat_Balloon_Sup", Rect2(30, 420, 160, 95), Color.WHITE)
	c.draw_texture_rect(ART.portrait_small(20001), Rect2(40, 425, 100, 80), false)
	ART.nine(c, "Combat__Combat_Balloon_Sup", Rect2(210, 420, 90, 95), Color.WHITE)
	ART.blit(c, "Floater__Imagefont_Cri_Bg", Rect2(330, 410, 230, 104))
	NUM.draw(c, "13", Vector2(445, 428), 62.0, NUM.Tier.EFFECTIVE, Color.WHITE, 1)
	ART.blit(c, "Emoji__Emoji_Twinkle", Rect2(580, 420, 61, 68))
	ART.blit(c, "Combat__Ingame_Emo_NearlyDead", Rect2(670, 424, 57, 48))
	c.draw_texture_rect(ART.tex("UIs__00_Images__Ingame_Warning_Deco_3"), Rect2(24, 540, 300, 12), false)
	c.draw_texture_rect(ART.tex("UIs__00_Images__Ingame_Warning_Deco_1"), Rect2(24, 560, 300, 12), false)
	WORDS.draw(c, "best_record", Vector2(470, 556), 240.0)
	var halo: Texture2D = ART.tex("UIs__00_Images__Image_Deco_Circle")
	c.draw_texture_rect(halo, Rect2(760, 400, 240, 240), false, Color(1, 1, 1, 0.5))
	var tri: Texture2D = ART.tex("UIs__00_Images__Image_Triangle_Pattern_Deco_1")
	c.draw_texture_rect(tri, Rect2(900, 330, 360, 360), false, Color(1, 1, 1, 0.8))
	var flare := Page.new()
	flare.material = ART.additive()
	flare.fn = func(f: Node2D) -> void: ART.blit(f, "UIs__00_Images__Ingame_Start_Light", Rect2(1010, 20, 250, 240))
	c.add_child(flare)
	var streak := Page.new()
	streak.material = ART.additive()
	streak.fn = func(f: Node2D) -> void: ART.blit(f, "UIs__00_Images__Formation__UITex_BGBlueLight", Rect2(740, 300, 292, 108))
	c.add_child(streak)

func _meter(c: Node2D) -> void:
	_sky(c)
	_cap(c, Vector2(24, 16), "COST disc 117x123 (66x66 drawn) + ten Combat_Cost_Gauge cells on #182442 slots, 34x26 at 37 px pitch; cost tags at 5 and 10")
	for row in 3:
		var filled: int = [10, 6, 3][row]
		var y := 40.0 + 92.0 * row
		ART.blit(c, "Combat__Combat_CostBg", Rect2(30, y + 8, 66, 66))
		NUM.draw(c, str(filled), Vector2(70, y + 30), 28.0, NUM.Tier.NORMAL, Color.WHITE, 1)
		for i in 10:
			var r := Rect2(110.0 + 37.0 * i, y + 28, 34, 26)
			ART.nine(c, "Combat__Common_Bg_Raius5px", r, SLOT, LEAN)
			if i < filled:
				ART.nine(c, "Combat__Combat_Cost_Gauge", r.grow_individual(-2, -3, -2, -3), CELL, LEAN)
		for tag: int in [5, 10]:
			var cx := 110.0 + 37.0 * (tag - 1) + 17.0
			ART.blit(c, "Combat__Combat_CardBg_EX_CostTag", Rect2(cx - 14, y + 2, 28, 28), Color(1, 0.95, 0.4) if filled >= tag else Color.WHITE)
			NUM.draw(c, str(tag), Vector2(cx, y + 10), 11.0, NUM.Tier.MINI, Color.WHITE, 1)
	_cap(c, Vector2(24, 330), "numeral tiers, 0123456789 at 40 px and 128 at 78 px: NORMAL, EFFECTIVE, WEAK, RESIST, WHITE, MINI")
	for t in 6:
		var x := 24.0 + 420.0 * (t % 3)
		var y := 346.0 + 190.0 * (t / 3)
		c.draw_rect(Rect2(x, y, 400, 175), Color(0.1, 0.16, 0.3, 0.55) if t == 4 else Color(1, 1, 1, 0.35))
		_cap(c, Vector2(x + 6, y + 14), NUM.KEYS[t], Color.WHITE if t == 4 else INK)
		NUM.draw(c, "0123456789", Vector2(x + 8, y + 22), 40.0, t)
		NUM.draw(c, "128", Vector2(x + 8, y + 76), 78.0, t)
		NUM.draw(c, "7", Vector2(x + 300, y + 76), 78.0, t)
	ART.blit(c, "Common__Common_Attack_Icon", Rect2(900, 40, 43, 44))
	NUM.draw(c, "129", Vector2(950, 46), 28.0, NUM.Tier.NORMAL)
	ART.blit(c, "Common__Common_Defense_Icon", Rect2(900, 100, 43, 44))
	NUM.draw(c, "30", Vector2(950, 106), 28.0, NUM.Tier.RESIST)
	WORDS.draw(c, "combo", Vector2(1100, 200), 132.0)
	WORDS.draw(c, "block", Vector2(1100, 250), 134.0)
	WORDS.draw(c, "miss", Vector2(1190, 100), 113.0)
	WORDS.draw(c, "immune", Vector2(1170, 150), 174.0)

func _words(c: Node2D) -> void:
	c.draw_rect(Rect2(0, 0, 1280, 360), Color("DCEBFA"))
	c.draw_rect(Rect2(0, 360, 1280, 360), Color("1D3A63"))
	var names: Array = ART.data()["words"].keys()
	names.sort()
	for i in names.size():
		var w: String = names[i]
		var t: Texture2D = WORDS.tex(w)
		var box := Vector2(290, 40)
		var wide := minf(box.x, box.y * float(t.get_width()) / float(t.get_height()))
		for half in 2:
			var centre := Vector2(160.0 + 310.0 * (i % 4), 32.0 + 58.0 * (i / 4) + 360.0 * half)
			WORDS.draw(c, w, centre, wide)
			_cap(c, centre + Vector2(-150, 31), "%s %dx%d" % [w, t.get_width(), t.get_height()], Color.WHITE if half == 1 else INK)

func _wall(c: Node2D, kind: String, cols: int, cell: Vector2, scale: float) -> void:
	_sky(c)
	var list: Array = roster[kind]
	for i in list.size():
		var p: Dictionary = list[i]
		var o := Vector2(8.0 + cell.x * (i % cols), 22.0 + cell.y * (i / cols))
		var t: Texture2D = ART.portrait(int(p["id"]))
		c.draw_texture_rect(t, Rect2(o, t.get_size() * scale), false)
		_cap(c, o + Vector2(2, t.get_size().y * scale + 11.0), "%s %d" % [p["name"], int(p["id"])])

func _fighters(c: Node2D) -> void:
	_wall(c, "fighters", 8, Vector2(158, 140), 0.62)
	_cap(c, Vector2(8, 14), "the fighters, Student_Portrait at 0.62")

func _specials(c: Node2D) -> void:
	_wall(c, "specials", 12, Vector2(106, 88), 0.4)
	_cap(c, Vector2(8, 14), "the 81 specials (assists), Student_Portrait at 0.4")

func _name(c: Node2D, text: String, pos: Vector2, size: int) -> void:
	var f: Font = load("res://scripts/ui/ui.gd").font_ui(700)
	c.draw_set_transform_matrix(Transform2D(Vector2(1.0, 0.0), Vector2(-LEAN, 1.0), Vector2(LEAN * pos.y, 0.0)))
	c.draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color("39436F"))
	c.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

## One top cluster. side 1 is the left one (outer edge left); side 2 mirrors positions, not the lean.
func _top(c: Node2D, side: int, id: int, who: String, frac: float, guard: float, badges: Array) -> void:
	var left := side == 1
	var fill := RED if left else CYAN
	var ox := 0.0 if left else 1280.0
	var dir := 1.0 if left else -1.0
	var card := Rect2(22, 28, 160, 129) if left else Rect2(1098, 28, 160, 129)
	ART.blit(c, "Combat__Combat_CardBg_EX", card, Color("FFC4CB") if left else Color("B9E2FF"))
	c.draw_texture_rect(ART.portrait(id), Rect2(26, 24, 150, 121) if left else Rect2(1104, 24, 150, 121), false)
	_bar(c, Rect2(129, 40, 480, 42) if left else Rect2(657, 40, 480, 42), frac, fill, LEAN, not left)
	_name(c, who, Vector2(233, 69) if left else Vector2(1137.0 - 104.0 - 84.0, 69), 22)
	var crest: Texture2D = ART.school_crest("Gehenna" if left else "Abydos")
	c.draw_texture_rect(crest, Rect2(197, 41, 34, 31) if left else Rect2(1035, 37, 34, 31), false)
	_bar(c, Rect2(234, 89, 250, 12) if left else Rect2(786, 89, 250, 12), guard, Color("EAF6FF") if guard > 0.3 else Color("FEE600"), LEAN, not left)
	ART.blit(c, "Combat__Combat_CardBg_EX_CostTag", Rect2(200, 82, 30, 30) if left else Rect2(1058, 82, 30, 30), Color.WHITE)
	c.draw_texture_rect(ART.role_icon("Tanker"), Rect2(207, 89, 16, 16) if left else Rect2(1065, 89, 16, 16), false)
	for i in badges.size():
		ART.blit(c, badges[i], Rect2((234.0 + 31.0 * i) if left else (1036.0 - 31.0 * i - 28.0), 112, 28, 32))
	var chip := Rect2(168, 106, 36, 34) if left else Rect2(1090, 106, 36, 34)
	ART.blit(c, "Common__Card_Role_Bg", chip, ART.attack_color("Explosion" if left else "Pierce"))
	c.draw_texture_rect(ART.role_icon("DamageDealer" if left else "Tanker"), chip.grow(-6.0), false)

func _mock(c: Node2D) -> void:
	_sky(c)
	var halo: Texture2D = ART.tex("UIs__00_Images__Image_Deco_Circle")
	c.draw_texture_rect(halo, Rect2(78, -40, 240, 240), false, Color(1, 1, 1, 0.5))
	c.draw_texture_rect(halo, Rect2(962, -40, 240, 240), false, Color(1, 1, 1, 0.5))
	_top(c, 1, 10004, "Hina", 0.72, 0.8, ["Combat__Combat_Icon_Buff_ATK", "Combat__Combat_Icon_Buff_AmmoCount"])
	_top(c, 2, 10005, "Hoshino", 0.55, 0.25, ["Combat__Combat_Icon_Buff_Shield", "Combat__Combat_Icon_CC_Stunned"])
	ART.nine(c, "Common__Common_Bg_Raius10px", Rect2(558, 16, 164, 72), Color("062D51"), LEAN)
	ART.nine(c, "Combat__Combat_Bg_Hp", Rect2(558, 16, 164, 72), Color.WHITE, LEAN)
	ART.blit(c, "Combat__Combat_Time_Icon", Rect2(578, 38, 26, 29))
	NUM.draw(c, "60", Vector2(664, 28), 40.0, NUM.Tier.WHITE, Color.WHITE, 1)
	for x in [516.0, 546.0, 708.0, 738.0]:
		ART.blit(c, "Combat__Combat_CardBg_EX_CostTag", Rect2(x, 88, 26, 26))
	ART.blit(c, "Emoji__Emoji_Twinkle", Rect2(550, 92, 16, 18))
	ART.nine(c, "Combat__Combat_Title_Bg", Rect2(583, 90, 114, 22), Color.WHITE, LEAN)
	WORDS.draw(c, "round_2", Vector2(640, 101), 64.0)
	NUM.draw(c, "8", Vector2(34, 170), 78.0, NUM.Tier.EFFECTIVE)
	WORDS.draw(c, "combo", Vector2(173, 214), 132.0)
	ART.blit(c, "Common__Common_Attack_Icon", Rect2(42, 263, 43, 44))
	NUM.draw(c, "129", Vector2(90, 266), 28.0, NUM.Tier.NORMAL)
	WORDS.draw(c, "block", Vector2(948, 350), 134.0)
	NUM.draw(c, "7", Vector2(1022, 336), 29.0, NUM.Tier.RESIST)
	WORDS.draw(c, "just_guard", Vector2(460, 330), 190.0)
	WORDS.draw(c, "guard_crush", Vector2(920, 290), 240.0)
	# bottom row: assist card, COST disc, ten cells, tags, EX plate
	ART.blit(c, "Combat__Combat_CardBg_EX", Rect2(16, 580, 158, 129), Color("FFC4CB"))
	c.draw_texture_rect(ART.portrait(20001), Rect2(20, 576, 148, 120), false)
	ART.nine(c, "Common__Card_Select_Line", Rect2(22, 574, 164, 136), Color("FEE600"))
	ART.blit(c, "Combat__Combat_CardBg_EX_CostTag", Rect2(14, 566, 40, 40))
	_name(c, "Q", Vector2(27, 594), 20)
	ART.nine(c, "Common__Common_Nonoutline_W_Bg", Rect2(34, 692, 130, 20), Color.WHITE, LEAN)
	ART.blit(c, "Combat__Combat_CostBg", Rect2(153, 619, 66, 66))
	NUM.draw(c, "10", Vector2(186, 645), 28.0, NUM.Tier.NORMAL, Color.WHITE, 1)
	for i in 10:
		var r := Rect2(228.0 + 37.0 * i, 640, 34, 26)
		ART.nine(c, "Combat__Common_Bg_Raius5px", r, SLOT, LEAN)
		ART.nine(c, "Combat__Combat_Cost_Gauge", r.grow_individual(-2, -3, -2, -3), CELL, LEAN)
	for tag in [[409.0, 625.0, "5"], [592.0, 623.0, "10"]]:
		ART.blit(c, "Combat__Combat_CardBg_EX_CostTag", Rect2(tag[0], tag[1], 28, 28), Color(1, 0.95, 0.4))
		NUM.draw(c, tag[2], Vector2(tag[0] + 14.0, tag[1] + 8.0), 11.0, NUM.Tier.MINI, Color.WHITE, 1)
	ART.nine(c, "Combat__Common_Btn_BG", Rect2(445, 588, 136, 49), Color("FEE600"), LEAN)
	ART.blit(c, "Common__Common_Btn_Normal_Y_S_Pt", Rect2(445, 586, 140, 52))
	WORDS.draw(c, "ex_ready", Vector2(515, 612), 96.0)
	# P2 bottom: COST disc at the right end, cells fill away from it
	for i in 10:
		var r := Rect2(676.0 + 37.0 * i, 640, 34, 26)
		ART.nine(c, "Combat__Common_Bg_Raius5px", r, SLOT, LEAN)
		if i >= 4:
			ART.nine(c, "Combat__Combat_Cost_Gauge", r.grow_individual(-2, -3, -2, -3), CELL, LEAN)
	ART.nine(c, "Combat__Common_Btn_BG", Rect2(728, 571, 109, 41), Color("77DEFF"), LEAN)
	ART.blit(c, "Common__Common_Btn_Normal_B_S_Pt", Rect2(728, 569, 112, 44))
	WORDS.draw(c, "super", Vector2(783, 592), 80.0)
	ART.blit(c, "Combat__Combat_CardBg_EX", Rect2(1090, 580, 158, 129), Color("B9E2FF"))
	c.draw_texture_rect(ART.portrait(23005), Rect2(1094, 576, 148, 120), false)
	ART.blit(c, "Combat__Combat_CostBg", Rect2(1061, 619, 66, 66))
	NUM.draw(c, "6", Vector2(1094, 645), 28.0, NUM.Tier.NORMAL, Color.WHITE, 1)
