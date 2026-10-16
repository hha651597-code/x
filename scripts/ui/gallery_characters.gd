class_name GalleryCharacters
extends Control
## Extras > CHARACTERS. A scrolling grid of BA portrait cards (the fighters, or the 81 specials with their names) on the left and
## the highlighted student on the right: the art standing on a school-tinted facet card, and a popup with the school, the name
## on a navy plate with rarity stars, role / weapon / armour / bullet chips, club, height, voice, striker type, ease of use, the
## intro, the official EX skill name on a navy ribbon and a move table with D_Font numerals generated from Movesets (frame data
## and damage; shots for projectile skills). Specials show their assist card instead of the table.
##
## The screen owns tabs / back and calls: begin(first), handle(act) -> bool (false = "up" off the top row), set_page_focus(b),
## set_active(b), exit(), probe().

const Menu := preload("res://scripts/ui/ba_menu.gd")
const PainterScript := preload("res://scripts/ui/painter.gd")

signal wants_focus

const COLS := 5
const TILE := Vector2(96, 84)
const PITCH := Vector2(94, 90)
const VIEW := Rect2(12, 118, 480, 570)
const TILE_X0 := 0.0
const TILE_Y0 := 8.0
const SUB_Y := 76.0
const SUB_SIZE := Vector2(150, 32)
const PLATE_BOX := Rect2(486, 66, 322, 624)
const FIGHTER_CARD := Rect2(2, 364, 312, 256)
const SPECIAL_CARD := Rect2(2, 190, 312, 256)
const SPECIAL_ART := Rect2(8, 198, 296, 334)
const HEAD_AT := Vector2(176, 150)
const HEAD_PX := 168.0
const INFO := Rect2(806, 70, 450, 618)
const IX := 22.0
const IW := 406.0
const HEAD_H := 54.0
const NAME_Y := 62.0
const NAME_H := 54.0
const CHIP_Y := 124.0
const CHIP_SIZE := Vector2(200, 38)
const FACTS_Y := 210.0
const FACT_H := 34.0
const INTRO_Y := 318.0
const EX_H := 34.0
const TABLE_HEAD := 24.0
const BOTTOM_PAD := 14.0
const SKILL_NAMES := {
	"SMG": "Spray", "HG": "Double tap", "SG": "Buckshot", "SR": "Snipe", "MG": "Suppress", "GL": "Grenade",
	"RL": "Rocket", "RG": "Rail beam", "MT": "Mortar", "FT": "Flames", "AR": "Burst",
}
## roster.json carries Japanese intro / EX text for a couple of students (the bundled font has no kanji): English stand-ins.
const JA_FALLBACK := {
	10090: {"intro": "A first-year member of the Festival Management Committee at Hyakkiyako Alliance Academy.", "exName": "Let the Festival Begin!"},
	10093: {"intro": "A cheerful high school girl from Gehenna Academy.", "exName": "Gehenna's Celebrity!"},
}
const ASSIST_KIND := {"volley": "Ranged", "guard": "Defensive", "heal": "Healing", "buff": "Buff", "strike": "Vehicle"}
const ASSIST_TEXT := {
	"volley": "Fires a five-round covering volley across the screen.",
	"guard": "Raises a shield wall that absorbs incoming hits for about five seconds.",
	"heal": "Patches you up: restores 14% of your maximum health.",
	"buff": "A rousing call-out: your attacks hit harder for about seven seconds.",
	"strike": "A vehicle charges in from behind you and knocks the opponent down.",
}
const TABLE_COLS := [168.0, 60.0, 60.0, 58.0, 60.0]     # widths: the move column, then damage, startup, active, recovery
const TABLE_HEADS := ["DAMAGE", "STARTUP", "ACTIVE", "RECOVERY"]

var active := false
var _t := 0.0
var _first := true
var _page_focus := true
var _mode := 0                              # 0 fighters, 1 specials
var _sel := [0, 0]
var _scroll := 0.0
var _scroll_to := 0.0
var _grids: Array = [null, null]            # {holder, tiles[], rows}
var _grid_t := [0.0, 0.0]                   # time since each grid was shown
var _view: Control
var _toggle: Array = []
var _bar: Control
var _plate: GalleryPlate
var _info: Control
var _info_t := 1.0
var _dir := 1.0
var _cur_id := -1
var _s: Dictionary = {}
var _lay: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_select(0, false, false)

