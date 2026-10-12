class_name AutoPlayer
extends RefCounted
## A simple scripted player for headless balance runs and tests.
## It stands in for a human making decisions so we can simulate many runs fast.

## "balanced": huts as needed, a longhouse early, then watch posts; picks by need.
## "workers": never takes heroes or builds the longhouse; picks townsfolk only.
## "heroes": rushes the longhouse and takes every hero card it can afford.
## "market": like balanced, but builds every workshop and stall early and the hunting lodge.
## "bronze": like market, then raises the Bronze moot as soon as it can, the smelter and bronzesmith,
## buys tool sets (picks, chisels, then spears) and some tin from the caravan.
## Every style takes a Promote card when one is offered and affordable.
## Every style builds the stone-layers' yard from round 5 so craftspeople pave the busiest paths,
## and orders up to `gates` gates from `gate_round` (see below).
## "balanced" and "heroes" also open the arms and hide chains (market, knapper, hide rack, two stalls) from round 3,
## since the market is now the only place heroes can buy gear.
var style := "balanced"
## Gates: how many it orders at most (one a round, when a gap is free) and from which round.
## balance_run.gd sets these with gates= and gate_round=.
var gates := 0
var gate_round := 3


func play_run(run: RunState) -> void:
	while not run.is_over():
		match run.phase:
			RunState.Phase.BUILD:
				build(run)
				run.begin_round()
			RunState.Phase.PICK:
				run.choose_pick(pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")


func build(run: RunState) -> void:
	_paving(run)
	if style != "workers" and (run.round_number >= 2 or style == "heroes"):
		run.build("longhouse")
	# Heroes without a bed sulk and leave, so add lodging when the beds run out.
	if style != "workers" and not run.heroes.is_empty() and free_beds(run) <= 0:
		for type: String in ["tavern", "shrine", "longhouse"]:
			if run.build(type):
				break
	# Saving up for the Bronze moot: only essentials until it is ordered.
	if style == "bronze" and run.round_number >= 3 and run.world.count_buildings("bronze_moot", false) == 0:
		if run.housing() - run.population() <= 1:
			run.build("hut")
		run.build("market")
		run.build("bronze_moot")
		return
	if style == "heroes" and run.round_number >= 2:
		run.build("tavern")
	if run.housing() - run.population() <= 2:
		run.build("hut")
	if style == "bronze":
		_bronze(run)
	if (style == "market" or style == "bronze") and run.round_number >= 2:
		for type: String in ["market", "arms_stall", "knapper", "hide_stall", "hide_rack", "hunting_lodge",
				"charm_stall", "bone_carver", "provisions_stall", "smoke_hut"]:
			run.build(type)
	elif style != "workers" and run.round_number >= 3:
		for type: String in ["market", "arms_stall", "knapper", "hide_stall", "hide_rack"]:
			run.build(type)
	if style != "workers" and run.round_number >= (3 if style == "heroes" else 4):
		run.build("shrine")
	if run.round_number >= 3:
		run.build("drying_rack")
	if run.round_number >= 2:
		run.build("watch_post")
	# Gates last, with whatever is left over.
	_gates(run)


## From round 5, a yard so craftspeople pave the busiest paths (from round 3 cost about 9 points:
## paving early eats the stone and wood the town needs).
func _paving(run: RunState) -> void:
	if run.round_number >= 5:
		for b in run.content.buildings:
			if run.content.buildings[b].get("paves", false):
				run.build(b)


## One gate a round across the busiest gap, up to `gates`.
func _gates(run: RunState) -> void:
	if run.round_number < gate_round:
		return
	for b in run.content.buildings:
		if run.content.buildings[b].has("gate_hp") and run.world.count_buildings(b, false) < gates:
			run.build(b)


func _bronze(run: RunState) -> void:
	if run.round_number >= 3:
		run.build("bronze_moot")
	if run.world.count_buildings("bronze_moot", false) == 0:
		return
	if not run.build("smelter") and run.world.count_buildings("smelter", false) == 0:
		return
	run.build("bronzesmith")
	for id: String in ["bronze_picks", "bronze_chisels", "bronze_spears"]:
		if run.tools.has(id):
			continue
		run.buy_tools(id)
		break
	while int(run.stock["shells"]) > 45 and int(run.stock["tin"]) < 4 and run.trade("tin"):
		pass


## Beds in finished and ordered lodgings, minus heroes.
func free_beds(run: RunState) -> int:
	var beds := 0
	for b in run.world.buildings:
		var def: Dictionary = run.content.buildings[b["type"]]
		if def.has("lodging"):
			beds += int(def["lodging"]["beds"])
	return beds - run.living_heroes().size()


func pick(run: RunState) -> int:
	var best := -1
	var best_score := -INF
	for i in run.pick_offer.size():
		if not run.can_take_pick(i):
			continue
		var card := run.pick_offer[i]
		var score := 0.0
		match "promote" if card["kind"] == "promote" else card["role"]:
			"promote":
				score = 6.0
			"hero":
				score = 5.0 if style != "workers" else -100.0
				if style == "heroes":
					score = 50.0
				if free_beds(run) <= 0:
					score = -50.0
			"tribesperson":
				score = 4.0 - run.count_role("tribesperson") * 0.6
			"warrior":
				score = 3.0 - run.count_role("warrior") * 0.8
			"craftsperson":
				var pending := run.world.buildings.any(func(b: Dictionary) -> bool: return float(b["work_left"]) > 0.0)
				var benches := run.world.buildings.filter(func(b: Dictionary) -> bool:
					return run.content.buildings[b["type"]].has("workshop")).size()
				score = (4.0 if pending else 1.0) + benches * 1.2 - run.count_role("craftsperson") * 1.5
		if score > best_score:
			best_score = score
			best = i
	return best
