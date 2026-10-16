extends Control
## Arena presentation behind the fighters: the stage plate (blurred, parallax), a full-screen grade (haze on the horizon,
## drifting light shafts, vignette), seeded drifting particles that suit the stage, and the glossy floor factory.
## Colours are sampled from the plate itself so every stage gets its own tinted floor.
## Built by FightScreen._build_stage; FightScreen._apply_camera calls update_camera().

const BACKDROP_SHADER := preload("res://shaders/backdrop.gdshader")
const GRADE_SHADER := preload("res://shaders/stage_grade.gdshader")
const FLOOR_SHADER := preload("res://shaders/stage_floor.gdshader")
const PainterScript := preload("res://scripts/ui/painter.gd")
const FEET_ROW := 612.0
const FLOOR_LIP := 24.0
const BLOB_RADIUS := 0.5
const BLOB_FADE := 1.4
const PLATE_MAX_ZOOM := 1.24

const KINDS := {"gehenna-night": "ember"}

var colors := {}
var plate: TextureRect
var grade: ColorRect
var motes: Control
var view: StageView
var _grade_mat: ShaderMaterial
var _t := 0.0
var _kind := "mote"
var _parts: Array = []
var _cam_x := 0.0
var _zoom := 1.0
var _horizon_y := 616.0
var _world: Node

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Builds plate + grade + particles for `stage` and returns the plate texture.
func build(stage: Dictionary) -> Texture2D:
	var plate_path: String = stage.get("plate", "")
	var tex: Texture2D = UI.tex(plate_path) if plate_path != "" else UI.tex("bg/BG_View_Kivotos.jpg")
	colors = sample_colors(tex)
	if stage.has("map"):
		_build_3d(stage)
		return tex
	plate = TextureRect.new()
	plate.name = "Plate"
	plate.texture = tex
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	plate.size = Vector2(1500, 860)
	plate.position = Vector2(-110, -70)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = BACKDROP_SHADER
	m.set_shader_parameter("radius", 0.0055)
	m.set_shader_parameter("tint_amount", 0.0)
	m.set_shader_parameter("brightness", 1.0)
	m.set_shader_parameter("saturation", 1.12)
	plate.material = m
	add_child(plate)
	grade = ColorRect.new()
	grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = GRADE_SHADER
	var avg: Color = colors["avg"]
	_grade_mat.set_shader_parameter("tint", avg)
	_grade_mat.set_shader_parameter("light_col", Color(1, 1, 1).lerp(_boost(avg, 1.2), 0.25))
	grade.material = _grade_mat
	add_child(grade)
	var sid: String = stage.get("id", "")
	_kind = KINDS.get(sid, "mote")
	_seed_particles(sid)
	motes = PainterScript.new().setup(Vector2(1280, 720), _draw_motes)
	add_child(motes)
	return tex

func _build_3d(stage: Dictionary) -> void:
	var dir := "res://assets/ba/stages/" + String(stage["map"])
	var times: Dictionary = StageLoader.read_json(dir + "/stage.json")["times"]
	view = StageView.new()
	add_child(view)
	view.load_stage(dir, times[stage.get("time", stage["times"][0])])
	set_process(false)

# colour sampling
static func _boost(c: Color, s: float) -> Color:
	return Color.from_hsv(c.h, clampf(c.s * s, 0.0, 1.0), c.v)

## Average / top / bottom colour of a plate (16x12 box average).
static func sample_colors(tex: Texture2D) -> Dictionary:
	var out := {"avg": Color(0.5, 0.7, 0.95), "top": Color(0.5, 0.7, 0.95), "bottom": Color(0.6, 0.75, 0.9)}
	if tex == null:
		return out
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return out
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.resize(16, 12, Image.INTERPOLATE_LANCZOS)
	var all := Color(0, 0, 0, 0)
	var top := Color(0, 0, 0, 0)
	var bot := Color(0, 0, 0, 0)
	var na := 0.0
	var nt := 0.0
	var nb := 0.0
	for y in 12:
		for x in 16:
			var px := img.get_pixel(x, y)
			all += px
			na += 1.0
			if y < 4:
				top += px
				nt += 1.0
			elif y >= 8:
				bot += px
				nb += 1.0
	out["avg"] = Color(all.r / na, all.g / na, all.b / na)
	out["top"] = Color(top.r / nt, top.g / nt, top.b / nt)
	out["bottom"] = Color(bot.r / nb, bot.g / nb, bot.b / nb)
	return out

