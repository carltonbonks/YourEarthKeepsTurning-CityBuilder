class_name RunRecord
extends RefCounted
## The run's machine-readable history (`run.record`), for the Run history screen, bot balance runs,
## tools/run_report.gd and tools/export_csv.py. `entry` is the round being played; finished rounds
## go to `rounds`. Every rule that should show up in the data logs it through a note_* method here.
##
## Format changes bump RECORD_FORMAT so old saved runs can still be read. Never drop or rename fields.
## 1: one wave per round. 2: days, dawn picks, townsfolk, dens.
## 3: small raids on early nights, a report per night ("nights").
## 4: hero energy, lodgings, whims and items ("whims", "loot", "sales", "hero_spending"; hero items).
## 5: each night's report also lists who walked away hungry ("left").
## 6: the marketplace: "prices", "crafted", "market" (stall sales), "prizes", "obsidian", "yields"; hero "pack";
##    "sales" are now made at the market and there are no trader purchases.
## 7: ages and promotions: "age", "age_up_round", "tools", "departed" (heroes who left unhappy), hero "mood";
##    per round "promotions", "trades", "cassiterite", "heroes_left"; per night "heroes_left", "hero_deaths", "cold".
## 8: the ring town and roads: "road" actions (waypoints, squares), per round "paving" (goods spent on roads) and
##    "town" at the round's end (squares staked, paved per road kind, trail squares, plots built per ring);
##    "plots" (each building's ring and sector) in the run record.
## 9: palisades: "wall" / "unstake_wall" actions, per round "walling" (goods spent on palisades) and
##    "breaches" (palisade squares raiders broke), and "walls" in the round's "town" (squares staked, standing, gates).
## 10: roads and palisades are no longer staked (no "road" / "wall" actions, no "walling"); the round's
##    "town" drops "staked" and "walls" and adds "paths" (worn path squares) and "gates" ({built, broken});
##    "breaches" now counts gate squares raiders broke. Stone-layers pave the busiest worn paths.
## 11: per round "power" when the wave comes: the town's power level by part (heroes, fighters, defences, total)
##     and the wave's ("wave", and "wave_scheduled" before catch-up), on the same scale (sim/power.gd);
##     per round "wave_eased" (raiders catch-up held back from the scheduled wave).
## 12: per round "food_grown" (food gardens brought in at dawns); a dawn pick has "hunger_turned_away"
##     (the role of someone who had just left hungry, so none of that role were offered).
## 13: the medieval age: "age_rounds" (age -> round reached), new goods in "stock" (bog_iron, charcoal, iron, steel);
##     a dawn pick can take "family" (several townsfolk at once); "promotions" can be a champion knighted
##     (role "champion", "level"); per round "siege_damage" (what battering rams did to gates and the hearth).
## 14: building cards: per round "build_hands" (the building cards dealt, then one more list per redraw,
##     each {"cards": [building types]}); a "redraw" action ({"kind": "redraw", "cost"}).
## 15: towers can be broken: per round "towers_broken" (watch posts or the keep knocked out by sentient raiders).
## 16: gathering trips: per round "gathered" (good -> amount townsfolk brought in from nodes) and "trips_cut_short"
##     (why -> count of gathering trips given up empty-handed: "dusk", "emptied" (node ran out), "unsafe").
## 17: the war camp: per round "camp_joined" (held-back raiders who joined the war camp as the round began),
##     "camp_raiders" (raiders in the camp then), "camps_cleared" and "camp_spoils" (shells the town took).
## 18: per round "tended" (good -> how much nodes regrew thanks to buildings that tend them, the Forester's hut).
## 19: the shifting earth: per round "shift" (from round 2) = what the earth did as the round began: "shift" (its number),
##     "swallowed" (node type -> count sunk at subducting seams), "dens_swallowed", "ridges" (colliding seams that pushed
##     their ridge up), "raised" (node type -> upthrust nodes ridges raised), "rifts" (seams that opened), "grown" (node
##     type -> fresh nodes in rifts), "roads_refunded" (squares of paving swallowed and paid back).
## 20: rule-changing relics: per round "relic_effects" (effect key from data/relics.json -> times its rule fired,
##     or shells/fuel it brought, e.g. "kill_shells", "turncoat_chance", "risen_per_night") and "relic_gifts" (relics
##     Broken Crown handed out with it). Relics now include pacts (tag "pact"), offered on pact_rounds.
## 21: tribespeople's leanings: a dawn pick entry has "offered_leanings" (one per offered card, "" for none) when any card
##     had one, and "leaning" when the card taken had one; per round "gathered_leaned" (good -> amount brought in by
##     gatherers leaning toward it) and "leanings_end" (leaning -> townsfolk with it at the round's end).
## 22: leaning bands: per round "gathered_band" (good -> extra a band's bigger loads brought in) and "bands_end"
##     (leaning -> band tier reached at the round's end, 1 = first tier; leanings with no band are left out).
## 23: spoils of a beaten attack: per round "spoils" (when one was offered) = {id, kind (enemy tag), foes (how many of
##     that kind came), taken, goods (good -> amount it brought, when taken)}; its id is also in "relic_offer".
## 24: hearty meals: per round "hearty_meals" (extra meals heroes ate at dawn, each making them well fed for the day).
## 25: founding traditions: "traditions" (the ids chosen before round 1, [] for none).
## 26: ventures: a dawn pick can take "venture:<id>" (data/ventures.json); that entry has "venture_lost" (tribespeople
##     who never came home) and "venture_goods" (good -> amount brought).
## 27: cluster combos: per round "combos_end" (combo id from data/combos.json -> buildings in it at the round's end).
## 28: the pedlar's carousel: per round "carousel" (on carousel rounds) = one entry per pick, in order: {hero, level,
##     base, tier, affixes, equipped}, plus "carousel_left" (items nobody took).
## 29: the earth wakes and the attack rides the dens: a round's "shift" also has "woke" (the kind of seam that woke and did
##     something big: "subduct", "collide", "rift", or "" for none) and "woke_ring" (its ring, -1 for none); per round
##     "wave_side_dens" (per warned side, the den type the warband came by, "" for open country).
## 30: the geomancer and earth finds: a round's "shift" also has "omen" (the geomancer's omen it followed, "" for none)
##     and "finds" (node type -> earth finds it left: starstone, sunk hoards); per round "finds_dug" (node type ->
##     finds heroes dug out, each an earthborn item, also in "loot").
## 31: who did what: per round "impact" = {"folk": {role: row}, "heroes": {name: row}, "defences": {who: row}}, a row
##     being any of "dealt", "taken" (damage, never more than the victim had left), "kills", "lost" (townsfolk who died),
##     "goods" (good -> amount brought home), "made" (things crafted), "raised" (buildings finished), "paved"
##     (squares), "patched" (hearth health mended); a hero row also has "class". Defences are "hearth", a tower's
##     building type, or "relic" (damage relics did on their own). Risen bones count as the role "risen".
## 32: the pedlar's camp replaces the carousel (no more "carousel"): on pedlar rounds "pedlar_offer" (the pedlar ids
##     offered) and, when one was invited, "pedlar" = {id, distance, wares, visits, sold (items heroes sold it),
##     sold_value, bought: [{hero, base, tier, affixes, price}], guards (names hired), paid: [{hero, base, tier,
##     affixes}] (wares guards took as pay), fell (raiders overran it), left (wares it took away)}; the "pedlar"
##     action records the choice ("" for none); hero_spending gains "pedlar".
## 33: row cards replace silent cluster combos: "combos_end" now counts only rows (combo ids from data/combos.json)
##     ordered on a row card; build hand labels list a row card as "row:<id>"; the "row" action records ordering one.
## 34: geomancy spells replace omens (a shift's "omen" is always ""): per round "spells" = [{day, cast (spell id from
##     data/plates.json spells)} or {day, finished, did: {grown, raised (node type -> count), dens_swallowed, finds}}];
##     a dawn pick can take "spell:<id>".
## 35: blueprints replace one-use building cards: "build_hands" now lists each round's draft offers (then one list per
##     reroll, and one after each draft while drafts are left); per round "blueprints" = [{building}] drafted that round
##     (a drafted row adds its non-basic buildings); a "blueprint" action ({"kind": "blueprint", "building"} or {"row"}).
## 36: trade cards replace the caravan's per-good shop: per round "deals_offered" (deal ids from data/trades.json the
##     caravan laid out, [] before it comes) and "deals" = [{deal, rarity, got (good -> amount), reforged (heroes whose
##     weapon a smith raised), relic (one a relic dealer sold)}]; "trades" still counts goods bought, by good; a
##     "deal" action ({"kind": "deal", "deal"}).
## 37: idle hands: per round "idle_seconds" (role -> daytime seconds townsfolk stood idle), "trips_bumped" (good ->
##     gathering trips a gatherer leaning to the good took over from one who didn't); impact rows gain "helped" (seconds
##     townsfolk lent a hand at buildings) and, for heroes, "drilled" (XP from drilling on quiet days).
## 38: rarities (data/rarity.json): a dawn pick entry has "offered_rarities" (one rarity id per offered card) and
##     "legend": true when the hero taken was a legend (a few levels up, carrying a mythic item). Items' and relics'
##     rarities follow from their ids and affixes (Loot.rarity, Content.rarity_of).
## 39: opening rings: "rings_open" (rings of plots open at the end, and per round at its start); a "clear_ring"
##     action ({"kind": "clear_ring", "ring": rings now open}) when the player paid to clear the next ring; a
##     round's "build_hands" lists "ring" while the draft offered it.
## 40: runners (a building tagged courier, the runners' hut): per round "supply_runs" (provision recipe -> runs a
##     runner delivered to a hero in the wilds) and "runners_lost" (hero -> runners killed on the way); hero_spending
##     gains "runners" (the fees); impact rows gain "supplied" (deliveries made, for townsfolk; taken, for heroes); a
##     runner's delivery is also a "market" sale; trips_cut_short gains "runner" (a gatherer called away to run).
## 41: hero-shaping buildings: per round "drill_seconds" (hero-seconds drilled at the training yard), "hounds_given"
##     (hounds the kennel handed out) and "duels" (bouts in the duelling ring), each only when it happened. Rows are
##     offered only once the town has one of their buildings, so a drafted row adds at most one blueprint.
## 42: upgrades, rule-breakers and outposts: top-level "upgrades" (ids from data/upgrades.json, in the order taken)
##     and an "upgrade" action ({"kind": "upgrade", "upgrade"}); build_hands may list "upgrade:<id>" offers; per round
##     "outpost_goods" (good -> amount outposts brought in), "outposts_wrecked" and "outposts_moved" (building -> count),
##     only when it happened; a final plot of an outpost has ring 0 and sector -1.
## 43: a run's own blueprint pool: top-level "pool" (building ids the run's draft could offer, sorted).
## 44: escorts and marks: per round "escort_seconds" (gatherer-seconds walked faster with a warrior escorting) and
##     "marks_earned" (mark id from data/marks.json -> townsfolk who earned it drilling beside a hero), each only when
##     it happened; impact rows gain "trained" (seconds warriors drilled beside heroes); per round "marks_end"
##     (mark id -> living townsfolk carrying it as the round ends).
## 45: rolled dawn cards (sim/card_roll.gd): a pick entry gains "offered_rolls" (each card's rolled rarity, only when
##     one rolled above white) and, for a rolled card taken, "roll" and "mods" (its mark and card modifiers, mark first);
##     a legend hero's roll is orange. Per round "card_mods_taken" (modifier id -> newcomers who arrived with it) and
##     "card_mods_fired" (hollow_seer extra cards, many_mother kin, bloodsworn laid to rest), each only when it happened.
## 46: every dawn card and trade card rolls (sim/card_roll.gd): pick entries' "offered_rolls", "roll" and "mods" now
##     cover hero, family, venture and spell cards too (a legend is a hero card's "legend" modifier); per round
##     "deals_rolls" (each deal's rolled rarity, in deals_offered order), and a taken deal's entry in "deals" gains
##     "roll" and "mods" when it rolled; "card_mods_fired" also counts echoing, smugglers_hoard and cursed_gold.
## 47: blueprint and upgrade offers roll (sim/card_roll.gd): a "build_hands" entry gains "rolls" (each offer's rolled
##     rarity, in "cards" order, only when one rolled above white); a drafted blueprint's entry in "blueprints" and an
##     "upgrade" action gain "roll" and "mods" when it rolled; "card_mods_taken" counts blueprint and upgrade
##     modifiers and "card_mods_fired" counts twin_built's free building.
## 48: the earth dial (Yusuf, 2026-10-24): the rings click a whole plate; per round "crossing" (per warned side, the
##     near plate's kind the attack crosses: an id from data/plates.json near_kinds) as the round begins; a
##     "feed_earth" action ({"kind": "feed_earth", "cost", "from", "to": crossings before and after}); a round's
##     "shift" drops "rifts" and gains "wakes" (seams that woke) and "held" (the geomancer held the near ring);
##     per round "earth_risen" (enemy type -> raiders who got up again on a Barrow) and "grave_goods" (items heroes dug
##     up there), each only when it happened. The quicken spell is gone; "hold" and "wake" are new spell ids.
## 49: a round's "shift" may have "camp_swallowed" (true when a waking trench took the war camp).
## 50: the earth as this round's weather (Yusuf, 2026-10-25): only the near ring turns, so a round's "shift" is just
##     {"shift", "roads_refunded"}; seams, wakes, finds, spells and feeding the earth are gone, so "spells",
##     "finds_dug", "feed_earth" actions and "spell:<id>" picks no longer appear. "crossing", "earth_risen" and
##     "grave_goods" stay.
## 51: one founding tradition (Yusuf, 2026-10-25): "traditions" holds at most one id; "tradition_random" is true
##     when the player left it to chance for tradition_random_bonus goods.
## 52: crafts (Yusuf, 2026-10-26): top-level "crafts" (ids from data/crafts.json, in the order drafted); a "blueprint"
##     action may be {"kind": "blueprint", "craft"}; "build_hands" may list "craft:<id>" offers. Rows are gone, so
##     "combos_end" is always empty and no "row:<id>" offers or "row" actions appear.
## 53: first-run intro (Yusuf, 2026-10-26): a tradition's blueprint is drafted as the town is founded, logged as a
##     "tradition_blueprint" action ("building" or "craft") and in "blueprints"; top-level "gentle" is true for a
##     player's first run (its first dawn offers only a few tribespeople, round 1's draft has no reroll).
## 54: townsfolk at work (Yusuf, 2026-10-26): per round "folk_time" = {role: {kind: seconds}}, how each townsfolk
##     role spent the round (kinds work, fallback, idle, down from data/townsfolk.json time_kinds; workers by day,
##     warriors day and night), rounded to whole seconds.
## 55: mercy as a loan (Yusuf, 2026-10-26): per round "camp_due" (war camp raiders who joined in an earlier round,
##     due to march with this round's attack, as the round begins), "camp_marched" (how many did march),
##     "outmatched" (the scheduled wave was over catch-up's limit) and "glory" (the town held an attack the warband
##     didn't need to ease, so the relic offer had glory_relic_choices more). "wave" now also counts the camp's
##     raiders due, and "power"'s "wave" includes those who marched. "camp_spoils" stays 0 (no plunder).
## 56: raider routes and quick defences (Yusuf, 2026-10-27): per round "spotted" (who first saw each raider coming
##     for the town: folk, hero, tower or hearth -> count), "barricades_planned" (gaps the alarm sent folk to
##     barricade, each paid for), "barricades_raised" and "barricades_broken"; townsfolk impact rows may have
##     "barricaded" (barricades raised).
## 57: run paths and trades guilds (Yusuf, 2026-10-27): top-level "paths" (path id -> tier held) and "guilds"
##     (tribesperson leaning -> round chartered); a "charter" action ({offered, path, tier}, path "" when let go); a dawn
##     pick may take "guild:<leaning>"; per round "guild_spared" (good -> goods a gentle guild left in the node) and
##     "guild_tended" (good -> goods guild-worked nodes regrew at dawn, also counted in "tended").
const RECORD_FORMAT := 57

