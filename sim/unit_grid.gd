class_name UnitGrid
extends RefCounted
## Buckets units by where they stand so "who is nearest" only looks at nearby squares.
## World rebuilds one for enemies and one for townsfolk and heroes each step, at moments when
## those units are not moving, and answers nearest-unit questions from it. It gives exactly the
## answer a scan of the whole list would (ties go to the unit earlier in the list), so runs are
## unchanged; it is only faster once there are hundreds of units.

const CELL := 64.0

var units: Array[Unit] = []
var _side := 0
var _origin := Vector2.ZERO
var _start := PackedInt32Array()  ## Per bucket: where its entries begin in _items (bucket b is _start[b] .. _start[b + 1]).
var _items := PackedInt32Array()  ## Indices into `units`, grouped by bucket.


func _init(world_radius: float) -> void:
	_side = int(ceil(world_radius * 2.0 / CELL)) + 1
	_origin = Vector2(-_side * CELL / 2.0, -_side * CELL / 2.0)


func rebuild(list: Array[Unit]) -> void:
	units = list
	var buckets := _side * _side
	var where := PackedInt32Array()
	where.resize(list.size())
	var counts := PackedInt32Array()
	counts.resize(buckets + 1)
	for i in list.size():
		var b := _bucket(list[i].pos)
		where[i] = b
		counts[b + 1] += 1
	for b in buckets:
		counts[b + 1] += counts[b]
	_start = counts.duplicate()
	_items.resize(list.size())
	for i in list.size():
		_items[counts[where[i]]] = i
		counts[where[i]] += 1


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((p.x - _origin.x) / CELL), 0, _side - 1), clampi(floori((p.y - _origin.y) / CELL), 0, _side - 1))


func _bucket(p: Vector2) -> int:
	var c := _cell(p)
	return c.y * _side + c.x


## The nearest living unit strictly closer than max_distance, or null. With `spawned_only`, enemies still
## waiting to come on are skipped; units farther than max_from_home from the hearth are skipped too.
## Same answer as walking `units` in order and keeping the first closest.
func nearest(from: Vector2, max_distance: float, max_from_home := INF, spawned_only := false) -> Unit:
	var lo := _cell(from - Vector2(max_distance, max_distance))
	var hi := _cell(from + Vector2(max_distance, max_distance))
	var best_i := -1
	var best_d := max_distance
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var b := y * _side + x
			for k in range(_start[b], _start[b + 1]):
				var i := _items[k]
				var unit := units[i]
				var d := from.distance_to(unit.pos)
				if (d < best_d or (d == best_d and best_i >= 0 and i < best_i)) and unit.alive \
						and (unit.spawned or not spawned_only) and unit.pos.length() <= max_from_home:
					best_d = d
					best_i = i
	return units[best_i] if best_i >= 0 else null
