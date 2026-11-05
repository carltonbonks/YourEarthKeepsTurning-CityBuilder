class_name DraftStage
extends RefCounted
## The blueprint draft as a scene in the town (picks in the town, slice 3; Yusuf, 2026-11-05). The camera pulls out
## to the whole town, low in the map, and each offer's card floats in a row above it on a leader line down to where it
## would go: a ghost of the building on the plot it would place itself on (Town.choose_plot), a craft's workshop on
## its plot, an upgrade's building lit, an outpost by its far node, clearing a ring the new ring lit all round.
## Overlays lays the cards out (`layout`) and owns them; this draws the ghosts, the lights and the leader lines and
## moves the camera. View only: nothing here is placed or saved.

const GLIDE_MS := 900.0
const LEAVE_MS := 600.0
## The gap between neighbouring cards and the map's sides (px).
const GAP := 12.0
const EDGE := 16.0
## The space between the cards and the top of the town (px), for the leader lines.
const LEAD := 26.0
## Cards shrink to fit down to this, below which the classic pop-up shows.
const MIN_SCALE := 0.6
## The share of the map's height kept for the town under the cards.
const TOWN := 0.35
## How much bigger than the room under the cards the town is drawn: its far edge may pass under them.
const SPILL := 1.3
## The farthest the camera pulls out (below the player's own zoom range, so a big town still fits).
const FAR_ZOOM := 0.6
const GOLD := Color(1.0, 0.85, 0.35)
const LINE := Color(0.95, 0.88, 0.62)

## When the scene began (ms), or -1 when there is none.
var born := -1.0
## When the draft was done (ms), or -1 while the player chooses.
var ended := -1.0
## Each offer's place: {at (ground point), ghost (building type drawn there, or ""), plot (or -1), lit (a building
## type to light), ring (radius of a ring to light, or 0)}, in the cards' order.
var anchors: Array = []
## Where each card's foot is on screen (the arena's coordinates), in the cards' order, for the leader lines.
var feet: Array = []
var _from_zoom := 1.0
var _from_pan := Vector2.ZERO
var _to_zoom := 1.0
var _to_pan := Vector2.ZERO


func active() -> bool:
	return born >= 0.0


func choosing() -> bool:
	return active() and ended < 0.0


## Where one draft offer would go. `target` is BuildHandView.draft_entries' second half: {building}, {craft},
## {upgrade} or {ring}.
static func anchor(run: RunState, target: Dictionary) -> Dictionary:
	var town := run.world.town
	var out := {"at": Vector2.ZERO, "ghost": "", "plot": -1, "lit": "", "ring": 0.0, "placed": true, "far": false}
	if target.has("ring"):
		var rings: Array = run.content.town["rings"]
		var r := float(rings[mini(run.rings_open, rings.size() - 1)]["radius"])
		out["ring"] = r
		# The ring's far side, straight up the screen from the hearth.
		out["at"] = Vector2(-1.0, -1.0).normalized() * r
		return out
	if target.has("upgrade"):
		var type: String = run.content.upgrades[target["upgrade"]]["building"]
		out["lit"] = type
		var best := -1
		for i in run.world.buildings.size():
			var b: Dictionary = run.world.buildings[i]
			# The one highest on screen, nearest the cards.
			var p := Vector2(b["pos"])
			if b["type"] == type and (best < 0 or p.x + p.y < Vector2(run.world.buildings[best]["pos"]).x + Vector2(run.world.buildings[best]["pos"]).y):
				best = i
		if best >= 0:
			out["at"] = run.world.buildings[best]["pos"]
		else:
			out["placed"] = false
		return out
	var type: String = run.content.crafts[target["craft"]]["workshop"] if target.has("craft") else target["building"]
	out["ghost"] = type
	if run.content.buildings[type].has("outpost"):
		var node := run.world.market.outpost_node(type)
		out["far"] = true
		if node >= 0:
			out["at"] = run.world.nodes[node]["pos"]
		else:
			out["ghost"] = ""
			out["placed"] = false
		return out
	var k := town.choose_plot(type)
	if k >= 0:
		out["plot"] = k
		out["at"] = town.plots[k]["pos"]
	else:
		out["ghost"] = ""
		out["placed"] = false
	return out


## How far out the scene must show: the open rings and every offer's place but an outpost's (out in the wilds, its
## line points the way off the map instead of shrinking the town to fit it).
static func reach(run: RunState, places: Array) -> float:
	var rings: Array = run.content.town["rings"]
	var r := float(rings[clampi(run.rings_open - 1, 0, rings.size() - 1)]["radius"]) + float(run.content.town["ring_depth"]) / 2.0
	for a: Dictionary in places:
		if a["far"]:
			continue
		r = maxf(r, Vector2(a["at"]).length() + 12.0)
		r = maxf(r, float(a["ring"]) + float(run.content.town["ring_depth"]) / 2.0)
	return r


## The card scale for `n` cards of `card` size over a map of `area` with `header` px taken at its top: as big as fits
## the width, and small enough to leave the town TOWN of the map's height. 0 when they'd shrink past MIN_SCALE.
static func card_scale(n: int, card: Vector2, area: Vector2, header: float) -> float:
	var across := (area.x - 2.0 * EDGE - GAP * maxi(0, n - 1)) / (card.x * maxi(1, n))
	var tall := (area.y * (1.0 - TOWN) - header - LEAD) / card.y
	var s := minf(1.0, minf(across, tall))
	return s if s >= MIN_SCALE else 0.0