func items() -> Array:
	return Game.fighters if _mode == 0 else Game.specials

# construction
func _build() -> void:
	for i in 2:
		var tb := GalleryKit.Tab.new().setup(SUB_SIZE, ["Fighters  %d" % Game.fighters.size(), "Specials  %d" % Game.specials.size()][i], 15)
		tb.position = Vector2(14.0 + float(i) * (SUB_SIZE.x + 12.0), SUB_Y)
		tb.gui_input.connect(_on_toggle_input.bind(i))
		add_child(tb)
		_toggle.append(tb)
	_view = Control.new()
	_view.position = VIEW.position
	_view.size = VIEW.size
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	add_child(_view)
	_build_grid(0)
	_bar = PainterScript.new().setup(Vector2(8, VIEW.size.y), _draw_bar)
	_bar.position = Vector2(VIEW.end.x - 2.0, VIEW.position.y)
	add_child(_bar)
	_plate = GalleryPlate.new().setup(PLATE_BOX.size)
	_plate.position = PLATE_BOX.position
	add_child(_plate)
	_info = PainterScript.new().setup(INFO.size, _draw_info)
	_info.position = INFO.position
	add_child(_info)

func _build_grid(mode: int) -> void:
	var list: Array = Game.fighters if mode == 0 else Game.specials
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(holder)
	var tiles := []
	for i in list.size():
		var h := GalleryKit.Tile.new()
		h.s = list[i]
		h.foot = 17.0 if mode == 1 else 0.0
		h.size = TILE
		h.position = Vector2(TILE_X0 + float(i % COLS) * PITCH.x, TILE_Y0 + float(i / COLS) * PITCH.y)
		h.pivot_offset = TILE * 0.5
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.gui_input.connect(_on_tile_input.bind(mode, i))
		holder.add_child(h)
		tiles.append({"node": h, "base": h.position, "bump": 0.0, "sc": 1.0})
	_grids[mode] = {"holder": holder, "tiles": tiles}

# page API
func begin(first: bool) -> void:
	_t = 0.0
	_first = first
	_grid_t[_mode] = 0.0
	_info_t = 0.0

func set_active(b: bool) -> void:
	active = b
	visible = b
	set_process(b)
	for tb in _toggle:
		(tb as Control).mouse_filter = Control.MOUSE_FILTER_STOP if b else Control.MOUSE_FILTER_IGNORE
	_view.mouse_filter = Control.MOUSE_FILTER_STOP if b else Control.MOUSE_FILTER_IGNORE

func set_page_focus(b: bool) -> void:
	_page_focus = b
	_apply_highlight()

func _apply_highlight() -> void:
	var g: Dictionary = _grids[_mode]
	if g == null:
		return
	for k in (g["tiles"] as Array).size():
		var tl: GalleryKit.Tile = g["tiles"][k]["node"]
		tl.sel = k == _sel[_mode] and _page_focus
		tl.queue_redraw()

func exit() -> void:
	pass

func handle(act: String) -> bool:
	var n := items().size()
	var i: int = _sel[_mode]
	match act:
		"left":
			if i > 0:
				_select(i - 1)
		"right":
			if i < n - 1:
				_select(i + 1)
		"down":
			if i + COLS < n:
				_select(i + COLS)
			elif int(i / COLS) < int((n - 1) / COLS):
				_select(n - 1)
		"up":
			if i - COLS >= 0:
				_select(i - COLS)
			else:
				return false
		"aux", "aux2":
			_set_mode(1 - _mode)
		"confirm":
			var g: Dictionary = _grids[_mode]
			(g["tiles"][i] as Dictionary)["bump"] = 1.0
			Sfx.play("pop", 1.2, 0.8)
			_plate.pulse()
			_info_t = 0.0
	return true

func probe() -> Dictionary:
	var s: Dictionary = items()[_sel[_mode]]
	return {"mode": "specials" if _mode == 1 else "fighters", "index": _sel[_mode], "id": s["id"], "name": Fighters.display_name(s),
			"scroll": snappedf(_scroll, 0.1), "count": items().size()}

# selection
func _set_mode(m: int) -> void:
	if m == _mode:
		return
	_mode = m
	Sfx.play("whoosh", 1.2, 0.5)
	if _grids[m] == null:
		_build_grid(m)
	for k in 2:
		(_grids[k]["holder"] as Control).visible = k == m
	_grid_t[m] = 0.0
	_scroll = 0.0
	_scroll_to = 0.0
	_cur_id = -1
	_select(_sel[m], false, true)
	_info_t = 0.0

