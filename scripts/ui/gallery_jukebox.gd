class_name GalleryJukebox
extends Control
## Extras > JUKEBOX. A player box on top and the track strip under it, scrolling left and right.
## The box shows the selected track: its album cover, composer and album, the playback position, and the transport row (shuffle,
## previous, play / pause, next, repeat all / one). The strip lists AUTO plus every real Blue Archive OST track Bgm knows
## (Bgm.tracks(), credits in assets/audio/bgm/TRACKS.md) as cards with their album cover. Covers and the track to album map are in
## assets/ba/jukebox (tools/jukebox_assets.py).
## Confirm on a card plays it by setting Game.session.bgm (the Bgm autoload follows it and crossfades); the Extras screen restores
## "auto" on exit. Up from the strip goes to the transport row, up again to the tabs. Shuffle and repeat live on the session and are
## saved with the other settings; Bgm does the stepping (step, neighbour) and the hand over at the end of a track on repeat all.

const Menu := preload("res://scripts/ui/ba_menu.gd")
const PainterScript := preload("res://scripts/ui/painter.gd")
const DIR := "res://assets/ba/jukebox/"

signal wants_focus

const PLAYER := Rect2(24, 66, 1232, 372)
const HEAD_H := 54.0
const STRIP := Rect2(24, 446, 1232, 236)
const COVER := Rect2(30, 72, 236, 236)       # in the player's own pixels, like everything below down to BTN_*
const INFO_X := 304.0
const INFO_W := 896.0
const GAUGE := Rect2(304, 246, 896, 22)
const BTN_Y := 306.0                          # the centre line of the transport row
const BTN_SMALL := Vector2(88, 52)
const BTN_PLAY := Vector2(120, 60)
const BTN_GAP := 24.0
const KEYS := ["shuffle", "prev", "play", "next", "repeat"]
const CARD := Vector2(176, 218)
const PITCH := 190.0
const CARD_X0 := 12.0
const CARD_Y := 6.0
const VISIBLE := 6                          # cards that fit completely; a seventh peeks in
const AUTO := {"id": "auto", "name": "Auto", "role": "Default"}

static var _albums := {}
static var _covers := {}

var active := false
var _t := 0.0
var _first := true
var _page_focus := true
var _zone := "strip"                        # "strip" | "ctl"
var _ctl := 2                               # focused transport button
var _cursor := 0
var _items: Array = []                      # AUTO + Bgm.tracks()
var _cards: Array = []                      # {node, home, sc, bump}
var _strip: Control
var _edge: Control
var _scroll := 0.0
var _scroll_to := 0.0
var _panel: Control
var _live := false
var _pos := 0.0
var _len := 1.0
var _shown_id := Bgm.MAIN_THEME
var _last_play_row := 0
var _pop := 1.0
var _btns: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items = [AUTO]
	for trk in Bgm.tracks():
		_items.append(trk)
	_build()
	_cursor = _playing_row()
	_last_play_row = _cursor
	_scroll_to = _wanted_scroll()
	_scroll = _scroll_to
	_cursor_changed(false)

# data
## assets/ba/jukebox/albums.json: {albums: {id: {name, subtitle, cover}}, tracks: {track id: album id or null}}.
static func albums() -> Dictionary:
	if _albums.is_empty():
		_albums = JSON.parse_string(FileAccess.get_file_as_string(DIR + "albums.json"))
	return _albums

## The album of a track: {name, subtitle, cover}; the generic soundtrack card for a track on no listed volume or an unknown id.
static func album_of(track_id: String) -> Dictionary:
	var a: Dictionary = albums()
	var id: Variant = a["tracks"].get(track_id, null)
	return a["albums"][id] if id != null and a["albums"].has(id) else a["albums"]["generic"]

static func cover_of(track_id: String) -> Texture2D:
	var file: String = album_of(track_id)["cover"]
	if not _covers.has(file):
		_covers[file] = load(DIR + file)
	return _covers[file]

static func fmt_time(sec: float) -> String:
	var s := maxi(int(sec), 0)
	return "%d:%02d" % [floori(float(s) / 60.0), s % 60]

