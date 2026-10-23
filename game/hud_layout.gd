class_name HudLayout
extends RefCounted
## Keeps the map's heads-up panels off one another. The map is split into regions: the clock and alerts
## down the left edge, the attack card down the right, the building hand along the bottom (while
## building) and the blueprint draft wherever its window is (top middle at first). Each edge column gets
## the tallest stretch of its edge that the draft window and the hand leave free, and folds what doesn't
## fit there (ThreatCard.fit, Alerts.fit), so however busy the round or small the window, panels sit side
## by side or one under another, never on top. Only sums here; main.gd measures the panels and moves them.

## The gap kept between panels and from the map's edges.
const MARGIN := 8.0


## The tallest free stretch [top, bottom] of a column spanning x0..x1 between top and bottom, keeping
## MARGIN clear of every block (rects on the map, such as the draft window). The higher one wins a tie.
## Vector2(top, top) when blocks cover the whole column.
static func free_span(x0: float, x1: float, top: float, bottom: float, blocks: Array[Rect2]) -> Vector2:
	var spans: Array[Vector2] = [Vector2(top, bottom)]
	for b in blocks:
		if b.size.x <= 0.0 or b.size.y <= 0.0 or b.end.x <= x0 or b.position.x >= x1:
			continue
		var next: Array[Vector2] = []
		for s in spans:
			if b.end.y + MARGIN <= s.x or b.position.y - MARGIN >= s.y:
				next.append(s)
				continue
			if b.position.y - MARGIN > s.x:
				next.append(Vector2(s.x, b.position.y - MARGIN))
			if b.end.y + MARGIN < s.y:
				next.append(Vector2(b.end.y + MARGIN, s.y))
		spans = next
	var best := Vector2(top, top)
	for s in spans:
		if s.y - s.x > best.y - best.x:
			best = s
	return best