func _select(i: int, sound := true, animate := true) -> void:
	var list := items()
	i = clampi(i, 0, list.size() - 1)
	var old: int = _sel[_mode]
	_sel[_mode] = i
	if _grids[_mode] != null:
		_apply_highlight()
		_scroll_into_view(i)
	var s: Dictionary = list[i]
	if int(s["id"]) == _cur_id:
		return
	if sound and i != old:
		Sfx.play("tick")
	_dir = 1.0 if i >= old else -1.0
	_cur_id = int(s["id"])
	_show(s, animate and _cur_id != -1)

func _scroll_into_view(i: int) -> void:
	var top := TILE_Y0 + float(int(i / COLS)) * PITCH.y
	var bottom := top + TILE.y
	var margin := 8.0
	if top - _scroll_to < margin:
		_scroll_to = top - margin
	elif bottom - _scroll_to > VIEW.size.y - margin:
		_scroll_to = bottom - VIEW.size.y + margin
	_scroll_to = clampf(_scroll_to, 0.0, _max_scroll())

func _max_scroll() -> float:
	var rows := int((items().size() - 1) / COLS) + 1
	return maxf(0.0, TILE_Y0 + float(rows - 1) * PITCH.y + TILE.y + 8.0 - VIEW.size.y)

# detail
func _show(s: Dictionary, animate: bool) -> void:
	var special := _mode == 1
	_s = s
	_lay = layout(s, special)
	_plate.set_scheme(GalleryKit.tint_of(s))
	var id := int(s["id"])
	if special:
		var tex := UI.collection(id)
		_plate.set_plate(SPECIAL_CARD, 0.0)
		_plate.set_halo(Vector2(158.0, 318.0), 380.0)
		_plate.show_art(tex, SPECIAL_ART, _dir, animate)
	else:
		var tex := UI.portrait(id)
		var hd := SelectFrames.head(id, tex)
		var sc := HEAD_PX / float(hd[2])
		var centre := Vector2(float(hd[0]) + float(hd[2]) * 0.5, float(hd[1]) + float(hd[2]) * 0.5)
		_plate.set_plate(FIGHTER_CARD, FIGHTER_CARD.position.y - 8.0)
		_plate.set_halo(HEAD_AT, 250.0)
		_plate.show_art(tex, Rect2(HEAD_AT - centre * sc, Vector2(tex.get_size()) * sc), _dir, animate)
	if animate:
		_info_t = 0.0
	_info.queue_redraw()

static func _latin(s: Dictionary, key: String, generic: String) -> String:
	var txt := String(s.get(key, ""))
	for ch in txt:
		if ch.unicode_at(0) > 0x2E80:
			return String((JA_FALLBACK.get(int(s["id"]), {}) as Dictionary).get(key, generic))
	return txt

## Everything the popup draws for student s, and where: text, sizes, wrapped lines and the y of each block, so a test can check
## that the longest strings fit without drawing anything. fits is false when something had to be cut.
static func layout(s: Dictionary, special: bool) -> Dictionary:
	var role := String(s["role"])
	var lay := {"special": special}
	var nm := Fighters.display_name(s).to_upper()
	lay["name"] = nm
	lay["school"] = String(s["schoolName"])
	lay["stars"] = int(s["stars"])
	lay["chips"] = [
		["ROLE", String(GalleryKit.ROLE_NAMES.get(role, role))],
		["WEAPON", String(GalleryKit.WEAPON_NAMES.get(s["weapon"], s["weapon"]))],
		["ARMOR", String(GalleryKit.ARMOR_NAMES.get(s["armor"], s["armor"]))],
		["BULLET", String(s["bullet"])],
	]
	if special:
		lay["facts"] = [["Club", String(s["clubName"])], ["Height", String(s["height"])], ["Voice", String(s["voice"])],
				["Position", String(GalleryKit.POSITION_NAMES.get(s["position"], s["position"]))], ["Squad", "Special" if String(s["squad"]) == "Support" else "Striker"]]
	else:
		lay["facts"] = [["Club", String(s["clubName"])], ["Height", String(s["height"])], ["Voice", String(s["voice"])],
				["Striker type", Fighters.striker_type(s)], ["Ease of use", Fighters.ease_of_use(s)]]
	var max_intro := 6 if special else 4
	var intro := GalleryKit.fit_paragraph(_latin(s, "intro", "A student of %s." % String(s["schoolName"])), 600, 14, 12, IW, max_intro)
	lay["intro"] = intro
	lay["ex"] = _latin(s, "exName", "EX Skill")
	var line_h := float(intro["size"]) + 4.0
	var y_ex := INTRO_Y + line_h * float((intro["lines"] as Array).size()) + 8.0
	var y_tab := y_ex + EX_H + 10.0
	lay["y_ex"] = y_ex
	lay["y_tab"] = y_tab
	lay["tab_h"] = INFO.size.y - BOTTOM_PAD - y_tab
	var need := 112.0 if special else TABLE_HEAD + 8.0 * 16.0
	lay["fits"] = bool(intro["fits"]) and float(lay["tab_h"]) >= need
	if special:
		var a := Movesets.assist_for(s)
		lay["assist"] = {"name": String(a["name"]), "color": a["color"], "kind": String(ASSIST_KIND.get(a["kind"], "Assist")),
				"text": String(ASSIST_TEXT.get(a["kind"], ""))}
	else:
		lay["rows"] = move_rows(s)
	return lay

