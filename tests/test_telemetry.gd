extends TestCase
## Anonymous play data (game/telemetry.gd): opt-in, never from dev, desktop or local builds, and runs go
## up as the compact record with the ids they are filed under.


func test_nothing_is_sent_unless_every_condition_holds() -> void:
	var cfg := {"url": "https://example.supabase.co", "key": "pk"}
	check(Telemetry.allowed(cfg, true, false, true, "carltonbonks.github.io"), "the live page sends for a player who said yes")
	check(not Telemetry.allowed(cfg, false, false, true, "carltonbonks.github.io"), "nothing without the player's yes")
	check(not Telemetry.allowed(cfg, true, true, true, "carltonbonks.github.io"), "nothing from a ?dev=1 session")
	check(not Telemetry.allowed(cfg, true, false, false, "carltonbonks.github.io"), "nothing from desktop builds")
	check(not Telemetry.allowed(cfg, true, false, true, "localhost"), "nothing from a local build")
	check(not Telemetry.allowed(cfg, true, false, true, "127.0.0.1"), "nothing from a local build by address")
	check(not Telemetry.allowed({"url": "", "key": "pk"}, true, false, true, "carltonbonks.github.io"), "nothing before the database is set up")


func test_the_shipped_config_parses() -> void:
	var cfg := Telemetry.load_config(Telemetry.CONFIG)
	check(cfg.has("_note") and cfg.has("url") and cfg.has("key"), "telemetry.json has its note, url and key")
	check_eq(Telemetry.load_config("res://no_such_telemetry.json"), {}, "a missing file reads as nothing to send")


func test_sharing_makes_a_random_id_only_when_turned_on() -> void:
	var s := GameSettings.new()
	s.persist = false
	check_eq(s.player_id, "", "no id until the player says yes")
	s.set_sharing(false)
	check(s.share_asked and s.player_id == "", "no thanks is remembered and makes no id")
	s.set_sharing(true)
	var id := s.player_id
	check(id.length() == 36 and id.substr(14, 1) == "4" and id.count("-") == 4, "a version 4 id: %s" % id)
	s.set_sharing(false)
	s.set_sharing(true)
	check_eq(s.player_id, id, "turning sharing off and on keeps the same id")
	check(GameSettings.new_id() != GameSettings.new_id(), "ids are random")


func test_a_saved_run_says_which_build_and_whose_it_is() -> void:
	var s := GameSettings.new()
	s.persist = false
	var about := RunHistory.about(s, true, "sess", "2026-11-14T00:00:00Z", 75)
	check_eq(about["player_id"], "", "no player id for a player not sharing")
	check_eq(about["build"], StoryLog.build_label(), "the CI build stamp")
	check(about["dev"] and int(about["wall_seconds"]) == 75 and about["settings"].has("tour"), "dev flag, play time and settings")
	s.set_sharing(true)
	check_eq(RunHistory.about(s, false, "sess", "", 0)["player_id"], s.player_id, "a sharing player's id")


func test_runs_go_up_compact_with_their_ids() -> void:
	var record := bot_record()
	record["id"] = "123-4821"
	record["story"] = ["a long story"]
	var p := Telemetry.run_payload(record, "player", "session")
	check_eq(p["run_id"], "123-4821", "filed under the run's id")
	check(p["player_id"] == "player" and p["session_id"] == "session", "with the player's and session's ids")
	check(not (p["record"] as Dictionary).has("story"), "without the story text")
	check_eq(p["upload_version"], Telemetry.UPLOAD_VERSION, "the wrapper's version")
	check(JSON.stringify({"p": p}).length() < 512 * 1024, "a whole run fits under the upload limit")
	check(record.has("story"), "the saved record is left as it was")
