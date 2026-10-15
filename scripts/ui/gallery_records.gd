class_name GalleryRecords
extends Control
## Extras > RECORDS. Reads Records.load_all(): matches played, human wins, win rate, best combo, total damage, arcade clears, the
## per-mode match counts, the most-played and best-winning fighters on their portrait cards. Popups on BA's facet header with navy
## ribbon labels and D_Font numerals; flat gauges in BA's HP frame. With no data yet it shows Plana and the modes that count.
## `override` (set by the screen from params {"records": {...}}) replaces the saved file, for tests.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const PainterScript := preload("res://scripts/ui/painter.gd")
const PLANA := "UIs__00_Images__Image_Normal_Empty2"
const MODE_NAMES := {"versus2p": "Versus 2P", "versus-cpu": "Versus CPU", "training": "Training", "arcade": "Single Play"}
const COUNTED_MODES := ["Versus 2P", "Versus CPU", "Single Play"]     # a training match never finishes, so it never counts
const OVERVIEW := Rect2(24, 70, 560, 304)
const MODES := Rect2(24, 384, 560, 304)
const MOST := Rect2(600, 70, 656, 302)
const BEST := Rect2(600, 382, 656, 306)
const EMPTY := Rect2(170, 120, 940, 450)
const HEAD_H := 54.0
const CELL := Vector2(268, 78)
const RIBBON := Vector2(190, 24)
const STAT_H := 34.0
const NAME_PX := 36

var override: Dictionary = {}
var active := false
var _t := 0.0
var _first := true
var _m: Dictionary = {}
var _paint: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint = PainterScript.new().setup(Vector2(1280, 720), _draw_all)
	add_child(_paint)

# ── page API ─────────────────────────────────────────────────────────────────
func begin(first: bool) -> void:
	_t = 0.0
	_first = first
	_m = model(override if not override.is_empty() else Records.load_all(), Game.by_id)
	_paint.queue_redraw()

func set_active(b: bool) -> void:
	active = b
	visible = b
	set_process(b)

func set_page_focus(_b: bool) -> void:
	pass

func exit() -> void:
	pass

func handle(act: String) -> bool:
	return act != "up"

func probe() -> Dictionary:
	return {"empty": _m.get("empty", true), "matches": int(_m.get("matches", 0)), "human_wins": int(_m.get("wins", 0)),
			"best_combo": int(_m.get("best_combo", 0)), "fighters": int(_m.get("fighters", 0))}

# ── data ─────────────────────────────────────────────────────────────────────
## What the page shows, from a Records dictionary: the six totals, the mode counts (most played first, four at most) and the
## top three fighters by games and by win rate. `roster` maps roster id -> fighter; ids it lacks are skipped.
static func model(d: Dictionary, roster: Dictionary) -> Dictionary:
	var matches := int(d.get("matches", 0))
	var wins := int(d.get("human_wins", 0))
	var m := {"empty": matches <= 0, "matches": matches, "wins": wins, "losses": maxi(matches - wins, 0),
			"rate": 100.0 * float(wins) / float(maxi(matches, 1)), "best_combo": int(d.get("best_combo", 0)),
			"damage": int(round(float(d.get("total_damage", 0.0)))), "clears": int(d.get("arcade_clears", 0))}
	m["per_match"] = int(round(float(m["damage"]) / float(maxi(matches, 1))))
	var modes: Dictionary = d.get("by_mode", {})
	var list := []
	for k in modes:
		list.append([String(k), int(modes[k])])
	list.sort_custom(func(a, b): return a[1] > b[1])
	m["modes"] = list.slice(0, 4)
	m["mode_total"] = maxi(list.reduce(func(a, b): return a + int(b[1]), 0), 1)
	var rows := []
	var pf: Dictionary = d.get("per_fighter", {})
	for k in pf:
		var id := int(k)
		if not roster.has(id):
			continue
		var w := int(pf[k].get("wins", 0))
		var l := int(pf[k].get("losses", 0))
		if w + l > 0:
			rows.append({"id": id, "wins": w, "losses": l, "games": w + l, "rate": float(w) / float(w + l)})
	m["fighters"] = rows.size()
	var most := rows.duplicate()
	most.sort_custom(func(a, b): return a["games"] > b["games"] or (a["games"] == b["games"] and (a["wins"] > b["wins"] or (a["wins"] == b["wins"] and a["id"] < b["id"]))))
	var best := rows.duplicate()
	best.sort_custom(func(a, b): return a["rate"] > b["rate"] or (a["rate"] == b["rate"] and (a["wins"] > b["wins"] or (a["wins"] == b["wins"] and a["id"] < b["id"]))))
	m["most"] = most.slice(0, 3)
	m["best"] = best.slice(0, 3)
	return m

