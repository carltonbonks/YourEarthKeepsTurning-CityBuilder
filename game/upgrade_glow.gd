class_name UpgradeGlow
extends RefCounted
## Makes upgrades felt on the map (Yusuf, 2026-10-26): while an upgrade card is hovered, every building it would
## change glows gold and pulses (`hover_type`); when one is taken, those buildings flash and sparkle (`sparkle`).
## Only shows things: the upgrade itself is RunState.take_upgrade.

## How long a taken upgrade's sparkle lasts, in milliseconds.
const SPARKLE_MS := 2200.0
const GOLD := Color(1.0, 0.86, 0.4)

## The building type the hovered upgrade card changes ("" for none).
var hover_type := ""
## Sparkles playing: each {"type", "start"} (start in Time.get_ticks_msec()).
var _sparkles: Array[Dictionary] = []


## Starts the sparkle over every building of this type.
func sparkle(type: String, now: int) -> void:
	_sparkles.append({"type": type, "start": now})


func playing(now: int) -> bool:
	return _sparkles.any(func(s: Dictionary) -> bool: return now - int(s["start"]) < SPARKLE_MS)


## outline(bi) gives building bi's outline on screen; roof(bi) the middle of its roof on screen.
func draw(canvas: CanvasItem, run: RunState, now: int, outline: Callable, roof: Callable) -> void:
	_sparkles = _sparkles.filter(func(s: Dictionary) -> bool: return now - int(s["start"]) < SPARKLE_MS)
	var w := run.world
	if hover_type != "":
		var pulse := 0.5 + 0.5 * sin(now * 0.009)
		for bi in w.buildings.size():
			if w.buildings[bi]["type"] != hover_type:
				continue
			var shape: PackedVector2Array = outline.call(bi)
			canvas.draw_colored_polygon(shape, Color(GOLD, 0.25 + 0.3 * pulse))
			canvas.draw_polyline(_closed(shape), Color(GOLD, 0.7 + 0.3 * pulse), 3.0)
			var top: Vector2 = roof.call(bi)
			canvas.draw_arc(top, 18.0 + 8.0 * pulse, 0.0, TAU, 24, Color(GOLD, 0.5 + 0.4 * pulse), 2.5)
			# A bobbing arrow over each one, readable however far out the map is zoomed.
			var tip := top - Vector2(0.0, 22.0 + 6.0 * pulse)
			canvas.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-12, -18), tip + Vector2(12, -18)]), GOLD)
			canvas.draw_line(tip + Vector2(0, -18), tip + Vector2(0, -38), GOLD, 5.0)
	for s in _sparkles:
		var t := float(now - int(s["start"])) / SPARKLE_MS
		for bi in w.buildings.size():
			if w.buildings[bi]["type"] != s["type"]:
				continue
			var top: Vector2 = roof.call(bi)
			# A flash over the building first, then a ring opening out and stars rising and twinkling.
			var flash := clampf(1.0 - t * 4.0, 0.0, 1.0)
			if flash > 0.0:
				canvas.draw_colored_polygon(outline.call(bi), Color(1.0, 0.95, 0.75, 0.8 * flash))
			canvas.draw_arc(top, 10.0 + 70.0 * t, 0.0, TAU, 32, Color(GOLD, 0.9 * (1.0 - t)), 3.5)
			for k in 10:
				var angle := float(k) / 10.0 * TAU + float(bi) * 0.7
				var spread := 12.0 + 40.0 * t
				var at := top + Vector2(cos(angle) * spread, sin(angle) * spread * 0.6 - 60.0 * t * (0.6 + 0.4 * float(k % 3)))
				var twinkle := 0.5 + 0.5 * sin(now * 0.03 + k * 1.7)
				_star(canvas, at, 5.0 + 5.0 * twinkle, Color(1.0, 0.92, 0.6, (1.0 - t) * (0.5 + 0.5 * twinkle)))


static func _star(canvas: CanvasItem, at: Vector2, r: float, c: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.3, -r * 0.3), at + Vector2(r, 0),
		at + Vector2(r * 0.3, r * 0.3), at + Vector2(0, r), at + Vector2(-r * 0.3, r * 0.3), at + Vector2(-r, 0),
		at + Vector2(-r * 0.3, -r * 0.3)]), c)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
