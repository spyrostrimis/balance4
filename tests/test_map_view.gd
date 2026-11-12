extends TestCase
## Drawing the map: tile layers, camera, minimap and the map scene.

const FOREST := "res://data/biomes/forest.tres"
const MAPS := ["res://data/maps/forest_01.tres", "res://data/maps/desert_01.tres"]


func _small_map() -> MapData:
	var map := MapData.new()
	map.display_name = "Small"
	map.biome = load(FOREST)
	map.rows = PackedStringArray([
		"....",
		".ww.",
		".w..",
		"....",
	])
	return map


## True if two colours match to within 8-bit rounding.
func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func test_corner_mask() -> void:
	var map := _small_map()
	var water := 3
	check_eq(TerrainView.corner_mask(map, water, 0, 0), 0, "corner (0,0): no water around")
	check_eq(TerrainView.corner_mask(map, water, 1, 1), TerrainView.BOTTOM_RIGHT, "corner (1,1)")
	check_eq(TerrainView.corner_mask(map, water, 2, 1), TerrainView.BOTTOM_LEFT | TerrainView.BOTTOM_RIGHT, "corner (2,1)")
	check_eq(TerrainView.corner_mask(map, water, 2, 2),
			TerrainView.TOP_LEFT | TerrainView.TOP_RIGHT | TerrainView.BOTTOM_LEFT, "corner (2,2)")
	check_eq(TerrainView.corner_mask(map, water, 3, 2), TerrainView.TOP_LEFT, "corner (3,2)")
	check_eq(TerrainView.corner_mask(map, water, 1, 3), TerrainView.TOP_RIGHT, "corner (1,3)")


func test_corner_mask_at_the_map_edge() -> void:
	var map := MapData.new()
	map.biome = load(FOREST)
	map.rows = PackedStringArray(["w.", ".."])
	# Outside cells copy their nearest inside cell, so water in the corner fills the corner.
	check_eq(TerrainView.corner_mask(map, 3, 0, 0), 15, "map corner")
	check_eq(TerrainView.corner_mask(map, 3, 1, 0), TerrainView.TOP_LEFT | TerrainView.BOTTOM_LEFT, "top edge")
	check_eq(TerrainView.corner_mask(map, 3, 2, 2), 0, "far corner")


func test_border_tile_position() -> void:
	check_eq(TerrainView.border_tile(0, 0, 5), Vector2i(0, 5), "(0,0)")
	check_eq(TerrainView.border_tile(3, 2, 15), Vector2i(19, 15), "(3,2)")
	check_eq(TerrainView.border_tile(8, 9, 1), Vector2i(8, 1), "wraps every 8 cells")
	check_eq(TerrainView.border_tile(-1, 0, 1), Vector2i(7, 1), "negative positions wrap too")


func test_layers_for_a_small_map() -> void:
	var view := TerrainView.new()
	tree.root.add_child(view)
	view.show_map(_small_map())
	check_eq(view.terrain_layers.size(), 5, "one layer per forest terrain")
	check_eq(view.terrain_layers[0].get_used_cells().size(), 16, "ground covers every cell")
	check_eq(view.terrain_layers[0].get_cell_atlas_coords(Vector2i(3, 2)), Vector2i(3, 2), "ground tile at (3,2)")
	var water := view.terrain_layers[3]
	check_eq(water.position, Vector2(-16, -16), "border layers are shifted by half a cell")
	check_eq(water.get_used_cells().size(), 8, "border tiles around three water cells")
	check_eq(water.get_cell_source_id(Vector2i(2, 2)), 3, "water tiles come from the water atlas")
	check_eq(water.get_cell_atlas_coords(Vector2i(2, 2)), Vector2i(2 + 8 * 2, 7), "water tile at corner (2,2)")
	check_eq(view.terrain_layers[1].get_used_cells().size(), 0, "no dirt on this map")
	# Showing another map replaces the layers instead of adding to them.
	view.show_map(_small_map())
	check_eq(view.terrain_layers.size(), 5, "layers after showing a second map")
	check_eq(view.get_child_count(), 6, "children after showing a second map (5 terrains + decor)")
	view.free()