# ── frame ────────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_t += delta
	if _t < 2.2:
		_paint.queue_redraw()

## Entrance of panel i: slides in along `dir` (0 up from below, 1 in from the right), the second one a beat later.
func _enter(i: int, dir: int) -> Vector2:
	var k := Motion.whip(_t - (0.05 if _first else 0.0) - Motion.stagger(i * 4), 0.15, 0.3)
	return Vector2((1.0 - k) * 520.0, 0.0) if dir == 1 else Vector2(0.0, (1.0 - k) * 140.0)

func _count() -> float:
	return Motion.whip(_t - 0.45, 0.3, 0.7, 0.8)

# ── drawing ──────────────────────────────────────────────────────────────────
func _draw_all(c: Control) -> void:
	if _m.is_empty():
		return
	if _m["empty"]:
		_draw_empty(c)
		return
	_draw_overview(c, OVERVIEW.position + _enter(0, 0))
	_draw_modes(c, MODES.position + _enter(1, 0))
	_draw_fighters(c, MOST.position + _enter(2, 1), MOST.size, "MOST PLAYED", _m["most"], false)
	_draw_fighters(c, BEST.position + _enter(3, 1), BEST.size, "BEST RECORD", _m["best"], true)

## One stat: a navy ribbon label and the value in D_Font numerals under it, shrunk until it fits the cell.
func _stat(c: Control, at: Vector2, label: String, value: String, tail := "") -> void:
	GalleryKit.ribbon_left(c, Rect2(at, RIBBON), label, Color.WHITE, 12)
	var room := CELL.x - 30.0 - (Menu.text_width(tail, 14, 800) + 8.0 if tail != "" else 0.0)
	var h := GalleryKit.fit_number(value, STAT_H, room, BaNumerals.Tier.MINI, 16.0)
	var w := GalleryKit.draw_number(c, value, at + Vector2(10.0, 32.0 + (STAT_H - h) * 0.5), h, BaNumerals.Tier.MINI, Color.WHITE)
	if tail != "":
		Menu.label(c, tail, at + Vector2(10.0 + w + 8.0, 32.0 + STAT_H - 4.0), 14, BaTokens.INK, Color(0, 0, 0, 0), 0, 0, 800)

func _draw_overview(c: Control, p: Vector2) -> void:
	GalleryKit.popup(c, Rect2(p, OVERVIEW.size), HEAD_H)
	Menu.label(c, "OVERVIEW", p + Vector2(28.0, 40.0), 32, BaTokens.INK, Color.WHITE, 2, 0, 800)
	var e := _count()
	var cells := [
		["MATCHES PLAYED", GalleryKit.group(int(round(float(_m["matches"]) * e))), ""],
		["HUMAN WINS", GalleryKit.group(int(round(float(_m["wins"]) * e))), ""],
		["WIN RATE", "%d%%" % int(round(float(_m["rate"]) * e)), ""],
		["BEST COMBO", GalleryKit.group(int(round(float(_m["best_combo"]) * e))), "HITS"],
		["TOTAL DAMAGE", GalleryKit.group(int(round(float(_m["damage"]) * e))), ""],
		["ARCADE CLEARS", GalleryKit.group(int(round(float(_m["clears"]) * e))), ""],
	]
	for i in 6:
		var at := p + Vector2(24.0 + float(i % 2) * CELL.x, HEAD_H + 16.0 + float(i / 2) * CELL.y)
		_stat(c, at, cells[i][0], cells[i][1], cells[i][2])
		if i < 4:
			GalleryKit.draw_dots(c, at.x, at.x + CELL.x - 24.0, at.y + CELL.y - 12.0)

