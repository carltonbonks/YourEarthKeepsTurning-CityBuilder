class_name TestCase
extends RefCounted
## Base class for tests. Any method named test_* is run by tests/run_tests.gd.

var failures: PackedStringArray = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, expected, actual])


## A whole bot run takes 10-15 s, so tests that only read a finished run's record share one per seed and style.
## Each test gets its own copy. Play a fresh run instead when the test needs the live RunState or other choices.
static var _bot_records := {}


static func bot_record(seed_value := 4821, style := "balanced") -> Dictionary:
	var key := "%d/%s" % [seed_value, style]
	if not _bot_records.has(key):
		var run := RunState.new(Content.load_default(), seed_value)
		var bot := AutoPlayer.new()
		bot.style = style
		bot.play_run(run)
		_bot_records[key] = run.to_record()
		run.dispose()
	return _bot_records[key].duplicate(true)
