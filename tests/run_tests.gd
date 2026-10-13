extends SceneTree
## Headless test runner. Runs every test_*.gd file in tests/ and exits non-zero on failure.
## Usage: godot --headless --path . -s res://tests/run_tests.gd [-- <filter>...]
## A filter keeps only tests whose "file::method" contains it (e.g. "town", "test_market.gd", "::test_gate_").
## Tests slower than SLOW_MS show their time, so slow ones are easy to spot.

const TEST_DIR := "res://tests"
const SLOW_MS := 2000


func _init() -> void:
	var filters := OS.get_cmdline_user_args()
	var failed := 0
	var passed := 0
	var started := Time.get_ticks_msec()
	for file in DirAccess.get_files_at(TEST_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load(TEST_DIR.path_join(file))
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_") or not _wanted("%s::%s" % [file, name], filters):
				continue
			var t0 := Time.get_ticks_msec()
			var test: TestCase = script.new()
			test.call(name)
			var ms := Time.get_ticks_msec() - t0
			var took := "  (%.1fs)" % (ms / 1000.0) if ms >= SLOW_MS else ""
			if test.failures.is_empty():
				passed += 1
				print("PASS  %s::%s%s" % [file, name, took])
			else:
				failed += 1
				print("FAIL  %s::%s%s" % [file, name, took])
				for failure in test.failures:
					print("        %s" % failure)
	print("\n%d passed, %d failed in %.0fs" % [passed, failed, (Time.get_ticks_msec() - started) / 1000.0])
	quit(1 if failed > 0 or passed == 0 else 0)


static func _wanted(id: String, filters: PackedStringArray) -> bool:
	if filters.is_empty():
		return true
	for f in filters:
		if id.contains(f):
			return true
	return false
