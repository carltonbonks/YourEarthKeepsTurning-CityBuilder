class_name SeededRng
extends RefCounted
## Deterministic random numbers for the simulation.
##
## Every random roll in the simulation goes through one of these, created from
## the run's seed, so a run can be replayed exactly ("seed 4821, round 6").
## Lives in sim/, which never touches scenes or nodes, so it can run headless.

var seed_value: int
var _rng := RandomNumberGenerator.new()


func _init(run_seed: int) -> void:
	seed_value = run_seed
	_rng.seed = run_seed


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randf() -> float:
	return _rng.randf()


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]


## A key of `weights` (key -> weight), chosen with chance in proportion to its weight.
## Keys are sorted first so the result only depends on the seed. "" if all weights are 0.
func weighted(weights: Dictionary) -> String:
	var keys := weights.keys()
	keys.sort()
	var sum := 0.0
	for k in keys:
		sum += maxf(0.0, float(weights[k]))
	if sum <= 0.0:
		return ""
	var roll := _rng.randf() * sum
	for k in keys:
		roll -= maxf(0.0, float(weights[k]))
		if roll < 0.0:
			return k
	return keys[-1]


## One of `items`, chosen with chance in proportion to weight.call(item). null if empty or all weights are 0.
func pick_by(items: Array, weight: Callable) -> Variant:
	var sum := 0.0
	for item in items:
		sum += maxf(0.0, float(weight.call(item)))
	if sum <= 0.0:
		return null
	var roll := _rng.randf() * sum
	for item in items:
		roll -= maxf(0.0, float(weight.call(item)))
		if roll < 0.0:
			return item
	return items[-1]


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## A separate, reproducible stream for one part of the run (e.g. "wave", round 6),
## so a player's choices elsewhere don't change what that stream rolls.
static func stream(run_seed: int, label: String, index: int = 0) -> SeededRng:
	return SeededRng.new(hash("%d:%s:%d" % [run_seed, label, index]))
