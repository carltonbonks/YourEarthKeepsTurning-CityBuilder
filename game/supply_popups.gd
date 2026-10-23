class_name SupplyPopups
extends RefCounted
## "+smoked meat" popups that rise where a runner hands supplies to a hero out in the wilds. View only: it compares the
## world's running `supplies_delivered` count with what it saw last frame and reads the newest `supply_drops`.

const RISE_MS := 2200.0
const RISE_PX := 30.0
const FONT_SIZE := 14
const COLOR := Color("#e8c890")

var _world: World
var _seen := 0
## Live popups: {pos (world), text, born (ms)}.
var popups: Array[Dictionary] = []


## Call every frame. A new world (a new run) starts afresh.
func update(w: World, now_ms: float) -> void:
	if w != _world:
		_world = w
		_seen = w.supplies_delivered
		popups.clear()
		return
	while not popups.is_empty() and now_ms - float(popups[0]["born"]) >= RISE_MS:
		popups.pop_front()
	var fresh := mini(w.supplies_delivered - _seen, w.supply_drops.size())
	for i in range(w.supply_drops.size() - fresh, w.supply_drops.size()):
		var drop: Dictionary = w.supply_drops[i]
		popups.append({"pos": drop["pos"], "text": drop["text"], "born": now_ms})
	_seen = w.supplies_delivered


## Draws the live popups; `to_screen` maps a world position to the screen.
func draw(view: CanvasItem, font: Font, now_ms: float, to_screen: Callable) -> void:
	for popup in popups:
		var t := clampf((now_ms - float(popup["born"])) / RISE_MS, 0.0, 1.0)
		var alpha := 1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4
		var text: String = popup["text"]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var at: Vector2 = to_screen.call(popup["pos"])
		var p := Vector2(at.x - width * 0.5, at.y - 14.0 - RISE_PX * t)
		view.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color(0, 0, 0, 0.75 * alpha))
		view.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(COLOR, alpha))
