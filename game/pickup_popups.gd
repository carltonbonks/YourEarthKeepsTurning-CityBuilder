class_name PickupPopups
extends RefCounted
## The "+2 stone" popups that rise over the hearth as goods are carried in. View only: it compares the world's
## running `brought_in` tally with what it saw last time, so it never changes the run.
## Hauls are gathered into one popup every BUCKET_MS of real time (one line per good, biggest first), so at 8x speed
## the hearth shows a few bigger numbers rather than a cloud of little ones, and drawing stays cheap.

const BUCKET_MS := 1500.0
## How long a popup takes to rise and fade, and how far it rises, in screen pixels.
const RISE_MS := 2400.0
const RISE_PX := 34.0
## At most this many popups in the air at once; the oldest goes first.
const MAX_LIVE := 3
## At most this many goods per popup; the rest are summed into "+N more".
const MAX_LINES := 4
const FONT_SIZE := 15
const LINE_PX := 16.0

var _world: World
var _seen := {}
var _next_ms := 0.0
## Live popups: {lines: [[text, good]], born: ms}.
var popups: Array[Dictionary] = []


## Call every frame. A new world (a new run) starts the tally afresh rather than showing everything it already holds.
func update(w: World, now_ms: float) -> void:
	if w != _world:
		_world = w
		_seen = w.brought_in.duplicate()
		_next_ms = now_ms + BUCKET_MS
		popups.clear()
		return
	while not popups.is_empty() and now_ms - float(popups[0]["born"]) >= RISE_MS:
		popups.pop_front()
	if now_ms < _next_ms:
		return
	_next_ms = now_ms + BUCKET_MS
	var lines := gained(_seen, w.brought_in)
	_seen = w.brought_in.duplicate()
	if lines.is_empty():
		return
	popups.append({"lines": lines, "born": now_ms})
	if popups.size() > MAX_LIVE:
		popups.pop_front()


## What was brought in between two tallies, as [[text, good]] lines, biggest first.
static func gained(before: Dictionary, now: Dictionary) -> Array:
	var got: Array = []
	for good: String in now:
		var n := int(now[good]) - int(before.get(good, 0))
		if n > 0:
			got.append([n, good])
	got.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var lines: Array = []
	var rest := 0
	for i in got.size():
		if i < MAX_LINES:
			lines.append(["+%d %s" % [got[i][0], String(got[i][1]).replace("_", " ")], got[i][1]])
		else:
			rest += int(got[i][0])
	if rest > 0:
		lines.append(["+%d more" % rest, ""])
	return lines


## Draws the live popups rising from `at` (screen position). `color_of` gives a good's colour as a hex string.
func draw(view: CanvasItem, at: Vector2, font: Font, now_ms: float, color_of: Callable) -> void:
	for popup in popups:
		var t := clampf((now_ms - float(popup["born"])) / RISE_MS, 0.0, 1.0)
		var alpha := 1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4
		var lines: Array = popup["lines"]
		var top := at.y - RISE_PX * t - LINE_PX * float(lines.size() - 1)
		for i in lines.size():
			var text: String = lines[i][0]
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			var p := Vector2(at.x - width * 0.5, top + LINE_PX * i)
			var c := Color(color_of.call(lines[i][1]) if lines[i][1] != "" else "#e8e4d8")
			view.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 3, Color(0, 0, 0, 0.75 * alpha))
			view.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(c, alpha))
