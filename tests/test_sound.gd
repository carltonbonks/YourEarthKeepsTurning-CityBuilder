extends TestCase
## Sound by moment (audio/manifest.json, game/sound_director.gd, docs/SOUND_SPEC.md): every row is complete and
## licensed, every file has its row, every key the code asks for exists, and the director hears the interface
## by itself without repeating a rebuilt screen's cards.

const TIERS := [0, 1, 2, 3, 4]
## Licences the game may ship (the repo is public and the game may sell): no NC, ND or SA.
const ALLOWED := ["CC0", "CC-BY 3.0", "CC-BY 4.0", "Own work"]
const BANNED := "\\b(NC|ND|SA)\\b|non-?commercial|no derivatives|share-?alike"
## Budget for all audio in the repository and the web build (sound plan: under 15 MB).
const AUDIO_BUDGET_MB := 15.0


func _rows() -> Dictionary:
	return SoundDirector.read_manifest()


func _files_under(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files_under(dir.path_join(sub)))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".ogg") or file.ends_with(".wav") or file.ends_with(".mp3"):
			out.append(dir.path_join(file))
	return out


func test_every_row_says_where_it_plays_how_and_why() -> void:
	var rows := _rows()
	check(rows.size() >= 8, "the manifest lists the first UI sounds")
	var key_shape := RegEx.create_from_string("^[a-z]+\\.[a-z0-9_]+$")
	var banned := RegEx.create_from_string("(?i)" + BANNED)
	for key: String in rows:
		var row: Dictionary = rows[key]
		check(key_shape.search(key) != null, "%s is written area.event" % key)
		check(str(row.get("bus", "")) in SoundDirector.BUSES, "%s plays on a known bus" % key)
		check(int(row.get("tier", -1)) in TIERS, "%s has an emphasis tier 0-4" % key)
		check(str(row.get("name", "")) != "", "%s has a name for the Credits screen" % key)
		check(str(row.get("brief", "")).length() > 20, "%s has a brief saying what it should feel like" % key)
		check(row.has("volume_db") and float(row["volume_db"]) <= 0.0, "%s has a volume at or under 0 dB" % key)
		check(int(row.get("max_voices", 0)) >= 1, "%s may sound at least once at a time" % key)
		var files: Array = row.get("files", [])
		check(not files.is_empty(), "%s has a file" % key)
		var stem := key.replace(".", "_")
		for file: String in files:
			check(FileAccess.file_exists(SoundDirector.AUDIO_DIR + file), "%s's file %s exists" % [key, file])
			check(file.get_file().begins_with(stem + "_") and file.ends_with(".ogg"), "%s is named %s_<nn>.ogg (docs/SOUND_SPEC.md)" % [file, stem])
		var licence: Array = row.get("licence", [])
		check(not licence.is_empty(), "%s says where its sound comes from (licence)" % key)
		for line: String in licence:
			check(ALLOWED.any(func(l: String) -> bool: return l in line), "%s's licence \"%s\" is CC0, CC-BY or own work" % [key, line])
			check(banned.search(line) == null, "%s's licence \"%s\" has no NC, ND or SA terms" % [key, line])
			if "CC-BY" in line:
				check(line.get_slice(",", 0).strip_edges().length() > 2, "%s's CC-BY line names its author first" % key)


func test_every_sound_file_has_a_row_and_fits_the_budget() -> void:
	var listed := {}
	for key: String in _rows():
		for file: String in _rows()[key]["files"]:
			listed[SoundDirector.AUDIO_DIR + file] = true
	var bytes := 0
	for path in _files_under("res://audio"):
		check(listed.has(path), "%s is in audio/manifest.json (or delete it)" % path)
		bytes += FileAccess.get_file_as_bytes(path).size()
	check(bytes / 1048576.0 < AUDIO_BUDGET_MB, "audio stays under %d MB (%.1f MB)" % [AUDIO_BUDGET_MB, bytes / 1048576.0])


## Code names sounds only by key: every key cued in game/ is in the manifest.
func test_every_key_the_code_asks_for_exists() -> void:
	var rows := _rows()
	var asks := RegEx.create_from_string("(?:cue|play|play_later|bind)\\(\"([a-z]+\\.[a-z0-9_]+)\"")
	var found := 0
	for file in DirAccess.get_files_at("res://game"):
		if not file.ends_with(".gd"):
			continue
		for m in asks.search_all(FileAccess.get_file_as_string("res://game".path_join(file))):
			found += 1
			check(rows.has(m.get_string(1)), "%s asks for \"%s\", which audio/manifest.json lacks" % [file, m.get_string(1)])
	check(found >= 4, "the interface cues its sounds by key")
	for roll: String in SoundDirector.ROLL_KEYS:
		check(rows.has(SoundDirector.ROLL_KEYS[roll]), "the %s roll has its glint" % roll)
	check(rows.has("card.deal"), "dealt cards flip")