var run: RunState
## Finished rounds, oldest first.
var rounds: Array[Dictionary] = []
## The round being played ({} between a finished run's last round and nothing).
var entry := {}


func _init(run_state: RunState) -> void:
	run = run_state


## The whole run so far as plain data (saved by the game, read by tools/run_report.gd).
## Deterministic: no clock or machine details; the game adds those when saving.
func to_record() -> Dictionary:
	var world := run.world
	var result := "in_progress"
	if run.phase == RunState.Phase.WON:
		result = "won"
	elif run.phase == RunState.Phase.LOST:
		result = "lost"
	var all_rounds: Array = rounds.duplicate(true)
	if not run.is_over():
		var current := entry.duplicate(true)
		current["impact"] = rounded_impact(current.get("impact", {}))
		current["folk_time"] = rounded_time(run.world.folk_ai.role_time)
		all_rounds.append(current)
	return {
		"format": RECORD_FORMAT,
		"seed": run.run_seed,
		"result": result,
		"round_reached": run.round_number,
		"rounds_to_win": run.content.int_num("rounds_to_win"),
		"stock": run.stock.duplicate(),
		"keep_hp": roundi(world.hearth_hp),
		"buildings": world.buildings.map(func(b: Dictionary) -> String: return b["type"]),
		"plots": world.buildings.map(func(b: Dictionary) -> Dictionary:
			if int(b["plot"]) < 0:
				return {"building": b["type"], "ring": 0, "sector": -1}
			var plot: Dictionary = world.town.plots[b["plot"]]
			return {"building": b["type"], "ring": int(plot["ring"]) + 1, "sector": int(plot["sector"])}),
		"townsfolk": folk_counts(),
		"townsfolk_lost": run.fallen_folk,
		"relics": run.relics.duplicate(),
		"upgrades": run.upgrades.duplicate(),
		"crafts": run.hand.crafts_taken.duplicate(),
		"pool": run.hand.pool().duplicate(),
		"traditions": run.traditions.duplicate(),
		"tradition_random": run.tradition_random,
		"paths": run.paths.duplicate(),
		"guilds": run.guilds.duplicate(),
		"gentle": run.gentle,
		"prices": run.prices.duplicate(),
		"age": run.age,
		"age_up_round": run.age_up_round,
		"age_rounds": run.age_rounds.duplicate(),
		"rings_open": run.rings_open,
		"tools": run.tools.duplicate(),
		"heroes": run.heroes.map(hero_snapshot),
		"fallen": run.fallen.map(hero_snapshot),
		"departed": run.departed.map(hero_snapshot),
		"rounds": all_rounds,
		"story": run.story.duplicate(),
	}