## Share of the track played, 0 when it is not the one that is playing.
static func progress(pos: float, length: float, live: bool) -> float:
	return clampf(pos / maxf(length, 0.001), 0.0, 1.0) if live else 0.0

## First card of the visible window that keeps `cursor` in view, starting from `scroll` (cards, not px).
static func window_for(cursor: int, scroll: float, cards: int) -> float:
	var s := scroll
	if float(cursor) < s:
		s = float(cursor)
	elif float(cursor) > s + float(VISIBLE - 1):
		s = float(cursor - VISIBLE + 1)
	return clampf(s, 0.0, float(maxi(cards - VISIBLE, 0)))

## The number disc on a card, in the card's own pixels (it pokes 12 px out over the cover's corner).
static func disc_rect() -> Rect2:
	return Rect2(Vector2(6.0 + 14.0 - 12.0, 4.0 + 14.0 - 12.0), Vector2(38.0, 38.0))

## Where the transport row's button i sits, in the player's own pixels.
static func button_rect(i: int) -> Rect2:
	var total := BTN_SMALL.x * 4.0 + BTN_PLAY.x + BTN_GAP * 4.0
	var x := INFO_X + INFO_W * 0.5 - total * 0.5
	for k in i:
		x += (BTN_PLAY.x if k == 2 else BTN_SMALL.x) + BTN_GAP
	var sz := BTN_PLAY if i == 2 else BTN_SMALL
	return Rect2(Vector2(x, BTN_Y - sz.y * 0.5), sz)

func _playing_id() -> String:
	var b := String(Game.session.bgm)
	return "auto" if b == "auto" or not Bgm.has_track(b) else b

func _playing_row() -> int:
	var id := _playing_id()
	for i in _items.size():
		if _items[i]["id"] == id:
			return i
	return 0

## The track whose data the box shows for a card (AUTO shows whatever Auto is playing right now).
func _track_data_id(row: int) -> String:
	var id: String = _items[row]["id"]
	if id != "auto":
		return id
	return Bgm.current if Bgm.has_track(Bgm.current) else Bgm.MAIN_THEME

func _wanted_scroll() -> float:
	return window_for(_cursor, _scroll_to, _items.size())

# construction
func _build() -> void:
	_strip = Control.new()
	_strip.position = STRIP.position
	_strip.size = STRIP.size
	_strip.clip_contents = true
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	for i in _items.size():
		var h := _Card.new()
		h.page = self
		h.index = i
		h.size = CARD
		h.position = Vector2(CARD_X0 + float(i) * PITCH, CARD_Y)
		h.pivot_offset = CARD * 0.5
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.gui_input.connect(_on_card_input.bind(i))
		_strip.add_child(h)
		_cards.append({"node": h, "home": h.position, "sc": 1.0, "bump": 0.0})
	_edge = PainterScript.new().setup(STRIP.size, _draw_edges)
	_edge.position = STRIP.position
	add_child(_edge)
	_panel = PainterScript.new().setup(PLAYER.size, _draw_panel)
	_panel.position = PLAYER.position
	add_child(_panel)
	for i in KEYS.size():
		var b := Control.new()
		var r := button_rect(i)
		b.position = r.position
		b.size = r.size
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.gui_input.connect(_on_button_input.bind(i))
		_panel.add_child(b)
		_btns.append(b)

# page API
func begin(first: bool) -> void:
	_t = 0.0
	_first = first
	_pop = 0.0
	if first:
		_cursor = _playing_row()
		_last_play_row = _cursor
		_scroll_to = _wanted_scroll()
		_scroll = _scroll_to
	_cursor_changed(false)

func set_active(b: bool) -> void:
	active = b
	visible = b
	set_process(b)
	for c in _cards:
		(c["node"] as Control).mouse_filter = Control.MOUSE_FILTER_STOP if b else Control.MOUSE_FILTER_IGNORE
	for bt in _btns:
		(bt as Control).mouse_filter = Control.MOUSE_FILTER_STOP if b else Control.MOUSE_FILTER_IGNORE

func set_page_focus(b: bool) -> void:
	_page_focus = b