func test_decor_only_on_open_ground() -> void:
	var map := _small_map()
	check_eq(TerrainView.decor_at(map, Vector2i(0, 0), 1.0, 8).x, -1, "no prop next to water")
	check_eq(TerrainView.decor_at(map, Vector2i(3, 2), 1.0, 8).x, -1, "no prop diagonal to water")
	check(TerrainView.decor_at(map, Vector2i(3, 3), 1.0, 8).x >= 0, "a prop two cells from water")
	var open := MapData.new()
	open.biome = load(FOREST)
	open.rows = PackedStringArray(["....", "....", "....", "...."])
	var placed := 0
	for y in 4:
		for x in 4:
			var pick := TerrainView.decor_at(open, Vector2i(x, y), 1.0, 8)
			check(pick.x >= 0 and pick.x < 8, "prop index in range at (%d,%d)" % [x, y])
			check_eq(pick, TerrainView.decor_at(open, Vector2i(x, y), 1.0, 8), "same answer every time")
			placed += 1 if TerrainView.decor_at(open, Vector2i(x, y), 0.0, 8).x >= 0 else 0
	check_eq(placed, 0, "density 0 places nothing")


func test_decor_density_on_shipped_map() -> void:
	var map := load(MAPS[1]) as MapData
	var size := map.get_size()
	var open := 0
	var placed := 0
	for y in size.y:
		for x in size.x:
			if TerrainView.decor_at(map, Vector2i(x, y), 1.0, 8).x >= 0:
				open += 1
				if TerrainView.decor_at(map, Vector2i(x, y), 0.3, 8).x >= 0:
					placed += 1
	var share := float(placed) / open
	check(share > 0.24 and share < 0.36, "about 30%% of open cells get a prop, got %.2f" % share)


func test_camera_stays_inside_the_map() -> void:
	var map_size := Vector2(2048, 1536)
	var view := Vector2(748, 540)
	check_eq(MapCamera.clamp_top_left(Vector2(-50, -50), map_size, view), Vector2.ZERO, "top-left limit")
	check_eq(MapCamera.clamp_top_left(Vector2(5000, 5000), map_size, view), Vector2(1300, 996), "bottom-right limit")
	check_eq(MapCamera.clamp_top_left(Vector2(100, 200), map_size, view), Vector2(100, 200), "inside is unchanged")
	check_eq(MapCamera.clamp_top_left(Vector2(40, 40), Vector2(320, 320), view), Vector2.ZERO, "a map smaller than the view")


func test_camera_centering() -> void:
	var camera := MapCamera.new()
	camera.setup(Vector2(2048, 1536), Vector2(748, 540), Vector2(960, 540))
	camera.center_on(Vector2(1024, 768))
	check_eq(camera.position, Vector2(650, 498), "centred on the middle of the map")
	check_eq(camera.get_view_rect(), Rect2(650, 498, 748, 540), "view rect")
	camera.center_on(Vector2.ZERO)
	check_eq(camera.position, Vector2.ZERO, "centring on a corner stops at the edge")
	camera.set_top_left(Vector2(10.4, 20.6))
	check_eq(camera.position, Vector2(10, 21), "position is rounded to whole pixels")
	camera.free()


func test_camera_scrolls_with_the_arrow_keys() -> void:
	var camera := MapCamera.new()
	camera.setup(Vector2(2048, 1536), Vector2(748, 540), Vector2(960, 540))
	camera.scroll_speed = 480.0
	Input.action_press("ui_right")
	camera._process(0.5)
	Input.action_release("ui_right")
	check_eq(camera.position, Vector2(240, 0), "half a second to the right")
	Input.action_press("ui_down")
	camera._process(10.0)
	Input.action_release("ui_down")
	check_eq(camera.position, Vector2(240, 996), "scrolling down stops at the bottom of the map")
	camera._process(1.0)
	check_eq(camera.position, Vector2(240, 996), "no key, no movement")
	camera.free()


func test_camera_reports_changes() -> void:
	var camera := MapCamera.new()
	camera.setup(Vector2(2048, 1536), Vector2(748, 540), Vector2(960, 540))
	var count := [0]
	camera.view_changed.connect(func() -> void: count[0] += 1)
	camera.center_on(Vector2(500, 500))
	check_eq(count[0], 1, "view_changed is emitted when the camera moves")
	camera.free()