## Card centres along the row: each as near as it can be above its offer's place (`want`, screen x), in order of
## those places, never overlapping and inside the map. Empty when they can't fit.
static func spread(want: Array, w: float, width: float) -> Array:
	var n := want.size()
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return float(want[a]) < float(want[b]))
	var xs: Array = []
	xs.resize(n)
	var lo := EDGE + w / 2.0
	var hi := width - EDGE - w / 2.0
	if n == 0:
		return xs
	if hi < lo or (n - 1) * (w + GAP) > hi - lo + 0.01:
		return []
	var prev := -INF
	for i in n:
		var x := clampf(float(want[order[i]]), lo, hi)
		x = maxf(x, prev + w + GAP)
		xs[order[i]] = x
		prev = x
	var nxt := INF
	for i in range(n - 1, -1, -1):
		var x: float = minf(float(xs[order[i]]), minf(hi, nxt - w - GAP))
		xs[order[i]] = x
		nxt = x
	return xs


## Begins the scene: the camera's way to `zoom` and `pan`, and each offer's place.
func start(view: ArenaView, places: Array, zoom: float, pan: Vector2, now_ms: float) -> void:
	# The draft is laid out again on every refresh (and for a second blueprint): the scene carries on from where it is.
	if not active():
		_from_zoom = view.zoom
		_from_pan = view.pan
		born = now_ms
	ended = -1.0
	anchors = places
	feet = []
	_to_zoom = zoom
	_to_pan = pan


## The draft is done (or the screen closed): the camera goes back.
func finish(now_ms: float) -> void:
	if choosing():
		ended = now_ms


## Skips the camera's glide (Space).
func skip(now_ms: float) -> void:
	if choosing():
		born = minf(born, now_ms - GLIDE_MS)


func update(view: ArenaView, now_ms: float) -> void:
	if not active():
		return
	if ended >= 0.0:
		var k := smoothstep(0.0, LEAVE_MS, now_ms - ended)
		view.zoom = lerpf(_to_zoom, _from_zoom, k)
		view.pan = _to_pan.lerp(_from_pan, k)
		if now_ms - ended >= LEAVE_MS:
			born = -1.0
			anchors = []
			feet = []
		return
	var g := smoothstep(0.0, GLIDE_MS, now_ms - born)
	view.zoom = lerpf(_from_zoom, _to_zoom, g)
	view.pan = _from_pan.lerp(_to_pan, g)


## How settled the scene is: 1 once the camera is there, falling as it leaves.
func shown(now_ms: float) -> float:
	if not active():
		return 0.0
	var k := smoothstep(GLIDE_MS * 0.5, GLIDE_MS, now_ms - born)
	if ended >= 0.0:
		k *= 1.0 - smoothstep(0.0, LEAVE_MS * 0.5, now_ms - ended)
	return k


## A ghost on its plot: the building's sprite see-through over a lit plot (ArenaView draws it in depth order).
func draw_ghost(view: ArenaView, a: Dictionary, now_ms: float) -> void:
	var s := shown(now_ms)
	if s <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(now_ms * 0.006)
	var at: Vector2 = a["at"]
	if int(a["plot"]) >= 0:
		var shape := view._screen_poly(view.run.world.town.plot_outline(int(a["plot"])))
		view.draw_colored_polygon(shape, Color(GOLD, (0.18 + 0.14 * pulse) * s))
		view.draw_polyline(view._closed(shape), Color(GOLD, (0.6 + 0.3 * pulse) * s), 2.0)
	var type: String = a["ghost"]
	if view._has_art(type):
		view.sprites.draw(view, type, view._to_screen(at), view.sprites.building_scale(type, view._scale()),
			SpriteBook.facing_of(at, int(view.sprites.info(type)["facings"])), Color(1.0, 0.95, 0.8, (0.45 + 0.15 * pulse) * s))
	elif int(a["plot"]) < 0:
		view.draw_circle(view._to_screen(at), 6.0, Color(GOLD, 0.7 * s))


## Over the map: rings to clear and buildings to change lit, then each card's leader line down to its place.
func draw_front(view: ArenaView, now_ms: float) -> void:
	var s := shown(now_ms)
	if s <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(now_ms * 0.006)
	for i in anchors.size():
		var a: Dictionary = anchors[i]
		if float(a["ring"]) > 0.0:
			var ring := view._ground_ring(Vector2.ZERO, float(a["ring"]), 96)
			view.draw_polyline(view._closed(ring), Color(GOLD, (0.5 + 0.4 * pulse) * s), 4.0)
		if a["lit"] != "":
			for b: Dictionary in view.run.world.buildings:
				if b["type"] == a["lit"]:
					var ring := view._ground_ring(b["pos"], 16.0, 24)
					view.draw_polyline(view._closed(ring), Color(GOLD, (0.5 + 0.4 * pulse) * s), 2.5)
		if i >= feet.size() or not a["placed"]:
			continue
		var from: Vector2 = feet[i]
		var to := view._to_screen(a["at"])
		# Off the map (an outpost's far node): the line stops at the map's edge, pointing the way.
		var inside := Rect2(Vector2(8, 8), view.size - Vector2(16, 16))
		if not inside.has_point(to):
			var d := to - from
			var t := 1.0
			if d.x != 0.0:
				t = minf(t, ((inside.end.x if d.x > 0.0 else inside.position.x) - from.x) / d.x)
			if d.y != 0.0:
				t = minf(t, ((inside.end.y if d.y > 0.0 else inside.position.y) - from.y) / d.y)
			to = from + d * maxf(0.0, t)
		view.draw_line(from, to, Color(0, 0, 0, 0.45 * s), 4.0)
		view.draw_line(from, to, Color(LINE, 0.85 * s), 2.0)
		view.draw_circle(to, 3.5, Color(LINE, s))
