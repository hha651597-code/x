class_name SpriteHalo
extends Node2D
## The official halo, overlaid at runtime above each sprite frame's head (the frames themselves leave it out).
##
## Hi-res frames: the layers come from the Spine extraction (assets/ba/rig/<rig>/rig.json, group "halo": normal + additive
## glow layers), composed at their rig positions, scaled to `width` world px and flattened into a side-view ellipse. A soft
## additive glow sits behind; the halo floats with a slow bob / sway and trails the head a little when frames change.
##
## PIXEL ART (the set is pixel art and assets/ba/sprites/<char>/halo_rot.png or halo.png exists — made from the same official
## layers): the halo is a pixel sprite drawn with the frames' pixel rules — one art pixel =
## SpriteSet.art_px world px, nearest texels, position / bob snapped to whole art pixels (the actor's grid), never rotated
## at runtime: the tilt picks the nearest pre-rendered column of halo_rot.png (-90..+90 deg, 15 deg steps; beyond 90 deg the
## cell is turned 180 deg, which is exact on a pixel grid); rows A / B give a 2-frame shimmer; the glow is the frame
## shader's stepped 1-2 pixel ring (no smooth glow circles). Config keys "width" / "flatten" / sway are hi-res only.
##
## Config (anims.json "halo"): {"rig": "hoshino", "width": 54, "flatten": 0.62, "dx": -4, "dy": -16, "tilt": -6,
##   "bob": 2.0, "glow": 0.55, "glow_color": "#ffd7ef", "follow": 26,
##   "pixel_png": "halo_rot.png", "shimmer": 0.22}   (pixel_png: sheet or single halo PNG in the set folder; shimmer: share
##   of the time frame B shows)

const FRAME_SHADER := preload("res://scripts/sprites/sprite_frame.gdshader")
const SHEET_ANGLES := 13                # columns of halo_rot.png: -90 .. +90 deg in 15 deg steps

var cfg := {}
var flat: Node2D
var pixel := false                      # pixel-art halo (see above)
var art := 2.0                          # pixel mode: world px per art pixel
var _px_spr: Sprite2D
var _px_mat: ShaderMaterial
var _cell := 0                          # pixel mode: cell size (art px)
var _cols := 1
var _rows := 1
var _glow_col := Color(1.0, 0.9, 0.95)
var _glow_amt := 0.5
var _w := 54.0
var _t := 0.0
var _alpha := 1.0
var _goal_alpha := 1.0
var _target := Vector2.ZERO
var _target_rot := 0.0
var _pos := Vector2.ZERO                # pixel mode: un-snapped position (the node itself sits on the art-pixel grid)
var _snap := true
var _seed := 0.0
var fade := 1.0                       # extra multiplier (the actor fades the halo out on KO)

func setup(c: Dictionary, seed_ := 0.0, s: SpriteSet = null) -> void:
	cfg = c
	_seed = seed_
	_w = float(cfg.get("width", 54.0))
	_glow_amt = float(cfg.get("glow", 0.5))
	_glow_col = Color.from_string(String(cfg.get("glow_color", "#fff2fa")), Color(1.0, 0.95, 0.98))
	if s != null and s.pixel and _build_pixel(s):
		return
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add                         # the glow drawn by this node is additive; children keep their own blend
	flat = Node2D.new()
	flat.scale = Vector2(1.0, float(cfg.get("flatten", 0.62)))
	add_child(flat)
	_build_layers(String(cfg.get("rig", "")))

