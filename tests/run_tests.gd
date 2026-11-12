extends SceneTree
## Headless test runner. Runs every test_* method of every tests/test_*.gd file.
##
## Run from the repo root (after the project has been imported once):
##   godot --headless --path . --script res://tests/run_tests.gd
## Exit code 0 means every test passed, 1 means at least one failed.

const TEST_DIR := "res://tests"


var _started := false


func _process(_delta: float) -> bool:
	# Tests run on the first frame, not in _initialize: only then is the scene
	# tree live, so nodes a test adds to it get their _ready call.
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var files: Array[String] = []
	for file in DirAccess.get_files_at(TEST_DIR):
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			files.append(file)
	files.sort()

	var passed := 0
	var failed := 0
	for file in files:
		var script := load("%s/%s" % [TEST_DIR, file]) as GDScript
		if script == null or not script.can_instantiate():
			printerr("FAIL  %s: could not load" % file)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.tree = self
			test.call(method_name)
			if test.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for failure in test.failures:
					printerr("FAIL  %s  %s: %s" % [file, method_name, failure])

	if files.is_empty():
		printerr("No tests found in %s" % TEST_DIR)
		failed += 1
	print("%d passed, %d failed" % [passed, failed])
	print("TESTS PASSED" if failed == 0 else "TESTS FAILED")
	quit(0 if failed == 0 else 1)
