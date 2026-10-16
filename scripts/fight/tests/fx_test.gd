extends SceneTree
## Effects: curated assets and provenance, the sprite shader, the sprite-based kinds, visibility on bright and dark grounds,
## hostile options. Run: TEST=res://scripts/fight/tests/fx_test.gd zsh tools/sd_test.sh   (a real small window)
## Game scripts are load()ed inside _run(): preloading them here would parse them before the autoloads exist.

const FX_DIR := "res://assets/ba/fx"

var checks := 0
var failures: Array = []

## A session with Reduce Flashes on.
class StubSession extends Session:
	func _init() -> void:
		super()
		reduce_flashes = true

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		print("FX_CHECK FAIL ", label)
		failures.append(label)

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void:
		print("FX_TEST FAIL watchdog timeout")
		quit(3))
	await process_frame
	Game_session().reduce_flashes = false
	_assets()
	await _art()
	await _spark()
	await _visible()
	await _ex_hue()
	await _ring_thickness()
	await _star_ring()
	await _block_layers()
	await _muzzle_look()
	await _digit_bleed()
	await _spark_look()
	await _dust()
	await _sparkle()
	await _heal()
	await _boom()
	await _ko()
	await _swish()
	await _impact()
	await _particles()
	await _reduced()
	await _frozen()
	_muzzle()
	_ring_block()
	_text()
	await _sweep()
	_source()
	print("FX_TEST ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _pngs(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".png"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_pngs(dir.path_join(d), out)

## Every tracked PNG has a PROVENANCE entry with the right hash, and every entry has its file.
func _assets() -> void:
	var f := FileAccess.open(FX_DIR + "/PROVENANCE.json", FileAccess.READ)
	check(f != null, "PROVENANCE.json exists")
	if f == null:
		return
	var prov: Dictionary = JSON.parse_string(f.get_as_text())
	var listed := {}
	for e in prov["files"]:
		listed[str(e["runtime_path"])] = e
	var found: Array = []
	_pngs(FX_DIR, found)
	check(found.size() >= 14, "at least 14 curated textures (%d)" % found.size())
	for path in found:
		var rel: String = (path as String).trim_prefix("res://")
		check(listed.has(rel), "provenance entry for " + rel)
		if listed.has(rel):
			check(FileAccess.get_sha256(path) == str(listed[rel]["sha256"]), "sha256 matches for " + rel)
	for rel in listed:
		check(FileAccess.file_exists("res://" + str(rel)), "file exists for entry " + str(rel))

func _art() -> void:
	var ART: GDScript = load("res://scripts/fight/fx_art.gd")
	for sheet in ART.SHEETS:
		var t: Texture2D = ART.tex(sheet)
		check(t != null, "sheet loads: " + sheet)
		if t == null:
			continue
		var info: Dictionary = ART.SHEETS[sheet]
		var fs: Vector2 = ART.frame_size(sheet)
		check(absf(fs.x * float(info["cols"]) - float(t.get_width())) < 0.01, "frame width divides the sheet: " + sheet)
	check(ART.material("mix", true, false) == ART.material("mix", true, false), "materials are shared")
	check(ART.material("mix", true, false) != ART.material("add", true, false), "blend picks the material")
	await _soft_disc()
	await _grey()

## A soft luminance sprite, tinted red and alpha-mixed over a near-white ground: its soft edge must blend between ground
## and red, never go darker than both (the sheet's colour is premultiplied against black, so it must not be multiplied again).
func _soft_disc() -> void:
	var ART: GDScript = load("res://scripts/fight/fx_art.gd")
	var vp := SubViewport.new()
	vp.size = Vector2i(120, 120)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.93, 0.93)
	bg.size = Vector2(120, 120)
	vp.add_child(bg)
	var soft: Sprite2D = ART.sprite("glow_disc", "mix", false)
	soft.position = Vector2(60, 60)
	soft.scale = Vector2.ONE * (96.0 / 128.0)
	soft.modulate = Color(1.0, 0.0, 0.0, 1.0)
	vp.add_child(soft)
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	var min_r := 1.0
	for y in range(8, 112):
		for x in range(8, 112):
			min_r = minf(min_r, img.get_pixel(x, y).r)
	check(min_r > 0.9, "a soft luminance sprite blends between ground and tint, never darker (min red %.2f)" % min_r)
	var core: Color = img.get_pixel(60, 60)
	check(core.r > 0.95 and core.g < 0.2, "the glow disc core is the tint (%s)" % str(core))
	vp.queue_free()

## Over a mid-grey ground: mix tint, add, transparent black, erode, and gray-mode tinting of a yellow sheet.
func _grey() -> void:
	var ART: GDScript = load("res://scripts/fight/fx_art.gd")
	var vp := SubViewport.new()
	vp.size = Vector2i(400, 120)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.5, 0.5, 0.5)
	bg.size = Vector2(400, 120)
	vp.add_child(bg)
	var tint := Color(0.4, 0.2, 0.0)
	var mix_s: Sprite2D = ART.sprite("circle", "mix", false)
	mix_s.position = Vector2(50, 60)
	mix_s.scale = Vector2.ONE * (80.0 / 512.0)
	mix_s.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	vp.add_child(mix_s)
	var add_s: Sprite2D = ART.sprite("circle", "add", false)
	add_s.position = Vector2(150, 60)
	add_s.scale = Vector2.ONE * (80.0 / 512.0)
	add_s.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	vp.add_child(add_s)
	var gone: Sprite2D = ART.sprite("circle", "mix", true)
	gone.position = Vector2(250, 60)
	gone.scale = Vector2.ONE * (80.0 / 512.0)
	gone.modulate = Color(1.0, 1.0, 1.0, 0.0)
	vp.add_child(gone)
	var star: Sprite2D = ART.sprite("hit_star", "mix", false)
	star.position = Vector2(350, 60)
	star.scale = Vector2.ONE * (90.0 / 512.0)
	star.frame = 0
	star.modulate = Color(0.0, 0.6, 1.0, 1.0)
	vp.add_child(star)
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	img.save_png("res://tmp/fx_art_test.png")
	var m: Color = img.get_pixel(50, 60)
	var a: Color = img.get_pixel(150, 60)
	check(absf(m.r - tint.r) < 0.05 and absf(m.g - tint.g) < 0.05, "mix draws the tint over the ground (%s)" % m)
	check(absf(a.r - (0.5 + tint.r)) < 0.06 and absf(a.g - (0.5 + tint.g)) < 0.06, "add brightens the ground by the tint (%s)" % a)
	check(absf(img.get_pixel(14, 24).r - 0.5) < 0.02, "the black corner of a luminance sheet is transparent")
	check(absf(img.get_pixel(250, 60).r - 0.5) < 0.02, "an eroded sprite with nothing left is gone")
	var blue := 0.0
	var red := 0.0
	var n := 0
	for y in range(15, 105):
		for x in range(305, 395):
			var c := img.get_pixel(x, y)
			if absf(c.r - 0.5) + absf(c.g - 0.5) + absf(c.b - 0.5) > 0.3:
				blue += c.b
				red += c.r
				n += 1
	check(n > 200 and blue / float(n) > red / float(n) + 0.15, "a yellow sheet takes a blue tint in gray mode (%d px)" % n)
	vp.queue_free()

func _pose() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	check(FX.pose(0.0, 3) == 0 and FX.pose(0.34, 3) == 1 and FX.pose(0.99, 3) == 2 and FX.pose(1.0, 3) == 2, "pose steps through 0..n-1")
	check(FX.pose(-1.0, 4) == 0 and FX.pose(9.0, 4) == 3, "pose clamps")

func _spark() -> void:
	_pose()
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 240)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var ground := ColorRect.new()
	ground.color = Color(0.93, 0.95, 0.97)       # near-white snow
	ground.size = Vector2(480, 240)
	vp.add_child(ground)
	var fx: Node2D = FX.make(vp, "spark", Vector2(240, 120), 0.32, {"color": Color(1.0, 0.66, 0.22), "size": 1.6, "seed": 2.0, "dir": 1})
	fx.set_process(false)
	fx._process(0.32 * 0.3)
	check(fx.parts.size() >= 5, "a heavy spark builds its layers (%d)" % fx.parts.size())
	for i in 4:
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png("res://tmp/fx_spark_test.png")
	var best := 0.0
	for dy in range(-40, 41, 4):
		for dx in range(-40, 41, 4):
			var c := img.get_pixel(240 + dx, 120 + dy)
			best = maxf(best, maxf(absf(c.r - 0.93), maxf(absf(c.g - 0.95), absf(c.b - 0.97))))
	check(best > 0.25, "a heavy spark shows on a near-white ground (max channel difference %.2f)" % best)
	fx._process(0.32)
	check(fx.is_queued_for_deletion(), "a spark is freed at the end of its life")
	vp.queue_free()

