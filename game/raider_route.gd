class_name RaiderRoute
extends RefCounted
## The way tonight's warned attack will come (Yusuf, 2026-10-27): a faint red line that draws itself from the
## map's edge to the hearth along the raiders' own route (World.raider_routes), holds, fades and draws again.
## Where it crosses the turning ring it takes on that plate's look (data/plates.json route_looks: the Fen wavy,
## the Greenwood faint dots, the Stonefield bold chevrons, the Barrow crosses) with the plate's few words beside
## it, so when the ring turns under the line the crossing repaints with it. It shows from the build until the
## wave sets off and is for the player alone: townsfolk only know what they spot (FolkAI.raise_alarm). View only.
## Timings are in real milliseconds.

const DRAW_MS := 2600.0
const HOLD_MS := 2200.0
const FADE_MS := 700.0
## A second way's line starts this much later than the first.
const STAGGER_MS := 900.0
## Spacing along the line, in world units: samples, dashes and marks.
const STEP := 3.0
const DASH := 12.0
const DASH_ON := 7.0
const MARK_EVERY := 14.0
const RED := Color(0.82, 0.28, 0.24)
## How strong the line is by day, and as the attack night falls.
const ALPHA := 0.6
const ALPHA_DUSK := 0.9


## True while there is a warned attack still to come this round.
static func showing(run: RunState) -> bool:
	var w := run.world
	if w.wave_sides.is_empty():
		return false
	# Last round's wave has spawned until this round begins, so the build always shows the line.
	return run.phase == RunState.Phase.BUILD or (run.phase in [RunState.Phase.PICK, RunState.Phase.SIM] and not w.wave_spawned)


## Draws every way's line on the map, under everything standing. `slide` is how far the near ring is still drawn
## short of where it lies (ArenaView._slide_angle), so the crossing matches the plates as the player sees them.
func draw(view: ArenaView, run: RunState, now_ms: float, slide: float) -> void:
	if not showing(run):
		return
	var w := run.world
	var routes := w.raider_routes()
	var dusk := w.is_dusk() and w.day_index() == run.content.int_num("days_per_round") - 1
	for k in routes.size():
		var t := fmod(now_ms - k * STAGGER_MS + 100000.0, DRAW_MS + HOLD_MS + FADE_MS)
		var shown := 1.0 - pow(1.0 - clampf(t / DRAW_MS, 0.0, 1.0), 2.0)
		var alpha := (ALPHA_DUSK if dusk else ALPHA) * (1.0 - clampf((t - DRAW_MS - HOLD_MS) / FADE_MS, 0.0, 1.0))
		_draw_route(view, run, _samples(routes[k]), shown, alpha, slide)


## The crossing's label for each way ("Fen: raiders wade slowly under your towers"), on the top layer so the
## night and the buildings never hide it. It shows once the line has drawn past the crossing.
func draw_labels(layer: CanvasItem, view: ArenaView, run: RunState, font: Font, now_ms: float, slide: float) -> void:
	if not showing(run):
		return
	var routes := run.world.raider_routes()
	for k in routes.size():
		var t := fmod(now_ms - k * STAGGER_MS + 100000.0, DRAW_MS + HOLD_MS + FADE_MS)
		var samples := _samples(routes[k])
		var crossing := _crossing(run, samples, slide)
		if crossing.is_empty():
			continue
		var at_share := float(crossing["start"]) / maxf(1.0, samples.size() - 1.0)
		var shown := 1.0 - pow(1.0 - clampf(t / DRAW_MS, 0.0, 1.0), 2.0)
		var a := clampf((shown - at_share) * 6.0, 0.0, 1.0) * (1.0 - clampf((t - DRAW_MS - HOLD_MS) / FADE_MS, 0.0, 1.0))
		if a <= 0.0:
			continue
		var kind: String = crossing["kind"]
		var kd := run.world.earth.kind_def(kind)
		var text := "%s: %s" % [kd.get("name", kind), kd.get("short", "")]
		var look := _look(run, kind)
		var p := view._to_screen(samples[int(crossing["mid"])]) + Vector2(14.0, -10.0)
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
		# Keep it on the map.
		p.x = clampf(p.x, 4.0, view.size.x - size.x - 10.0)
		p.y = clampf(p.y, size.y + 4.0, view.size.y - 6.0)
		var box := Rect2(p - Vector2(6.0, size.y - 1.0), size + Vector2(12.0, 6.0))
		layer.draw_rect(box, Color(0.06, 0.08, 0.05, 0.85 * a))
		layer.draw_rect(box, Color(look["color"], a), false, 1.0)
		layer.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.92, 0.82, a))


