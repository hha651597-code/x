extends Node
## Game-wide state and the screen router. Autoload "Game".
##
##   Game.go("select", params, "crest")   replace everything with a screen (history push), with a transition
##   Game.push("stage", params)            overlay a screen over the current one (which stays alive underneath)
##   Game.pop()                            remove the top overlay
##   Game.back()                           return along the history (or pop an overlay)

signal screen_changed(screen_name: String)

const SCREEN_PATHS := {
	"title": "res://scripts/screens/title_screen.gd",
	"menu": "res://scripts/screens/menu_screen.gd",
	"assign": "res://scripts/screens/assign_screen.gd",
	"select": "res://scripts/screens/select_screen.gd",
	"stage": "res://scripts/screens/stage_screen.gd",
	"vs": "res://scripts/screens/vs_screen.gd",
	"options": "res://scripts/screens/options_screen.gd",
	"fight": "res://scripts/fight/fight_screen.gd",
	"result": "res://scripts/screens/result_screen.gd",
	"gallery": "res://scripts/screens/gallery_screen.gd",
	"rigtest": "res://scripts/sprites/rig_test_screen.gd",
	"sdpreview": "res://scripts/models/sd_preview_screen.gd",
}

var roster := {}
var fighters: Array = []
var specials: Array = []
var by_id := {}
var session := Session.new()

var host: Control            # set by main.gd
var transition: Node         # set by main.gd (scripts/ui/transition.gd)
var stack: Array = []        # Screen nodes, bottom → top (overlays on top)
var history: Array = []      # [{name, params}] for back()
var busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_roster()
	Controls.action.connect(_on_action)

func _load_roster() -> void:
	var f := FileAccess.open("res://assets/ba/roster.json", FileAccess.READ)
	if f == null:
		push_error("roster.json missing")
		return
	roster = JSON.parse_string(f.get_as_text())
	fighters = roster.get("fighters", [])
	specials = roster.get("specials", [])
	for s in fighters + specials:
		by_id[int(s["id"])] = s

# ── routing ──────────────────────────────────────────────────────────────────
func current() -> Screen:
	return stack.back() if not stack.is_empty() else null

func current_name() -> String:
	var c := current()
	return c.screen_name if c else ""

func _make(screen_name: String) -> Screen:
	var path: String = SCREEN_PATHS.get(screen_name, "")
	if path == "" or not ResourceLoader.exists(path):
		push_error("unknown or missing screen: " + screen_name)
		return null
	var s: Screen = load(path).new()
	s.screen_name = screen_name
	return s

func _on_action(dev: String, act: String) -> void:
	if busy:
		return
	var c := current()
	if c and not c.covered:
		c.on_action(dev, act)

## First screen, no transition.
func start(screen_name := "menu", params := {}) -> void:
	_swap(screen_name, params, {"from": "", "back": false})

func _swap(screen_name: String, params: Dictionary, info: Dictionary) -> void:
	for s in stack:
		s.exit()
		s.queue_free()
	stack.clear()
	if screen_name != "fight":
		Controls.latch_repeats()
	var s := _make(screen_name)
	if s == null:
		return
	s.params = params
	host.add_child(s)
	stack.append(s)
	s.enter(params, info)
	screen_changed.emit(screen_name)

## Replace the whole stack with `screen_name`. style: "cut" | "fade" | "crest" (see transition.gd).
func go(screen_name: String, params := {}, style := "fade", opts := {}) -> bool:
	if busy:
		return false
	busy = true
	var from := current_name()
	history.append({"name": from, "params": current().params if current() else {}})
	if history.size() > 24:
		history.pop_front()
	await transition.play(style, opts, func(): _swap(screen_name, params, {"from": from, "back": false, "style": style}))
	busy = false
	return true

## Return to the previous screen in the history (or pop an overlay if one is up).
func back(style := "fade", opts := {}) -> bool:
	if busy:
		return false
	if stack.size() > 1:
		return await pop()
	if history.is_empty():
		return false
	var target: Dictionary = history.pop_back()
	if target["name"] == "":
		return false
	busy = true
	var from := current_name()
	await transition.play(style, opts, func(): _swap(target["name"], target["params"], {"from": from, "back": true}))
	busy = false
	return true

## Overlay a screen over the current one (the lower screen stays alive, covered).
func push(screen_name: String, params := {}) -> void:
	if busy:
		return
	var below := current()
	var s := _make(screen_name)
	if s == null:
		return
	s.params = params
	if below:
		below.set_covered(true)
	Controls.latch_repeats()
	host.add_child(s)
	stack.append(s)
	s.enter(params, {"overlay": true, "from": below.screen_name if below else "", "back": false})
	screen_changed.emit(screen_name)

## Remove the top overlay; the screen below resumes.
func pop() -> bool:
	if stack.size() < 2:
		return false
	var top: Screen = stack.pop_back()
	top.exit()
	top.queue_free()
	Controls.latch_repeats()
	var below := current()
	if below:
		below.set_covered(false)
		if below.has_method("resume"):
			below.call("resume")
	screen_changed.emit(below.screen_name if below else "")
	return true

# ── debug ────────────────────────────────────────────────────────────────────
func probe() -> Dictionary:
	var names := []
	var screens := {}
	for s in stack:
		names.append(s.screen_name)
		screens[s.screen_name] = s.probe()
	return {
		"stack": names,
		"history": history.map(func(h): return h["name"]),
		"busy": busy,
		"session": {"mode": session.mode, "players": session.players, "stage": session.stage.get("id", ""), "bgm": session.bgm},
		"screens": screens,
		"sfx": Sfx.played,
		"bgm": Bgm.probe(),
		"input": Controls.log,
	}