## Every sprite-based kind must show on a bright ground and on a dark one, early and mid-life: the largest channel difference
## against the bare ground, within 150 px of the centre, must reach 0.15. Each kind adds its own rows.
const VISIBLE := [
	["spark light", "spark", {"color": Color(1.0, 0.93, 0.55), "size": 1.0, "seed": 1.0}, 0.22],
	["spark heavy", "spark", {"color": Color(1.0, 0.66, 0.22), "size": 1.6, "seed": 2.0}, 0.32],
	["spark ex", "spark", {"color": Color(0.62, 0.93, 1.0), "size": 2.5, "seed": 3.0}, 0.46],
	["muzzle right", "muzzle", {"color": Color(1.0, 0.8, 0.4), "size": 1.6, "dir": 1}, 0.14],
	["muzzle left", "muzzle", {"color": Color(1.0, 0.8, 0.4), "size": 1.6, "dir": -1}, 0.14],
	["ring heavy", "ring", {"color": Color(1.0, 0.8, 0.4), "size": 1.0}, 0.35],
	["ring small", "ring", {"color": Color(0.62, 0.93, 1.0), "size": 0.3}, 0.5],
	["block right", "block", {"dir": 1}, 0.3],
	["block left", "block", {"dir": -1}, 0.3],
	["numerals", "text", {"text": "45", "color": Color(1.0, 0.95, 0.6), "fsize": 44, "digits": true}, 0.7],
	["dust", "dust", {"seed": 1.0, "size": 1.0}, 0.45],
	["sparkle white", "sparkle", {"color": Color(1.0, 1.0, 1.0), "size": 1.4}, 0.6],
	["sparkle ice", "sparkle", {"color": Color(0.62, 0.93, 1.0), "size": 1.4}, 0.6],
	["heal", "heal", {"seed": 1.0}, 1.1],
	["boom small", "boom", {"color": Color(1.0, 0.55, 0.2), "size": 0.8, "seed": 1.0}, 0.5],
	["boom big", "boom", {"color": Color(1.0, 0.45, 0.25), "size": 1.4, "seed": 2.0}, 0.6],
	["ko", "ko", {"color": Color(1.0, 0.45, 0.4), "seed": 1.0}, 1.0],
	["swish right", "swish", {"color": Color(0.9, 0.7, 0.4), "dir": 1, "off": Vector2.ZERO, "r": 100.0, "thick": 30.0}, 0.3],
	["swish left", "swish", {"color": Color(0.6, 0.85, 1.0), "dir": -1, "off": Vector2.ZERO, "r": 100.0, "thick": 30.0}, 0.3],
	["slash", "slash", {"color": Color(1.0, 1.0, 1.0), "dir": 1}, 0.35],
	["impact", "impact", {"seed": 1.0}, 0.2],
]

func _visible() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.size = Vector2(480, 300)
	vp.add_child(bg)
	var grounds := {"bright": Color(0.91, 0.95, 0.97), "dark": Color(0.07, 0.14, 0.23)}
	for ground in grounds:
		bg.color = grounds[ground]
		for spec in VISIBLE:
			for frac in [0.15, 0.4]:
				if spec[1] == "impact":
					FlashH().set("_last_impact_ms", -100000)
				var fx: Node2D = FX.make(vp, spec[1], Vector2(240, 150), spec[3], spec[2])
				fx.set_process(false)
				fx._process(float(spec[3]) * float(frac))
				for i in 3:
					await process_frame
				var img := vp.get_texture().get_image()
				var g: Color = grounds[ground]
				var best := 0.0
				for y in range(0, 300, 2):
					for x in range(90, 390, 2):
						var c := img.get_pixel(x, y)
						best = maxf(best, maxf(absf(c.r - g.r), maxf(absf(c.g - g.g), absf(c.b - g.b))))
				check(best >= 0.15, "%s shows on a %s ground at %.0f percent of its life (%.2f)" % [spec[0], ground, frac * 100.0, best])
				fx.free()
	vp.queue_free()

## An EX spark is cyan, not green: the blue channel of its bright pixels beats the red.
func _ex_hue() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var vp := SubViewport.new()
	vp.size = Vector2i(480, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.14, 0.23)
	bg.size = Vector2(480, 300)
	vp.add_child(bg)
	var fx: Node2D = FX.make(vp, "spark", Vector2(240, 150), 0.46, {"color": Color(0.62, 0.93, 1.0), "size": 2.5, "seed": 3.0})
	fx.set_process(false)
	fx._process(0.46 * 0.3)
	for i in 3:
		await process_frame
	var img := vp.get_texture().get_image()
	var blue := 0.0
	var red := 0.0
	var n := 0
	for y in range(0, 300, 2):
		for x in range(0, 480, 2):
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 1.6:
				blue += c.b
				red += c.r
				n += 1
	check(n > 100 and blue / float(n) > red / float(n) + 0.05, "the ex spark is cyan, not green (%d px)" % n)
	vp.queue_free()

func FlashH() -> GDScript:
	return load("res://scripts/fight/fx_flash.gd")

# measuring helpers
const SNOW := Color(0.91, 0.95, 0.97)
const NAVY := Color(0.07, 0.14, 0.23)

func _stage(w: int, h: int, ground: Color) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = ground
	bg.size = Vector2(w, h)
	vp.add_child(bg)
	return vp

## One effect stepped to `frac` of its life at the stage centre, rendered and freed. `hide`: part indices to switch off, so
## a layer's own ink is the difference between two shots.
func _shot(vp: SubViewport, kind: String, life: float, opts: Dictionary, frac: float, hide := []) -> Image:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var fx: Node2D = FX.make(vp, kind, Vector2(vp.size) * 0.5, life, opts)
	fx.set_process(false)
	fx._process(life * frac)
	for i in hide:
		(fx.parts[i] as Sprite2D).visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	fx.free()
	return img

func _diff(img: Image, p: Vector2, g: Color) -> float:
	var x := int(roundf(p.x))
	var y := int(roundf(p.y))
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return 0.0
	var c := img.get_pixel(x, y)
	return maxf(absf(c.r - g.r), maxf(absf(c.g - g.g), absf(c.b - g.b)))

## Rays from the stage centre: how many meet a ring whose outer edge is near radius r (hit, 0..1), and the median run of
## ink (difference from the ground of at least 0.15) going inward from that edge, in px.
func _band(img: Image, g: Color, r: float) -> Dictionary:
	var c := Vector2(img.get_size()) * 0.5
	var runs: Array = []
	for i in 24:
		var d := Vector2.from_angle(TAU * float(i) / 24.0 + 0.1)
		var t := r * 1.15
		while t > 0.0 and _diff(img, c + d * t, g) < 0.15:
			t -= 0.5
		if t < r * 0.85:
			continue
		var w := 0.0
		while t > 0.0 and _diff(img, c + d * t, g) >= 0.15:
			t -= 0.5
			w += 0.5
		runs.append(w)
	runs.sort()
	return {"hit": float(runs.size()) / 24.0, "med": 0.0 if runs.is_empty() else float(runs[runs.size() / 2])}

## Pixels that differ from the ground by at least `thr` inside the disc of radius `rad` around the stage centre.
func _ink_in(img: Image, g: Color, rad: float, thr := 0.15) -> int:
	var c := Vector2(img.get_size()) * 0.5
	var n := 0
	for y in range(int(c.y - rad), int(c.y + rad) + 1):
		for x in range(int(c.x - rad), int(c.x + rad) + 1):
			if Vector2(float(x), float(y)).distance_to(c) <= rad and _diff(img, Vector2(float(x), float(y)), g) >= thr:
				n += 1
	return n

## Rings read as hard bands: in the first two radius poses nearly every ray meets a ring at its radius and the band is thick
## enough to see (at least a tenth of the radius, 5 px at the least), on snow and on navy. It thins in steps, and the spikes of
## a heavy ring show on snow (they were white on white).
func _ring_thickness() -> void:
	for ground in [SNOW, NAVY]:
		var vp := _stage(420, 420, ground)
		for size in [0.3, 1.0]:
			var opts := {"color": Color(0.62, 0.93, 1.0) if size < 0.5 else Color(1.0, 0.8, 0.4), "size": size, "seed": 1.0}
			var rel := []
			for frac in [0.1, 0.3, 0.45, 0.6]:
				var r: float = 26.0 + 190.0 * size * [0.4, 0.7, 1.0][int(frac * 3.0)]
				var b := _band(await _shot(vp, "ring", 0.35, opts, frac), ground, r)
				check(float(b["hit"]) >= 0.9, "ring size %.1f at %.0f%% of its life is one band (%.2f of rays, ground %s)" % [size, frac * 100.0, b["hit"], ground])
				check(float(b["med"]) >= maxf(7.0, 0.1 * r), "ring size %.1f at %.0f%% of its life is thick enough (%.1f px of %.0f, ground %s)" % [size, frac * 100.0, b["med"], r, ground])
				rel.append(float(b["med"]) / r)
			check(rel[1] < rel[0] and rel[3] < rel[2], "ring size %.1f thins from one step to the next inside a radius pose (%s)" % [size, str(rel)])
			check(rel[2] < rel[0], "ring size %.1f is thinner for its radius in the second pose than in the first (%s)" % [size, str(rel)])
		vp.queue_free()
	var vp2 := _stage(420, 420, SNOW)
	var heavy := {"color": Color(1.0, 0.8, 0.4), "size": 1.0, "seed": 1.0}
	var lit := await _shot(vp2, "ring", 0.35, heavy, 0.1)
	var bare := await _shot(vp2, "ring", 0.35, heavy, 0.1, [1, 3])
	var inside := 0.75 * (26.0 + 190.0 * 0.4)
	var blades := _ink_in(lit, SNOW, inside) - _ink_in(bare, SNOW, inside)
	check(blades >= 2500, "the spikes of a heavy ring show on snow (%d px)" % blades)
	vp2.queue_free()