## The route as evenly spaced points, stopping short of the hearth.
static func _samples(route: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if route.size() < 2:
		return out
	for n in route.size() - 1:
		var a := route[n]
		var b := route[n + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / STEP))
		for s in steps:
			out.append(a.lerp(b, float(s) / steps))
	out.append(route[route.size() - 1])
	var stop := World.HEARTH_RADIUS + 6.0
	while out.size() > 2 and out[out.size() - 1].length() < stop:
		out.remove_at(out.size() - 1)
	return out


## The near plate's kind under ground point p as the player sees the plates now ("" off the ring).
static func _kind(run: RunState, p: Vector2, slide: float) -> String:
	return run.world.earth.kind_at(p.rotated(-slide))


## The first stretch of samples on the ring: {kind, start, mid}, or {} if the way never crosses it.
func _crossing(run: RunState, samples: PackedVector2Array, slide: float) -> Dictionary:
	var start := -1
	for n in samples.size():
		var kind := _kind(run, samples[n], slide)
		if start < 0 and kind != "":
			start = n
		elif start >= 0 and kind != _kind(run, samples[start], slide):
			return {"kind": _kind(run, samples[start], slide), "start": start, "mid": (start + n) / 2}
	return {} if start < 0 else {"kind": _kind(run, samples[start], slide), "start": start, "mid": (start + samples.size()) / 2}


static func _look(run: RunState, kind: String) -> Dictionary:
	return run.content.plates.get("route_looks", {}).get(kind, {"color": "#d0483f", "line": "plain"})


func _draw_route(view: ArenaView, run: RunState, samples: PackedVector2Array, shown: float, alpha: float, slide: float) -> void:
	if samples.size() < 2 or alpha <= 0.0:
		return
	var last := int((samples.size() - 1) * shown)
	for n in last:
		var a := samples[n]
		var b := samples[n + 1]
		var along := n * STEP
		var kind := _kind(run, a, slide)
		var sa := view._to_screen(a)
		var sb := view._to_screen(b)
		if kind == "":
			if fmod(along, DASH) < DASH_ON:
				view.draw_line(sa, sb, Color(RED, alpha), 2.4)
			continue
		var look := _look(run, kind)
		var c := Color(look["color"])
		var dir := (b - a).normalized()
		match look["line"]:
			"wave":
				var off := dir.orthogonal() * 3.2
				view.draw_line(view._to_screen(a + off * sin(along / 4.0)), view._to_screen(b + off * sin((along + STEP) / 4.0)), Color(c, alpha), 3.0)
			"dots":
				if fmod(along, 9.0) < STEP:
					view.draw_circle(sa, 2.0, Color(c, alpha * 0.6))
			"chevrons":
				view.draw_line(sa, sb, Color(c, alpha), 3.4)
				if fmod(along, MARK_EVERY) < STEP:
					var side := dir.orthogonal() * 4.5
					var tip := view._to_screen(a + dir * 2.0)
					view.draw_polyline(PackedVector2Array([view._to_screen(a - dir * 3.0 + side), tip, view._to_screen(a - dir * 3.0 - side)]),
						Color(1.0, 0.82, 0.62, alpha), 1.6)
			"crosses":
				if fmod(along, 8.0) < 5.0:
					view.draw_line(sa, sb, Color(c, alpha), 3.0)
				if fmod(along, MARK_EVERY) < STEP:
					var cross := Color(0.92, 0.86, 0.95, alpha)
					view.draw_line(sa + Vector2(-4, -4), sa + Vector2(4, 4), cross, 1.6)
					view.draw_line(sa + Vector2(4, -4), sa + Vector2(-4, 4), cross, 1.6)
			_:
				view.draw_line(sa, sb, Color(c, alpha), 2.0)
	# The head: an arrow on the drawn end, pointing the way the raiders walk.
	if last >= 1:
		var head := view._to_screen(samples[last])
		var back := view._to_screen(samples[maxi(0, last - 3)])
		var dir := (head - back).normalized()
		if dir != Vector2.ZERO:
			var side := dir.orthogonal() * 5.0
			view.draw_colored_polygon(PackedVector2Array([head + dir * 4.0, head - dir * 6.0 + side, head - dir * 6.0 - side]), Color(RED, minf(1.0, alpha + 0.2)))