## Move list rows: [code, descriptor, damage text, startup, active, recovery, kind]
static func move_rows(s: Dictionary) -> Array:
	var kit := Kits.make(s)
	var mv := kit.build_moves(kit.build_stats())
	var defs := [["5L", "5L", "Light"], ["5H", "5H", "Heavy"], ["2L", "2L", "Low"], ["2H", "2H", "Launcher"],
			["jL", "jL", "Air light"], ["jH", "jH", "Air heavy"], ["skill", "Skill", ""], ["ex", "EX", "EX Skill"]]
	var out := []
	for d in defs:
		var m: Dictionary = mv.get(d[0], {})
		var dm := _damage_of(m)
		var per: int = dm[0]
		var shots: int = dm[1]
		var desc: String = d[2]
		if d[0] == "skill":
			desc = String(SKILL_NAMES.get(s["weapon"], "Skill")) + " · %d shot%s" % [shots, "" if shots == 1 else "s"]
		elif d[0] == "ex":
			desc = "EX Skill · %d shot%s" % [shots, "" if shots == 1 else "s"]
		out.append([String(d[1]), desc, ("%d" % per) if shots <= 1 else ("%d×%d" % [per, shots]),
				int(m.get("startup", 0)), int(m.get("active", 0)), int(m.get("recovery", 0)), String(d[0])])
	return out

## [damage per hit, number of shots]. Kit moves carry decorative spawns with no hit of their own: only a spawn that deals damage is a shot.
static func _damage_of(m: Dictionary) -> Array:
	var shots: Array = []
	for sp: Dictionary in m.get("spawns", []):
		var ex: Dictionary = sp.get("explode", {})
		var h: Dictionary = ex.get("hit", {}) if not ex.is_empty() else sp.get("hit", {})
		if float(h.get("dmg", 0.0)) > 0.0:
			shots.append(float(h["dmg"]))
	if shots.is_empty():
		return [int(round(float((m.get("hit", {}) as Dictionary).get("dmg", 0.0)))), 1]
	return [int(round(shots[0])), shots.size()]

# drawing the popup
func _draw_info(c: Control) -> void:
	if _lay.is_empty():
		return
	GalleryKit.popup(c, Rect2(Vector2.ZERO, INFO.size), HEAD_H)
	_draw_header(c)
	_draw_name(c)
	_draw_chips(c)
	_draw_facts(c)
	_draw_intro(c)
	_draw_ex(c)
	if _lay["special"]:
		_draw_assist(c)
	else:
		_draw_table(c)

func _draw_header(c: Control) -> void:
	var crest := BaArt.school_crest(String(_s["school"]))
	if crest != null:
		c.draw_texture_rect(crest, Rect2(IX - 4.0, 10.0, 38.0, 34.5), false, Color(GalleryKit.tint_of(_s).darkened(0.55), 1.0))
	var size := Menu.fit(_lay["school"], 19, IW - 60.0, 12, 800)
	Menu.label(c, Menu.clip(_lay["school"], size, IW - 60.0, 800), Vector2(IX + 42.0, 33.0), size, BaTokens.INK, Color.WHITE, 2, 0, 800)

