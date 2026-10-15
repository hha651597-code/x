class_name VsLayout
extends RefCounted
## Where everything on the VS screen sits, in 1280x720 reference px, and how its text is fitted. Pure geometry: the screen draws
## from it and the tests measure the longest fighter, school, special and stage names against it.
## Side 0 is the left, side 1 the right; the right side mirrors positions and right-aligns its text, the lean is not mirrored.

const Menu := preload("res://scripts/ui/ba_menu.gd")

const W := 1280.0
const BAND := Rect2(0.0, 326.0, 1280.0, 150.0)
const VS_C := Vector2(640.0, 206.0)
const VS_W := 210.0
const PLATE := Rect2(46.0, 486.0, 366.0, 108.0)
const PLATE_PAD := 22.0
const NAME_MAX := 72
const NAME_MIN := 44
const SCHOOL_SIZE := 14
const SPECIAL_Y := 608.0
const SPECIAL_NAME_MAX := 230.0
const STAGE_Y := 642.0
const STAGE_MIN_W := 340.0
const STAGE_MAX_W := 520.0
const STAGE_THUMB := Vector2(96.0, 42.0)

# UIAni_StageStart, 60 fps: the band opens by scale-Y in 11 frames, the VS lettering stamps from 1.5x to 1.0x by 0.383 s (nothing
# overshoots) with alpha 0.02 to 1 in 0.05 s, the flare grows to 1.25x at 0.083 s and settles to 1.0x at 0.383 s.
const BAND_OPEN := 11.0 / 60.0
const STAMP := [[0.0, 1.5], [0.117, 1.099], [0.383, 1.0]]
const FLARE := [[0.0, 0.0], [0.083, 1.25], [0.383, 1.0]]
const DECO := [[0.0, 0.0], [0.117, 0.8], [0.383, 1.0]]

static func _keys(keys: Array, t: float) -> float:
	if t <= keys[0][0]:
		return keys[0][1]
	for n in range(1, keys.size()):
		if t <= keys[n][0]:
			var u: float = (t - keys[n - 1][0]) / (keys[n][0] - keys[n - 1][0])
			return lerpf(keys[n - 1][1], keys[n][1], u)
	return keys[keys.size() - 1][1]

## Band height factor 0..1 at t seconds.
static func band_k(t: float) -> float:
	var u := clampf(t / BAND_OPEN, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u)

## (scale, alpha) of a stamped word t seconds after it starts.
static func stamp(t: float) -> Vector2:
	return Vector2(_keys(STAMP, t), lerpf(0.02, 1.0, clampf(t / 0.05, 0.0, 1.0)) if t >= 0.0 else 0.0)

## Scale-Y of the two triangle decos.
static func deco_k(t: float) -> float:
	return _keys(DECO, t)

static func flare(t: float) -> float:
	return _keys(FLARE, t) if t >= 0.0 else 0.0

## x of a rect [x, x + w] drawn on side i.
static func mx(i: int, x: float, w: float) -> float:
	return x if i == 0 else W - x - w

static func mirror(i: int, r: Rect2) -> Rect2:
	return Rect2(mx(i, r.position.x, r.size.x), r.position.y, r.size.x, r.size.y)