func exit() -> void:
	Bgm.set_paused(false)

func handle(act: String) -> bool:
	if act == "aux":
		_play_pause()
		return true
	if _zone == "strip":
		match act:
			"left": _move(_cursor - 1)
			"right": _move(_cursor + 1)
			"confirm": _play(_cursor)
			"up": _set_zone("ctl")
	else:
		match act:
			"left": _focus_button(_ctl - 1)
			"right": _focus_button(_ctl + 1)
			"confirm": _press(KEYS[_ctl])
			"down": _set_zone("strip")
			"up": return false
	return true

func probe() -> Dictionary:
	var shown := _track_data_id(_cursor)
	var alb := album_of(shown)
	return {"cursor": _items[_cursor]["id"], "playing": _playing_id(), "bgm": Game.session.bgm, "paused": Bgm.paused,
			"shuffle": Game.session.jukebox_shuffle, "repeat": Game.session.jukebox_repeat, "zone": _zone, "ctl": KEYS[_ctl],
			"bgm_current": Bgm.current, "live": _live, "pos": snappedf(_pos, 0.01), "len": snappedf(_len, 0.01),
			"scroll": snappedf(_scroll_to, 0.1), "cards": _items.size(), "title": String(_items[_cursor]["name"]).to_upper(),
			"composer": String(Bgm.track(shown).get("composer", "")), "album": String(alb["name"]), "subtitle": String(alb["subtitle"]), "cover": String(alb["cover"])}

# actions
func _move(i: int) -> void:
	i = clampi(i, 0, _items.size() - 1)
	if i == _cursor:
		return
	_cursor = i
	_scroll_to = _wanted_scroll()
	Sfx.play("tick")
	_cursor_changed(true)

func _set_zone(z: String) -> void:
	if z == _zone:
		return
	_zone = z
	Sfx.play("tick", 0.9 if z == "ctl" else 1.1, 0.7)

func _focus_button(i: int) -> void:
	i = clampi(i, 0, KEYS.size() - 1)
	if i != _ctl:
		_ctl = i
		Sfx.play("tick")

func _press(key: String) -> void:
	match key:
		"shuffle":
			Game.session.jukebox_shuffle = not Game.session.jukebox_shuffle
			Sfx.play("tick", 1.2 if Game.session.jukebox_shuffle else 0.9, 0.8)
		"repeat":
			Game.session.jukebox_repeat = "all" if Game.session.jukebox_repeat == "one" else "one"
			Sfx.play("tick", 1.2 if Game.session.jukebox_repeat == "all" else 0.9, 0.8)
		"prev":
			Bgm.step(-1)
			_follow_playing()
		"next":
			Bgm.step(1)
			_follow_playing()
		"play":
			_play_pause()
	_panel.queue_redraw()

## The cursor goes to the track that plays now (after Next or Previous).
func _follow_playing() -> void:
	Sfx.play("tick", 1.1, 0.8)
	_cursor = _playing_row()
	_last_play_row = _cursor
	_scroll_to = _wanted_scroll()
	_cursor_changed(true)

func _play_pause() -> void:
	if _cursor != _playing_row():
		_play(_cursor)
	elif Bgm.paused:
		Bgm.set_paused(false)
		Sfx.play("tick", 1.2, 0.8)
	elif Bgm.is_playing():
		Bgm.set_paused(true)
		Sfx.play("tick", 0.8, 0.8)
	else:
		_play(_cursor)

func _cursor_changed(animate: bool) -> void:
	_shown_id = _track_data_id(_cursor)
	_len = maxf(Bgm.length_of(_shown_id), 1.0)
	if animate:
		_pop = 0.0
	for c in _cards:
		(c["node"] as Control).queue_redraw()
	_panel.queue_redraw()

func _play(row: int) -> void:
	var id: String = _items[row]["id"]
	Sfx.play("confirm")
	_cards[row]["bump"] = 1.0
	Game.session.bgm = id
	Bgm.set_paused(false)
	_last_play_row = _playing_row()
	_cursor_changed(false)