# a hit's star and its ring
## The hits that pair a ring with a star: Fx.spark's heavy and ex, and fight_screen's explosions (the ring first, then the star,
## sized from the blast radius).
const PAIRS := ["heavy", "ex", "boom60", "boom80", "boom120"]

func _spawn_pair(holder: Node2D, pair: String) -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	if pair.begins_with("boom"):
		var r := float(pair.trim_prefix("boom"))
		FX.make(holder, "ring", Vector2.ZERO, 0.35, {"color": Color(1.0, 0.5, 0.2), "size": r / 120.0})
		FX.make(holder, "spark", Vector2.ZERO, 0.3, {"color": Color(1.0, 0.8, 0.4), "size": r / 60.0, "seed": 1.0})
	else:
		FX.spark(holder, Vector2.ZERO, pair, 1, 1.0)

## Half the width of the star's burst frame as drawn now: the radius the star is built to (its tips reach past it).
func _star_radius(star: Node2D) -> float:
	var sp: Sprite2D = star.parts[0]
	return sp.get_rect().size.x * sp.scale.x * 0.5

## The largest radius the star's burst frame takes over its life.
func _star_peak(pair: String) -> float:
	var holder := Node2D.new()
	root.add_child(holder)
	_spawn_pair(holder, pair)
	var star: Node2D = null
	for fx in holder.get_children():
		fx.set_process(false)
		if fx.kind == "spark":
			star = fx
	var peak := 0.0
	for i in 49:
		star._process(star.life / 50.0)
		peak = maxf(peak, _star_radius(star))
	holder.free()
	return peak

## One hit (`pair`) with all its nodes stepped to the same age, `frac` of the ring's life, drawn at the stage centre. `hide`: the
## node kinds to switch off. Returns the image, the star's radius at that age, and whether the ring draws below the star.
func _pair_shot(vp: SubViewport, pair: String, frac: float, hide := []) -> Dictionary:
	var holder := Node2D.new()
	holder.position = Vector2(vp.size) * 0.5
	vp.add_child(holder)
	_spawn_pair(holder, pair)
	var ring: Node2D = null
	var star: Node2D = null
	for fx in holder.get_children():
		fx.set_process(false)
		if fx.kind == "ring":
			ring = fx
		else:
			star = fx
	for fx in [ring, star]:
		fx._process(frac * ring.life)
	var below: bool = ring.z_index < star.z_index or (ring.z_index == star.z_index and ring.get_index() < star.get_index())
	var star_r := _star_radius(star)
	for fx in [ring, star]:
		fx.visible = not (fx.kind in hide)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	holder.free()
	return {"img": img, "star_r": star_r, "below": below}

## The outer radius of the ink around the stage centre: the median over 36 rays of the farthest ink, in px.
func _outer(img: Image, g: Color) -> float:
	var c := Vector2(img.get_size()) * 0.5
	var far: Array = []
	for i in 36:
		var d := Vector2.from_angle(TAU * float(i) / 36.0 + 0.05)
		var t := minf(c.x, c.y) - 1.0
		while t > 0.0 and _diff(img, c + d * t, g) < 0.15:
			t -= 0.5
		far.append(t)
	far.sort()
	return float(far[18])

## A hit's ring starts at its star's edge, grows past it, and draws behind it (the shockwave expands outside the star and the
## star keeps the focus). The star's radius is half the width of its burst frame at the same age; the ring's outer radius is
## measured on a render of the ring alone. First pose of the ring: its outer radius is 0.9 to 1.3 of the star's. Last pose: at
## least 1.15 of the largest the star ever gets. The ring draws below the star, the star's centre is pure star (the render with
## the ring on equals the render without it), and so is nearly all of the star's solid body (the spikes of the shockwave
## do not show through it). The ring still shows outside the star at mid-life.
func _star_ring() -> void:
	for ground in [SNOW, NAVY]:
		var vp := _stage(760, 760, ground)
		var gname := "snow" if ground == SNOW else "navy"
		for pair in PAIRS:
			var peak := _star_peak(pair)
			var first := await _pair_shot(vp, pair, 0.05, ["spark"])
			var last := await _pair_shot(vp, pair, 0.9, ["spark"])
			var r0 := _outer(first["img"], ground)
			var r1 := _outer(last["img"], ground)
			var sr: float = first["star_r"]
			var lo := 0.8 if pair.begins_with("boom") else 0.9      # the explosions' ring sizes come from fight_screen and the kits
			check(r0 >= lo * sr and r0 <= 1.3 * sr, "%s ring starts at its star's edge: outer radius %.0f px, star %.0f px (%.2f of it), %s ground" % [pair, r0, sr, r0 / sr, gname])
			check(r1 >= 1.15 * peak, "%s ring ends past its star: outer radius %.0f px, the star's largest %.0f px (%.2f of it), %s ground" % [pair, r1, peak, r1 / peak, gname])
			for frac in [0.1, 0.3, 0.5]:
				var all := await _pair_shot(vp, pair, frac)
				var star_only := await _pair_shot(vp, pair, frac, ["ring"])
				var bare := await _pair_shot(vp, pair, frac, ["ring", "spark"])
				var where := "%s at %.0f%% of the ring's life, %s ground" % [pair, frac * 100.0, gname]
				check(all["below"], "the ring draws below its star: " + where)
				var core_r: float = 0.3 * float(all["star_r"])
				var worst := 0.0
				var body := 0
				var kept := 0
				var out_ring := 0
				var c := Vector2(vp.size) * 0.5
				for y in range(int(c.y - 300.0), int(c.y + 300.0)):
					for x in range(int(c.x - 300.0), int(c.x + 300.0)):
						var p := Vector2(float(x), float(y))
						var a: Color = (all["img"] as Image).get_pixel(x, y)
						var s: Color = (star_only["img"] as Image).get_pixel(x, y)
						var delta := maxf(absf(a.r - s.r), maxf(absf(a.g - s.g), absf(a.b - s.b)))
						if p.distance_to(c) <= core_r:
							worst = maxf(worst, delta)
						if ground == NAVY and _diff(star_only["img"], p, ground) >= 0.5:
							body += 1
							if delta <= 0.05:
								kept += 1
						if _diff(all["img"], p, ground) >= 0.15 and _diff(star_only["img"], p, ground) < 0.15:
							out_ring += 1
				check(worst <= 0.02, "the star's centre is the star's own colours, not the ring's (largest change %.2f in %.0f px): %s" % [worst, core_r, where])
				if ground == NAVY:
					check(float(kept) >= 0.95 * float(body), "the ring does not show through the star's body (%d of %d px unchanged): %s" % [kept, body, where])
				check(out_ring >= 300, "the ring still shows around its star (%d px of its own): %s" % [out_ring, where])
		vp.queue_free()
	var one := Node2D.new()
	root.add_child(one)
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	FX.spark(one, Vector2.ZERO, "light", 1, 1.0)
	FX.spark(one, Vector2.ZERO, "block", 1, 1.0)
	FX.spark(one, Vector2.ZERO, "heavy", 1, 1.0)
	check(one.get_child_count() == 4, "a light hit and a block are one effect each, a heavy hit is a star and a ring (%d nodes)" % one.get_child_count())
	one.free()

## Pixels inked (difference from the ground of at least `thr`) in `a` that are not in `b`: a layer's own ink when `b` is the same
## shot with that layer off.
func _new_ink(a: Image, b: Image, g: Color, thr := 0.15) -> int:
	var n := 0
	for y in range(0, a.get_height(), 1):
		for x in range(0, a.get_width(), 1):
			var p := Vector2(float(x), float(y))
			if _diff(a, p, g) >= thr and _diff(b, p, g) < thr:
				n += 1
	return n

