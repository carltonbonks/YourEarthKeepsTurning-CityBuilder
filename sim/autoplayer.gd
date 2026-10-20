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
## "medieval": like bronze, then saves for the Stone keep once the bronzesmith stands, and after it
## the charcoal burner, bloomery, blacksmith, townhouses, fields, guildhall, chapel and iron tool sets;
## it takes family cards whenever the houses have room.
## Every style takes a Promote card when one is offered and affordable.
## Every style takes the offered relic it ranks highest (RELIC_RANK).
## Every style can only order buildings on the round's cards (run.hand), and redraws once when shells are spare.
## Every style builds the stone-layers' yard from round 5 so craftspeople pave the busiest paths,
## orders the forester and charcoal pit when they are needed (see _upkeep),
## and orders up to `gates` gates from `gate_round` (see below), and a garden when food runs short.
## "balanced" and "heroes" also open the arms and hide chains (market, knapper, hide rack, two stalls) from round 3,
## since the market is now the only place heroes can buy gear.
var style := "balanced"
## Gates: how many it orders at most (after everything else, when a plot fits) and from which round.
## Free gates were worth about 11 points; ordered last it rarely has 6 wood spare, so it builds few.
## balance_run.gd sets these with gates= and gate_round=.
var gates := 2
var gate_round := 3
## Gardens: one a round while food in store would last fewer than this many days (0 = never). balance_run.gd: gardens=.
var garden_days := 3.0
## Orders the forester and charcoal pit when the cards recommend them. balance_run.gd: upkeep=0 turns it off.
var upkeep := true
## Redraws the building cards once a round when it has at least this many shells (after its first pass).
var redraw_above := 40


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
				run.choose_relic(pick_relic(run))


## Orders from the round's building cards, then redraws once when shells are spare and orders again.
func build(run: RunState) -> void:
	_build_pass(run)
	if int(run.stock["shells"]) >= redraw_above and run.hand.can_redraw():
		run.hand.redraw()
		_build_pass(run)


## Orders a building if a card for it is in hand.
func _order(run: RunState, type: String) -> bool:
	return run.hand.order(type)


func _build_pass(run: RunState) -> void:
	if _ages(style):
		_buy_goods(run)
	_paving(run)
	if style != "workers" and (run.round_number >= 2 or style == "heroes"):
		_order(run, "longhouse")
	# Heroes without a bed sulk and leave, so add lodging when the beds run out.
	if style != "workers" and not run.heroes.is_empty() and free_beds(run) <= 0:
		for type: String in ["tavern", "shrine", "longhouse"]:
			if _order(run, type):
				break
	# Saving up for the Bronze moot: only essentials until it is ordered.
	if _ages(style) and run.round_number >= 3 and run.world.count_buildings("bronze_moot", false) == 0:
		if run.housing() - run.population() <= 1:
			_order(run, "hut")
		_order(run, "market")
		_order(run, "bronze_moot")
		_gardens(run)
		_upkeep(run)
		return
	if style == "heroes" and run.round_number >= 2:
		_order(run, "tavern")
	if run.housing() - run.population() <= 2:
		_order(run, "hut")
	_gardens(run)
	_upkeep(run)
	if _ages(style):
		_bronze(run)
	if style == "medieval" and _medieval(run):
		return
	if (style == "market" or _ages(style)) and run.round_number >= 2:
		for type: String in ["market", "arms_stall", "knapper", "hide_stall", "hide_rack", "hunting_lodge",
				"charm_stall", "bone_carver", "provisions_stall", "smoke_hut"]:
			_order(run, type)
	elif style != "workers" and run.round_number >= 3:
		for type: String in ["market", "arms_stall", "knapper", "hide_stall", "hide_rack"]:
			_order(run, type)
	if style != "workers" and run.round_number >= (3 if style == "heroes" else 4):
		_order(run, "shrine")
	if run.round_number >= 3:
		_order(run, "drying_rack")
	if run.round_number >= 2:
		_order(run, "watch_post")
	# Gates last, with whatever is left over.
	_gates(run)


## From round 5, a yard so craftspeople pave the busiest paths (from round 3 cost about 9 points:
## paving early eats the stone and wood the town needs).
## The ages styles wait until their age-up building is ordered: the yard and paving eat the stone it needs.
func _paving(run: RunState) -> void:
	var saving_for := "stone_keep" if style == "medieval" else ("bronze_moot" if style == "bronze" else "")
	if saving_for != "" and run.world.count_buildings(saving_for, false) == 0:
		return
	if run.round_number >= 5:
		for b in run.content.buildings:
			if run.content.buildings[b].get("paves", false):
				_order(run, b)


## A garden when food is short: less than `garden_days` days of eating in store at the start of the round.
func _gardens(run: RunState) -> void:
	if garden_days <= 0.0 or float(run.stock["food"]) >= run.food_needed_today() * garden_days:
		return
	for b in run.content.buildings:
		if run.content.buildings[b].get("daily", {}).has("food"):
			_order(run, b)
			return


