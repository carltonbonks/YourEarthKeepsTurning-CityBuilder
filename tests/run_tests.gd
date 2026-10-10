extends SceneTree
## Headless test runner. Runs every test_*.gd file in tests/ and exits non-zero on failure.
## Usage: godot --headless --path . -s res://tests/run_tests.gd

const TEST_DIR := "res://tests"


func _init() -> void:
	var failed := 0
	var passed := 0
	for file in DirAccess.get_files_at(TEST_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load(TEST_DIR.path_join(file))
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.call(name)
			if test.failures.is_empty():
				passed += 1
				print("PASS  %s::%s" % [file, name])
			else:
				failed += 1
				print("FAIL  %s::%s" % [file, name])
				for failure in test.failures:
					print("        %s" % failure)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or passed == 0 else 0)