func _draw_modes(c: Control, p: Vector2) -> void:
	GalleryKit.popup(c, Rect2(p, MODES.size), HEAD_H)
	Menu.label(c, "MATCHES BY MODE", p + Vector2(28.0, 40.0), 28, BaTokens.INK, Color.WHITE, 2, 0, 800)
	var e := _count()
	var modes: Array = _m["modes"]
	var top := 0
	for i in modes.size():
		var k: String = modes[i][0]
		var n: int = modes[i][1]
		var y := p.y + HEAD_H + 12.0 + float(i) * 32.0
		Menu.label(c, String(MODE_NAMES.get(k, k.capitalize())), Vector2(p.x + 28.0, y + 18.0), 17, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)
		var most := maxi(int(modes[0][1]), 1)
		GalleryKit.draw_gauge(c, Rect2(p.x + 190.0, y + 2.0, 170.0, 20.0), float(n) / float(most) * e, BaTokens.COST)
		var count := GalleryKit.group(int(round(float(n) * e)))
		var ch := GalleryKit.fit_number(count, 22.0, 110.0, BaNumerals.Tier.MINI, 12.0)
		GalleryKit.draw_number(c, count, Vector2(p.x + 478.0, y + 1.0 + (22.0 - ch) * 0.5), ch, BaNumerals.Tier.MINI, Color.WHITE, 2)
		Menu.label(c, "%d%%" % int(round(100.0 * float(n) / float(_m["mode_total"]))), Vector2(p.x + 532.0, y + 18.0), 13, Color(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 2, 700)
		top = i + 1
	var sy := p.y + HEAD_H + 12.0 + float(maxi(top, 1)) * 32.0 + 6.0
	GalleryKit.draw_dots(c, p.x + 24.0, p.x + MODES.size.x - 24.0, sy)
	Menu.label(c, "WIN / LOSS", Vector2(p.x + 28.0, sy + 32.0), 14, BaTokens.INK, Color(0, 0, 0, 0), 0, 0, 800)
	var won := int(_m["wins"])
	var lost := int(_m["losses"])
	var gr := Rect2(p.x + 190.0, sy + 14.0, 330.0, 24.0)
	GalleryKit.draw_gauge(c, gr, float(won) / float(maxi(won + lost, 1)) * e, BaTokens.COST, BaTokens.P1)
	Menu.label(c, "%s won" % GalleryKit.group(won), Vector2(gr.position.x + 12.0, gr.get_center().y + 4.6), 12, Color.WHITE, BaTokens.HEAD_OUTLINE, 3, 0, 800)
	Menu.label(c, "%s lost" % GalleryKit.group(lost), Vector2(gr.end.x - 12.0, gr.get_center().y + 4.6), 12, Color.WHITE, BaTokens.HEAD_OUTLINE, 3, 2, 800)
	Menu.label(c, "DAMAGE / MATCH", Vector2(p.x + 28.0, sy + 72.0), 14, BaTokens.INK, Color(0, 0, 0, 0), 0, 0, 800)
	var per := GalleryKit.group(int(round(float(_m["per_match"]) * e)))
	var ph := GalleryKit.fit_number(per, 26.0, 330.0, BaNumerals.Tier.MINI, 14.0)
	GalleryKit.draw_number(c, per, Vector2(p.x + 190.0, sy + 50.0 + (26.0 - ph) * 0.5), ph, BaNumerals.Tier.MINI, Color.WHITE)

func _draw_fighters(c: Control, p: Vector2, size: Vector2, title: String, rows: Array, rate: bool) -> void:
	GalleryKit.popup(c, Rect2(p, size), HEAD_H)
	Menu.label(c, title, p + Vector2(28.0, 40.0), 28, BaTokens.INK, Color.WHITE, 2, 0, 800)
	if rows.is_empty():
		Menu.label(c, "Nothing yet", p + Vector2(28.0, HEAD_H + 40.0), 18, Color(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 0, 700)
		return
	var most := 1
	for r in rows:
		most = maxi(most, int(r["games"]))
	var e := _count()
	var row_h := (size.y - HEAD_H - 14.0) / 3.0
	for i in rows.size():
		var r: Dictionary = rows[i]
		var s: Dictionary = Game.by_id[int(r["id"])]
		var y := p.y + HEAD_H + 8.0 + float(i) * row_h
		var disc := Rect2(p.x + 20.0, y + (row_h - 34.0) * 0.5, 34.0, 34.0)
		BaArt.blit(c, "Combat__Combat_CardBg_EX_CostTag", disc)
		GalleryKit.draw_number(c, str(i + 1), Vector2(disc.get_center().x, disc.get_center().y - 8.0), 16.0, BaNumerals.Tier.WHITE, Color.WHITE, 1)
		var tile := Vector2(84.0, 74.0)
		var tp := Vector2(p.x + 66.0, y + (row_h - tile.y) * 0.5)
		GalleryKit.draw_tile(c, tile, s, 1.0, tp)
		var nx := tp.x + tile.x + 14.0
		var room := size.x - (nx - p.x) - 200.0
		GalleryKit.draw_name(c, Fighters.display_name(s).to_upper(), Vector2(nx, y + row_h * 0.5 + 2.0), NAME_PX, room, BaTokens.INK, Color.WHITE, 4)
		var sub := "%s match%s  ·  %s W  %s L" % [GalleryKit.group(r["games"]), "" if r["games"] == 1 else "es", GalleryKit.group(r["wins"]), GalleryKit.group(r["losses"])]
		Menu.label(c, Menu.clip(sub, 13, room, 700), Vector2(nx + 1.0, y + row_h * 0.5 + 22.0), 13, Color(BaTokens.INK, 0.85), Color(0, 0, 0, 0), 0, 0, 700)
		var frac := float(r["rate"]) if rate else float(r["games"]) / float(most)
		var text := "%d%%" % int(round(100.0 * float(r["rate"]) * e)) if rate else GalleryKit.group(int(round(float(r["games"]) * e)))
		var gx := p.x + size.x - 24.0 - 150.0
		var nh := GalleryKit.fit_number(text, 26.0, 150.0, BaNumerals.Tier.MINI, 14.0)
		GalleryKit.draw_number(c, text, Vector2(gx + 150.0, y + row_h * 0.5 - 28.0 + (26.0 - nh) * 0.5), nh, BaNumerals.Tier.MINI, Color.WHITE, 2)
		GalleryKit.draw_gauge(c, Rect2(gx, y + row_h * 0.5 + 8.0, 150.0, 18.0), frac * e, BaTokens.COST)

func _draw_empty(c: Control) -> void:
	var p := EMPTY.position + _enter(0, 0)
	GalleryKit.popup(c, Rect2(p, EMPTY.size), HEAD_H)
	Menu.label(c, "NO BATTLES ON RECORD YET", p + Vector2(28.0, 40.0), 32, BaTokens.INK, Color.WHITE, 2, 0, 800)
	var card := Rect2(p + Vector2(44.0, 150.0), Vector2(340.0, 279.0))
	GalleryKit.blit(c, GalleryKit.art(GalleryKit.CARD), card, BaTokens.SKY_BOT.lerp(Color.WHITE, 0.3))
	var art := GalleryKit.art(PLANA)
	if art != null:
		c.draw_texture_rect_region(art, Rect2(card.position + Vector2(10.0, -70.0), Vector2(324.0, 340.0)), Rect2(280, 130, 590, 620))
	var x := p.x + 424.0
	GalleryKit.draw_row_title(c, Vector2(x, p.y + 122.0), 460.0, "WHAT COUNTS")
	var f := UI.font_ui(600)
	var y := p.y + 170.0
	for line in GalleryKit.wrap_text("Finish a match in any of these modes and your results show up on this page.", 600, 19, 450.0):
		c.draw_string(f, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, 460.0, 19, Color(BaTokens.INK, 0.92))
		y += 27.0
	for i in COUNTED_MODES.size():
		var r := Rect2(x + float(i % 2) * 232.0, y + 24.0 + float(i / 2) * 50.0, 210.0, 36.0)
		GalleryKit.plate(c, r)
		Menu.label(c, COUNTED_MODES[i], Vector2(r.get_center().x, r.get_center().y + 6.0), 17, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 1, 800)
