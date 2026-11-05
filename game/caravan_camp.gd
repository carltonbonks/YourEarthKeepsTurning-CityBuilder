class_name CaravanCamp
extends RefCounted
## The southern caravan on the map (picks in the town, slice 2): once it comes (Caravan.is_here) its wagons stand just
## outside the town by the Bronze moot. Hovering a deal in the hand lights the camp and names the deal over it; taking
## one sends what it brings up from the wagons. Presentation only: the deals and their rules are sim/caravan.gd.

## How far past the town's edge the wagons stand (world units).
const MARGIN := 22.0
## The way round the hearth the wagons stand when there is no moot to stand by (the caravan came early): up and to
## the right on screen, clear of the build hand along the screen's foot.
const ANGLE := -PI * 0.3
## How long what a deal brought rises over the wagons (ms), and how far (px).
const RISE_MS := 1800.0
const RISE := 46.0
const GOLD := Color(1.0, 0.85, 0.35)

## The deal the player is pointing at in the hand (index into run.caravan.offers), or -1.
var hovered := -1
## Deals just taken: {text, born (ms)}.
var risings: Array = []


## Where the wagons stand: just outside the town on the Bronze moot's side (or the caravan's own way when it came
## before the moot), always on the far half of the town so the build hand never hides them.
static func spot(run: RunState) -> Vector2:
	var angle := ANGLE
	var needs: String = run.content.trades["needs"]
	for b: Dictionary in run.world.buildings:
		if b["type"] == needs:
			var at: Vector2 = b["pos"]
			if at.length() > 0.01:
				angle = Vector2(at.x, -maxf(absf(at.y), at.length() * 0.5)).angle()
			break
	return Vector2.from_angle(angle) * (run.world.town.patrol_radius(angle) + MARGIN)


## True when the wagons are on the map.
static func here(run: RunState) -> bool:
	return run.caravan.is_here()


## A deal was taken: what it brings rises over the wagons.
func traded(run: RunState, index: int, now_ms: float) -> void:
	if index < 0 or index >= run.caravan.offers.size():
		return
	var offer: Dictionary = run.caravan.offers[index]
	var text := BuildHandView.deal_brings(run, offer["deal"], offer)
	if text == "":
		text = run.caravan.deal(offer["deal"])["name"]
	risings.append({"text": text, "born": now_ms})


## Draws the wagons, the hovered deal's ring and name, and whatever rises from a deal just taken.
func draw(view: ArenaView, run: RunState, font: Font, now_ms: float) -> void:
	var at := spot(run)
	var base := view._to_screen(at)
	var r := view._den_radius() * 0.9
	var lit := hovered >= 0 and hovered < run.caravan.offers.size()
	if lit:
		var beat := 0.5 + 0.5 * sin(now_ms * 0.006)
		var ring := view._ground_ring(at, r * (1.5 + 0.35 * beat) / view._scale(), 40)
		view.draw_polyline(view._closed(ring), Color(GOLD, 0.95 - 0.4 * beat), 3.0)
	if view._has_art("caravan"):
		view.sprites.draw(view, "caravan", base, view.sprites.building_scale("caravan", view._scale()))
	else:
		view._shadow(at, r)
		var w := r * 1.6
		view.draw_rect(Rect2(base + Vector2(-w / 2.0, -r * 0.9), Vector2(w, r * 0.6)), Color("#7a5a38"))
		view.draw_arc(base + Vector2(0.0, -r * 0.9), w * 0.45, PI, TAU, 16, Color("#d8c8a0"), r * 0.3)
	var name: String = run.content.trades["name"]
	var label := name
	var colour := Color("#ffe0a0")
	if lit:
		label = run.caravan.deal(run.caravan.offers[hovered]["deal"])["name"]
		colour = GOLD
	_text(view, font, base + Vector2(0.0, 18.0), label, UiKit.BODY, colour, 1.0)
	if lit:
		var offer: Dictionary = run.caravan.offers[hovered]
		var brings := BuildHandView.deal_brings(run, offer["deal"], offer)
		if brings != "":
			_text(view, font, base + Vector2(0.0, 34.0), brings, UiKit.CAPTION, Color(0.95, 0.9, 0.8), 1.0)
	risings = risings.filter(func(x: Dictionary) -> bool: return now_ms - float(x["born"]) < RISE_MS)
	for x: Dictionary in risings:
		var t := (now_ms - float(x["born"])) / RISE_MS
		var a := 1.0 - smoothstep(0.6, 1.0, t)
		_text(view, font, base + Vector2(0.0, -r * 2.2 - RISE * t), x["text"], UiKit.STRONG, Color("#9be07a"), a)


static func _text(view: ArenaView, font: Font, centre: Vector2, text: String, size: int, colour: Color, a: float) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := centre - Vector2(w / 2.0, 0.0)
	view.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.75 * a))
	view.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(colour, a))
