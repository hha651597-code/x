extends SceneTree
## Fx contact sheets: every sprite-based kind in a 5 by 3 grid, once on a bright ground (a snow stage) and once on a dark one,
## at three moments of each effect's life. Two pages: the first set (hits, muzzles, rings, blocks, numerals) and the second
## (dust, sparkles, heals, explosions, the K.O. burst, melee swings, the impact frame). Each Fx is stepped by hand, so the frames are exact. The hit_* cells spawn a star
## and its ring the way the game does (Fx.spark, and fight_screen's explosion pair) and step both by the same age.
## Each effect is scaled to fit its 256 x 240 cell from the reach of its layers over the three moments (never above 0.6), so
## sizes are not comparable between cells. Ink on a cell border means something still runs out of its cell: it prints
## GALLERY_CLIP and the script exits 1.
## Run: zsh tools/fx_gallery.sh   ->   tmp/fx_gallery_<bright|dark>_<0..2>.png and fx_gallery2_<...>.png (1280x720)

const PAGE_1 := [
	["spark", 0.22, {"color": Color(1.0, 0.93, 0.55), "size": 1.0, "seed": 1.0, "dir": 1}],
	["spark", 0.32, {"color": Color(1.0, 0.66, 0.22), "size": 1.6, "seed": 2.0, "dir": 1}],
	["spark", 0.46, {"color": Color(0.62, 0.93, 1.0), "size": 2.5, "seed": 3.0, "dir": 1}],
	["hit_heavy", 0.32, {"seed": 2.0}],
	["hit_ex", 0.46, {"seed": 3.0}],
	["hit_boom", 0.35, {"seed": 2.0, "radius": 80.0}],
	["muzzle", 0.14, {"color": Color(1.0, 0.8, 0.4), "size": 1.6, "dir": 1, "seed": 1.0}],
	["muzzle", 0.14, {"color": Color(1.0, 0.8, 0.4), "size": 1.6, "dir": -1, "seed": 1.0}],
	["ring", 0.35, {"color": Color(1.0, 0.8, 0.4), "size": 1.0, "seed": 1.0}],
	["ring", 0.5, {"color": Color(0.62, 0.93, 1.0), "size": 0.3, "seed": 2.0}],
	["block", 0.3, {"dir": 1, "seed": 1.0}],
	["block", 0.3, {"dir": -1, "seed": 1.0}],
	["text", 0.7, {"text": "45", "color": Color(1.0, 0.95, 0.6), "fsize": 44, "digits": true}],
	["text", 0.7, {"text": "15", "color": Color(1.0, 1.0, 1.0), "fsize": 32, "digits": true}],
	["text", 0.9, {"text": "LOCK & LOAD", "color": Color(0.8, 0.6, 1.0), "fsize": 40}],
]
const PAGE_2 := [
	["dust3", 0.45, {"seed": 0.0}],
	["dust", 0.45, {"seed": 1.0, "spread": 1.8, "drift": 1.0, "size": 1.3, "at": Vector2(0.0, 40.0)}],
	["sparkle", 0.6, {"color": Color(1.0, 1.0, 1.0), "size": 1.4, "seed": 1.0}],
	["sparkle", 0.6, {"color": Color(0.62, 0.93, 1.0), "size": 1.4, "seed": 2.0}],
	["heal", 1.1, {"seed": 1.0, "at": Vector2(0.0, 100.0)}],
	["boom", 0.5, {"color": Color(1.0, 0.55, 0.2), "size": 0.8, "seed": 1.0}],
	["boom", 0.6, {"color": Color(1.0, 0.45, 0.25), "size": 1.4, "seed": 2.0}],
	["ko", 1.0, {"color": Color(1.0, 0.45, 0.4), "seed": 1.0}],
	["swish", 0.3, {"color": Color(0.9, 0.7, 0.4), "dir": 1, "r": 110.0, "thick": 30.0}],
	["swish", 0.3, {"color": Color(0.6, 0.85, 1.0), "dir": -1, "r": 110.0, "thick": 30.0}],
	["swish", 0.4, {"color": Color(1.0, 0.6, 0.7), "dir": 1, "r": 120.0, "a0": -2.0, "a1": 0.3, "thick": 44.0, "squash": 0.8}],
	["slash", 0.35, {"color": Color(1.0, 1.0, 1.0), "dir": 1, "size": 1.0}],
	["slash", 0.35, {"color": Color(0.7, 0.9, 1.0), "dir": -1, "size": 1.0}],
	["impact", 0.2, {"seed": 1.0, "size": 0.3, "field": 330.0}],
]
const PAGES := [PAGE_1, PAGE_2]
const MOMENTS := [0.15, 0.4, 0.7]       # fractions of each effect's life
const GROUNDS := {"bright": Color(0.91, 0.95, 0.97), "dark": Color(0.07, 0.14, 0.23)}
const COLS := 5
const CELL := Vector2(256.0, 240.0)
const FIT := Vector2(118.0, 112.0)     # half the room a cell gives an effect, less a margin

func _initialize() -> void:
	call_deferred("_run")