func folk_counts() -> Dictionary:
	var counts := {}
	for u in run.world.folk:
		counts[u.type_id] = int(counts.get(u.type_id, 0)) + 1
	return counts


func begin_round() -> void:
	entry = {"round": run.round_number, "stock_start": run.stock.duplicate(), "keep_hp_start": roundi(run.world.hearth_hp),
		"wave": run.waves.counts(), "wave_sides": run.world.side_names(),
		"wave_side_dens": run.world.wave_side_dens.duplicate(), "townsfolk_start": folk_counts(),
		"heroes_start": run.living_heroes().size(), "actions": [], "picks": [],
		"whims": [], "loot": [], "sales": [], "hero_spending": {},
		"prices": run.prices.duplicate(), "crafted": {}, "market": [], "prizes": 0, "obsidian": 0, "yields": {},
		"age": run.age, "rings_open": run.rings_open, "promotions": [], "trades": {}, "cassiterite": 0, "heroes_left": [], "paving": {},
		"breaches": 0, "wave_eased": run.wave_eased, "siege_damage": 0, "towers_broken": 0,
		"gathered": {}, "gathered_leaned": {}, "gathered_band": {}, "trips_cut_short": {}, "tended": {}, "idle_seconds": {}, "trips_bumped": {},
		"camp_joined": run.camp_joined, "camp_raiders": run.world.enemy_ai.camp_raiders().size(),
		"camps_cleared": 0, "camp_spoils": 0, "camp_due": run.waves.camp_due().size(), "camp_marched": 0,
		"outmatched": run.outmatched, "glory": false, "hearty_meals": 0,
		"spotted": {}, "barricades_planned": 0, "barricades_raised": 0, "barricades_broken": 0,
		"build_hands": [run.hand.hand_entry()], "blueprints": [], "impact": {},
		"deals_offered": run.caravan.labels(), "deals_rolls": run.caravan.offers.map(CardRoll.roll_of), "deals": []}