# frame
func _process(delta: float) -> void:
	_t += delta
	if _items[_cursor]["id"] == "auto" and _track_data_id(_cursor) != _shown_id:
		_cursor_changed(false)
	var pr := _playing_row()
	if pr != _last_play_row:   # the music moved on by itself (repeat all): the cursor goes with it if it was on the old track
		if _cursor == _last_play_row:
			_cursor = pr
			_scroll_to = _wanted_scroll()
			_cursor_changed(true)
		_last_play_row = pr
	_scroll = lerpf(_scroll, _scroll_to, 1.0 - exp(-delta * 14.0))
	if absf(_scroll - _scroll_to) < 0.002:
		_scroll = _scroll_to
	for i in _cards.size():
		var r: Dictionary = _cards[i]
		var h: _Card = r["node"]
		var ct := _t - (0.1 if _first else 0.0) - Motion.stagger(mini(i, 8), 0.03)
		h.visible = ct > 0.0
		var e := Motion.whip(ct, 0.12, 0.25)
		r["bump"] = move_toward(float(r["bump"]), 0.0, delta * 3.0)
		var sel := i == _cursor
		var sc: float = lerpf(float(r["sc"]), 1.05 if sel else 1.0, 1.0 - exp(-delta * 16.0))
		r["sc"] = sc
		h.position = (r["home"] as Vector2) + Vector2(-_scroll * PITCH, (1.0 - e) * 90.0)
		h.scale = Vector2.ONE * sc * (1.0 + sin(float(r["bump"]) * PI) * 0.05)
		h.z_index = 2 if sel else 0
		var want := 1.0 if (sel or not _page_focus or _zone == "ctl") else GalleryKit.DIM
		var changed := absf(want - h.dim) > 0.002 or sel != h.sel or (i == pr) != h.playing or Bgm.paused != h.paused
		h.dim = lerpf(h.dim, want, 1.0 - exp(-delta * 14.0))
		h.sel = sel
		h.playing = i == pr and Bgm.is_playing()
		h.paused = Bgm.paused
		h.t += delta
		if changed or sel:
			h.queue_redraw()
	_edge.queue_redraw()
	_pop = minf(_pop + delta / 0.3, 1.0)
	_panel.position = PLAYER.position + Vector2(0.0, (1.0 - Motion.whip(_t - (0.1 if _first else 0.0), 0.15, 0.3)) * -120.0)
	_update_music()
	_panel.queue_redraw()

func _update_music() -> void:
	var cur_id: String = _items[_cursor]["id"]
	_live = _cursor == _playing_row() and Bgm.is_playing() and (cur_id == "auto" or Bgm.current == cur_id)
	_pos = Bgm.position() if _live else 0.0
	_len = maxf(Bgm.length() if _live else Bgm.length_of(_shown_id), 1.0)

# drawing
## Chevrons at the strip's ends when more cards lie beyond them.
func _draw_edges(c: Control) -> void:
	var more_l := _scroll > 0.05
	var more_r := _scroll < float(_items.size() - VISIBLE) - 0.05
	var my := CARD_Y + CARD.y * 0.5
	for side in 2:
		if (side == 0 and not more_l) or (side == 1 and not more_r):
			continue
		var x := 8.0 if side == 0 else STRIP.size.x - 8.0
		var d := 1.0 if side == 0 else -1.0
		var pts := PackedVector2Array([Vector2(x, my), Vector2(x + 16.0 * d, my - 22.0), Vector2(x + 16.0 * d, my + 22.0)])
		c.draw_colored_polygon(pts, Color(BaTokens.NAVY, 0.85))
		c.draw_polyline(PackedVector2Array([pts[1], pts[0], pts[2]]), Color.WHITE, 2.0, true)