## Upkeep buildings the cards recommend: a forester once the wild plants are picked over, a charcoal pit when fuel is low.
func _upkeep(run: RunState) -> void:
	if not upkeep:
		return
	for type: String in run.content.buildings:
		var why := run.hand.need(type)
		if why == "regrow" or why == "fuel":
			_order(run, type)


## One gate a round across the busiest gap, up to `gates`.
func _gates(run: RunState) -> void:
	if run.round_number < gate_round:
		return
	for b in run.content.buildings:
		if run.content.buildings[b].has("gate_hp") and run.world.count_buildings(b, false) < gates:
			_order(run, b)


func _bronze(run: RunState) -> void:
	if run.round_number >= 3:
		_order(run, "bronze_moot")
	if run.world.count_buildings("bronze_moot", false) == 0:
		return
	if not _order(run, "smelter") and run.world.count_buildings("smelter", false) == 0:
		return
	_order(run, "bronzesmith")
	while int(run.stock["shells"]) > 45 and int(run.stock["tin"]) < 4 and run.trade("tin"):
		pass
	# The medieval bot keeps its ingots for the Stone keep until it is ordered.
	if style == "medieval" and run.world.count_buildings("stone_keep", false) == 0:
		return
	for id: String in ["bronze_picks", "bronze_chisels", "bronze_spears"]:
		if run.tools.has(id):
			continue
		run.buy_tools(id)
		break


## Spare shells buy timber and stone from the caravan before anything is ordered.
func _buy_goods(run: RunState) -> void:
	for good: String in ["stone", "wood"]:
		while int(run.stock["shells"]) > 60 and int(run.stock[good]) < 30 and run.trade(good):
			pass


func _ages(s: String) -> bool:
	return s == "bronze" or s == "medieval"


## The medieval bot's build. Returns true while it is saving for the Stone keep (only essentials then).
func _medieval(run: RunState) -> bool:
	var w := run.world
	if w.count_buildings("bronzesmith", false) == 0:
		return false
	if w.count_buildings("stone_keep", false) == 0:
		if run.round_number < 5 or run.population() < int(run.content.buildings["stone_keep"].get("min_people", 0)):
			return false
		_order(run, "stone_keep")
		return w.count_buildings("stone_keep", false) == 0
	if not run.content.age_reached(run.age, "medieval"):
		return false
	if run.housing() - run.population() <= 4:
		_order(run, "townhouse")
	while run.count_role("tribesperson") / 2 > w.count_buildings("field", false) and _order(run, "field"):
		pass
	for type: String in ["charcoal_burner", "bloomery", "blacksmith", "guildhall", "chapel", "charcoal_burner"]:
		_order(run, type)
	for id: String in ["iron_ploughs", "mail_and_halberds", "iron_tools"]:
		if not run.tools.has(id):
			run.buy_tools(id)
			break
	return false


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
			"family":
				score = 8.0 if style == "medieval" else 3.5
			"hero":
				score = 5.0 if style != "workers" else -100.0
				if style == "heroes":
					score = 50.0
				if free_beds(run) <= 0:
					score = -50.0
			"tribesperson":
				score = 4.0 - run.count_role("tribesperson") * 0.6
				# Between two leanings, grow the bigger band. Favouring whatever the town was shortest of that dawn
				# instead cost the bots 5-13 win-rate points (40 seeds), since the shortage moves on while the newcomer stays.
				if card.has("leaning"):
					var counts := run.world.folk_ai.count_leanings()
					score += 0.05 * mini(int(counts.get("tribesperson/" + card["leaning"], 0)), 5)
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


## Relics it likes most first, ranked by how often bot runs that held them won (40 runs x 3 styles,
## blind picks, 2026-10-20). Anything not listed ranks after these; ties keep the offer's order.
const RELIC_RANK := ["lone_wolf_pelt", "horde_drum", "broken_crown", "levy_horn", "ram_thorn_stakes", "tithe_bowl",
	"grave_salt", "ancestor_mask", "raiders_spears", "wolfskin_cloaks", "pack_train", "ram_timbers", "owl_eyes", "sacred_spring", "witchs_thread", "chieftains_torc", "elders_tale",
	"turncoats_torc", "fire_arrows", "bone_flute", "moneylenders_knot", "hollow_drum", "bear_tooth_charm",
	"blood_brother_knot", "wanderers_fire", "smoked_haunches", "grave_goods", "bone_ward", "splintered_ram", "ember_stone",
	"oxhide_sledges", "seed_cache", "ridgeheart"]


## Takes the offered relic it ranks highest (never skips: every relic helps somewhat).
func pick_relic(run: RunState) -> String:
	var best := ""
	var best_rank := INF
	for id in run.relic_offer:
		var rank := RELIC_RANK.find(id)
		var score := float(rank) if rank >= 0 else 100.0
		if score < best_rank:
			best_rank = score
			best = id
	return best