func end_round() -> void:
	entry["stock_end"] = run.stock.duplicate()
	entry["town"] = town_snapshot()
	entry["townsfolk_end"] = folk_counts()
	var leanings := {}
	var marks := {}
	for u in run.world.folk:
		if u.leaning != "":
			leanings[u.leaning] = int(leanings.get(u.leaning, 0)) + 1
		if u.mark != "" and u.alive:
			marks[u.mark] = int(marks.get(u.mark, 0)) + 1
	entry["leanings_end"] = leanings
	entry["marks_end"] = marks
	var bands := {}
	var counts := run.world.folk_ai.count_leanings()
	for key: String in counts:
		var parts := key.split("/")
		var reached := run.world.folk_ai.band_level(parts[0], parts[1], int(counts[key]))
		if reached > 0:
			bands[parts[1]] = reached
	entry["bands_end"] = bands
	# Rows are gone (format 52), so no building is in one.
	entry["combos_end"] = {}
	entry["impact"] = rounded_impact(entry.get("impact", {}))
	entry["folk_time"] = rounded_time(run.world.folk_ai.role_time)
	rounds.append(entry)
	entry = {}


## How the town's ground looks now, for the round record.
func town_snapshot() -> Dictionary:
	var world := run.world
	var rings := {}
	for plot in world.town.plots:
		if int(plot["building"]) >= 0:
			rings[str(plot["ring"] + 1)] = int(rings.get(str(plot["ring"] + 1), 0)) + 1
	return {"paved": world.town.paved_counts(), "trails": world.pathing.count_ground(Pathing.TRAIL),
		"paths": world.pathing.count_ground(Pathing.PATH), "plots_by_ring": rings, "gates": world.town.gate_counts()}