func _draw_panel(c: Control) -> void:
	var w := PLAYER.size.x
	var it: Dictionary = _items[_cursor]
	GalleryKit.popup(c, Rect2(Vector2.ZERO, PLAYER.size), HEAD_H)
	var title := String(it["name"])
	var ts := Menu.fit(title, 34, w - 250.0, 18, 800)
	Menu.label(c, Menu.clip(title, ts, w - 250.0, 800), Vector2(28.0 + (1.0 - Motion.whip(_pop * 0.3, 0.1, 0.2)) * 24.0, 40.0), ts, BaTokens.INK, Color.WHITE, 2, 0, 800)
	Menu.ribbon(c, Rect2(w - 24.0 - 150.0, 14.0, 150.0, 26.0), String(it["role"]).to_upper())
	_draw_cover(c)
	var trk := Bgm.track(_shown_id)
	var alb := album_of(_shown_id)
	_draw_pair(c, 80.0, "COMPOSER", String(trk.get("composer", "")), 30)
	_draw_pair(c, 140.0, "ALBUM", String(alb["name"]), 24)
	if String(alb["subtitle"]) != "":
		Menu.label(c, Menu.clip(String(alb["subtitle"]), 17, INFO_W, 700), Vector2(INFO_X, 192.0), 17, Color(BaTokens.INK, 0.85), Color(0, 0, 0, 0), 0, 0, 700)
	if String(it["id"]) == "auto":
		Menu.label(c, "Auto plays the main theme in the menus and a battle track by stage in fights.", Vector2(INFO_X, 218.0), 15, Color(BaTokens.INK, 0.9), Color(0, 0, 0, 0), 0, 0, 700)
	_draw_progress(c)
	for i in KEYS.size():
		_draw_button(c, i)

func _draw_pair(c: Control, y: float, label: String, value: String, size: int) -> void:
	Menu.label(c, label, Vector2(INFO_X, y), 13, Color(BaTokens.INK, 0.75), Color(0, 0, 0, 0), 0, 0, 800)
	var s := Menu.fit(value, size, INFO_W, 14, 800)
	Menu.label(c, Menu.clip(value, s, INFO_W, 800), Vector2(INFO_X, y + float(size) + 4.0), s, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)

func _draw_cover(c: Control) -> void:
	var r := COVER
	c.draw_rect(Rect2(r.position + Vector2(5.0, 8.0), r.size), Color(BaTokens.NAVY, 0.28))
	c.draw_rect(r.grow(5.0), Color.WHITE)
	c.draw_texture_rect(cover_of(_shown_id), r, false, Color.WHITE)

func _draw_progress(c: Control) -> void:
	var frac := progress(_pos, _len, _live)
	var state := "NOT PLAYING"
	if _live:
		state = "PAUSED" if Bgm.paused else "NOW PLAYING"
	Menu.label(c, state, Vector2(GAUGE.position.x + 4.0, GAUGE.position.y - 10.0), 13, BaTokens.INK, Color(0, 0, 0, 0), 0, 0, 800)
	var stamp := "%s / %s" % [fmt_time(_pos if _live else 0.0), fmt_time(_len)]
	GalleryKit.draw_number(c, stamp, Vector2(GAUGE.end.x - 4.0, GAUGE.position.y - 28.0), 17.0, BaNumerals.Tier.WHITE, BaTokens.INK, 2)
	GalleryKit.draw_gauge(c, GAUGE, frac, BaTokens.COST)

## The caption under a transport button.
func button_caption(i: int) -> String:
	match KEYS[i]:
		"shuffle": return "SHUFFLE ON" if Game.session.jukebox_shuffle else "SHUFFLE OFF"
		"prev": return "PREVIOUS"
		"play": return "PAUSE" if (Bgm.is_playing() and not Bgm.paused and _cursor == _playing_row()) else "PLAY"
		"next": return "NEXT"
	return "REPEAT ALL" if Game.session.jukebox_repeat == "all" else "REPEAT ONE"