## Pixel halo from the set folder: cfg "pixel_png" (default halo_rot.png, then halo.png). False when there is none.
func _build_pixel(s: SpriteSet) -> bool:
	var names: Array = []
	if cfg.has("pixel_png") and cfg["pixel_png"] is String:
		names.append(String(cfg["pixel_png"]))
	names.append_array(["halo_rot.png", "halo.png"])
	var img: Image = null
	var file := ""
	for n in names:
		img = SpriteSet._load_image(s.dir + String(n))
		if img != null:
			file = String(n)
			break
	if img == null:
		return false
	pixel = true
	art = s.art_px
	# a sheet has 2 rows (A, B) of square cells; anything else is one upright cell
	var h := img.get_height()
	var half := int(float(h) * 0.5)
	if h % 2 == 0 and img.get_width() == half * SHEET_ANGLES:
		_cell = half
		_cols = SHEET_ANGLES
		_rows = 2
	else:
		_cell = 0
		_cols = 1
		_rows = 1
	var tex := ImageTexture.create_from_image(img)
	_px_spr = Sprite2D.new()
	_px_spr.name = "PixelHalo"
	_px_spr.texture = tex
	_px_spr.centered = false
	_px_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_px_spr.region_enabled = true
	var cw := _cell if _cell > 0 else img.get_width()
	var ch := _cell if _cell > 0 else img.get_height()
	_px_spr.region_rect = Rect2(0, 0, cw, ch)
	# whole-texel offset: the cell's centre pixel corner sits on the node (odd sizes round down, the grid is kept)
	_px_spr.offset = -Vector2(floorf(float(cw) * 0.5), floorf(float(ch) * 0.5))
	_px_spr.scale = Vector2(art, art)
	_px_mat = ShaderMaterial.new()
	_px_mat.shader = FRAME_SHADER
	_px_mat.set_shader_parameter("pixel_art", true)
	_px_mat.set_shader_parameter("outline_px", 0.0)
	_px_mat.set_shader_parameter("glow_color", _glow_col)
	_px_spr.material = _px_mat
	add_child(_px_spr)
	set_meta("pixel_png", file)
	return true

func _build_layers(rig_name: String) -> void:
	if rig_name == "":
		return
	var dir := "res://assets/ba/rig/" + rig_name + "/"
	if not FileAccess.file_exists(dir + "rig.json"):
		return
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(dir + "rig.json")) != OK or not (j.data is Dictionary):
		return
	var layers: Array = []
	var bb := Rect2()
	var first := true
	for l in ((j.data as Dictionary).get("layers", []) as Array):
		var L: Dictionary = l
		if String(L.get("group", "")) != "halo" and String(L.get("name", "")).find("halo") < 0:
			continue
		var r := _verts_rect(L.get("verts", []) as Array)
		if r.size.x <= 0.0:
			continue
		layers.append([L, r])
		bb = r if first else bb.merge(r)
		first = false
	if layers.is_empty():
		return
	var k := _w / maxf(bb.size.x, 1.0)
	var c := bb.get_center()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for pair in layers:
		var L2: Dictionary = pair[0]
		var r2: Rect2 = pair[1]
		var path := dir + String(L2.get("png", ""))
		if not ResourceLoader.exists(path):
			continue
		var tex := SpriteSet.mip(load(path) as Texture2D)
		if tex == null:
			continue
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sp.position = (r2.get_center() - c) * k
		sp.scale = Vector2(r2.size.x / float(tex.get_width()), r2.size.y / float(tex.get_height())) * k
		var col: Array = L2.get("color", [1, 1, 1, 1]) as Array
		if col.size() >= 4:
			sp.self_modulate = Color(float(col[0]), float(col[1]), float(col[2]), float(col[3]))
		if String(L2.get("blend", "normal")) == "additive":
			sp.material = add
		flat.add_child(sp)

static func _verts_rect(v: Array) -> Rect2:
	if v.is_empty():
		return Rect2()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in v:
		var q := Vector2(float(p[0]), float(p[1]))
		mn = mn.min(q)
		mx = mx.max(q)
	return Rect2(mn, mx - mn)

