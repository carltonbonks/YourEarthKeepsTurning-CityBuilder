class_name WavePlanner
extends RefCounted
## What attacks the town (`run.waves`): each round's warned wave, bought from a budget that grows
## on a fixed schedule, eased by catch-up when it would far outmatch the town (never grown),
## and the small probes of the early nights. Holds no state: the planned wave lives on RunState
## (`next_wave`, `wave_eased`).

var run: RunState


func _init(run_state: RunState) -> void:
	run = run_state


## Wave contents for a round: random enemies bought from a growing budget.
func generate(for_round: int) -> Array[String]:
	var content := run.content
	var rng := SeededRng.stream(run.run_seed, "wave", for_round)
	var budget := content.int_num("wave_budget_base") + content.int_num("wave_budget_per_round") * (for_round - 1)
	budget = roundi(budget * (1.0 + run.mod("wave_mult")))
	var wave: Array[String] = []
	var ids := content.enemies.keys()
	ids.sort()
	while budget > 0:
		var options := []
		for id: String in ids:
			var e: Dictionary = content.enemies[id]
			if e.get("wave", true) and not e.get("boss", false) and int(e["min_round"]) <= for_round and int(e["cost"]) <= budget:
				options.append(id)
		if options.is_empty():
			break
		var pick: String = rng.pick(options)
		wave.append(pick)
		budget -= int(content.enemies[pick]["cost"])
	for id: String in ids:
		if content.enemies[id].get("boss", false) and int(content.enemies[id].get("boss_round", content.int_num("rounds_to_win"))) == for_round:
			wave.append(id)
	return wave


## The round's warned wave: the scheduled wave, eased off while it would far outmatch the town.
## Catch-up only ever shrinks a wave, so a town that pulls ahead keeps its lead. Raiders are held
## back from the end of the list (never the boss) until the wave is at most catch_up_max_ratio
## times the town's power, keeping at least catch_up_min_share of them. Sets run.wave_eased and
## run.held_back (the raiders held back, who make a war camp: EnemyAI.make_camp), and run.outmatched (true when the
## scheduled wave was over that limit, even when a relic turns catch-up off; a round that wasn't earns glory).
func plan(for_round: int) -> Array[String]:
	var content := run.content
	var wave := generate(for_round)
	run.wave_eased = 0
	run.held_back = []
	var cap := content.num("catch_up_max_ratio")
	var limit := cap * float(Power.town(run.world)["total"])
	run.outmatched = cap > 0.0 and Power.wave(content, wave) > limit
	if cap <= 0.0 or run.has_effect("no_catch_up"):
		return wave
	var keep := ceili(wave.size() * content.num("catch_up_min_share"))
	while wave.size() > keep and Power.wave(content, wave) > limit:
		var i := wave.size() - 1
		while i >= 0 and content.enemies[wave[i]].get("boss", false):
			i -= 1
		if i < 0:
			break
		run.held_back.append(wave[i])
		wave.remove_at(i)
		run.wave_eased += 1
	return wave


## A small raid for an early night: cheap enemies from a small budget.
func probe(for_round: int, night: int) -> Array[String]:
	var content := run.content
	var rng := SeededRng.stream(run.run_seed, "probe_units", for_round * 10 + night)
	var budget := int(content.num("probe_budget_base") + content.num("probe_budget_per_round") * (for_round - 1))
	var ids := content.enemies.keys()
	ids.sort()
	var out: Array[String] = []
	while budget > 0:
		var options := []
		for id: String in ids:
			var e: Dictionary = content.enemies[id]
			if e.get("wave", true) and not e.get("boss", false) and not e.has("hold_at") \
					and int(e["min_round"]) <= for_round and int(e["cost"]) <= budget:
				options.append(id)
		if options.is_empty():
			break
		var pick: String = rng.pick(options)
		out.append(pick)
		budget -= int(content.enemies[pick]["cost"])
	return out


## The war camp's raiders who march with this round's attack: those who joined it in an earlier round (the loan
## comes due a round later) and are still alive. Heroes who break the camp first take them off the list.
func camp_due() -> Array[String]:
	var out: Array[String] = []
	for e in run.world.enemy_ai.camp_raiders():
		if e.joined_round < run.round_number:
			out.append(e.type_id)
	return out


## Everything that comes on the attack night: the planned wave and the war camp's raiders who march with it.
func attack() -> Array[String]:
	var out := run.next_wave.duplicate()
	out.append_array(camp_due())
	return out


## Enemy type id -> count of the attack (the planned wave and the war camp's raiders due), for the wave preview.
func counts() -> Dictionary:
	var out := {}
	for id in attack():
		out[id] = int(out.get(id, 0)) + 1
	return out