func _draw_button(c: Control, i: int) -> void:
	var r := button_rect(i)
	var key: String = KEYS[i]
	var on := (key == "shuffle" and Game.session.jukebox_shuffle) or (key == "repeat" and Game.session.jukebox_repeat == "all") or key == "play"
	var focused := _page_focus and _zone == "ctl" and _ctl == i
	Menu.nine(c, "Combat__Common_Btn_BG", r, Menu.K, BaTokens.CONFIRM if on else BaTokens.CYAN_PLATE, BaTokens.SHEAR)
	BaArt.blit(c, "Common__Common_Btn_Normal_Y_S_Pt" if on else "Common__Common_Btn_Normal_B_S_Pt", r.grow_individual(2.0, 1.0, 2.0, 0.0))
	var ink := BaTokens.CONFIRM_INK if on else Color.WHITE
	var ir := Rect2(r.get_center() - Vector2(18.0, 18.0), Vector2(36.0, 36.0))
	var kind := key
	if key == "play" and Bgm.is_playing() and not Bgm.paused and _cursor == _playing_row():
		kind = "pause"
	draw_icon(c, kind, ir, ink, key == "repeat" and Game.session.jukebox_repeat == "one")
	Menu.label(c, button_caption(i), Vector2(r.get_center().x, BTN_Y + BTN_PLAY.y * 0.5 + 20.0), 12, BaTokens.INK, Color(0, 0, 0, 0), 0, 1, 800)
	if focused:
		Menu.bracket(c, r.grow_individual(12.0, 6.0, 12.0, 6.0), Motion.pulse(_t))

## A transport icon in r: play, pause, prev, next, shuffle or repeat (one adds the 1 in the loop).
static func draw_icon(c: CanvasItem, kind: String, r: Rect2, col: Color, one := false) -> void:
	var p := func(x: float, y: float) -> Vector2: return r.position + Vector2(x * r.size.x, y * r.size.y)
	match kind:
		"play":
			c.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.12), p.call(0.3, 0.88), p.call(0.84, 0.5)]), col)
		"pause":
			c.draw_rect(Rect2(p.call(0.22, 0.14), Vector2(0.2, 0.72) * r.size), col)
			c.draw_rect(Rect2(p.call(0.58, 0.14), Vector2(0.2, 0.72) * r.size), col)
		"prev":
			c.draw_rect(Rect2(p.call(0.14, 0.16), Vector2(0.12, 0.68) * r.size), col)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.84, 0.14), p.call(0.84, 0.86), p.call(0.32, 0.5)]), col)
		"next":
			c.draw_rect(Rect2(p.call(0.74, 0.16), Vector2(0.12, 0.68) * r.size), col)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.16, 0.14), p.call(0.16, 0.86), p.call(0.68, 0.5)]), col)
		"shuffle":
			var w := 3.0
			c.draw_polyline(PackedVector2Array([p.call(0.06, 0.72), p.call(0.36, 0.72), p.call(0.58, 0.28), p.call(0.72, 0.28)]), col, w, true)
			c.draw_polyline(PackedVector2Array([p.call(0.06, 0.28), p.call(0.36, 0.28), p.call(0.58, 0.72), p.call(0.72, 0.72)]), col, w, true)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.7, 0.1), p.call(0.7, 0.46), p.call(0.96, 0.28)]), col)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.7, 0.54), p.call(0.7, 0.9), p.call(0.96, 0.72)]), col)
		"repeat":
			var w := 3.0
			c.draw_polyline(PackedVector2Array([p.call(0.08, 0.52), p.call(0.08, 0.36), p.call(0.2, 0.24), p.call(0.64, 0.24)]), col, w, true)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.62, 0.04), p.call(0.62, 0.44), p.call(0.92, 0.24)]), col)
			c.draw_polyline(PackedVector2Array([p.call(0.92, 0.48), p.call(0.92, 0.64), p.call(0.8, 0.76), p.call(0.36, 0.76)]), col, w, true)
			c.draw_colored_polygon(PackedVector2Array([p.call(0.38, 0.56), p.call(0.38, 0.96), p.call(0.08, 0.76)]), col)
			if one:
				Menu.label(c, "1", p.call(0.5, 0.64), 15, col, Color(0, 0, 0, 0), 0, 1, 800)

# mouse
func _can_mouse() -> bool:
	return active and not Game.busy and _t > 0.5

