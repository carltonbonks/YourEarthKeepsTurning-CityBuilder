class_name CardRoll
extends RefCounted
## Rolled rarity on dealt cards (Yusuf, 2026-10-23): each card dealt rolls its own rarity (roll in data/rarity.json),
## apart from how often its kind is offered, and a rolled card carries modifiers. Blue: one mark (data/marks.json).
## Yellow: a mark and one or two powerful modifiers (data/card_mods.json). Orange: one transmutation, a trade-off
## that bends a rule. Every dawn card (townsfolk, heroes, families, ventures) and the caravan's trade cards
## roll, and so do blueprint and upgrade offers in the build draft; the card keeps "roll", "mark" (townsfolk only) and
## "boons" (card modifier ids). A legend is the orange roll of a hero card. A drafted blueprint or upgrade writes its
## modifiers into the building's numbers for the rest of the run (`apply_to_building`).


## The rarity a dealt card rolls this round: each rolled rarity's chance climbs evenly from its first to its last
## round number (roll in data/rarity.json); white is what is left.
static func roll_rarity(content: Content, rng: SeededRng, round_number: int, odds_mult := 1.0) -> String:
	var r := rng.randf()
	var order: Array = content.rarity["order"]
	for i in range(order.size() - 1, 0, -1):
		var chance := roll_chance(content, order[i], round_number) * odds_mult
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
	var fits := {"role": card["role"], "leaning": card.has("leaning")}
	var boons: Array[String] = []
	var mark := ""
	if rarity == "orange":
		boons = _pick_boons(content, rng, "orange", "folk", fits, 1)
	else:
		mark = _pick_mark(content, rng, card["role"])
		if rarity == "yellow":
			var count := 2 if rng.randf() < content.num("card_mod_second_chance") else 1
			boons = _pick_boons(content, rng, "yellow", "folk", fits, count)
	if mark == "" and boons.is_empty():
		return
	card["roll"] = rarity
	if mark != "":
		card["mark"] = mark
	if not boons.is_empty():
		card["boons"] = boons


## Rolls any other card's rarity and modifiers into it (card kind: hero, family, venture, trade). fits says what
## the card is, for modifiers that need it (data/card_mods.json needs_*). Blue: one blue modifier. Yellow: a yellow
## one and a blue one, sometimes two. Orange: one orange. odds_mult makes rolls above white likelier (trades).
static func roll_card(content: Content, rng: SeededRng, card: Dictionary, kind: String, fits: Dictionary, round_number: int,
		odds_mult := 1.0) -> void:
	var rarity := roll_rarity(content, rng, round_number, odds_mult)
	if rarity == "white":
		return
	var boons: Array[String] = []
	if rarity == "orange":
		boons = _pick_boons(content, rng, "orange", kind, fits, 1)
	else:
		if rarity == "yellow":
			boons = _pick_boons(content, rng, "yellow", kind, fits, 1)
		var blues := 1 if rarity == "blue" else (2 if rng.randf() < content.num("card_mod_second_chance") else 1)
		if rarity == "yellow" and boons.is_empty():
			blues = 2
		boons.append_array(_pick_boons(content, rng, "blue", kind, fits, blues))
	if boons.is_empty():
		return
	card["roll"] = rarity
	card["boons"] = boons


## A mark that can come on a role's card (data/marks.json roles, if given), or "".
static func _pick_mark(content: Content, rng: SeededRng, role: String) -> String:
	var ids: Array = content.marks.keys().filter(func(id: String) -> bool:
		return content.marks[id].get("roles", [role]).has(role))
	ids.sort()
	return rng.pick(ids) if not ids.is_empty() else ""


## True when a card modifier can come on a card of this kind as fits describes it: its roles, a leaning, a hero's
## weapon, a deal's payment or goods.
static func fits_card(m: Dictionary, kind: String, fits: Dictionary) -> bool:
	if not m.get("cards", []).has(kind):
		return false
	if m.has("roles") and not m["roles"].has(fits.get("role", "")):
		return false
	for need: String in ["leaning", "weapon", "give", "get"]:
		if m.get("needs_" + need, false) and not fits.get(need, false):
			return false
	if fits.has("def"):
		return fits_building(m, fits["def"])
	return true


## True when a blueprint or upgrade modifier fits a building's data: it has every key in needs, at least one of the
## keys mult or add change (if any), and a max of at least min_max.
static func fits_building(m: Dictionary, def: Dictionary) -> bool:
	if int(def.get("max", 99)) < int(m.get("min_max", 0)):
		return false
	for key: String in m.get("needs", []):
		if not _has_path(def, key):
			return false
	var keys: Array = m.get("mult", {}).keys() + m.get("add", {}).keys()
	return keys.is_empty() or keys.any(func(key: String) -> bool: return _has_path(def, key))


