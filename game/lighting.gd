class_name Lighting
extends RefCounted
## Light over the map, view only: the sun's tint through the day, night falling and lifting, and
## warm glows where things burn. The hearth glows while it is lit, brighter at night. Shots from the
## hearth and watch posts glow when the town owns a relic tagged "fire" (Fire Arrows). Glows are
## added onto the picture (ArenaView draws them on a layer that blends by adding light), so they
## brighten the ground under the night instead of painting over it.

## How dark the night gets (the share of night blue laid over the map).
const NIGHT := 0.45
## How long dawn takes to lift the night, in game seconds (dusk's length is in data/balance.json).
const DAWN_SECONDS := 4.0
## Sunlight added at noon, and the warmer light of morning and evening.
const NOON_SUN := Color(0.07, 0.065, 0.045)
const LOW_SUN := Color(0.08, 0.04, 0.01)
const FIRE := Color(1.0, 0.55, 0.2)
## How far the hearth's light reaches, in hearth radii, by day and at night.
const HEARTH_REACH_DAY := 2.5
const HEARTH_REACH_NIGHT := 6.0
## A fire shot's glow at its flight's end, in world units, and how long it lingers (shots last 0.25 s).
const SHOT_GLOW := 26.0
const SHOT_SECONDS := 0.25

## A soft round light, white in the middle fading to nothing at the edge.
var glow: Texture2D


func _init() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.35, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	glow = tex


## How dark it is: 0 by day, rising through dusk to NIGHT, and lifting again over the next dawn.
static func darkness(run: RunState) -> float:
	if run.phase == RunState.Phase.BUILD:
		return 0.0
	var w := run.world
	var day := run.content.num("day_seconds")
	var dusk := run.content.num("dusk_seconds")
	var t := w.time_of_day()
	if t >= day:
		return NIGHT
	if t >= day - dusk:
		return NIGHT * (t - (day - dusk)) / dusk
	# The round's first morning follows the build phase in daylight; later mornings follow a night.
	if w.day_index() > 0 and t < DAWN_SECONDS:
		return NIGHT * (1.0 - t / DAWN_SECONDS)
	return 0.0


## The sunlight added over the whole map: warm and low at the day's ends, plainer at noon, none at night.
static func sun(run: RunState) -> Color:
	var up := 1.0 - darkness(run) / NIGHT
	if run.phase == RunState.Phase.BUILD:
		return dim(NOON_SUN, 0.6)
	var f := clampf(run.world.time_of_day() / run.content.num("day_seconds"), 0.0, 1.0)
	var high := sin(PI * f)
	return dim(LOW_SUN.lerp(NOON_SUN, high), up)


## True if the town owns a relic that sets its shots alight.
static func fire_shots(run: RunState) -> bool:
	for id in run.relics:
		if run.content.has_tag("relic", id, "fire"):
			return true
	return false


## A light scaled by k. The light layer adds colour times alpha, so only the colour is scaled.
static func dim(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 1.0)


## A slow, uneven flicker round 1.
static func flicker(now_ms: float, phase := 0.0) -> float:
	return 0.9 + 0.06 * sin(now_ms * 0.011 + phase) + 0.04 * sin(now_ms * 0.027 + phase * 2.3)


## Draws one glow: centred on screen point p, rx by ry pixels across its middle, of colour c.
func draw_glow(canvas: CanvasItem, p: Vector2, rx: float, ry: float, c: Color) -> void:
	canvas.draw_texture_rect(glow, Rect2(p - Vector2(rx, ry), Vector2(rx, ry) * 2.0), false, c)