func hero_snapshot(hero: Unit) -> Dictionary:
	var items := []
	for slot: String in Loot.SLOTS:
		if hero.items.has(slot):
			items.append(item_record(hero.items[slot]))
	return {"name": hero.display_name, "class": hero.type_id, "trait": hero.trait_id, "level": hero.level,
		"hp": roundi(hero.hp), "max_hp": roundi(hero.max_hp), "gold": hero.gold,
		"weapon": int(hero.items.get("weapon", {}).get("tier", 0)), "armor": int(hero.items.get("armor", {}).get("tier", 0)),
		"charm": int(hero.items.get("charm", {}).get("tier", 0)), "items": items,
		"energy": roundi(hero.energy), "pack": hero.pack.duplicate(),
		"lodging": run.world.buildings[hero.lodging]["type"] if hero.lodging >= 0 else "",
		"kills": hero.kills, "alive": hero.alive, "mood": roundi(hero.mood)}


func item_record(item: Dictionary) -> Dictionary:
	return {"base": item["base"], "slot": Loot.slot(run.content, item), "tier": item["tier"],
		"affixes": item["affixes"].duplicate(), "value": Loot.value(run.content, item)}


## Something the player did in the build phase (a building order, a price, a tool set).
func note_action(action: Dictionary) -> void:
	entry["actions"].append(action)