## Block: the hex shows as a line of its own through the whole expansion and the card holds, on snow and on navy. Each layer is
## measured by what disappears when it is switched off.
func _block_layers() -> void:
	for ground in [SNOW, NAVY]:
		var vp := _stage(480, 400, ground)
		for dir in [1, -1]:
			for frac in [0.05, 0.15, 0.4, 0.7, 0.9]:
				var all := await _shot(vp, "block", 0.3, {"dir": dir}, frac)
				var no_hex := await _shot(vp, "block", 0.3, {"dir": dir}, frac, [2])
				var no_card := await _shot(vp, "block", 0.3, {"dir": dir}, frac, [1])
				var hx := _new_ink(all, no_hex, ground)
				var cd := _new_ink(all, no_card, ground)
				var where := "%s, %s ground, dir %d" % ["%.0f%% of its life" % (frac * 100.0), "snow" if ground == SNOW else "navy", dir]
				check(hx >= 2500, "the block's hex is a line of its own at %s (%d px)" % [where, hx])
				check(cd >= 2000, "the block's card shows at %s (%d px)" % [where, cd])
				if frac == 0.7:
					check(cd >= 15000, "the block's card is held at %s (%d px)" % [where, cd])
				if frac == 0.9:
					check(cd >= 6000, "the block's card is still there at %s (%d px)" % [where, cd])
		vp.queue_free()

## Of the inked pixels of `img` within 2 px of the ground (the outline), the share darker than `tint` by at least 0.08 in
## luminance: a flame with a contrast edge scores high, a flat fill in its own tint scores near zero (its edge only blends
## towards the ground). Only meaningful on a light ground.
func _dark_edge(img: Image, g: Color, tint: Color) -> float:
	var edge := 0
	var dark := 0
	var tl := tint.get_luminance()
	for y in range(2, img.get_height() - 2):
		for x in range(2, img.get_width() - 2):
			var p := Vector2(float(x), float(y))
			if _diff(img, p, g) < 0.15:
				continue
			var rim := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if _diff(img, p + Vector2(float(dx), float(dy)), g) < 0.15:
						rim = true
			if rim:
				edge += 1
				if img.get_pixel(x, y).get_luminance() <= tl - 0.08:
					dark += 1
	return float(dark) / float(maxi(edge, 1))

## Muzzle: the tracers are thin lines above and below the flame and stay off it, and the flame shows as a flame: on snow it has
## a dark outline, on navy most of its ink is its own tint, for pale, violet and red tints.
func _muzzle_look() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	for dir in [1, -1]:
		var m: Node2D = FX.make(holder, "muzzle", Vector2.ZERO, 0.14, {"dir": dir, "size": 1.6, "color": Color(0.72, 0.25, 1.0)})
		m.set_process(false)
		m._process(0.03)
		var d := 130.0 * 1.6
		var up: Sprite2D = m.parts[2]
		var down: Sprite2D = m.parts[3]
		var frame_h: float = (load("res://scripts/fight/fx_art.gd") as GDScript).frame_size("capsule").y
		check(up.scale.y * frame_h <= 12.0 and down.scale.y * frame_h <= 12.0, "the muzzle tracers are thin lines (%.1f px)" % (up.scale.y * frame_h))
		check(up.position.y <= -0.2 * d and down.position.y >= 0.2 * d, "the muzzle tracers sit above and below the flame (%.0f, %.0f)" % [up.position.y, down.position.y])
	holder.queue_free()
	for ground in [SNOW, NAVY]:
		var vp := _stage(480, 300, ground)
		for tint in [Color(1.0, 0.8, 0.4), Color(0.72, 0.25, 1.0), Color(0.95, 0.2, 0.2)]:
			for dir in [1, -1]:
				var opts := {"dir": dir, "size": 1.6, "color": tint, "seed": 1.0}
				for frac in [0.1, 0.3]:
					var flame := await _shot(vp, "muzzle", 0.14, opts, frac, [2, 3])
					var lines := await _shot(vp, "muzzle", 0.14, opts, frac, [0, 1, 4, 5])
					var on_flame := 0
					var line_ink := 0
					for y in flame.get_height():
						for x in flame.get_width():
							var p := Vector2(float(x), float(y))
							if _diff(lines, p, ground) >= 0.15:
								line_ink += 1
								if _diff(flame, p, ground) >= 0.15:
									on_flame += 1
					var where := "tint %s, dir %d, %.0f%% of its life, %s ground" % [str(tint), dir, frac * 100.0, "snow" if ground == SNOW else "navy"]
					check(line_ink >= 300 and on_flame * 10 <= line_ink, "the muzzle tracers show and stay off the flame (%d px, %d on it): %s" % [line_ink, on_flame, where])
					if ground == SNOW:
						var de := _dark_edge(flame, ground, tint)
						check(de >= 0.3, "the muzzle flame has a dark outline on snow (%.2f of its edge): %s" % [de, where])
					else:
						var nt := _near_tint(flame, ground, tint)
						check(float(nt[0]) >= 0.35 * float(nt[1]), "most of the muzzle flame is its own tint on navy (%d of %d px): %s" % [nt[0], nt[1], where])
		vp.queue_free()

## Pixels of `img` inked against `g` that are within 0.2 (largest channel) of `tint`, and all inked pixels.
func _near_tint(img: Image, g: Color, tint: Color) -> Array:
	var near := 0
	var all := 0
	for y in img.get_height():
		for x in img.get_width():
			if _diff(img, Vector2(float(x), float(y)), g) >= 0.15:
				all += 1
				var c := img.get_pixel(x, y)
				if maxf(absf(c.r - tint.r), maxf(absf(c.g - tint.g), absf(c.b - tint.b))) <= 0.2:
					near += 1
	return [near, all]

## The numeral sheet is sampled with linear filtering, so a glyph's neighbour cell bleeds into its first or last column at
## some fractional scales and positions. Every digit sprite turns the region clip on, and the clip holds under the sprite
## shader: a sheet whose left cell is clear and whose right cell is solid red, drawn ten times at fractional offsets, shows a
## red line without the clip (the control) and none with it.
func _digit_bleed() -> void:
	var D: GDScript = load("res://scripts/fight/fx_digits.gd")
	var ART: GDScript = load("res://scripts/fight/fx_art.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	var built: Array = D.build(holder, "0123456789", "weak", 66.0)
	var clipped := 0
	for sp in built:
		if (sp as Sprite2D).region_filter_clip_enabled:
			clipped += 1
	check(built.size() == 10 and clipped == 10, "every numeral sprite clips its region to stop the neighbour cell bleeding in (%d of %d)" % [clipped, built.size()])
	holder.queue_free()
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(16, 0, 16, 16), Color(1.0, 0.0, 0.0, 1.0))
	var tex := ImageTexture.create_from_image(img)
	var vp := _stage(340, 70, Color(0.5, 0.5, 0.5))
	for row in 2:
		for i in 10:
			var sp: Sprite2D = ART.sprite("digits_weak", "mix", false)
			sp.texture = tex
			sp.region_enabled = true
			sp.region_rect = Rect2(0.0, 0.0, 16.0, 16.0)
			sp.region_filter_clip_enabled = row == 1
			sp.scale = Vector2.ONE * 1.6
			sp.position = Vector2(30.0 * float(i) + 20.0 + float(i) * 0.1, 18.0 + 32.0 * float(row))
			vp.add_child(sp)
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot := vp.get_texture().get_image()
	var red := [0, 0]
	for row in 2:
		for y in range(0, 32):
			for x in range(0, 340):
				var c := shot.get_pixel(x, y + 32 * row)
				if c.r - c.g > 0.15 and c.r - c.b > 0.15:
					red[row] += 1
	check(red[0] >= 20, "control: without the clip the neighbour cell bleeds in (%d red px)" % red[0])
	check(red[1] == 0, "with the clip nothing bleeds in (%d red px)" % red[1])
	vp.queue_free()