## Place the halo for this frame. `at` = head anchor in the actor's local space (world px, art facing right),
## `rot_deg` = per-frame tilt, `on` = shown on this frame. Call every render frame.
func track(at: Vector2, rot_deg: float, on: bool, delta: float) -> void:
	# the offset turns with the head (a lying student's halo floats beside her head, not above it)
	_target = at + Vector2(float(cfg.get("dx", 0.0)), float(cfg.get("dy", -14.0))).rotated(deg_to_rad(rot_deg))
	_target_rot = deg_to_rad(rot_deg + float(cfg.get("tilt", 0.0)))
	_goal_alpha = (1.0 if on else 0.0) * fade
	_t += delta
	var follow := float(cfg.get("follow", 26.0))
	var k := 1.0 if _snap else 1.0 - exp(-follow * delta)
	_snap = false
	var bob := float(cfg.get("bob", 2.0))
	var wave := 0.5 + 0.5 * sin(_t * 2.1 + _seed)
	_alpha = move_toward(_alpha, _goal_alpha, delta * (6.0 if _goal_alpha > _alpha else 3.0))
	modulate.a = _alpha
	visible = _alpha > 0.01
	if pixel:
		_track_pixel(k, bob, wave)
		return
	var goal := _target + Vector2(0.0, -bob * wave)
	position = position.lerp(goal, k)
	rotation = lerp_angle(rotation, _target_rot + deg_to_rad(2.5) * sin(_t * 1.3 + _seed), k)
	queue_redraw()

## Pixel halo: trails the head smoothly in _pos, but the node sits on whole art pixels; the bob is a 0/1-pixel step;
## the tilt selects a pre-rendered cell (no runtime rotation, no sway).
func _track_pixel(k: float, bob: float, wave: float) -> void:
	_pos = _target if k >= 1.0 else _pos.lerp(_target, k)
	var b := roundf(bob * wave / art) * art
	position = (_pos + Vector2(0.0, -b)).snapped(Vector2(art, art))
	rotation = 0.0
	var deg := wrapf(rad_to_deg(_target_rot), -180.0, 180.0)
	var turn := false
	if deg > 97.5:
		deg -= 180.0
		turn = true
	elif deg < -97.5:
		deg += 180.0
		turn = true
	var col := 0
	if _cols > 1:
		col = clampi(int(roundf((deg + 90.0) / (180.0 / float(_cols - 1)))), 0, _cols - 1)
	var row := 0
	if _rows > 1 and fposmod(_t * 1.1 + _seed * 0.37, 1.0) < float(cfg.get("shimmer", 0.22)):
		row = 1
	if _cell > 0:
		_px_spr.region_rect = Rect2(col * _cell, row * _cell, _cell, _cell)
	_px_spr.scale = Vector2(-art, -art) if turn else Vector2(art, art)
	# whole-texel offset: the cell centre stays on the node (also when turned 180 deg)
	var rr := _px_spr.region_rect.size
	_px_spr.offset = -Vector2(floorf(rr.x * 0.5), floorf(rr.y * 0.5))
	# stepped glow pulse: the shader's ring at strength 1/4, now and then 2/4 (for the config's "glow" 0.5)
	var pu := 1.0 if sin(_t * 2.4 + _seed) > 0.6 else 0.5
	_px_mat.set_shader_parameter("glow", clampf(_glow_amt * pu, 0.0, 1.0) * fade)

## Jump straight to the next target (new round / first frame) instead of floating there.
func snap() -> void:
	_snap = true

## Shader look of the pixel halo (dim during the EX freeze, the hit flash is the body's only).
func set_dim(d: float) -> void:
	if pixel:
		_px_mat.set_shader_parameter("dim", d)
	else:
		modulate = Color(d, d, d, modulate.a)

func _draw() -> void:
	if pixel:
		return
	# soft additive glow behind the rings (drawn by this node, children render on top)
	var pu := 0.85 + 0.15 * sin(_t * 3.0 + _seed)
	var fl := float(cfg.get("flatten", 0.62))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, fl))
	Fx.glow(self, Vector2.ZERO, _w * 0.62, Color(_glow_col.r, _glow_col.g, _glow_col.b, 0.35 * _glow_amt * pu))
	Fx.glow(self, Vector2.ZERO, _w * 0.95, Color(_glow_col.r, _glow_col.g, _glow_col.b, 0.16 * _glow_amt * pu))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