func _draw_name(c: Control) -> void:
	var r := Rect2(IX, NAME_Y, IW, NAME_H)
	Menu.nine(c, "Combat__Combat_Title_Bg", r, Menu.K, Color.WHITE, GalleryKit.SHEAR)
	GalleryKit.draw_name(c, _lay["name"], Vector2(r.position.x + 22.0, r.end.y - 11.0), 48, IW - 140.0, Color.WHITE, BaTokens.HEAD_OUTLINE, 3)
	GalleryKit.draw_stars(c, Vector2(r.end.x - 98.0, r.position.y + 14.0), int(_lay["stars"]), 26.0)

func _draw_chips(c: Control) -> void:
	var chips: Array = _lay["chips"]
	var s := _s
	var atk := BaArt.attack_color(String(s["bullet"]))
	var arm := BaArt.attack_color(String(GalleryKit.ARMOR_AS_BULLET.get(s["armor"], "")))
	var tiles := [
		[BaTokens.INK, BaArt.role_icon(String(s["role"])), ""],
		[BaTokens.INK, null, String(s["weapon"])],
		[arm, GalleryKit.white_of(BaArt.tex("Common__Common_Defense_Icon")), ""],
		[atk, GalleryKit.white_of(BaArt.tex("Common__Common_Attack_Icon")), ""],
	]
	for i in 4:
		var r := Rect2(IX + float(i % 2) * (CHIP_SIZE.x + 6.0), CHIP_Y + float(i / 2) * (CHIP_SIZE.y + 4.0), CHIP_SIZE.x, CHIP_SIZE.y)
		GalleryKit.draw_chip(c, r, chips[i][1], tiles[i][0], tiles[i][1], tiles[i][2], chips[i][0])

func _draw_facts(c: Control) -> void:
	var facts: Array = _lay["facts"]
	var cells := [
		Rect2(IX, FACTS_Y, IW, FACT_H),
		Rect2(IX, FACTS_Y + FACT_H, 194.0, FACT_H), Rect2(IX + 206.0, FACTS_Y + FACT_H, 200.0, FACT_H),
		Rect2(IX, FACTS_Y + FACT_H * 2.0, 194.0, FACT_H), Rect2(IX + 206.0, FACTS_Y + FACT_H * 2.0, 200.0, FACT_H),
	]
	for i in 5:
		var r: Rect2 = cells[i]
		Menu.label(c, String(facts[i][0]).to_upper(), Vector2(r.position.x, r.position.y + 11.0), 10, Color(BaTokens.INK, 0.7), Color(0, 0, 0, 0), 0, 0, 800)
		var v := String(facts[i][1])
		var size := Menu.fit(v, 16, r.size.x - 4.0, 11, 800)
		Menu.label(c, Menu.clip(v, size, r.size.x - 4.0, 800), Vector2(r.position.x, r.position.y + 28.0), size, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)
	GalleryKit.draw_dots(c, IX, IX + IW, FACTS_Y + FACT_H - 1.0)
	GalleryKit.draw_dots(c, IX, IX + IW, FACTS_Y + FACT_H * 2.0 - 1.0)

func _draw_intro(c: Control) -> void:
	var intro: Dictionary = _lay["intro"]
	var f := UI.font_ui(600)
	var size: int = intro["size"]
	var y := INTRO_Y + float(size)
	for line in intro["lines"]:
		c.draw_string(f, Vector2(IX, y), line, HORIZONTAL_ALIGNMENT_LEFT, IW + 2.0, size, Color(BaTokens.INK, 0.92))
		y += float(size) + 4.0

func _draw_ex(c: Control) -> void:
	var r := Rect2(IX, float(_lay["y_ex"]), IW, EX_H)
	Menu.nine(c, "Combat__Combat_Title_Bg", r, Menu.K, Color.WHITE, GalleryKit.SHEAR)
	Menu.label(c, "EX SKILL", Vector2(r.position.x + 18.0, r.get_center().y + 5.0), 14, BaTokens.CONFIRM, Color(0, 0, 0, 0), 0, 0, 800)
	var nm := String(_lay["ex"])
	var room := IW - 112.0
	var size := Menu.fit(nm, 17, room, 11, 800)
	Menu.label(c, Menu.clip(nm, size, room, 800), Vector2(r.position.x + 96.0, r.get_center().y + size * 0.36), size, Color.WHITE, Color(0, 0, 0, 0), 0, 0, 800)