## Light spark: the white core is gone after the first fifth of the life, and a warm star keeps the sheet's tones (a yellow
## body, a paler ring, a white-ish centre) instead of one flat khaki, with a body that stands well clear of snow.
func _spark_look() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	var s: Node2D = FX.make(holder, "spark", Vector2.ZERO, 0.22, {"color": Color(1.0, 0.93, 0.55), "size": 1.0, "seed": 1.0})
	s.set_process(false)
	s._process(0.22 * 0.1)
	check((s.parts[1] as Sprite2D).modulate.a > 0.4, "the spark core still shows at 10 percent of its life")
	s._process(0.22 * 0.15)
	check((s.parts[1] as Sprite2D).modulate.a < 0.4, "the spark core is fading at 25 percent of its life")
	s._process(0.22 * 0.04)
	check((s.parts[1] as Sprite2D).modulate.a == 0.0, "the spark core is gone after the first fifth of its life")
	holder.queue_free()
	for spec in [["light", Color(1.0, 0.93, 0.55), 1.0, 0.22], ["heavy", Color(1.0, 0.66, 0.22), 1.6, 0.32]]:
		var opts := {"color": spec[1], "size": spec[2], "seed": 1.0}
		var snow := _stage(400, 400, SNOW)
		var on_snow := await _shot(snow, "spark", spec[3], opts, 0.4)
		snow.queue_free()
		var strong := _ink_in(on_snow, SNOW, 100.0, 0.6)
		check(strong >= 3000, "the %s spark body stands well clear of snow (%d px at 0.6)" % [spec[0], strong])
	var navy := _stage(400, 400, NAVY)
	var img := await _shot(navy, "spark", 0.22, {"color": Color(1.0, 0.93, 0.55), "size": 1.0, "seed": 1.0}, 0.4)
	var blues: Array = []
	for y in range(150, 251):
		for x in range(150, 251):
			if _diff(img, Vector2(float(x), float(y)), NAVY) >= 0.4:
				blues.append(img.get_pixel(x, y).b)
	blues.sort()
	var spread := 0.0 if blues.size() < 50 else float(blues[int(float(blues.size()) * 0.95)]) - float(blues[int(float(blues.size()) * 0.05)])
	check(spread >= 0.2, "the light star keeps its yellow, pale and white tones (blue spread %.2f over %d px)" % [spread, blues.size()])
	var pink := await _shot(navy, "spark", 0.3, {"color": Color(1.0, 0.5, 0.7), "size": 1.6, "seed": 1.0}, 0.3)
	var blue := 0.0
	var green := 0.0
	var n := 0
	for y in range(0, 400, 2):
		for x in range(0, 400, 2):
			var c := pink.get_pixel(x, y)
			if c.r + c.g + c.b > 1.6:
				blue += c.b
				green += c.g
				n += 1
	check(n > 100 and blue / float(n) > green / float(n) + 0.05, "a pink spark stays pink and does not turn orange (%d px)" % n)
	navy.queue_free()

func _muzzle() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	var right: Node2D = FX.make(holder, "muzzle", Vector2.ZERO, 0.14, {"dir": 1, "size": 1.6, "color": Color(1.0, 0.8, 0.4)})
	var left: Node2D = FX.make(holder, "muzzle", Vector2.ZERO, 0.14, {"dir": -1, "size": 1.6, "color": Color(1.0, 0.8, 0.4)})
	right.set_process(false)
	left.set_process(false)
	right._process(0.03)
	left._process(0.03)
	check(right.parts.size() == 6 and left.parts.size() == 6, "a muzzle flash has a flash, a core, two tracers, a hot centre and a rim")
	check((right.parts[0] as Sprite2D).position.x > 0.0 and (left.parts[0] as Sprite2D).position.x < 0.0, "the flash sits on the barrel side it faces")
	check(not (right.parts[0] as Sprite2D).flip_h and (left.parts[0] as Sprite2D).flip_h, "the flash flips for dir -1")
	var f0: int = (right.parts[0] as Sprite2D).frame
	right._process(0.06)
	check((right.parts[0] as Sprite2D).frame != f0, "the flash changes pose halfway through")
	holder.queue_free()

func _ring_block() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	var small: Node2D = FX.make(holder, "ring", Vector2.ZERO, 0.35, {"color": Color(1.0, 0.8, 0.4), "size": 0.3})
	var big: Node2D = FX.make(holder, "ring", Vector2.ZERO, 0.35, {"color": Color(1.0, 0.8, 0.4), "size": 1.2})
	var blk: Node2D = FX.make(holder, "block", Vector2.ZERO, 0.3, {"dir": 1})
	for fx in [small, big, blk]:
		fx.set_process(false)
		fx._process(0.1)
	var mid: Node2D = FX.make(holder, "ring", Vector2.ZERO, 0.35, {"color": Color(1.0, 0.8, 0.4), "size": 0.48})
	mid.set_process(false)
	mid._process(0.1)
	check(small.parts.size() == 2 and mid.parts.size() == 4 and big.parts.size() == 4, "rings above size 0.45 (a heavy hit's is 0.9) get the spiky shockwave and its rim, smaller ones only the ring and its rim")
	check((big.parts[0] as Sprite2D).scale.x > (small.parts[0] as Sprite2D).scale.x, "a larger ring is larger")
	var r1 := (big.parts[0] as Sprite2D).scale.x
	big._process(0.15)
	check((big.parts[0] as Sprite2D).scale.x >= r1, "the ring never shrinks while it expands")
	check(blk.parts.size() == 8, "a block has glow, shield, hex and five sparks (%d)" % blk.parts.size())
	check((blk.parts[1] as Sprite2D).position.x > 0.0, "the shield stands in front of a right-facing fighter")
	holder.queue_free()

## The visible gap between the ink of two neighbouring digits is the advance plus the next glyph's left ink margin minus this
## glyph's right ink edge. After a 1 it must not be wider than the widest gap any other pair has (5 px at 64 px high).
func _digit_gaps(D: GDScript) -> void:
	var sheet: Image = (load("res://scripts/fight/fx_art.gd") as GDScript).tex("digits_weak").get_image()
	var ink := {}
	for ch in D.RECTS:
		var r: Array = D.RECTS[ch]
		var lo := 9999
		var hi := -1
		for x in int(r[2]):
			for y in int(r[3]):
				if sheet.get_pixel(int(r[0]) + x, int(r[1]) + y).a > 0.16:
					lo = mini(lo, x)
					hi = maxi(hi, x + 1)
					break
		ink[ch] = [lo, hi]
	var widest_other := -99
	var widest_after_one := -99
	for p in D.RECTS:
		for q in D.RECTS:
			var gap: int = int((D.RECTS[p] as Array)[4]) + int((ink[q] as Array)[0]) - int((ink[p] as Array)[1])
			if p == "1":
				widest_after_one = maxi(widest_after_one, gap)
			elif q != "1":
				widest_other = maxi(widest_other, gap)
	check(widest_after_one <= widest_other, "the widest gap after a 1 (%d px) is no wider than between other digits (%d px)" % [widest_after_one, widest_other])

## No glyph region carries a stray strip at its edge: an edge column that has any ink must have strong ink (alpha 128 or more)
## in that column or the one inside it, otherwise it is a neighbour's fringe or a detached sliver.
func _digit_edges(D: GDScript) -> void:
	var sheet: Image = (load("res://scripts/fight/fx_art.gd") as GDScript).tex("digits_weak").get_image()
	for ch in D.RECTS:
		var r: Array = D.RECTS[ch]
		var peak: Array = []
		for c in int(r[2]):
			var m := 0.0
			for y in int(r[3]):
				m = maxf(m, sheet.get_pixel(int(r[0]) + c, int(r[1]) + y).a)
			peak.append(m)
		var last: int = int(r[2]) - 1
		check(float(peak[0]) == 0.0 or maxf(float(peak[0]), float(peak[1])) >= 0.5, "digit %s has no stray strip on its left edge (%.2f, %.2f)" % [ch, peak[0], peak[1]])
		check(float(peak[last]) == 0.0 or maxf(float(peak[last]), float(peak[last - 1])) >= 0.5, "digit %s has no stray strip on its right edge (%.2f, %.2f)" % [ch, peak[last], peak[last - 1]])

func _text() -> void:
	var D: GDScript = load("res://scripts/fight/fx_digits.gd")
	check(D.width("", 64.0) == 0.0, "empty text has no width")
	check(absf(D.width("10", 64.0) - 84.0) < 0.001, "width counts the digit advances (1 is 36, 0 is 48)")
	check(absf(D.width("11", 64.0) - 72.0) < 0.001, "the digit 1 advances 36 px at 64 px high")
	_digit_gaps(D)
	_digit_edges(D)
	check(absf(D.width("00", 32.0) - 48.0) < 0.001, "width scales with the digit height")
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	var n: Node2D = FX.make(holder, "text", Vector2.ZERO, 0.7, {"text": "45", "color": Color(1.0, 0.95, 0.6), "fsize": 44, "digits": true})
	var w: Node2D = FX.make(holder, "text", Vector2.ZERO, 0.9, {"text": "LOCK & LOAD", "color": Color(0.8, 0.6, 1.0), "fsize": 40})
	var label: Node2D = FX.make(holder, "text", Vector2.ZERO, 0.9, {"text": "404", "color": Color(0.8, 0.6, 1.0), "fsize": 40})
	var neg: Node2D = FX.make(holder, "text", Vector2.ZERO, 0.9, {"text": "-5", "fsize": 40, "digits": true})
	for fx in [n, w, label, neg]:
		fx.set_process(false)
		fx._process(0.1)
	check(n.parts.size() == 2, "a damage number (digits opt-in) draws one sprite per digit")
	check(w.parts.is_empty(), "a name keeps the font path")
	check(label.parts.is_empty(), "a numeric label without the digits opt-in keeps the font path")
	check(neg.parts.is_empty(), "a signed number keeps the font path")
	var y0 := (n.parts[0] as Sprite2D).position.y
	n._process(0.3)
	check((n.parts[0] as Sprite2D).position.y < y0, "numerals rise")
	check((n.parts[0] as Sprite2D).modulate.a >= 0.99, "numerals hold full alpha for the first 60 percent")
	n._process(0.2)
	check((n.parts[0] as Sprite2D).modulate.a < 0.6, "numerals fade at the end")
	holder.queue_free()