## Appends to one of the round's lists ("picks", "promotions", "heroes_left", "sales").
func note_list(key: String, item: Dictionary) -> void:
	if entry.has(key):
		entry[key].append(item)


## Adds to one of the round's counters (a plain number, or good -> number when `what` is given).
func note_count(key: String, amount: int, what := "") -> void:
	if entry.is_empty():
		return
	if what != "":
		if not entry.has(key):
			entry[key] = {}
		entry[key][what] = int(entry[key].get(what, 0)) + amount
	else:
		entry[key] = int(entry.get(key, 0)) + amount


## Adds to one row of the round's "impact" (who did what): group "folk", "heroes" or "defences", then who
## (a role, a hero's name, "hearth" or a tower's type). `good` puts the amount under "goods".
func note_impact(group: String, who: String, stat: String, amount: float, good := "") -> void:
	if entry.is_empty() or amount <= 0.0:
		return
	var row: Dictionary = entry.get_or_add("impact", {}).get_or_add(group, {}).get_or_add(who, {})
	if good != "":
		var goods: Dictionary = row.get_or_add("goods", {})
		goods[good] = float(goods.get(good, 0.0)) + amount
	else:
		row[stat] = float(row.get(stat, 0.0)) + amount


## The impact row a unit's deeds go in: its group and who, or [] for enemies.
func impact_key(unit: Unit) -> Array:
	if unit == null or unit.is_enemy():
		return []
	if unit.is_hero():
		if entry.is_empty():
			return []
		var row: Dictionary = entry.get_or_add("impact", {}).get_or_add("heroes", {}).get_or_add(unit.display_name, {})
		row["class"] = unit.type_id
		return ["heroes", unit.display_name]
	return ["folk", "risen" if unit.risen else unit.type_id]


