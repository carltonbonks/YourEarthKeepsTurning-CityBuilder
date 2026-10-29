class_name GroundProps
extends RefCounted
## The look of the turning ring's plates (Yusuf, 2026-10-29, rendered art slice 3): reeds and pools on the
## Fen, trees on the Greenwood, stones on the Stonefield, graves on the Barrow, scattered over each plate and
## turning with it. Their spots come from the plate's place in the ring, not the run's dice, so they never
## change the game; nodes and dens keep a little room round them. View only: ArenaView asks `props` once a frame
## and draws each in its depth order. Sprites are art/sprites/plate_<kind>.png, one look per column.

## World units of plate per prop (about one prop per this many square units).
const AREA_PER_PROP := 2600.0
## How close a prop may come to a node, den or the ring's edges, in world units.
const KEEP_CLEAR := 26.0
const EDGE := 10.0

## Props in each plate's own terms ([along 0..1, radius, look, size]) by plate index, made once per world.
var _layout := {}
var _world: World = null


## Every prop to draw: [world position, sprite id, look (column), size] for the near ring as it lies, its plates
## turned `slide` radians short of where they lie while they slide into place after a turn.
func props(w: World, slide: float, has_art: Callable) -> Array:
	var out: Array = []
	var earth := w.earth
	if not earth.enabled():
		return out
	if w != _world:
		_world = w
		_layout.clear()
	var near: Dictionary = earth.rings[0]
	var seams: Array = near["seams"]
	var r0 := float(near["r0"])
	var r1 := float(near["r1"])
	for k in seams.size():
		var kind: String = near["plate_kinds"][k]
		var id := "plate_" + kind
		if kind == "" or not has_art.call(id):
			continue
		var a0 := float(seams[k]) + slide
		var width := fposmod(float(seams[(k + 1) % seams.size()]) - float(seams[k]), TAU)
		if not _layout.has(k):
			_layout[k] = _lay_out(k, width, r0, r1)
		for p: Array in _layout[k]:
			var at := Vector2.from_angle(a0 + width * float(p[0])) * float(p[1])
			if _crowded(w, at):
				continue
			out.append([at, id, p[2], p[3]])
	return out


## Spots for plate k, spread evenly with a little jitter from a hash of where they are.
func _lay_out(k: int, width: float, r0: float, r1: float) -> Array:
	var area := width / 2.0 * (r1 * r1 - r0 * r0)
	var n := int(area / AREA_PER_PROP)
	var out: Array = []
	for i in n:
		var h := _hash(k * 7919 + i)
		var along := (float(i) + 0.15 + 0.7 * _frac(h)) / float(n)
		var depth := EDGE + (r1 - r0 - 2.0 * EDGE) * _frac(h * 31 + 7)
		out.append([along, r0 + depth, int(_frac(h * 17 + 3) * 4.0) % 4, 0.75 + 0.5 * _frac(h * 13 + 5)])
	return out


func _crowded(w: World, at: Vector2) -> bool:
	for node in w.nodes:
		if w.node_active(node) and at.distance_to(node["pos"]) < KEEP_CLEAR:
			return true
	for den in w.dens:
		if at.distance_to(den["pos"]) < KEEP_CLEAR * 1.6:
			return true
	return false


static func _hash(x: int) -> int:
	x = ((x >> 16) ^ x) * 0x45d9f3b
	x = ((x >> 16) ^ x) * 0x45d9f3b
	return ((x >> 16) ^ x) & 0x7fffffff


static func _frac(x: int) -> float:
	return float(_hash(x) % 10007) / 10007.0