## Rolls a blueprint or upgrade offer (kind "blueprint" or "upgrade") for the building it is or changes.
static func roll_building(content: Content, rng: SeededRng, card: Dictionary, kind: String, type: String, round_number: int) -> void:
	roll_card(content, rng, card, kind, {"def": content.buildings[type]}, round_number)


## Writes a drafted card's modifiers into this run's data for a building (Content.for_run keeps it to this run), so
## every one of it, built or still to come, is changed: mult and add only where the building has the key, grant always.
static func apply_to_building(run: RunState, type: String, card: Dictionary) -> void:
	var def: Dictionary = run.content.buildings[type]
	for id: String in card.get("boons", []):
		var m: Dictionary = run.content.card_mods[id]
		for key: String in m.get("mult", {}):
			if not _has_path(def, key):
				continue
			var share := float(m["mult"][key])
			var at: Variant = _get_path(def, key)
			if at is Dictionary:
				for r: String in at:
					at[r] = roundi(float(at[r]) * (1.0 + share)) if share <= -1.0 else maxi(1, roundi(float(at[r]) * (1.0 + share)))
			else:
				_set_path(def, key, float(at) * (1.0 + share))
		for key: String in m.get("add", {}):
			if _has_path(def, key):
				_set_path(def, key, float(_get_path(def, key)) + float(m["add"][key]))
		for key: String in m.get("grant", {}):
			_set_path(def, key, float(_get_path(def, key) if _has_path(def, key) else 0.0) + float(m["grant"][key]))
		run.record.note_count("card_mods_taken", 1, id)


static func _has_path(def: Dictionary, key: String) -> bool:
	var at: Variant = def
	for part in key.split("."):
		if not (at is Dictionary and at.has(part)):
			return false
		at = at[part]
	return true


static func _get_path(def: Dictionary, key: String) -> Variant:
	var at: Variant = def
	for part in key.split("."):
		at = at[part]
	return at


static func _set_path(def: Dictionary, key: String, value: Variant) -> void:
	var parts := key.split(".")
	var at: Dictionary = def
	for i in parts.size() - 1:
		if not at.has(parts[i]):
			at[parts[i]] = {}
		at = at[parts[i]]
	at[parts[parts.size() - 1]] = value


## Up to count different modifiers of a rarity that fit a card of this kind.
static func _pick_boons(content: Content, rng: SeededRng, rarity: String, kind: String, fits: Dictionary, count: int) -> Array[String]:
	var ids: Array = content.card_mods.keys().filter(func(id: String) -> bool:
		var m: Dictionary = content.card_mods[id]
		return m.get("rarity", "") == rarity and fits_card(m, kind, fits))
	ids.sort()
	var out: Array[String] = []
	while out.size() < count and not ids.is_empty():
		var id: String = rng.pick(ids)
		ids.erase(id)
		out.append(id)
	return out


## One number summed over a card's modifiers (data/card_mods.json), e.g. a deal's price_mult.
static func card_sum(content: Content, card: Dictionary, key: String) -> float:
	var total := 0.0
	for id: String in card.get("boons", []):
		total += float(content.card_mods[id].get(key, 0.0))
	return total


## Goods or people summed over a card's modifiers for a key whose values are {id: amount}, e.g. goods, extra_folk.
static func card_goods(content: Content, card: Dictionary, key: String) -> Dictionary:
	var out := {}
	for id: String in card.get("boons", []):
		var add: Dictionary = content.card_mods[id].get(key, {})
		for g: String in add:
			out[g] = int(out.get(g, 0)) + int(add[g])
	return out


## True when one of a card's modifiers has this key.
static func card_has(content: Content, card: Dictionary, key: String) -> bool:
	return card.get("boons", []).any(func(id: String) -> bool: return content.card_mods[id].has(key))


## Counts the modifiers on a card taken (not a townsperson's: apply_to counts those) in the round record.
static func note_taken(run: RunState, card: Dictionary) -> void:
	for id: String in card.get("boons", []):
		run.record.note_count("card_mods_taken", 1, id)


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


## People a rolled card brings beyond the usual (Twins, a bigger family, an escort).
static func extra_people(content: Content, card: Dictionary) -> int:
	var extra := int(card_sum(content, card, "twin"))
	for n: int in card_goods(content, card, "extra_folk").values():
		extra += n
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
