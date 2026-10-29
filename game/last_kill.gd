class_name LastKill
extends RefCounted
## Makes the night's last kill land (Yusuf, 2026-10-26: wins and losses should feel impactful). When the last
## raider of a night falls, time slows for a moment, the camera leans in on the spot, a ring of light breaks
## outward and a line says who landed the blow; the dawn pick or the relic pick opens only once it has played
## (main.gd holds them). Space ends it at once. View only, like TurnCamera: it reads World.last_felled, and
## slowing time is main.gd ticking the sim more slowly (sim_speed), never a rule.
## Timings are in real milliseconds.

## The whole beat: in, hold on the kill, back to the player's camera.
const BEAT_MS := 1800.0
const IN_MS := 250.0
const OUT_MS := 450.0
## How fast the game runs while the beat holds, in game seconds per real second (the player's speed is 2 to 8),
## and when it starts easing back to the player's speed.
const SLOW_SPEED := 0.3
const SLOW_UNTIL_MS := 1100.0
## How far the camera leans toward the kill (0 stays, 1 centres it) and how much closer it comes.
const LEAN := 0.6
const CLOSER := 1.3
## The ring of light: how wide it opens on the ground, in world units, how long it takes, and the second
## ring's lag behind the first.
const RING_REACH := 110.0
const RING_MS := 750.0
const RING_LAG_MS := 160.0
## How dark the rest of the map goes while the kill is held.
const VIGNETTE := 0.35
const GOLD := UiKit.GOLD

## When the beat began (ms), or -1 when none is playing.
var _from_ms := -1.0
var _from_zoom := 1.0
var _from_pan := Vector2.ZERO
var _released := false
## The kill being shown: World.last_felled, plus "ends" (true when it ended the attack night).
var kill := {}
## Whether a raider still stood after the last step watched, so the step that fells the last can be told.
var _had_invaders := false


## True while the beat is playing.
func playing() -> bool:
	return _from_ms >= 0.0


## Called after each sim step. Starts the beat when that step felled the night's last raider (not a den
## wanderer, not one who slipped away). Returns true if it did.
func watch(view: ArenaView, w: World) -> bool:
	var standing := w.enemies.any(func(e: Unit) -> bool: return e.alive and e.den_index < 0)
	var was := _had_invaders
	_had_invaders = standing
	if not was or standing or not is_last_kill(w):
		return false
	start(view, w.last_felled.merged({"ends": w.pause == World.Pause.ROUND_OVER}))
	return true


## True if the last enemy to fall is a raider felled by this very step, at night (or as the attack night ends).
static func is_last_kill(w: World) -> bool:
	var felled := w.last_felled
	if felled.is_empty() or not felled["invader"] or not is_equal_approx(float(felled["time"]), w.time):
		return false
	return w.is_night() or w.pause == World.Pause.ROUND_OVER


## Starts the beat on `felled` from the view's current camera.
func start(view: ArenaView, felled: Dictionary) -> void:
	_from_ms = Time.get_ticks_msec()
	_from_zoom = view.zoom
	_from_pan = view.pan
	_released = false
	kill = felled


## Ends the beat now and gives the player their camera back.
func skip(view: ArenaView) -> void:
	if not playing():
		return
	if not _released:
		view.zoom = _from_zoom
		view.pan = _from_pan
	_from_ms = -1.0


## The player moved the camera: stop steering it (the rest of the beat still plays).
func release() -> void:
	_released = true


## A new run: forget the last one's raiders.
func reset() -> void:
	_from_ms = -1.0
	_had_invaders = false
	kill = {}


func elapsed() -> float:
	return Time.get_ticks_msec() - _from_ms if playing() else -1.0


## How far the camera leans in at `ms` into the beat: 0 the player's camera, 1 the closest.
static func weight_at(ms: float) -> float:
	if ms < 0.0 or ms >= BEAT_MS:
		return 0.0
	if ms < IN_MS:
		return smoothstep(0.0, 1.0, ms / IN_MS)
	if ms > BEAT_MS - OUT_MS:
		return smoothstep(0.0, 1.0, (BEAT_MS - ms) / OUT_MS)
	return 1.0


## The game speed (game seconds per real second) `ms` into the beat, for a player playing at `speed`: slow while
## the kill is held, then easing back. Never faster than the player's own speed, so a paused game stays paused.
static func speed_at(ms: float, speed: float) -> float:
	if ms < 0.0 or ms >= BEAT_MS:
		return speed
	var slow := minf(speed, SLOW_SPEED)
	if ms < SLOW_UNTIL_MS:
		return slow
	return lerpf(slow, speed, smoothstep(0.0, 1.0, (ms - SLOW_UNTIL_MS) / (BEAT_MS - SLOW_UNTIL_MS)))