# the second set: dust, sparkle, heal, boom, ko, swish and slash, impact
## One effect at `holder`, stepped by hand with no processing of its own.
func _make(holder: Node, kind: String, life: float, opts: Dictionary) -> Node2D:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var fx: Node2D = FX.make(holder, kind, Vector2.ZERO, life, opts)
	fx.set_process(false)
	return fx

func _holder() -> Node2D:
	var h := Node2D.new()
	root.add_child(h)
	return h

## Dust: puffs from BA's Smoke_02 on three held positions and six held sizes (grow, hold, shrink out), no alpha fade, the second
## and third puff smaller, odd seeds going left.
func _dust() -> void:
	var h := _holder()
	var d := _make(h, "dust", 0.45, {"seed": 0.0, "size": 1.0})
	var l := _make(h, "dust", 0.45, {"seed": 1.0, "size": 1.0})
	check(d.parts.size() == 3 and l.parts.size() == 3, "a dust node is three puffs")
	var xs := {}
	var sizes: Array = []
	var alphas_ok := true
	for i in 30:
		d._process(0.45 / 30.0)
		var p0: Sprite2D = d.parts[0]
		xs[roundi(p0.position.x)] = true
		sizes.append(p0.scale.x)
		alphas_ok = alphas_ok and p0.modulate.a == 1.0
	check(xs.size() <= 3, "the puff holds on at most three positions (%d)" % xs.size())
	check(alphas_ok, "a puff never fades: it stays opaque and shrinks out")
	var peak: float = sizes.max()
	check(float(sizes[0]) < 0.7 * peak and float(sizes[sizes.size() - 1]) < 0.55 * peak and float(sizes[sizes.size() - 1]) > 0.0, "it grows from small and shrinks out in steps (first %.3f, peak %.3f, last %.3f)" % [sizes[0], peak, sizes[sizes.size() - 1]])
	var distinct := {}
	for v in sizes:
		distinct[snappedf(float(v), 0.0001)] = true
	check(distinct.size() <= 6, "sizes are six held poses (%d)" % distinct.size())
	l._process(0.4)
	check((d.parts[0] as Sprite2D).position.x > 0.0 and (l.parts[0] as Sprite2D).position.x < 0.0, "an even seed throws dust right, an odd one left")
	check((d.parts[1] as Sprite2D).scale.x < (d.parts[0] as Sprite2D).scale.x and (d.parts[2] as Sprite2D).scale.x < (d.parts[1] as Sprite2D).scale.x, "the second and third puffs are smaller")
	check(float((d.parts[0] as Sprite2D).position.y) < 0.0, "puffs sit above the ground line")
	h.queue_free()
	var vp := _stage(300, 200, SNOW)
	var on_snow := await _shot(vp, "dust", 0.45, {"seed": 0.0, "size": 1.0}, 0.45)
	var grey := 0
	var white := 0
	for y in range(0, 200, 2):
		for x in range(0, 300, 2):
			var c := on_snow.get_pixel(x, y)
			if _diff(on_snow, Vector2(float(x), float(y)), SNOW) >= 0.25:
				grey += 1
	check(grey >= 200, "the grey rim of the puffs stands clear of snow (%d samples)" % grey)
	vp.queue_free()

## Sparkle: four held poses (small, big, mid, small), a darker rim larger than the body, a white flare on top.
func _sparkle() -> void:
	var h := _holder()
	var sp := _make(h, "sparkle", 0.6, {"color": Color(0.62, 0.93, 1.0), "size": 1.4})
	var seq: Array = []
	for i in 40:
		sp._process(0.6 / 40.0)
		var sc := roundi((sp.parts[1] as Sprite2D).scale.x / float((sp.parts[1] as Sprite2D).get_meta("base")) * 1000.0)
		if seq.is_empty() or seq[seq.size() - 1] != sc:
			seq.append(sc)
	check(seq == [350, 1000, 650, 300], "four held poses: small, big, mid, small (%s)" % str(seq))
	sp._process(0.0)
	sp.age = 0.3
	sp._process(0.0)
	var rim: Sprite2D = sp.parts[0]
	var body: Sprite2D = sp.parts[1]
	var flare: Sprite2D = sp.parts[2]
	check(rim.scale.x > body.scale.x and rim.modulate.get_luminance() < body.modulate.get_luminance(), "the rim is larger and darker than the body")
	check(flare.modulate == Color.WHITE, "the flare on top is white in any tint")
	check(body.modulate.b > body.modulate.r, "the body takes the tint")
	h.queue_free()

## Heal: pluses rise one after another and are gone by the end, a ground ellipse steps out, mint unless data["color"].
func _heal() -> void:
	var h := _holder()
	var he := _make(h, "heal", 1.1, {"seed": 1.0})
	check(he.parts.size() == 2 + 14 + 5, "a heal is a ring and its rim, seven pluses with rims and five stars (%d)" % he.parts.size())
	var on_counts: Array = []
	var y_track := {}
	var down := true
	for i in 40:
		he._process(1.1 / 40.0)
		var on := 0
		for j in 7:
			var plus: Sprite2D = he.parts[3 + 2 * j]
			if plus.modulate.a > 0.0:
				on += 1
				if y_track.has(j):
					down = down and plus.position.y <= float(y_track[j]) + 0.001
				y_track[j] = plus.position.y
		on_counts.append(on)
	check(int(on_counts[0]) == 0 and int(on_counts[39]) == 0, "no plus at the first tick or the last")
	check(on_counts.max() >= 3 and on_counts.max() <= 7, "several pluses are up at once, never more than seven (%d)" % on_counts.max())
	check(y_track.size() == 7, "every plus gets its turn (%d)" % y_track.size())
	check(down, "a plus only rises while it is up")
	he._process(0.0)
	he.age = 0.5
	he._process(0.0)
	var ring: Sprite2D = he.parts[0]
	check(ring.scale.y < ring.scale.x * 0.4, "the ring is a ground ellipse")
	check(ring.modulate.g > ring.modulate.r and ring.modulate.g > ring.modulate.b, "the heal is mint by default")
	var blue := _make(h, "heal", 1.1, {"seed": 1.0, "color": Color(0.4, 0.6, 1.0)})
	blue.age = 0.5
	blue._process(0.0)
	check((blue.parts[0] as Sprite2D).modulate.b > (blue.parts[0] as Sprite2D).modulate.g, "data[color] overrides the mint")
	h.queue_free()

## Boom: smoke frames in steps of three, fire on six held sizes growing then shrinking, a core that leaves early, a flash on the
## first poses, eight streaks, and radius scaling with size.
func _boom() -> void:
	var h := _holder()
	var b := _make(h, "boom", 0.5, {"color": Color(1.0, 0.55, 0.2), "size": 1.0, "seed": 1.0})
	var big := _make(h, "boom", 0.5, {"color": Color(1.0, 0.55, 0.2), "size": 2.0, "seed": 1.0})
	check(b.parts.size() == 9 + 8, "a boom is a ring and rim, three smoke puffs, fire rim, fire, core, a flash star and eight streaks (%d)" % b.parts.size())
	var frames := {}
	var fire: Array = []
	var core_gone_at := -1.0
	var flash_at: Array = []
	for i in 50:
		b._process(0.5 / 50.0)
		frames[(b.parts[2] as Sprite2D).frame] = true
		fire.append((b.parts[6] as Sprite2D).scale.x)
		if core_gone_at < 0.0 and (b.parts[7] as Sprite2D).modulate.a == 0.0:
			core_gone_at = float(i) / 50.0
		if (b.parts[8] as Sprite2D).modulate.a > 0.0:
			flash_at.append(i)
	var ok := true
	for f in frames:
		ok = ok and (int(f) % 3 <= 2 and int(f) <= 15)
	check(frames.size() <= 6 and ok, "the smoke plays at most six frames, every third (%s)" % str(frames.keys()))
	var peak_i := 0
	for i in fire.size():
		if fire[i] > fire[peak_i] + 0.0001:
			peak_i = i
	var up := true
	var dn := true
	for i in range(1, peak_i + 1):
		up = up and fire[i] >= fire[i - 1] - 0.00001
	for i in range(peak_i + 1, fire.size()):
		dn = dn and fire[i] <= fire[i - 1] + 0.00001
	check(up and dn and peak_i > 4 and peak_i < 40, "the fire grows to a peak and shrinks out (peak at step %d)" % peak_i)
	check(core_gone_at > 0.4 and core_gone_at < 0.7, "the pale core leaves after the first half (%.2f)" % core_gone_at)
	check(flash_at.size() > 0 and int(flash_at[flash_at.size() - 1]) < 25, "the flash star is only in the first poses (last at step %d)" % flash_at[flash_at.size() - 1])
	b.age = 0.2
	big.age = 0.2
	b._process(0.0)
	big._process(0.0)
	check(absf((big.parts[6] as Sprite2D).scale.x / (b.parts[6] as Sprite2D).scale.x - 2.0) < 0.01, "size 2 draws a fireball twice the width")
	check((b.parts[6] as Sprite2D).modulate.r > (b.parts[6] as Sprite2D).modulate.b, "the fire is the given colour, the smoke a dark grey")
	check((b.parts[2] as Sprite2D).modulate.get_luminance() < 0.4, "the smoke is dark")
	h.queue_free()