## Spawns one cell's effect into `parent` and steps every Fx it made to `frac` of the cell's life (one age for all of them).
func _spawn(FX: GDScript, parent: Node, spec: Array, frac: float) -> void:
	match spec[0]:
		"hit_heavy", "hit_ex":
			FX.spark(parent, Vector2.ZERO, str(spec[0]).trim_prefix("hit_"), 1, float(spec[2]["seed"]))
		"impact":      # the rate limit (3 a second) would refuse most of a sheet's impact frames
			(load("res://scripts/fight/fx_flash.gd") as GDScript).set("_last_impact_ms", -100000)
			FX.make(parent, "impact", spec[2].get("at", Vector2.ZERO), spec[1], spec[2])
		"dust3":      # fight_screen.fx_dust: three nodes at one spot, odd seeds go left
			for i in 3:
				FX.make(parent, "dust", Vector2(0.0, 50.0), float(spec[1]), {"seed": float(i), "size": 1.0})
		"hit_boom":
			var r := float(spec[2]["radius"])      # fight_screen.spawn_blast: the ring first, then the star
			FX.make(parent, "ring", Vector2.ZERO, 0.35, {"color": Color(1.0, 0.5, 0.2), "size": r / 120.0})
			FX.make(parent, "spark", Vector2.ZERO, 0.3, {"color": Color(1.0, 0.8, 0.4), "size": r / 60.0, "seed": float(spec[2]["seed"])})
		_:
			FX.make(parent, spec[0], spec[2].get("at", Vector2.ZERO), spec[1], spec[2])
	for fx in parent.get_children():
		fx.set_process(false)
	for fx in parent.get_children():
		fx._process(float(spec[1]) * frac)

## How far from its origin, in x and y, any layer that shows reaches at any of the three moments.
func _reach(FX: GDScript, spec: Array) -> Vector2:
	var B2: GDScript = load("res://scripts/fight/fx_kinds_art.gd")
	var reach := Vector2.ZERO
	for m in MOMENTS:
		var probe := Node2D.new()
		root.add_child(probe)
		_spawn(FX, probe, spec, float(m))
		for fx in probe.get_children():
			var drawn: Vector2 = B2.drawn_reach(fx)
			reach = Vector2(maxf(reach.x, absf(fx.position.x) + drawn.x), maxf(reach.y, absf(fx.position.y) + drawn.y))
			for p in fx.parts:
				var sp := p as Sprite2D
				if not sp.visible or sp.modulate.a < 0.05:
					continue
				var r := sp.get_rect()
				for c in [r.position, r.position + Vector2(r.size.x, 0.0), r.end, r.position + Vector2(0.0, r.size.y)]:
					var q: Vector2 = fx.position + sp.transform * c
					reach = Vector2(maxf(reach.x, absf(q.x)), maxf(reach.y, absf(q.y)))
		probe.free()
	return reach

## Cells with ink on their outermost two pixels.
func _clipped(img: Image, g: Color, kinds: Array) -> Array:
	var out: Array = []
	for i in kinds.size():
		var x0 := (i % COLS) * int(CELL.x)
		var y0 := (i / COLS) * int(CELL.y)
		var hit := false
		for t in 2:
			for a in range(0, int(CELL.x)):
				hit = hit or _ink(img, x0 + a, y0 + t, g) or _ink(img, x0 + a, y0 + int(CELL.y) - 1 - t, g)
			for a in range(0, int(CELL.y)):
				hit = hit or _ink(img, x0 + t, y0 + a, g) or _ink(img, x0 + int(CELL.x) - 1 - t, y0 + a, g)
		if hit:
			out.append(i)
	return out

func _ink(img: Image, x: int, y: int, g: Color) -> bool:
	var c := img.get_pixel(x, y)
	return maxf(absf(c.r - g.r), maxf(absf(c.g - g.g), absf(c.b - g.b))) >= 0.05

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(3))
	await process_frame
	var FX: GDScript = load("res://scripts/fight/fx.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp"))
	var clipped := 0
	for page in PAGES.size():
		var kinds: Array = PAGES[page]
		var fit: Array = []
		for spec in kinds:
			var reach := _reach(FX, spec)
			fit.append(minf(0.6, minf(FIT.x / maxf(reach.x, 1.0), FIT.y / maxf(reach.y, 1.0))))
		for ground in GROUNDS:
			for m in MOMENTS.size():
				var world := Node2D.new()
				root.add_child(world)
				var bg := ColorRect.new()
				bg.color = GROUNDS[ground]
				bg.size = Vector2(1280.0, 720.0)
				world.add_child(bg)
				for i in kinds.size():
					var cell := Vector2(float(i % COLS) * CELL.x, float(i / COLS) * CELL.y)
					var holder := Node2D.new()
					holder.position = cell + CELL * 0.5
					holder.scale = Vector2.ONE * float(fit[i])
					world.add_child(holder)
					_spawn(FX, holder, kinds[i], float(MOMENTS[m]))
				for i in 3:
					await process_frame
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				img.save_png("res://tmp/fx_gallery%s_%s_%d.png" % ["" if page == 0 else str(page + 1), ground, m])
				for i in _clipped(img, GROUNDS[ground], kinds):
					print("GALLERY_CLIP page ", page + 1, " ", ground, " moment ", m, " cell ", i, " (", kinds[i][0], ")")
					clipped += 1
				world.queue_free()
				await process_frame
	print("fx_gallery: done, ", clipped, " clipped cells")
	quit(1 if clipped > 0 else 0)
