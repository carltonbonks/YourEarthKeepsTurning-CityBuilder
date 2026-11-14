class_name RunHistory
extends RefCounted
## Saves finished and in-progress runs on this machine (in the browser build this is
## the browser's own storage) so they can be reviewed and shared for balancing.
## One JSON file per run in user://runs/, rewritten as the run progresses.

const DIR := "user://runs"
const KEEP_RUNS := 100


static func new_run_id(seed_value: int) -> String:
	return "%d-%d" % [int(Time.get_unix_time_from_system()), seed_value]


## Saves the run and returns the record as saved. `extra` is what the game adds beside the sim's record
## (`about`): the build, whether it is a dev session, play time and the settings that change play.
static func save(run_id: String, run: RunState, extra := {}) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := run.to_record()
	data["id"] = run_id
	data["saved_at"] = Time.get_datetime_string_from_system(true) + "Z"
	data["game_version"] = ProjectSettings.get_setting("application/config/version")
	data["player"] = "human"
	data.merge(extra, true)
	var file := FileAccess.open(DIR.path_join(run_id + ".json"), FileAccess.WRITE)
	if file == null:
		push_warning("Could not save run %s" % run_id)
		return data
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_prune()
	return data


## The game's own fields for a saved run (record format 65): which build made it ("build", the CI stamp, as
## the version number alone stopped changing), "dev" for ?dev=1 and desktop sessions, "session_id",
## "player_id" (only for players sharing play data, else ""), "started_at", "wall_seconds" (time since the
## run began, pauses included) and "settings" (the ones that change how a run plays or reads).
static func about(settings: GameSettings, dev: bool, session_id: String, started_at: String, wall_seconds: int) -> Dictionary:
	return {"build": StoryLog.build_label(), "dev": dev, "session_id": session_id,
		"player_id": settings.player_id if settings.share_data else "", "started_at": started_at,
		"wall_seconds": wall_seconds, "settings": {"tour": settings.tour, "intro_seen": settings.intro_seen,
		"advisor": settings.advisor, "picks_in_town": settings.picks_in_town, "tips": settings.tips,
		"night_camera": settings.night_camera, "art": settings.art, "start_speed": settings.start_speed}}


## All saved runs, newest first.
static func load_all() -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(DIR):
		return runs
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(file)))
		if parsed is Dictionary:
			runs.append(parsed)
	runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("saved_at", "")) > str(b.get("saved_at", "")))
	return runs


## A run without the long story text, small enough to paste into a chat.
static func compact(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out.erase("story")
	for r: Dictionary in out.get("rounds", []):
		r.erase("heroes_before")
	return out


static func one_line(data: Dictionary) -> String:
	var result: String = data.get("result", "?")
	var outcome := "Won" if result == "won" else ("Lost in round %d" % int(data.get("round_reached", 0)) if result == "lost" \
		else "Unfinished, round %d" % int(data.get("round_reached", 0)))
	return "%s  ·  seed %d  ·  %s  ·  %d heroes lost  ·  %d townsfolk lost  ·  %d relics" % [
		str(data.get("saved_at", "")).left(16).replace("T", " "), int(data.get("seed", 0)), outcome,
		(data.get("fallen", []) as Array).size(), int(data.get("townsfolk_lost", 0)), (data.get("relics", []) as Array).size()]


static func _prune() -> void:
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool: return f.ends_with(".json"))
	if files.size() <= KEEP_RUNS:
		return
	files.sort()  # Ids start with the save time, so oldest first.
	for i in files.size() - KEEP_RUNS:
		DirAccess.remove_absolute(DIR.path_join(files[i]))
