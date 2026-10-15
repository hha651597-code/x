extends Sprite2D
## A soft additive ring behind the model's halo, drawn in the fight's 2D canvas so it spills past the viewport's transparent pixels
## (viewport glow only brightens pixels inside the geometry, and use_hdr_2d would change the whole 2D colour pipeline). Follows the halo mesh each frame: its centre places the ring and its projected box sets the
## size, its colour is the halo texture's saturated hue times BA's halo tint. Blue Archive blooms its halos; this is the hand-made stand-in.

const RING_GROW := 1.25     # ring diameter over the halo's projected box
const STRENGTH := 0.35      # additive alpha at the ring's peak

var halo: MeshInstance3D
var camera: Camera3D
var body: Sprite2D
var _extremes := PackedVector3Array()   # the halo's vertices farthest along 26 directions: its outline without projecting them all
var _centre := Vector3.ZERO             # the ring sits here; the box centre of a tilted crown's projection drifts off it

static func _ring() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 0.74, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

## The mean colour of the texture's most saturated texels, so a magenta halo glows magenta and a pink one pink.
static func hue_of(tex: Texture2D) -> Color:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(24, 24)
	var sum := Vector3.ZERO
	var weight := 0.0
	for y in 24:
		for x in 24:
			var c := img.get_pixel(x, y)
			var w := c.a * maxf(c.s, 0.0) * c.v
			sum += Vector3(c.r, c.g, c.b) * w
			weight += w
	if weight < 0.001:
		return Color.WHITE
	var m := sum / weight
	var top := maxf(m.x, maxf(m.y, m.z))
	return Color(m.x / top, m.y / top, m.z / top)

func setup(halo_mesh: MeshInstance3D, cam: Camera3D, sprite: Sprite2D) -> void:
	halo = halo_mesh
	camera = cam
	body = sprite
	var m := halo.get_surface_override_material(0) as ShaderMaterial
	if m == null:     # a model without BA shading numbers keeps its own materials and gets no ring
		queue_free()
		return
	var tint: Color = m.get_shader_parameter("tint")
	var colour := hue_of(m.get_shader_parameter("albedo_tex"))
	colour = Color(colour.r * tint.r, colour.g * tint.g, colour.b * tint.b)
	colour /= maxf(colour.r, maxf(colour.g, colour.b))
	_centre = halo.mesh.get_aabb().get_center()
	var verts: PackedVector3Array = halo.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or y != 0 or z != 0:
					var dir := Vector3(x, y, z)
					var best := verts[0]
					for v in verts:
						if v.dot(dir) > best.dot(dir):
							best = v
					_extremes.append(best)
	texture = _ring()
	show_behind_parent = true   # under the body sprite, so the head and hair cover the glow of a halo that is behind them
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	modulate = Color(colour, STRENGTH)
	RenderingServer.frame_pre_draw.connect(place)

## Placed just before each draw, when the fight view has posed the model for the frame; _process runs ahead of it.
func place() -> void:
	visible = halo.is_visible_in_tree()
	if not visible:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in _extremes:
		var p := camera.unproject_position(halo.global_transform * v)
		lo = lo.min(p)
		hi = hi.max(p)
	position = (camera.unproject_position(halo.global_transform * _centre) + body.offset) * body.scale
	scale = (hi - lo) * body.scale * RING_GROW / float(texture.width)