func test_buses_exist_and_every_bus_with_sounds_has_a_slider() -> void:
	SoundDirector.ensure_buses()
	for bus: String in SoundDirector.BUSES:
		check(AudioServer.get_bus_index(bus) >= 0, "the mixer has a %s bus" % bus)
		check(GameSettings.DEFAULT_VOLUMES.has(bus), "settings keep a volume for %s" % bus)
	var layout := FileAccess.get_file_as_string("res://default_bus_layout.tres")
	for bus: String in SoundDirector.BUSES:
		check("&\"%s\"" % bus in layout, "default_bus_layout.tres names %s" % bus)
	check(SettingsPanel.VOLUME_ROWS.has("Master"), "Settings has an overall volume")
	for key: String in _rows():
		var bus := str(_rows()[key]["bus"])
		check(SettingsPanel.VOLUME_ROWS.has(bus), "%s plays on %s, so Settings has a slider for it" % [key, bus])


func test_volumes_round_trip_and_silence_mutes() -> void:
	var s := GameSettings.new()
	s.volumes["UI"] = 0.0
	s.volumes["Master"] = 0.5
	s.apply_sound()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")), "a bus at 0 is muted")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")) - linear_to_db(0.5)) < 0.01, "Master plays at half")
	GameSettings.new().apply_sound()
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")), "back to the defaults, UI sounds again")


func test_cooldown_and_voices_keep_repeats_in_check() -> void:
	var d := SoundDirector.new()
	check(d.play("card.pick"), "a card pick plays")
	check(not d.play("card.pick"), "the same pick at once is skipped (cooldown and one voice)")
	check(not d.play("no.such_sound"), "an unknown key plays nothing")
	check_eq(d.cued.size(), 1, "only the first pick was cued")
	check(SoundDirector.current == null, "out of the game, cues go nowhere")
	SoundDirector.cue("ui.click")
	d.free()


func _card(title: String, roll := "white", family := "folk") -> CardView:
	var c := CardView.new(CardView.Size.MEDIUM, family, "Townsperson", title)
	c.roll = roll
	return c


func test_the_director_hears_buttons_and_deals_new_cards_once() -> void:
	var d := SoundDirector.new()
	var b := Button.new()
	d._on_node_added(b)
	d._on_node_added(b)
	b.pressed.emit()
	check_eq(d.cued, ["ui.click"] as Array[String], "a plain button clicks, once however often it enters the tree")
	var cb := CheckBox.new()
	d._on_node_added(cb)
	cb.button_pressed = true
	check("ui.toggle" in d.cued, "a check box toggles")

	var first: Array = [_card("Card 0"), _card("Card 1", "yellow"), _card("Card 2")]
	d.note_cards(first)
	check_eq(d._queue.filter(func(q: Array) -> bool: return q[1] == "card.deal").size(), 3, "three new cards, three flips")
	check(d._queue.any(func(q: Array) -> bool: return q[1] == "card.roll_yellow"), "the yellow card glints")
	d._queue.clear()
	var rebuilt: Array = [_card("Card 0"), _card("Card 1", "yellow"), _card("Card 2")]
	d.note_cards(rebuilt)
	check(d._queue.is_empty(), "the same cards rebuilt are not dealt again")
	var fresh := _card("A new one", "white", "relic")
	d.note_cards(rebuilt + [fresh])
	check_eq(d._queue.size(), 1, "one new card, one flip and no glint for a white roll")
	d._on_node_added(fresh)
	fresh.pressed.emit()
	check("card.pick" in d.cued, "pressing a card picks it")
	for c: CardView in first + rebuilt + [fresh]:
		c.free()
	b.free()
	cb.free()
	d.free()


func test_credits_list_every_sound_source() -> void:
	var lines := CreditsPanel.sound_lines()
	for key: String in _rows():
		for line: String in _rows()[key]["licence"]:
			check(lines.any(func(l: String) -> bool: return l.begins_with(line)), "credits name %s" % line)
	check(not CreditsPanel.art_lines().is_empty(), "credits name the art's sources")