## KO: white cloud first, the colour after, eight radial focus lines, a band that thins, everything gone by the end.
func _ko() -> void:
	var h := _holder()
	var k := _make(h, "ko", 1.0, {"color": Color(1.0, 0.45, 0.4), "seed": 1.0})
	check(k.parts.size() == 4 + 2 + 1 + 8, "a K.O. burst is a band and spikes with rims, a cloud with its rim, a star and eight focus lines (%d)" % k.parts.size())
	k.age = 0.1
	k._process(0.0)
	check((k.parts[5] as Sprite2D).modulate == Color.WHITE, "the cloud starts white")
	k.age = 0.5
	k._process(0.0)
	var late := (k.parts[5] as Sprite2D).modulate
	check(late.r > late.b and late.a == 1.0, "and turns to the colour")
	var radial := true
	for i in 8:
		var s: Sprite2D = k.parts[7 + i]
		var ang: float = s.get_meta("ang")
		radial = radial and absf(angle_difference(s.position.angle(), ang)) < 0.001 and absf(angle_difference(s.rotation, ang + PI * 0.5)) < 0.001
	check(radial, "every focus line points along its own ray")
	var share: Array = []
	for t in [0.1, 0.4, 0.7]:
		k.age = t
		k._process(0.0)
		share.append((k.parts[0] as Sprite2D).modulate.a)
	check(share[0] > share[1] and share[1] > share[2], "the band thins as it grows (%s)" % str(share))
	k.age = 0.9
	k._process(0.0)
	check((k.parts[5] as Sprite2D).modulate.a == 0.0 and (k.parts[7] as Sprite2D).modulate.a == 0.0, "the cloud and the lines are gone at 90 percent")
	h.queue_free()

## Swish and slash: the window of the arc that shows moves in quarters (the head first, then the tail), a left-facing swing is the
## mirror of a right-facing one, and the ink stays on the arc.
func _swish() -> void:
	var B2: GDScript = load("res://scripts/fight/fx_kinds_art.gd")
	var heads: Array = []
	var tails: Array = []
	var okq := true
	for i in 101:
		var w: Vector2 = B2._window(float(i) / 100.0)
		heads.append(w.y)
		tails.append(w.x)
		okq = okq and absf(w.y * 4.0 - roundf(w.y * 4.0)) < 0.001 and absf(w.x * 4.0 - roundf(w.x * 4.0)) < 0.001
	var mono := true
	for i in range(1, 101):
		mono = mono and heads[i] >= heads[i - 1] and tails[i] >= tails[i - 1]
	check(okq and mono, "the visible window of the arc moves in quarters and never backs up")
	check(heads[0] == 0.25 and heads[60] == 1.0 and tails[0] == 0.0 and tails[100] > 0.0, "the head starts a quarter in, reaches the end by 60 percent, and the tail leaves after")
	var vp := _stage(480, 300, SNOW)
	var data := {"color": Color(0.9, 0.7, 0.4), "off": Vector2.ZERO, "r": 100.0, "thick": 30.0}
	var right := await _shot(vp, "swish", 0.3, data.merged({"dir": 1}), 0.4)
	var left := await _shot(vp, "swish", 0.3, data.merged({"dir": -1}), 0.4)
	right.flip_x()
	var ink := 0
	var off := 0
	for y in range(0, 300, 2):
		for x in range(2, 478, 2):
			var a := _diff(right, Vector2(float(x), float(y)), SNOW) >= 0.15
			var b := _diff(left, Vector2(float(x - 1), float(y)), SNOW) >= 0.15 or _diff(left, Vector2(float(x), float(y)), SNOW) >= 0.15 or _diff(left, Vector2(float(x + 1), float(y)), SNOW) >= 0.15
			if a:
				ink += 1
				if not b:
					off += 1
	check(ink >= 400, "a swing leaves a solid shape (%d samples)" % ink)
	check(off * 10 <= ink, "the left swing is the right one mirrored (%d of %d samples differ)" % [off, ink])
	var lo := 9999.0
	var hi := -9999.0
	var rows := 0
	for y in range(0, 300, 2):
		for x in range(0, 480, 2):
			if _diff(left, Vector2(float(x), float(y)), SNOW) >= 0.15:
				lo = minf(lo, float(x))
				hi = maxf(hi, float(x))
				rows += 1
	check(hi < 240.0 + 8.0 and lo > 240.0 - 150.0, "the left swing lies left of its owner (ink from x %.0f to %.0f)" % [lo, hi])
	vp.queue_free()
	var h := _holder()
	var sl := _make(h, "slash", 0.35, {"color": Color.WHITE, "dir": 1, "size": 2.0})
	var sw: Dictionary = B2._swing(sl)
	check(absf(float(sw["rad"]) - 260.0) < 0.01 and absf(float(sw["thick"]) - 52.0) < 0.01, "a slash defaults to a 130 px arc and 26 px blade per unit of size")
	check(sl.material != null and sl.parts.size() == 2, "a swing is drawn strips under a shared material with a head star of two sprites")
	h.queue_free()
	# A flat arc (2L: squash 0.4, thick 20) is tight: the strip must stay thinner than its curvature radius or the inner edge folds
	# and the engine fails to triangulate the segments.
	var flat := {"color": Color(0.9, 0.7, 0.4), "dir": 1, "off": Vector2.ZERO, "r": 90.0, "thick": 20.0, "squash": 0.4, "a0": -0.55, "a1": 0.5}
	var vp3 := _stage(480, 300, SNOW)
	var flat_img := await _shot(vp3, "swish", 0.3, flat, 0.4)
	var flat_ink := 0
	for y in range(0, 300, 2):
		for x in range(0, 480, 2):
			if _diff(flat_img, Vector2(float(x), float(y)), SNOW) >= 0.15:
				flat_ink += 1
	check(flat_ink >= 40, "a flat 2L arc draws a swing (%d samples)" % flat_ink)
	vp3.queue_free()
	var tight := {"rad": 90.0, "thick": 20.0, "sq": 0.4}
	check(B2._fit(tight) < 1.0 and B2._fit({"rad": 100.0, "thick": 30.0, "sq": 1.0}) == 1.0, "only a tight arc has its strip narrowed")

## Impact frame: an ink field with a white burst and white lines, refused inside 340 ms of the last one and while Reduce Flashes
## is on, freed at its life.
func _impact() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	FlashH().set("_last_impact_ms", -100000)
	var vp := _stage(480, 300, SNOW)
	var img := await _shot(vp, "impact", 0.2, {"seed": 1.0}, 0.1)
	var dark := 0
	var white := 0
	for y in range(0, 300, 3):
		for x in range(0, 480, 3):
			var c := img.get_pixel(x, y)
			if c.get_luminance() < 0.2:
				dark += 1
			if c.get_luminance() > 0.97:
				white += 1
	check(dark >= 4000 and img.get_pixel(2, 2).get_luminance() < 0.2 and img.get_pixel(477, 297).get_luminance() < 0.2, "the whole frame goes to ink, corners included (%d dark samples)" % dark)
	check(white >= 300, "with a white burst and lines on it (%d white samples)" % white)
	vp.queue_free()
	var h := _holder()
	FlashH().set("_last_impact_ms", -100000)
	var a := _make(h, "impact", 0.2, {"seed": 1.0})
	var b := _make(h, "impact", 0.2, {"seed": 2.0})
	check(a.parts.size() == 13 and a.visible, "an impact frame is a burst and twelve lines")
	check(b.parts.is_empty() and not b.visible, "a second one inside 340 ms is not built")
	FlashH().set("_last_impact_ms", -100000)
	var real: Object = Game_session()
	var stub := StubSession.new()
	set_session(stub)
	var c := _make(h, "impact", 0.2, {"seed": 3.0})
	set_session(real)
	check(c.parts.is_empty() and not c.visible, "with Reduce Flashes on it is not built")
	a._process(0.25)
	check(a.is_queued_for_deletion(), "it is freed at the end of its life")
	h.queue_free()

func Game_session() -> Object:
	return root.get_node("Game").session

