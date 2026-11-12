extends TestCase
## The project's basic settings and its start scene.


func test_viewport_is_960_by_540() -> void:
	check_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 960, "viewport width")
	check_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 540, "viewport height")
	check_eq(MapView.SCREEN_SIZE, Vector2(960, 540), "MapView.SCREEN_SIZE")


func test_pixels_stay_sharp() -> void:
	check_eq(ProjectSettings.get_setting("display/window/stretch/scale_mode"), "integer", "stretch scale mode")
	check_eq(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"), 0,
			"default texture filter (0 = nearest)")


func test_main_scene_loads() -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	check(ResourceLoader.exists(path), "main scene exists: '%s'" % path)
	var packed := load(path) as PackedScene
	check(packed != null, "main scene loads")
	if packed == null:
		return
	var node := packed.instantiate()
	tree.root.add_child(node)
	check(node.get_node_or_null("Center/Box/Title") != null, "title label exists")
	check(node.get_node_or_null("Center/Box/Buttons/Forest") != null, "forest button exists")
	check(node.get_node_or_null("Center/Box/Buttons/Desert") != null, "desert button exists")
	node.free()


func test_map_argument() -> void:
	var title := load("res://scripts/ui/title_screen.gd")
	check_eq(title.map_from_args(PackedStringArray(["--map=desert"])), "desert", "--map=desert")
	check_eq(title.map_from_args(PackedStringArray(["--other", "--map=forest"])), "forest", "--map=forest")
	check_eq(title.map_from_args(PackedStringArray(["--map=moon"])), "", "unknown map")
	check_eq(title.map_from_args(PackedStringArray()), "", "no arguments")
	for map_name in title.MAPS:
		check(ResourceLoader.exists(title.MAPS[map_name]), "map file for '%s' exists" % map_name)
