class_name GameSettings
extends RefCounted
## The player's settings: screen, play and keys, plus which one-time tips they have seen. Saved to
## user://settings.cfg (in the browser that is the page's own storage), versioned like run records so
## a later build can read an older file. Nothing here touches the run's rules.

const PATH := "user://settings.cfg"
## Bump when the file's shape changes, and read older files in `load_saved`. 2: intro_seen.
const FORMAT := 2
## The keys a player can move, in the order the Settings screen lists them, with their names there.
const ACTIONS := {
	"pause": "Pause and play",
	"menu": "Menu",
	"tilt_map": "Tilt the map",
	"faster": "Faster",
	"slower": "Slower",
}
const DEFAULT_KEYS := {
	"pause": KEY_SPACE,
	"menu": KEY_ESCAPE,
	"tilt_map": KEY_V,
	"faster": KEY_BRACKETRIGHT,
	"slower": KEY_BRACKETLEFT,
}
const UI_SCALES := [0.8, 0.9, 1.0, 1.1, 1.2]

var fullscreen := false
var ui_scale := 1.0
## The speed each run starts at (one of TopBar.SPEEDS past 0).
var start_speed := 2
## The map closes in on the town as night falls (NightCamera).
var night_camera := true
## One-time tips while playing (FirstTips).
var tips := true
var tips_seen: Array = []
## How much the Elder speaks up (Advisor): "off", "urgent" (only when a problem costs this round) or "chatty".
var advisor := "urgent"
## The first-run camera tour has played (IntroTour); until it has, a new run opens on it and starts gently.
var intro_seen := false
var keys := DEFAULT_KEYS.duplicate()
## Off in tests, so they never write the player's settings.
var persist := true


static func load_saved() -> GameSettings:
	var s := GameSettings.new()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return s
	s.fullscreen = bool(cfg.get_value("screen", "fullscreen", s.fullscreen))
	s.ui_scale = float(cfg.get_value("screen", "ui_scale", s.ui_scale))
	s.start_speed = int(cfg.get_value("play", "start_speed", s.start_speed))
	s.night_camera = bool(cfg.get_value("play", "night_camera", s.night_camera))
	s.tips = bool(cfg.get_value("play", "tips", s.tips))
	s.advisor = str(cfg.get_value("play", "advisor", s.advisor))
	s.tips_seen = Array(cfg.get_value("play", "tips_seen", []))
	s.intro_seen = bool(cfg.get_value("play", "intro_seen", false))
	# Format 1's tips were paper notes; the highlights that replaced them start fresh, with the tour.
	if int(cfg.get_value("meta", "format", 1)) < 2:
		s.tips_seen = []
	for action: String in ACTIONS:
		s.keys[action] = int(cfg.get_value("keys", action, DEFAULT_KEYS[action]))
	return s


func save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "format", FORMAT)
	cfg.set_value("screen", "fullscreen", fullscreen)
	cfg.set_value("screen", "ui_scale", ui_scale)
	cfg.set_value("play", "start_speed", start_speed)
	cfg.set_value("play", "night_camera", night_camera)
	cfg.set_value("play", "tips", tips)
	cfg.set_value("play", "advisor", advisor)
	cfg.set_value("play", "tips_seen", tips_seen)
	cfg.set_value("play", "intro_seen", intro_seen)
	for action: String in ACTIONS:
		cfg.set_value("keys", action, keys[action])
	cfg.save(PATH)


## Puts the screen settings into effect on the game's window and the keys into the input map.
func apply(window: Window) -> void:
	apply_keys()
	if window == null or DisplayServer.get_name() == "headless":
		return
	window.content_scale_factor = ui_scale
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func apply_keys() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.keycode = keys[action] as Key
		InputMap.action_add_event(action, ev)


## Binds `action` to `keycode`; an action that had that key takes this one's old key, so no key does two
## things and none is left unbound.
func rebind(action: String, keycode: int) -> void:
	for other: String in keys:
		if other != action and int(keys[other]) == keycode:
			keys[other] = keys[action]
	keys[action] = keycode
	apply_keys()


## A key as its cap reads ("]" rather than "BracketRight"), for the settings, the menu and how a round works.
static func key_name(keycode: int) -> String:
	var printed := char(keycode) if keycode > 32 and keycode < 127 else ""
	return printed if printed != "" and not printed.is_valid_identifier() else OS.get_keycode_string(keycode as Key)