func set_session(s: Object) -> void:
	root.get_node("Game").session = s

## Particles: a puff and a star draw BA's textures. A puff on a dark ground is white with a grey rim, and its size steps; a star is
## a coloured star with a white centre.
func _particles() -> void:
	var P: GDScript = load("res://scripts/fight/fx_particles.gd")
	var vp := _stage(200, 200, NAVY)
	var parts: Node2D = P.new()
	vp.add_child(parts)
	parts.emit(P.K.PUFF, Vector2(60, 100), Vector2.ZERO, 1.0, 20.0, Color.WHITE)
	parts.emit(P.K.STAR, Vector2(140, 100), Vector2.ZERO, 1.0, 20.0, Color(1.0, 0.5, 0.2))
	var sizes: Array = []
	for step in [0.1, 0.25, 0.4, 0.55, 0.7]:
		for p in parts._ps:
			p.age = step
		parts.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var puff := 0
		var star_c := 0
		for y in range(60, 140, 1):
			for x in range(20, 100, 1):
				if img.get_pixel(x, y).get_luminance() > 0.7:
					puff += 1
			for x in range(100, 180, 1):
				var c := img.get_pixel(x, y)
				if c.r > 0.8 and c.g > 0.35 and c.b < 0.4:
					star_c += 1
		sizes.append([puff, star_c])
	check(int(sizes[0][0]) > 100 and int(sizes[1][0]) > int(sizes[0][0]), "a puff draws and grows through its first poses (%s)" % str(sizes))
	check(int(sizes[4][0]) < int(sizes[2][0]), "and shrinks out at the end")
	check(int(sizes[1][1]) > 50, "a star draws in its colour (%d)" % int(sizes[1][1]))
	check(int(sizes[1][1]) > int(sizes[0][1]) and int(sizes[4][1]) < int(sizes[1][1]), "and twinkles: small, big, small")
	vp.queue_free()

## Reduce Flashes: the sight line stops pulsing at 11 Hz, and an impact frame is refused (above).
func _reduced() -> void:
	var vp := _stage(300, 120, NAVY)
	var real: Object = Game_session()
	var diffs: Array = []
	for reduced in [false, true]:
		set_session(StubSession.new() if reduced else real)
		var a := await _shot(vp, "sight", 0.35, {"dir": 1}, 0.01)
		var b := await _shot(vp, "sight", 0.35, {"dir": 1}, 0.03)
		var n := 0
		for y in range(40, 80):
			for x in range(0, 300, 2):
				if absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance()) > 0.03:
					n += 1
		diffs.append(n)
	set_session(real)
	check(int(diffs[0]) >= 4, "the sight line pulses (%d samples change in 20 ms)" % int(diffs[0]))
	check(int(diffs[1]) == 0, "and holds steady with Reduce Flashes on (%d)" % int(diffs[1]))
	vp.queue_free()

## The EX freeze switches off processing of the whole world layer: an effect inside it must not age, move or change, and must
## pick up where it stopped.
func _frozen() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var layer := Node2D.new()
	root.add_child(layer)
	var made: Array = []
	FlashH().set("_last_impact_ms", -100000)
	for kind in ALL_KINDS:
		var opts := {"color": Color(1.0, 0.6, 0.3), "seed": 2.0, "size": 1.0, "dir": 1, "text": "45", "digits": true}
		made.append(FX.make(layer, kind, Vector2.ZERO, 1.2, opts))
	for i in 4:
		await process_frame
	var before: Array = []
	for fx in made:
		before.append([fx.age, fx.parts.map(func(p: Sprite2D) -> Array: return [p.modulate, p.scale, p.position, p.frame])])
	layer.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 12:
		await process_frame
	var still := true
	var which := ""
	for i in made.size():
		var fx: Node2D = made[i]
		var now: Array = [fx.age, fx.parts.map(func(p: Sprite2D) -> Array: return [p.modulate, p.scale, p.position, p.frame])]
		if now != before[i] and not (before[i][0] >= 1.2):
			still = false
			which = str(fx.kind)
	check(still, "no effect ages or changes while its layer is frozen (first to move: %s)" % which)
	layer.process_mode = Node.PROCESS_MODE_INHERIT
	for i in 4:
		await process_frame
	var moved := 0
	for i in made.size():
		if (made[i] as Node2D).age > float(before[i][0]):
			moved += 1
	check(moved == made.size(), "and each picks up again when the layer thaws (%d of %d)" % [moved, made.size()])
	layer.queue_free()

const ALL_KINDS := ["spark", "block", "ring", "muzzle", "dust", "text", "sight", "charge", "heal", "slash", "speed", "boom", "ko", "swish", "sparkle", "flare"]

func _sweep() -> void:
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	var holder := Node2D.new()
	root.add_child(holder)
	var hostile := [
		{},
		{"size": 0.0, "color": Color(1, 1, 1, 0.0), "dir": -1},
		{"size": 5.0, "color": Color(2.0, 2.0, 2.0, 1.0), "dir": 1, "seed": 9999.0},
		{"text": "", "fsize": 1},
		{"text": "123456789", "fsize": 99, "color": Color(1, 0, 0)},
		{"text": "123456789", "fsize": 99, "digits": true},
		{"text": "-5", "fsize": 40, "digits": true},
		{"text": "", "fsize": 40, "digits": true},
	]
	for kind in ALL_KINDS:
		for opts in hostile:
			var fx: Node2D = FX.make(holder, kind, Vector2(100, 100), 0.4, opts)
			fx.set_process(false)
			fx._process(0.1)
			fx._process(0.15)
			check(is_instance_valid(fx) and not fx.is_queued_for_deletion(), "%s survives options %s mid-life" % [kind, str(opts)])
			fx._process(0.2)
			check(fx.is_queued_for_deletion(), "%s is freed at the end of its life" % kind)
	for kind in ALL_KINDS:
		var zero: Node2D = FX.make(holder, kind, Vector2(100, 100), 0.0, {"text": "5"})
		check(zero.life > 0.0 and is_finite(clampf(zero.age / zero.life, 0.0, 1.0)), "%s with a life of 0 still has a usable life" % kind)
	await process_frame
	# many at once: 60 sparks, stepped to the end, are all gone after one frame
	for i in 60:
		var s: Node2D = FX.make(holder, "spark", Vector2(float(i), 0.0), 0.22, {"seed": float(i), "size": 1.0})
		s.set_process(false)
		s._process(0.3)
	await process_frame
	await process_frame
	check(holder.get_child_count() == 0, "no effect nodes are left behind (%d)" % holder.get_child_count())
	holder.queue_free()

## Source checks: no TIME in the sprite shader or the kind code (the EX freeze stops world nodes), no glow blobs in converted kinds.
func _source() -> void:
	var sh := FileAccess.get_file_as_string("res://shaders/fx_sprite.gdshader")
	check(not sh.contains("TIME"), "the sprite shader does not read TIME")
	var kinds := FileAccess.get_file_as_string("res://scripts/fight/fx_kinds.gd")
	check(not kinds.contains("TIME") and not kinds.contains("Time.get"), "kind code does not read the clock")
	check(not kinds.contains("Fx.glow(") and not kinds.contains("draw_circle("), "converted kinds draw no glow blobs")
	var fxsrc := FileAccess.get_file_as_string("res://scripts/fight/fx.gd")
	for gone in ["func _d_spark(", "func _d_muzzle(", "func _d_ring(", "func _d_block(", "func _d_dust(", "func _d_heal(", "func _d_slash(", "func _d_boom(", "func _d_ko(", "func _d_swish(", "func _d_sparkle(", "func crescent("]:
		check(not fxsrc.contains(gone), gone + " is deleted from fx.gd")
	var b2 := FileAccess.get_file_as_string("res://scripts/fight/fx_kinds_art.gd")
	check(not b2.contains("TIME") and not b2.contains("Time.get"), "the second set of kinds does not read the clock")
	check(not b2.contains("Fx.glow(") and not b2.contains("draw_circle(") and not b2.contains("glow_disc"), "and draws no glow blobs")
	check(not b2.contains("draw_polygon("), "a swing is one triangle array, not a polygon per segment")
	var parts := FileAccess.get_file_as_string("res://scripts/fight/fx_particles.gd")
	var star_puff := parts.substr(parts.find("K.STAR:"), parts.find("## A twinkle") - parts.find("K.STAR:"))
	check(not star_puff.contains("Fx.glow(") and not star_puff.contains("draw_circle("), "stars and puffs of the particle pool draw no glow blobs")
	var kind_names := ["dust", "sparkle", "heal", "boom", "ko", "swish", "slash", "impact"]
	var KINDS: Array = (load("res://scripts/fight/fx_kinds.gd") as GDScript).KINDS
	for kn in kind_names:
		check(kn in KINDS, kn + " is a sprite kind")
		check(b2.contains('"' + kn + '"'), kn + " is built by fx_kinds_art.gd")
