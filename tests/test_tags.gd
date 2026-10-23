extends TestCase
## Keeps the tag habit honest (see docs/DEVELOPMENT.md): every tag a rule reads is
## explained to players in data/tags.json, every explained tag is still read by a
## rule, and some entity carries it. Rules are found by scanning sim/ and game/ for
## has_tag(...) / unit_has_tag(...) calls with a tag written in quotes.

const CODE_DIRS := ["res://sim", "res://game"]
const READ_PATTERN := "has_tag\\([^)]*\"([a-z_]+)\"\\)"


## Tags named in quotes in has_tag / unit_has_tag calls, with the file each is read in.
func _tags_read_in_code() -> Dictionary:
	var found := {}
	var regex := RegEx.create_from_string(READ_PATTERN)
	for dir: String in CODE_DIRS:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(dir.path_join(file))
			for m in regex.search_all(text):
				found[m.get_string(1)] = dir.path_join(file)
	return found


## Tags buildings key on in their data: a prize's tag, and the tag of the nodes a building tends.
func _prize_tags(c: Content) -> Array:
	var out := []
	for id: String in c.buildings:
		for key in ["prize", "tends"]:
			var rule: Dictionary = c.buildings[id].get(key, {})
			if rule.has("tag"):
				out.append(rule["tag"])
	return out


## Tags relics key their effects on (RunState.TAG_EFFECTS, e.g. foe_damage {"beast": 0.4}): rules read these too.
func _relic_tags(c: Content) -> Array:
	var out := []
	for id: String in c.relics:
		for key: String in RunState.TAG_EFFECTS:
			out.append_array(c.relics[id]["effects"].get(key, {}).keys())
	return out


func _carried(c: Content, tag: String) -> bool:
	for kind: String in Content.TAG_KINDS:
		for id: String in c.tag_table(kind):
			if c.has_tag(kind, id, tag):
				return true
	return false


func test_rules_find_the_tags_they_read() -> void:
	var read := _tags_read_in_code()
	check(read.has("sentient"), "the scan finds the sentient rule in sim/world.gd")


func test_every_tag_a_rule_reads_is_explained() -> void:
	var c := Content.load_default()
	var read := _tags_read_in_code()
	for tag: String in read:
		check(c.tags.has(tag), "'%s' is read in %s: add a line for it to data/tags.json" % [tag, read[tag]])
		check(_carried(c, tag), "'%s' is read in %s but nothing in data/ carries it" % [tag, read[tag]])
	for tag in _prize_tags(c):
		check(_carried(c, tag), "a building pays a prize for '%s' but nothing in data/ carries it" % tag)
	for tag in _relic_tags(c):
		check(c.tags.has(tag), "a relic keys on '%s': add a line for it to data/tags.json" % tag)
		check(_carried(c, tag), "a relic keys on '%s' but nothing in data/ carries it" % tag)


func test_every_explained_tag_is_still_read() -> void:
	var c := Content.load_default()
	var read := _tags_read_in_code()
	var prizes := _prize_tags(c) + _relic_tags(c)
	for tag: String in c.tags:
		check(read.has(tag) or prizes.has(tag), "data/tags.json explains '%s', but no rule reads it any more" % tag)


func test_tags_are_plain_lowercase_words() -> void:
	var c := Content.load_default()
	var word := RegEx.create_from_string("^[a-z][a-z_]*$")
	for kind: String in Content.TAG_KINDS:
		for id: String in c.tag_table(kind):
			for tag in c.tags_of(kind, id):
				check(tag is String and word.search(tag) != null, "%s %s has an odd tag '%s'" % [kind, id, tag])


func test_units_carry_their_type_tags() -> void:
	var c := Content.load_default()
	var wolf := Unit.new()
	wolf.team = Unit.Team.ENEMY
	wolf.type_id = "wolf"
	check(c.unit_has_tag(wolf, "beast"), "a wolf unit is a beast")
	check(not c.unit_has_tag(wolf, "undead"), "a wolf unit is not undead")
	check(c.has_tag("enemy", "barrow_wight", "undead"), "has_tag reads enemy data")
	check(c.tags_of("relic", "no_such_relic").is_empty(), "unknown ids carry no tags")