func test_edge_scrolling_direction() -> void:
	var screen := Vector2(960, 540)
	check_eq(MapCamera.edge_direction(Vector2(480, 270), screen, 2), Vector2.ZERO, "middle of the screen")
	check_eq(MapCamera.edge_direction(Vector2(0, 270), screen, 2), Vector2(-1, 0), "left edge")
	check_eq(MapCamera.edge_direction(Vector2(959, 270), screen, 2), Vector2(1, 0), "right edge")
	check_eq(MapCamera.edge_direction(Vector2(480, 1), screen, 2), Vector2(0, -1), "top edge")
	check_eq(MapCamera.edge_direction(Vector2(958, 539), screen, 2), Vector2(1, 1), "bottom-right corner")
	check_eq(MapCamera.edge_direction(Vector2(5, 5), screen, 2), Vector2.ZERO, "just inside the margin")


func test_minimap_image() -> void:
	var map := _small_map()
	var image := Minimap.build_image(map)
	check_eq(image.get_size(), Vector2i(4, 4), "one pixel per cell")
	var grass := map.biome.terrains[0].minimap_color
	var water := map.biome.terrains[3].minimap_color
	check(_close(image.get_pixel(0, 0), grass), "grass pixel")
	check(_close(image.get_pixel(1, 2), water), "water pixel")
	check(not _close(image.get_pixel(1, 1), grass), "water is not drawn as grass")


func test_minimap_fit() -> void:
	check_eq(Minimap.fit_rect(Vector2i(64, 48), Vector2(192, 144)), Rect2(0, 0, 192, 144), "64x48 map fills a 192x144 box")
	check_eq(Minimap.fit_rect(Vector2i(32, 48), Vector2(192, 144)), Rect2(48, 0, 96, 144), "a narrow map is centred")
	check_eq(Minimap.fit_rect(Vector2i(50, 48), Vector2(192, 144)), Rect2(21, 0, 150, 144), "whole pixels per cell")
	check_eq(Minimap.fit_rect(Vector2i(384, 288), Vector2(192, 144)), Rect2(0, 0, 192, 144), "a huge map is shrunk to fit")


func test_map_scene_shows_both_maps() -> void:
	var packed := load("res://scenes/map_view.tscn") as PackedScene
	check(packed != null, "map scene loads")
	if packed == null:
		return
	MapView.requested_squad = ""
	for path in MAPS:
		MapView.requested_map = path
		var view := packed.instantiate() as MapView
		tree.root.add_child(view)
		check(view.map != null, "%s is shown" % path)
		if view.map != null:
			check_eq(view.terrain.terrain_layers.size(), view.map.biome.terrains.size(), "layers for %s" % path)
			check_eq(view.terrain.terrain_layers[0].get_used_cells().size(), 64 * 48, "ground tiles for %s" % path)
			check(view.terrain.decor_layer.get_used_cells().size() > 50, "props are scattered on %s" % path)
			check_eq(view.camera.position, Vector2(650, 498), "camera starts on the centre of %s" % path)
			# The minimap and the camera agree on where things are.
			check_eq(view.minimap.size, Vector2(192, 144), "minimap size")
			check_eq(view.minimap.local_to_map(Vector2(96, 72)), Vector2(1024, 768), "minimap centre is the map centre")
			check_eq(view.minimap.map_to_local(Vector2(2048, 1536)), Vector2(192, 144), "map corner is the minimap corner")
			# Clicking the minimap moves the camera there.
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = Vector2(0, 0)
			view.minimap._gui_input(click)
			check_eq(view.camera.position, Vector2.ZERO, "clicking the minimap corner jumps to the map corner")
			click.position = Vector2(191, 143)
			view.minimap._gui_input(click)
			check_eq(view.camera.position, Vector2(1300, 996), "clicking the far corner jumps to the far corner")
			check(MapView.describe_cell(view.map, Vector2i(32, 24)).contains("Passable"), "cell description")
			check_eq(MapView.describe_cell(view.map, Vector2i(-1, 0)), "", "no description outside the map")
		view.free()