# particles
func _seed_particles(sid: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sid) & 0x7fffffff
	_parts.clear()
	var n := 46 if _kind != "mist" else 14
	for i in n:
		_parts.append({
			"x": rng.randf_range(0.0, 1400.0), "y": rng.randf_range(0.0, 780.0),
			"s": rng.randf_range(0.6, 1.0), "v": rng.randf_range(0.6, 1.4),
			"ph": rng.randf_range(0.0, TAU), "amp": rng.randf_range(8.0, 36.0),
			"depth": rng.randf_range(0.25, 1.0), "f": rng.randf_range(0.4, 1.3),
		})

func _process(delta: float) -> void:
	_t += delta
	_grade_mat.set_shader_parameter("time", _t)
	motes.queue_redraw()

func _draw_motes(c: Control) -> void:
	var avg: Color = colors["avg"]
	for p in _parts:
		var depth: float = p["depth"]
		var sz: float = p["s"]
		var x := fposmod(float(p["x"]) + sin(_t * float(p["f"]) + float(p["ph"])) * float(p["amp"]) - _cam_x * depth * 0.55, 1400.0) - 60.0
		var y := 0.0
		var col := Color.WHITE
		match _kind:
			"snow":
				y = fposmod(float(p["y"]) + _t * 34.0 * float(p["v"]) * depth, 780.0) - 30.0
				x += _t * 6.0
			"ember", "bubble":
				y = 780.0 - fposmod(float(p["y"]) + _t * 26.0 * float(p["v"]) * depth, 780.0) - 30.0
				col = Color(1.0, 0.72, 0.35) if _kind == "ember" else Color(0.85, 0.97, 1.0)
			"petal":
				y = fposmod(float(p["y"]) + _t * 28.0 * float(p["v"]) * depth, 780.0) - 30.0
				x += _t * 18.0 * depth
				col = Color(1.0, 0.78, 0.86)
			"mist":
				y = 330.0 + float(p["y"]) * 0.45
				x = fposmod(float(p["x"]) + _t * 14.0 * float(p["v"]) - _cam_x * depth * 0.4, 1600.0) - 160.0
				col = Color(0.9, 0.97, 1.0)
			_:
				y = 780.0 - fposmod(float(p["y"]) + _t * 10.0 * float(p["v"]) * depth, 780.0) - 30.0
				col = Color(1.0, 0.98, 0.88)
		x = fposmod(x + 60.0, 1400.0) - 60.0
		var fade := 1.0 - smoothstep(_horizon_y - 30.0, _horizon_y + 30.0, y)
		if fade <= 0.01:
			continue
		var tw := 0.55 + 0.45 * sin(_t * 2.1 * float(p["f"]) + float(p["ph"]))
		var pos := Vector2(x, y)
		match _kind:
			"snow":
				var r := (1.6 + 2.6 * sz) * depth
				c.draw_circle(pos, r * 2.2, Color(1, 1, 1, 0.10 * fade))
				c.draw_circle(pos, r, Color(1, 1, 1, 0.85 * fade * depth))
			"petal":
				c.draw_set_transform(pos, _t * 0.8 * float(p["f"]) + float(p["ph"]), Vector2(1.0, 0.45))
				c.draw_circle(Vector2.ZERO, (3.5 + 3.0 * sz) * depth, Color(col.r, col.g, col.b, 0.8 * fade * depth))
				c.draw_set_transform_matrix(Transform2D.IDENTITY)
			"bubble":
				var rb := (3.0 + 5.0 * sz) * depth
				c.draw_arc(pos, rb, 0.0, TAU, 16, Color(col.r, col.g, col.b, 0.55 * fade * depth), 1.5, true)
				c.draw_circle(pos + Vector2(-rb * 0.3, -rb * 0.3), rb * 0.18, Color(1, 1, 1, 0.7 * fade * depth))
			"mist":
				var rm := 90.0 + 90.0 * sz
				c.draw_circle(pos, rm, Color(col.r, col.g, col.b, 0.045 * fade))
				c.draw_circle(pos, rm * 0.6, Color(col.r, col.g, col.b, 0.05 * fade))
			"ember":
				var re := (1.4 + 2.2 * sz) * depth
				c.draw_circle(pos, re * 3.0, Color(col.r, col.g, col.b, 0.10 * tw * fade))
				c.draw_circle(pos, re, Color(1.0, 0.9, 0.6, 0.9 * tw * fade * depth))
			_:
				var rs := (2.0 + 3.2 * sz) * depth * (0.7 + 0.5 * tw)
				c.draw_circle(pos, rs * 2.4, Color(col.r, col.g, col.b, 0.07 * tw * fade))
				var d := PackedVector2Array([pos + Vector2(0, -rs * 1.7), pos + Vector2(rs * 0.5, 0), pos + Vector2(0, rs * 1.7), pos + Vector2(-rs * 0.5, 0)])
				c.draw_colored_polygon(d, Color(col.r, col.g, col.b, 0.7 * tw * fade * depth))

