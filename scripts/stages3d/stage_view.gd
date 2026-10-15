class_name StageView
extends Control

const BASE_SIZE := Vector2(1280.0, 720.0)
const PREWARM := 2.0
const MAX_SCALE := 1.5

var viewport: SubViewport
var rect: TextureRect
var camera: Camera3D
var env: Environment
var world: StageLoader.World
var sky: StageSky
var info: Dictionary
var stage_dir := ""
var stage_time := PREWARM
var cam_state := {"cam_x": 0.0, "zoom": 1.0, "shake": Vector2.ZERO, "lift": 0.0}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "StageViewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	rect = TextureRect.new()
	rect.name = "StageRect"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture = viewport.get_texture()
	add_child(rect)
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	camera = Camera3D.new()
	camera.name = "StageCamera"
	viewport.add_child(camera)
	camera.current = true


func _ready() -> void:
	get_tree().root.size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var s := get_viewport().get_final_transform().get_scale()
	var size := Vector2i((BASE_SIZE * s * minf(1.0, MAX_SCALE / maxf(s.x, s.y))).round())
	if viewport.size != size:
		viewport.size = size


func load_stage(dir: String, variant: String) -> void:
	if world != null:
		world.queue_free()
		sky.queue_free()
	stage_dir = dir
	world = StageLoader.load_variant(dir, variant)
	viewport.add_child(world)
	info = world.info
	sky = StageSky.new()
	viewport.add_child(sky)
	camera.near = float(info["camera"]["near"])
	camera.far = float(info["camera"]["far"])
	camera.fov = float(info["camera"]["fov"])
	sky.setup(info, dir, camera, env, world.map_root)
	set_camera(0.0, 1.0)
	_push_time()


func set_camera(cam_x: float, zoom: float, shake := Vector2.ZERO, lift := 0.0) -> void:
	cam_state = {"cam_x": cam_x, "zoom": zoom, "shake": shake, "lift": lift}
	camera.transform = StageCamera.solve(info["lane"], info["camera"], cam_x, zoom, shake, lift)
	sky.follow(camera.global_position)


func set_shadow_blobs(blobs: Array) -> void:
	world.set_shadow_blobs(blobs)


func _process(delta: float) -> void:
	if world == null:
		return
	stage_time += delta
	_push_time()


func _push_time() -> void:
	world.set_stage_time(stage_time)
	sky.set_stage_time(stage_time)