func _draw_table(c: Control) -> void:
	var y0 := float(_lay["y_tab"])
	var h := float(_lay["tab_h"])
	var box := Rect2(IX, y0, IW, h)
	Menu.nine(c, "Common__Common_Bg_Raius10px", box, Menu.K, BaTokens.FACET_A)
	var rows: Array = _lay["rows"]
	var head := Rect2(IX, y0, IW, TABLE_HEAD)
	Menu.nine(c, "Combat__Combat_Title_Bg", head, Menu.K, Color.WHITE, GalleryKit.SHEAR)
	Menu.label(c, "MOVE", Vector2(IX + 18.0, y0 + 16.0), 11, Color.WHITE, Color(0, 0, 0, 0), 0, 0, 800)
	var cx := IX + TABLE_COLS[0]
	var centres := []
	for i in 4:
		centres.append(cx + TABLE_COLS[1 + i] * 0.5)
		cx += TABLE_COLS[1 + i]
		Menu.label(c, TABLE_HEADS[i], Vector2(centres[i], y0 + 16.0), 9, Color.WHITE, Color(0, 0, 0, 0), 0, 1, 800)
	var row_h := minf((h - TABLE_HEAD - 6.0) / float(rows.size()), 26.0)
	for r in rows.size():
		var row: Array = rows[r]
		var y := y0 + TABLE_HEAD + 3.0 + float(r) * row_h
		var kind: String = row[6]
		if kind == "ex":
			Menu.nine(c, "Common__Common_Bg_Raius10px", Rect2(IX + 5.0, y, IW - 10.0, row_h), Menu.K, Color(BaTokens.CONFIRM, 0.55))
		elif kind == "skill":
			Menu.nine(c, "Common__Common_Bg_Raius10px", Rect2(IX + 5.0, y, IW - 10.0, row_h), Menu.K, BaTokens.FACET_C)
		elif r % 2 == 1:
			Menu.nine(c, "Common__Common_Bg_Raius10px", Rect2(IX + 5.0, y, IW - 10.0, row_h), Menu.K, Color(1, 1, 1, 0.7))
		var mid := y + row_h * 0.5
		Menu.label(c, row[0], Vector2(IX + 14.0, mid + 4.6), 13, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)
		var room := TABLE_COLS[0] - 56.0
		var ds := Menu.fit(row[1], 12, room, 9, 600)
		Menu.label(c, Menu.clip(row[1], ds, room, 600), Vector2(IX + 52.0, mid + 4.4), ds, Color(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 0, 600)
		var nh := minf(row_h - 8.0, 15.0)
		GalleryKit.draw_number(c, row[2], Vector2(centres[0], mid - nh * 0.5), nh, BaNumerals.Tier.EFFECTIVE, Color.WHITE, 1)
		for j in 3:
			GalleryKit.draw_number(c, str(row[3 + j]), Vector2(centres[1 + j], mid - nh * 0.5), nh, BaNumerals.Tier.WHITE, BaTokens.INK, 1)

func _draw_assist(c: Control) -> void:
	var a: Dictionary = _lay["assist"]
	var y0 := float(_lay["y_tab"])
	var h := float(_lay["tab_h"])
	Menu.nine(c, "Common__Common_Bg_Raius10px", Rect2(IX, y0, IW, h), Menu.K, BaTokens.FACET_A)
	GalleryKit.ribbon_left(c, Rect2(IX, y0, 140.0, 24.0), "AS A SPECIAL", Color.WHITE, 12)
	var nm := String(a["name"])
	var ns := Menu.fit(nm, 22, IW - 170.0, 14, 800)
	Menu.label(c, nm, Vector2(IX + 156.0, y0 + 19.0), ns, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)
	var f := UI.font_ui(600)
	var y := y0 + 48.0
	for line in GalleryKit.wrap_text(String(a["text"]), 600, 14, IW - 32.0):
		c.draw_string(f, Vector2(IX + 16.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, IW - 30.0, 14, Color(BaTokens.INK, 0.92))
		y += 18.0
	var my := y0 + h - 16.0
	BaArt.blit(c, "Common__Card_Role_Bg", Rect2(IX + 14.0, my - 15.0, 20.0, 19.0), a["color"], GalleryKit.SHEAR)
	Menu.label(c, String(a["kind"]).to_upper(), Vector2(IX + 44.0, my), 13, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)

# frame
func _process(delta: float) -> void:
	_t += delta
	var g: Dictionary = _grids[_mode]
	if g == null:
		return
	_grid_t[_mode] += delta
	var gt: float = _grid_t[_mode]
	_scroll = lerpf(_scroll, _scroll_to, 1.0 - exp(-delta * 13.0))
	if absf(_scroll - _scroll_to) < 0.05:
		_scroll = _scroll_to
	(g["holder"] as Control).position.y = -_scroll
	var sel: int = _sel[_mode]
	var tiles: Array = g["tiles"]
	for k in tiles.size():
		var tl: Dictionary = tiles[k]
		var h: GalleryKit.Tile = tl["node"]
		var ct := gt - (0.2 if _first else 0.0) - Motion.stagger(mini(k, 24), 0.02)
		if ct <= 0.0:
			h.visible = false
			continue
		h.visible = true
		var e := Motion.whip(ct, 0.12, 0.25)
		h.position = (tl["base"] as Vector2) + Vector2(-(1.0 - e) * 44.0, 0.0)
		tl["bump"] = move_toward(float(tl["bump"]), 0.0, delta * 3.2)
		var bump := sin(float(tl["bump"]) * PI) * 0.1
		var target := 1.06 if k == sel else 1.0
		var cur: float = lerpf(float(tl["sc"]), target, 1.0 - exp(-delta * 16.0))
		tl["sc"] = cur
		h.scale = Vector2.ONE * cur * (1.0 + bump)
		h.z_index = 2 if k == sel else 0
		var want := 1.0 if (k == sel or not _page_focus) else GalleryKit.DIM
		var d := lerpf(h.dim, want, 1.0 - exp(-delta * 14.0))
		if absf(d - h.dim) > 0.002 or h.sel:
			h.dim = d
			h.t += delta
			h.queue_redraw()
	_bar.visible = _max_scroll() > 1.0
	_bar.queue_redraw()
	_info_t = minf(_info_t + delta / 0.3, 1.0)
	_info.position = INFO.position + Vector2((1.0 - Motion.whip(_t - (0.34 if _first else 0.04), 0.15, 0.3)) * 620.0
			+ (1.0 - Motion.whip(_info_t * 0.3, 0.1, 0.2)) * 20.0 * _dir, 0.0)
	var pl := Motion.whip(_t - (0.22 if _first else 0.0), 0.15, 0.3)
	_plate.position = PLATE_BOX.position + Vector2((1.0 - pl) * 520.0, 0.0)
	for i in _toggle.size():
		var tb: GalleryKit.Tab = _toggle[i]
		tb.selected = i == _mode
		tb.focused = false
		tb.position = Vector2(14.0 + float(i) * (SUB_SIZE.x + 12.0) - (1.0 - Motion.whip(_t - 0.08 - Motion.stagger(i * 3))) * 160.0, SUB_Y)
		tb.tick(delta)

func _draw_bar(c: Control) -> void:
	var h := c.size.y
	var total := _max_scroll() + VIEW.size.y
	Menu.nine(c, "Combat__Common_Bg_Raius5px", Rect2(1, 0, 5, h), Menu.K, Color(BaTokens.GAUGE_EMPTY, 0.45))
	var th := maxf(h * VIEW.size.y / total, 30.0)
	var ty := (h - th) * (_scroll / maxf(_max_scroll(), 1.0))
	Menu.nine(c, "Combat__Common_Bg_Raius5px", Rect2(0, ty, 7, th), Menu.K, BaTokens.COST)

# mouse
func _can_mouse() -> bool:
	return active and not Game.busy and _t > 0.4

## Hover = real mouse motion only (tiles that slide under a resting pointer while the keyboard scrolls must not steal the cursor).
func _on_tile_input(ev: InputEvent, mode: int, i: int) -> void:
	if not _can_mouse() or mode != _mode:
		return
	if ev is InputEventMouseMotion:
		if (ev as InputEventMouseMotion).relative == Vector2.ZERO:
			return
		if i != _sel[_mode] or not _page_focus:
			wants_focus.emit()
			_select(i)
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_select(i, false)
			handle("confirm")
		else:
			_wheel(ev)

func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		_wheel(ev)

func _wheel(ev: InputEventMouseButton) -> void:
	if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_to = clampf(_scroll_to + 96.0, 0.0, _max_scroll())
	elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
		_scroll_to = clampf(_scroll_to - 96.0, 0.0, _max_scroll())

func _on_toggle_input(ev: InputEvent, i: int) -> void:
	if not _can_mouse():
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_set_mode(i)