func _on_card_input(ev: InputEvent, i: int) -> void:
	if not _can_mouse():
		return
	if ev is InputEventMouseMotion:
		if (ev as InputEventMouseMotion).relative == Vector2.ZERO:
			return
		if i != _cursor or not _page_focus or _zone != "strip":
			wants_focus.emit()
			_zone = "strip"
			_move(i)
	elif ev is InputEventMouseButton and ev.pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			wants_focus.emit()
			_zone = "strip"
			_cursor = i
			_scroll_to = _wanted_scroll()
			_cursor_changed(false)
			_play(i)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move(_cursor - 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move(_cursor + 1)

func _on_button_input(ev: InputEvent, i: int) -> void:
	if not _can_mouse():
		return
	if ev is InputEventMouseMotion:
		if (ev as InputEventMouseMotion).relative != Vector2.ZERO and (_ctl != i or _zone != "ctl" or not _page_focus):
			wants_focus.emit()
			_zone = "ctl"
			_ctl = i
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		wants_focus.emit()
		_zone = "ctl"
		_ctl = i
		_press(KEYS[i])

# one card of the strip
class _Card extends Control:
	var page: GalleryJukebox
	var index := 0
	var sel := false
	var playing := false
	var paused := false
	var dim := 1.0
	var t := 0.0

	func _draw() -> void:
		var it: Dictionary = page._items[index]
		var mul := Color(dim, dim, dim, 1.0)
		var soft := Color.WHITE.lerp(mul, 0.33)
		var r := Rect2(Vector2(6.0, 4.0), size - Vector2(12.0, 8.0))
		GalleryKit.plate(self, r, BaTokens.CONFIRM_PLATE.lerp(Color.WHITE, 0.45) * soft if playing else soft)
		if sel and page._page_focus and page._zone == "strip":   # under the number disc and the cover, which poke over its edge
			GalleryKit.draw_bracket(self, Rect2(Vector2.ZERO, size).grow_individual(4.0, 0.0, 4.0, 0.0), Motion.pulse(t))
		var cv := Rect2(r.position + Vector2(14.0, 14.0), Vector2(r.size.x - 28.0, r.size.x - 28.0))
		var tid := String(it["id"])
		if tid == "auto":
			draw_texture_rect(GalleryJukebox.cover_of(Bgm.MAIN_THEME), cv, false, mul)
			GalleryKit.Menu.label(self, "AUTO", cv.get_center() + Vector2(0.0, 12.0), 40, Color.WHITE, BaTokens.HEAD_OUTLINE, 4, 1, 800)
		else:
			draw_texture_rect(GalleryJukebox.cover_of(tid), cv, false, mul)
		var disc := GalleryJukebox.disc_rect()
		BaArt.blit(self, "Combat__Combat_CardBg_EX_CostTag", disc, mul)
		if index == 0:
			GalleryKit.Menu.label(self, "A", Vector2(disc.get_center().x, disc.get_center().y + 7.0), 19, Color.WHITE, Color(0, 0, 0, 0), 0, 1, 800)
		else:
			GalleryKit.draw_number(self, "%02d" % index, Vector2(disc.get_center().x, disc.get_center().y - 8.0), 15.0, BaNumerals.Tier.WHITE, Color.WHITE, 1)
		var room := r.size.x - 44.0   # the plate leans: its right edge is further left down at the text
		var name := String(it["name"])
		var ts: int = GalleryKit.Menu.fit(name, 18, room, 12, 800)
		GalleryKit.Menu.label(self, GalleryKit.Menu.clip(name, ts, room, 800), Vector2(r.position.x + 12.0, cv.end.y + 28.0), ts, BaTokens.LABEL_INK, Color(0, 0, 0, 0), 0, 0, 800)
		var sub := "Menus and fights" if tid == "auto" else String(it["composer"])
		var ss: int = GalleryKit.Menu.fit(sub, 13, room, 10, 700)
		GalleryKit.Menu.label(self, GalleryKit.Menu.clip(sub, ss, room, 700), Vector2(r.position.x + 12.0, cv.end.y + 48.0), ss, Color(BaTokens.INK, 0.8), Color(0, 0, 0, 0), 0, 0, 700)
		if playing:
			GalleryKit.ribbon_left(self, Rect2(cv.position.x + 6.0, cv.end.y - 30.0, 92.0, 22.0), "PAUSED" if paused else "PLAYING", BaTokens.CONFIRM, 11)