## One blow landed (World.damage): `dealt` is the health it took, `source` names the defence when nobody struck it.
func note_blow(attacker: Unit, victim: Unit, dealt: float, source: String, killed: bool) -> void:
	if entry.is_empty():
		return
	if victim.is_enemy():
		var key := impact_key(attacker) if attacker != null else (["defences", source] if source != "" else [])
		if key.is_empty():
			return
		note_impact(key[0], key[1], "dealt", dealt)
		if killed:
			note_impact(key[0], key[1], "kills", 1.0)
		return
	var key := impact_key(victim)
	if key.is_empty():
		return
	note_impact(key[0], key[1], "taken", dealt)
	if killed and victim.is_folk() and not victim.risen:
		note_impact(key[0], key[1], "lost", 1.0)


## Role -> time kind -> seconds, rounded to whole seconds (kinds under a second are left out).
static func rounded_time(role_time: Dictionary) -> Dictionary:
	var out := {}
	for role: String in role_time:
		var row := {}
		for kind: String in role_time[role]:
			if roundi(role_time[role][kind]) > 0:
				row[kind] = roundi(role_time[role][kind])
		out[role] = row
	return out


## The round's impact with every number rounded (amounts pile up as fractions while the round plays).
static func rounded_impact(impact: Dictionary) -> Dictionary:
	var out := {}
	for group: String in impact:
		out[group] = {}
		for who: String in impact[group]:
			var row := {}
			for stat: String in impact[group][who]:
				var value: Variant = impact[group][who][stat]
				if value is Dictionary:
					var goods := {}
					for good: String in value:
						goods[good] = roundi(float(value[good]))
					row[stat] = goods
				elif value is String:
					row[stat] = value
				else:
					row[stat] = roundi(float(value))
			out[group][who] = row
	return out


## Sets a plain value on the round ("aged_up", "relic_offer", "battle", ...).
func note_value(key: String, value: Variant) -> void:
	entry[key] = value


## Files a night's report.
func note_night(report: Dictionary) -> void:
	if not entry.has("nights"):
		entry["nights"] = []
	entry["nights"].append(report)


## Goods spent this round on something, e.g. "paving" (roads).
func note_spend(key: String, cost: Dictionary) -> void:
	if not entry.has(key):
		return
	for r: String in cost:
		entry[key][r] = int(entry[key].get(r, 0)) + int(cost[r])


## A raider broke a square of a gate.
func note_breach() -> void:
	if entry.has("breaches"):
		entry["breaches"] = int(entry["breaches"]) + 1


func note_whim(hero: Unit) -> void:
	if entry.has("whims"):
		entry["whims"].append({"day": run.world.day_index() + 1, "hero": hero.display_name, "whim": hero.whim})


func note_loot(hero: Unit, item: Dictionary, equipped: bool) -> void:
	if entry.has("loot"):
		var e := item_record(item)
		e.merge({"day": run.world.day_index() + 1, "hero": hero.display_name, "trait": hero.trait_id, "equipped": equipped})
		entry["loot"].append(e)


## Shells heroes paid the settlement this round, by reason (tavern nights, carousing).
func note_hero_spending(reason: String, shells: int) -> void:
	if entry.has("hero_spending"):
		entry["hero_spending"][reason] = int(entry["hero_spending"].get(reason, 0)) + shells


## The town's and the wave's power levels as the wave comes (see Power).
func note_power(wave_types: Array) -> void:
	if not entry.is_empty():
		entry["power"] = {"town": Power.town(run.world), "wave": snappedf(Power.wave(run.content, wave_types), 0.1),
			"wave_scheduled": snappedf(Power.wave(run.content, run.waves.generate(run.round_number)), 0.1)}


func note_crafted(recipe_id: String) -> void:
	if entry.has("crafted"):
		entry["crafted"][recipe_id] = int(entry["crafted"].get(recipe_id, 0)) + 1


func note_market_sale(hero: Unit, good: Dictionary, price: int) -> void:
	if entry.has("market"):
		entry["market"].append({"day": run.world.day_index() + 1, "hero": hero.display_name, "trait": hero.trait_id,
			"recipe": good["recipe"], "tier": int(good.get("tier", 1)), "price": price,
			"stall": run.content.market["recipes"][good["recipe"]]["stall"]})


## Goods the settlement got from carcasses, prize shells paid and obsidian shards bought.
func note_economy(key: String, amount: int, what := "") -> void:
	if not entry.has(key):
		return
	if key == "yields":
		entry["yields"][what] = int(entry["yields"].get(what, 0)) + amount
	else:
		entry[key] = int(entry[key]) + amount