# camera hook
## cam_x / zoom as FightScreen computes them; shake = screen-space shake offset; horizon_y = screen y of the floor lip.
func update_camera(cam_x: float, zoom: float, shake: Vector2, horizon_y: float) -> void:
	_cam_x = cam_x
	_zoom = zoom
	_horizon_y = horizon_y
	if view != null:
		if view.world == null:
			return
		view.set_camera(cam_x, zoom, shake, (horizon_y - shake.y - FEET_ROW) / zoom + FLOOR_LIP)
		_feed_blobs()
		return
	var pz := minf(zoom, PLATE_MAX_ZOOM)
	var s := 1.0 + (1.0 - pz) * 0.2
	var at := Vector2(-110.0 - cam_x * 0.1 - (pz - 1.0) * 60.0, -70.0 + (1.0 - pz) * 40.0) + shake * 0.4
	# fixes bug(stage_fx): the plate pan uncovered the right edge past cam_x 236 at zoom 1.24 and up
	plate.position = Vector2(clampf(at.x, 1280.0 - plate.size.x * s, 0.0), clampf(at.y, 720.0 - plate.size.y * s, 0.0))
	plate.scale = Vector2(s, s)
	_grade_mat.set_shader_parameter("horizon_v", horizon_y / 720.0)
	_grade_mat.set_shader_parameter("shift", -cam_x * 0.00006)

# floor
## The floor + edge markers + fighter reflections, in world space. `colors` from sample_colors().
func make_floor(world: Node, cols: Dictionary) -> Node2D:
	if view != null:
		_world = world
		var holder := Node2D.new()
		holder.name = "Floor"
		holder.set_meta("floor_mat", ShaderMaterial.new())
		return holder
	var n := Node2D.new()
	n.name = "Floor"
	n.z_index = -5
	var y0 := Arena.GROUND - 24.0
	var avg: Color = cols.get("avg", Color(0.5, 0.7, 0.95))
	var bot: Color = cols.get("bottom", avg)
	var rect := ColorRect.new()
	rect.position = Vector2(-2400.0, y0)
	rect.size = Vector2(4800.0, 900.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = FLOOR_SHADER
	var far := Color.WHITE.lerp(_boost(bot, 1.35), 0.5)
	var near := _boost(bot, 1.15).lerp(Color(0.16, 0.32, 0.6), 0.5)
	m.set_shader_parameter("far_col", far)
	m.set_shader_parameter("near_col", near)
	m.set_shader_parameter("line_col", Color(1, 1, 1).lerp(_boost(avg, 1.4), 0.15))
	m.set_shader_parameter("accent", Color(1.0, 0.85, 0.3))
	m.set_shader_parameter("half_w", Arena.HALF_W + 100.0)
	rect.material = m
	n.add_child(rect)
	var lines := Node2D.new()
	lines.set_script(load("res://scripts/fight/floor_lines.gd"))
	lines.set("world", world)
	lines.set("colors", cols)
	n.add_child(lines)
	n.set_meta("floor_mat", m)
	return n

func set_floor_camera(mat: ShaderMaterial, zoom: float, horizon_y: float) -> void:
	if view != null:
		return
	mat.set_shader_parameter("horizon_v", horizon_y / 720.0)
	mat.set_shader_parameter("px_to_v", zoom / 720.0)
	mat.set_shader_parameter("time", _t)

func _feed_blobs() -> void:
	if _world == null or _world.fighters.size() < 2:
		return
	var lane: Dictionary = view.info["lane"]
	var cam: Dictionary = view.info["camera"]
	var blobs := []
	for f: Fighter in _world.fighters:
		var up := (Arena.GROUND - f.position.y) / float(cam["px_per_unit"])
		var p := StageCamera.feet(lane, cam, f.position.x)
		blobs.append(Vector4(p.x, p.y, p.z, BLOB_RADIUS * clampf(1.0 - up / BLOB_FADE, 0.0, 1.0)))
	view.set_shadow_blobs(blobs)
