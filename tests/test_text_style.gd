extends TestCase
## Keeps the text language honest (docs/TEXT_STYLE.md): one word for home and for the enemy, one way to write
## levels and copies, and names in sentence case. Scans every player-facing string: quoted strings with a space
## in game/ and sim/ (outside comments), and every string value in data/*.json (outside "_note" keys).

const CODE_DIRS := ["res://sim", "res://game"]
## Words the game doesn't use for the town or the raiders (docs/TEXT_STYLE.md, Vocabulary).
const BANNED := "\\b(settlements?|villages?|enem(y|ies)|attackers?|invaders?)\\b"
## "Lv3" and "x3": levels are "Lv 3", copies and speeds "×3".
const FORMATS := "\\bLv\\d|[^a-z]x%d|%dx\\b|\\bx\\d"
## Words a name may capitalise after its first word: places and the named.
const PROPER := ["Fen", "Greenwood", "Stonefield", "Barrow", "Margrave", "Antlered", "Hollow", "Black", "King"]


func _code_strings() -> Array:
	var out := []
	var quoted := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	for dir: String in CODE_DIRS:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var n := 0
			for line in FileAccess.get_file_as_string(dir.path_join(file)).split("\n"):
				n += 1
				if line.strip_edges().begins_with("#"):
					continue
				for m in quoted.search_all(line):
					var s := m.get_string(1)
					if " " in s:
						out.append(["%s:%d" % [file, n], s])
	return out


func _data_strings(value: Variant, where: String, out: Array) -> void:
	if value is Dictionary:
		for key: String in value:
			if not key.begins_with("_"):
				_data_strings(value[key], where + "." + key, out)
	elif value is Array:
		for v in value:
			_data_strings(v, where, out)
	elif value is String and " " in value:
		out.append([where, value])


func _all_strings() -> Array:
	var out := _code_strings()
	for file in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json"):
			_data_strings(JSON.parse_string(FileAccess.get_file_as_string("res://data".path_join(file))), file, out)
	return out


func test_one_word_for_home_and_for_the_enemy() -> void:
	var banned := RegEx.create_from_string("(?i)" + BANNED)
	for pair: Array in _all_strings():
		check(banned.search(pair[1]) == null, "%s says \"%s\": the town is the town, attackers are raiders, beasts or foes" % pair)


func test_levels_and_copies_are_written_one_way() -> void:
	var formats := RegEx.create_from_string(FORMATS)
	for pair: Array in _all_strings():
		check(formats.search(pair[1]) == null, "%s says \"%s\": write \"Lv 3\" and \"×3\"" % pair)


func test_names_are_in_sentence_case() -> void:
	var c := Content.load_default()
	var names := {}
	for id: String in c.relics:
		names[c.relics[id]["name"]] = "relic " + id
	for id: String in c.buildings:
		names[c.buildings[id]["name"]] = "building " + id
	for id: String in c.upgrades:
		names[c.upgrades[id]["name"]] = "upgrade " + id
	for id: String in c.crafts:
		names[c.crafts[id]["name"]] = "craft " + id
	for n: String in names:
		var words := n.split(" ")
		for i in range(1, words.size()):
			var w := words[i]
			check(w == "" or w[0] == w[0].to_lower() or w in PROPER, "%s is \"%s\": only the first word and proper names take a capital" % [names[n], n])


## Lines of game/ code outside the card look and the kit itself, with their file:line.
func _ui_lines() -> Array:
	var out := []
	for file in DirAccess.get_files_at("res://game"):
		if not file.ends_with(".gd") or file in ["card_view.gd", "ui_kit.gd"]:
			continue
		var n := 0
		for line in FileAccess.get_file_as_string("res://game".path_join(file)).split("\n"):
			n += 1
			if not line.strip_edges().begins_with("#"):
				out.append(["%s:%d" % [file, n], line])
	return out


func test_text_sizes_come_from_the_scale() -> void:
	# The title screen's logo is the one size of its own; the build stamp under the log is the other.
	var literal := RegEx.create_from_string("font_size\", \\d|UiKit\\.note\\(.*, \\d+[,)]")
	for pair: Array in _ui_lines():
		var line: String = pair[1]
		if "font_size\", 64" in line or "build_label(), 9" in line:
			continue
		check(literal.search(line) == null, "%s sets a size by number: use UiKit.CAPTION, BODY, STRONG, TITLE, HEADING or BANNER" % pair[0])


func test_text_colours_come_from_the_kit() -> void:
	for pair: Array in _ui_lines():
		check(not "[color=#" in pair[1], "%s writes a colour by hand: use UiKit.tint with a UiKit colour" % pair[0])


func test_story_lines_show_their_tier() -> void:
	check(UiKit.DIM.to_html(false) in UiKit.story_line("A hut is finished.", RunState.AMBIENT), "routine is dim")
	check_eq(UiKit.story_line("Night 2 falls.", RunState.NOTICE), "Night 2 falls.", "a notice is plain")
	check(UiKit.GOLD.to_html(false) in UiKit.story_line("Gorm reaches level 5.", RunState.MOMENT), "a moment is gold")
	check(UiKit.story_line("Round 4. Traders leave 9 shells.", RunState.NOTICE).begins_with("[b]"), "a round's first line stays bold")
	var run := RunState.new(Content.load_default(), 4821)
	check_eq(run.story.size(), run.story_tiers.size(), "every story line has a tier")
	run.dispose()
