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