## The game speed right now (see speed_at).
func sim_speed(speed: float) -> float:
	return speed_at(elapsed(), speed)


## Moves the view's camera for this frame; ArenaView calls it every frame instead of the night camera while the
## beat plays. Returns true on the frame the beat ends.
func update(view: ArenaView) -> bool:
	if not playing():
		return false
	var ms := elapsed()
	if ms >= BEAT_MS:
		skip(view)
		return true
	if not _released:
		var t := weight_at(ms)
		view.zoom = lerpf(_from_zoom, minf(ArenaView.MAX_ZOOM, _from_zoom * CLOSER), t)
		view.pan = _from_pan.lerp(_from_pan.lerp(Vector2(kill["pos"]), LEAN), t)
	return false


## The headline: what this kill means.
func headline() -> String:
	if kill.get("ends", false):
		return "The attack is broken"
	return "The night's last raider falls"


## Who landed the blow, as a line under the headline ("" when nobody can be named).
func byline() -> String:
	var by := String(kill.get("by", ""))
	return "" if by == "" else "felled by " + by


## Over the map (after the night's darkness): the rest of the map dims, the raider flashes white and fades,
## and rings of light open out on the ground from where it fell.
func draw(view: ArenaView) -> void:
	if not playing():
		return
	var ms := elapsed()
	var t := weight_at(ms)
	view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(0, 0, 0, VIGNETTE * t))
	var at := Vector2(kill["pos"])
	for k in 2:
		var ring := clampf((ms - k * RING_LAG_MS) / RING_MS, 0.0, 1.0)
		if ring <= 0.0 or ring >= 1.0:
			continue
		var reach := RING_REACH * (1.0 - pow(1.0 - ring, 3.0))
		var shape := view._ground_ring(at, maxf(1.0, reach), 40)
		shape.append(shape[0])
		view.draw_polyline(shape, Color(GOLD, (1.0 - ring) * (0.9 - 0.3 * k)), 4.0 - 1.5 * k)
	# The fallen raider: a white flash, then its own colour sinking and fading.
	var fade := clampf(1.0 - ms / 900.0, 0.0, 1.0)
	if fade > 0.0:
		var r := (ArenaView.BOSS_RADIUS if kill.get("boss", false) else ArenaView.ENEMY_RADIUS) * maxf(1.0, view.zoom * 0.7)
		var p := view._stand(at, r) + Vector2(0.0, r * (1.0 - fade))
		var flash := clampf(1.0 - ms / 160.0, 0.0, 1.0)
		var enemies: Dictionary = view.run.content.enemies
		var body := Color(enemies[kill["type"]]["color"]) if enemies.has(kill.get("type", "")) else ArenaView.INVADER_RED
		view.draw_circle(p, r * (0.6 + 0.4 * fade), Color(body.lerp(Color.WHITE, flash), fade))
		view.draw_arc(p, r * (1.0 + 0.6 * (1.0 - fade)), 0.0, TAU, 20, Color(1, 1, 1, fade * 0.8), 2.0)


## On the light layer: a warm burst where the raider fell.
func draw_lights(layer: CanvasItem, light: Lighting, view: ArenaView) -> void:
	if not playing():
		return
	var ms := elapsed()
	var burst := clampf(1.0 - ms / 1000.0, 0.0, 1.0) * 0.6 + 0.25 * weight_at(ms)
	var r := 70.0 * view.zoom
	var squash := ArenaView.ISO_SQUASH if view.iso else 1.0
	light.draw_glow(layer, view._to_screen(Vector2(kill["pos"])), r, r * squash, Lighting.dim(GOLD, burst))


## On the top layer: the headline and who felled the raider, rising a little over the spot.
func draw_top(layer: CanvasItem, view: ArenaView, font: Font) -> void:
	if not playing():
		return
	var ms := elapsed()
	var a := clampf(ms / 150.0, 0.0, 1.0) * clampf((BEAT_MS - ms) / 400.0, 0.0, 1.0)
	var over := view._to_screen(Vector2(kill["pos"])) - Vector2(0.0, 46.0 + 14.0 * ms / BEAT_MS)
	_centred(layer, font, over, headline(), UiKit.BANNER, Color(GOLD, a), a)
	var by := byline()
	if by != "":
		_centred(layer, font, over + Vector2(0.0, 22.0), by, UiKit.STRONG, Color(1, 0.95, 0.85, a), a)


static func _centred(layer: CanvasItem, font: Font, at: Vector2, text: String, font_size: int, c: Color, a: float) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var p := at - Vector2(width / 2.0, 0.0)
	layer.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.85 * a))
	layer.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)
