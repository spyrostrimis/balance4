extends SceneTree
## Headless smoke test: the project's main scene must load and instantiate.
##
## Run from the repo root:
##   godot --headless --path . --script res://tests/smoke_test.gd
## Exit code 0 means pass, 1 means fail.


func _initialize() -> void:
	var failures: Array[String] = []

	var main_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_path.is_empty():
		failures.append("application/run/main_scene is not set")
	elif not ResourceLoader.exists(main_path):
		failures.append("main scene does not exist: %s" % main_path)
	else:
		var packed := load(main_path) as PackedScene
		if packed == null:
			failures.append("main scene failed to load: %s" % main_path)
		else:
			var node := packed.instantiate()
			if node == null:
				failures.append("main scene failed to instantiate")
			else:
				root.add_child(node)
				if node.get_node_or_null("Center/Box/Title") == null:
					failures.append("title label is missing from the main scene")

	var width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	var height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	if width != 960 or height != 540:
		failures.append("viewport is %dx%d, expected 960x540" % [width, height])

	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		for failure in failures:
			printerr("SMOKE TEST FAILED: ", failure)
		quit(1)
