class_name CardRoll
extends RefCounted
## Rolled rarity on dealt cards (Yusuf, 2026-10-23): each card dealt rolls its own rarity (roll in data/rarity.json),
## apart from how often its kind is offered, and a rolled card carries modifiers. Blue: one mark (data/marks.json).
## Yellow: a mark and one or two powerful modifiers (data/card_mods.json). Orange: one transmutation, a trade-off
## that bends a rule. Townsfolk dawn cards roll today; the card keeps "roll", "mark" and "boons".


## The rarity a dealt card rolls this round: each rolled rarity's chance climbs evenly from its first to its last
## round number (roll in data/rarity.json); white is what is left.
static func roll_rarity(content: Content, rng: SeededRng, round_number: int) -> String:
	var r := rng.randf()
	var order: Array = content.rarity["order"]
	for i in range(order.size() - 1, 0, -1):
		var chance := roll_chance(content, order[i], round_number)
		if r < chance:
			return order[i]
		r -= chance
	return order[0]


## A rarity's chance to be rolled on a dealt card in a given round (0 for white, which takes what is left).
static func roll_chance(content: Content, rarity_id: String, round_number: int) -> float:
	var span: Array = content.rarity_tier(rarity_id).get("roll", [])
	if span.size() < 2:
		return 0.0
	var t := clampf(float(round_number - 1) / maxf(1.0, content.num("rounds_to_win") - 1.0), 0.0, 1.0)
	return lerpf(float(span[0]), float(span[1]), t)


## Rolls a townsfolk dawn card's rarity and modifiers into the card ({kind: "folk", role, leaning?}).
static func roll_folk(content: Content, rng: SeededRng, card: Dictionary, round_number: int) -> void:
	var rarity := roll_rarity(content, rng, round_number)
	if rarity == "white":
		return
	var role: String = card["role"]
	var boons: Array[String] = []
	var mark := ""
	if rarity == "orange":
		boons = _pick_boons(content, rng, "orange", role, card.has("leaning"), 1)
	else:
		mark = _pick_mark(content, rng, role)
		if rarity == "yellow":
			var count := 2 if rng.randf() < content.num("card_mod_second_chance") else 1
			boons = _pick_boons(content, rng, "yellow", role, card.has("leaning"), count)
	if mark == "" and boons.is_empty():
		return
	card["roll"] = rarity
	if mark != "":
		card["mark"] = mark
	if not boons.is_empty():
		card["boons"] = boons


## A mark that can come on a role's card (data/marks.json roles, if given), or "".
static func _pick_mark(content: Content, rng: SeededRng, role: String) -> String:
	var ids: Array = content.marks.keys().filter(func(id: String) -> bool:
		return content.marks[id].get("roles", [role]).has(role))
	ids.sort()
	return rng.pick(ids) if not ids.is_empty() else ""


## Up to count different modifiers of a rarity that fit a townsfolk card of this role.
static func _pick_boons(content: Content, rng: SeededRng, rarity: String, role: String, leaning: bool, count: int) -> Array[String]:
	var ids: Array = content.card_mods.keys().filter(func(id: String) -> bool:
		var m: Dictionary = content.card_mods[id]
		return m.get("rarity", "") == rarity and m.get("cards", []).has("folk") \
			and m.get("roles", [role]).has(role) and (leaning or not m.get("needs_leaning", false)))
	ids.sort()
	var out: Array[String] = []
	while out.size() < count and not ids.is_empty():
		var id: String = rng.pick(ids)
		ids.erase(id)
		out.append(id)
	return out


## The card's rolled rarity ("white" when it rolled nothing).
static func roll_of(card: Dictionary) -> String:
	return str(card.get("roll", "white"))


## Every modifier id on a card, mark first.
static func mods_of(card: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if card.has("mark"):
		out.append(card["mark"])
	for id: String in card.get("boons", []):
		out.append(id)
	return out


## One modifier's entry: a mark's (data/marks.json) or a card modifier's (data/card_mods.json).
static func mod_def(content: Content, id: String) -> Dictionary:
	return content.marks[id] if content.marks.has(id) else content.card_mods[id]


## The lines a rolled card shows, one a modifier: "Swift: moves 10% faster".
static func lines(content: Content, card: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in mods_of(card):
		var m := mod_def(content, id)
		out.append("%s: %s" % [m["name"], m["text"]])
	return out


## People a rolled card brings beyond the usual one (Twins).
static func extra_people(content: Content, card: Dictionary) -> int:
	var extra := 0
	for id: String in card.get("boons", []):
		extra += int(content.card_mods[id].get("twin", 0))
	return extra


## Gives a newcomer what its rolled card carried: the mark (born with it), the modifiers, and their stats.
static func apply_to(run: RunState, unit: Unit, card: Dictionary) -> void:
	if not card.has("roll"):
		return
	unit.mark = str(card.get("mark", ""))
	unit.mark_from = ""
	for id: String in card.get("boons", []):
		unit.boons.append(id)
		unit.kills += int(run.content.card_mods[id].get("kills", 0))
		run.record.note_count("card_mods_taken", 1, id)
	if unit.mark != "":
		run.record.note_count("card_mods_taken", 1, unit.mark)
	run.world.folk_ai.apply_folk_stats(unit)
	unit.hp = unit.max_hp