## Name plate block of side i: {plate, bar, chip, crest, school_x, school_y, name_x, name_y, name_size, name_w, school_w, align}.
## crest is the crest's size on screen (CrestIcon.fit), ZERO for none.
static func block(i: int, school: String, fighter_name: String, crest_size: Vector2) -> Dictionary:
	var plate := mirror(i, PLATE)
	var inner := PLATE.size.x - 2.0 * PLATE_PAD
	var name_size := NAME_MAX
	var font := UI.font_name()
	while name_size > NAME_MIN and font.get_string_size(fighter_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > inner:
		name_size -= 2
	var name_w := font.get_string_size(fighter_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	var crest_w := crest_size.x + 8.0 if crest_size.x > 0.0 else 0.0
	var school_size := Menu.fit(school, SCHOOL_SIZE, inner - crest_w, 10, 800)
	var school_w := Menu.text_width(school, school_size, 800)
	var right := i == 1
	var left_edge := plate.position.x + PLATE_PAD
	var right_edge := plate.end.x - PLATE_PAD
	var out := {"plate": plate, "name_size": name_size, "name_w": name_w, "school_size": school_size, "school_w": school_w, "align": 2 if right else 0}
	out["crest"] = Rect2((right_edge - crest_size.x) if right else left_edge, plate.position.y + 8.0 + (22.0 - crest_size.y) * 0.5, crest_size.x, crest_size.y)
	out["school_x"] = (right_edge - crest_w) if right else (left_edge + crest_w)
	out["school_y"] = plate.position.y + 29.0
	out["name_x"] = right_edge if right else left_edge
	out["name_y"] = plate.position.y + 91.0
	var bar_w := 178.0
	out["bar"] = Rect2((plate.end.x - bar_w + 12.0) if right else plate.position.x - 12.0, plate.position.y - 28.0, bar_w, 42.0)
	out["chip"] = Rect2((plate.position.x - 8.0) if right else plate.end.x - 40.0, plate.position.y - 26.0, 46.0, 44.0)
	return out

## The special's card, ribbon and name plate on side i: {card, face, ribbon, plate, text_x, text_y, size, align}.
static func special(i: int, special_name: String) -> Dictionary:
	var right := i == 1
	var card := Rect2(mx(i, 50.0, 96.0), SPECIAL_Y + 8.0, 96.0, 79.0)
	var size := Menu.fit(special_name, 22, SPECIAL_NAME_MAX, 12, 800)
	var tw := Menu.text_width(special_name, size, 800)
	var pw := tw + 36.0
	var plate_x := (card.position.x - pw + 12.0) if right else card.end.x - 12.0
	var plate := Rect2(plate_x, SPECIAL_Y + 36.0, pw, 38.0)
	var rw := 86.0
	var ribbon := Rect2((card.position.x - rw + 22.0) if right else card.end.x - 22.0, SPECIAL_Y + 8.0, rw, 22.0)
	return {"card": card, "face": Rect2(card.position.x - 2.0, card.position.y - 10.0, 92.0, 72.8), "ribbon": ribbon, "plate": plate,
		"text_x": (plate.end.x - 18.0) if right else plate.position.x + 18.0, "text_y": plate.position.y + 23.0, "size": size, "text_w": tw,
		"align": 2 if right else 0}

## The stage plate, as wide as its text needs: {plate, thumb, has_thumb, name_x, name_y, name_size, name_w, school_x, school_y, school_size, school_w}.
static func stage(stage_name: String, school: String, has_thumb: bool) -> Dictionary:
	var lead := (24.0 + STAGE_THUMB.x + 16.0) if has_thumb else 34.0
	var avail := STAGE_MAX_W - lead - 34.0
	var size := Menu.fit(stage_name, 21, avail, 12, 800)
	var ssize := Menu.fit(school, 12, avail, 9, 700)
	var nw := Menu.text_width(stage_name, size, 800)
	var sw := Menu.text_width(school, ssize, 700)
	var w := clampf(lead + maxf(nw, sw) + 34.0, STAGE_MIN_W, STAGE_MAX_W)
	var plate := Rect2(VS_C.x - w * 0.5, STAGE_Y, w, 56.0)
	var left := plate.position.x + lead
	return {"plate": plate, "thumb": Rect2(plate.position.x + 24.0, plate.position.y + 5.0, STAGE_THUMB.x, STAGE_THUMB.y), "has_thumb": has_thumb,
		"name_x": left, "name_y": plate.position.y + 37.0, "name_size": size, "name_w": nw,
		"school_x": left, "school_y": plate.position.y + 17.0, "school_size": ssize, "school_w": sw, "avail": avail}
