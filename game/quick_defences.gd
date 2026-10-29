class_name QuickDefences
extends RefCounted
## The town's quick defences on the map (Yusuf, 2026-10-27): barricades thrown up in the gaps once raiders are
## spotted (World.barricades), a low timber block with a health bar, its outline marked out while folk are still
## raising it; and who spotted the raiders (World.spots), a "!" over the spotter, a ring opening from them and a
## faint line to what they saw. View only.

const LIFT := 5.0
## How long, in game seconds, the spotting ring takes to open, and how wide it gets in world units.
const RING_SECONDS := 1.2
const RING_REACH := 60.0
const ALARM := Color(1.0, 0.82, 0.29)


## Barricades on the ground, under everything standing.
func draw(view: ArenaView, run: RunState) -> void:
	var w := run.world
	if w.barricades.is_empty() and w.spots.is_empty():
		return
	var def: Dictionary = run.content.town["barricades"]
	var timber := Color(def["color"])
	for bi in w.barricades.size():
		var b: Dictionary = w.barricades[bi]
		var base := view._screen_poly(w.town.plot_outline(int(b["plot"])))
		var art := view._has_art("barricade")
		var facing := SpriteBook.facing_of(Vector2(b["pos"]), 8)
		var scale := view.sprites.building_scale("barricade", view._scale()) if art else 0.0
		if not b["built"]:
			var done := 1.0 - float(b["work_left"]) / float(def["work"])
			view.draw_colored_polygon(base, Color(timber, 0.15 + 0.45 * done))
			view.draw_polyline(view._closed(base), Color(timber.lightened(0.3), 0.8), 1.0)
			if art:
				view.sprites.draw(view, "barricade", view._to_screen(b["pos"]), scale, facing, Color(1, 1, 1, 0.2 + 0.5 * done))
			continue
		var health := health_of(w, bi)
		if art:
			# Stood across the gap like a gate, darkened once it is broken down.
			view.sprites.draw(view, "barricade", view._to_screen(b["pos"]), scale, facing,
				Color.WHITE if health > 0.0 else Color(0.35, 0.35, 0.35, 0.8))
			if health > 0.0:
				view._bar(view._to_screen(b["pos"]) - Vector2(10.0, view._lift(LIFT) + 8.0), 20.0, health, Color("#7cc46a"))
			continue
		var c := timber if health > 0.0 else timber.darkened(0.55)
		view._draw_block(base, view._lift(LIFT if health > 0.0 else 1.0), c, timber.darkened(0.6))
		if health > 0.0:
			view._bar(view._to_screen(b["pos"]) - Vector2(10.0, view._lift(LIFT) + 8.0), 20.0, health, Color("#7cc46a"))
	# Who spotted the raiders: a ring opening from them and a faint line to the raider they saw.
	for spot in w.spots:
		var age := w.time - float(spot["time"])
		var t := clampf(age / RING_SECONDS, 0.0, 1.0)
		if t < 1.0:
			var ring := view._ground_ring(spot["by"], maxf(1.0, RING_REACH * t), 32)
			ring.append(ring[0])
			view.draw_polyline(ring, Color(ALARM, 1.0 - t), 2.0)
		var fade := 1.0 - clampf(age / float(def["spot_show_seconds"]), 0.0, 1.0)
		view.draw_dashed_line(view._to_screen(spot["by"]), view._to_screen(spot["at"]), Color(ALARM, 0.45 * fade), 1.0, 4.0)


## The "!" over each spotter, on the top layer.
func draw_top(layer: CanvasItem, view: ArenaView, run: RunState, font: Font) -> void:
	var w := run.world
	for spot in w.spots:
		var fade := 1.0 - clampf((w.time - float(spot["time"])) / float(run.content.town["barricades"]["spot_show_seconds"]), 0.0, 1.0)
		var at := view._to_screen(spot["by"]) - Vector2(4.0, 18.0)
		layer.draw_string_outline(font, at, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0, 0, 0, 0.8 * fade))
		layer.draw_string(font, at, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ALARM, fade))


## How whole barricade b is, 0..1 (its weakest square).
static func health_of(w: World, bi: int) -> float:
	var worst := 1.0
	var hp := float(w.run.content.town["barricades"]["hp"])
	for i: int in w.barricade_square:
		if int(w.barricade_square[i]) == bi:
			worst = minf(worst, w.pathing.wall_hp[i] / hp)
	return worst
