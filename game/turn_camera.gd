class_name TurnCamera
extends RefCounted
## Makes each turn of the earth a moment. When the plates have just clicked round, the map eases out
## until every ring is in view, holds while the land slides into place, then eases back to wherever the
## player had it. View only, like NightCamera. Space (or a wheel or drag) ends it at once.

## The whole beat, in real milliseconds: out, hold while the plates slide, back.
const BEAT_MS := 2400.0
const OUT_MS := 450.0
const BACK_MS := 550.0
## How much of the view the outermost ring fills at the widest point.
const FILL := 0.95

var _from_ms := -1.0
var _from_zoom := 1.0
var _from_pan := Vector2.ZERO


## True while the beat is playing.
func playing() -> bool:
	return _from_ms >= 0.0


## Starts the beat from the view's current camera.
func start(view: ArenaView) -> void:
	_from_ms = Time.get_ticks_msec()
	_from_zoom = view.zoom
	_from_pan = view.pan


## Ends the beat now and gives the player their camera back.
func skip(view: ArenaView) -> void:
	if not playing():
		return
	view.zoom = _from_zoom
	view.pan = _from_pan
	_from_ms = -1.0


## The player moved the camera: stop steering it, and leave it where they put it.
func release() -> void:
	_from_ms = -1.0


## How far out the camera is at `ms` into the beat: 0 the player's camera, 1 the widest view.
static func weight_at(ms: float) -> float:
	if ms < 0.0 or ms >= BEAT_MS:
		return 0.0
	if ms < OUT_MS:
		return smoothstep(0.0, 1.0, ms / OUT_MS)
	if ms > BEAT_MS - BACK_MS:
		return smoothstep(0.0, 1.0, (BEAT_MS - ms) / BACK_MS)
	return 1.0


## Moves the view's camera for this frame; ArenaView calls it every frame.
func update(view: ArenaView) -> void:
	if not playing():
		return
	var ms := Time.get_ticks_msec() - _from_ms
	if ms >= BEAT_MS:
		skip(view)
		return
	var rings: Array = view.run.content.plates["rings"]
	var wide := minf(_from_zoom, view.zoom_to_fit(float(rings[-1]["r1"]), FILL))
	var t := weight_at(ms)
	view.zoom = lerpf(_from_zoom, wide, t)
	view.pan = _from_pan.lerp(Vector2.ZERO, t)
