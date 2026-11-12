extends TestCase
## Selecting units, giving orders with the mouse, control groups, and drawing the shroud.

const FOREST := "res://data/biomes/forest.tres"
const INFANTRY := "res://data/units/blue_infantry.tres"
const MAP_SCENE := "res://scenes/map_view.tscn"


func _world(width := 12, height := 10) -> SimWorld:
	var map := MapData.new()
	map.biome = load(FOREST)
	var rows := []
	for y in height:
		rows.append(".".repeat(width))
	map.rows = PackedStringArray(rows)
	return SimWorld.new(map)


func _type() -> UnitType:
	return load(INFANTRY)


## The map scene with a 5-unit squad on the forest map. The caller frees it.
func _view() -> MapView:
	MapView.requested_map = "res://data/maps/forest_01.tres"
	MapView.requested_squad = INFANTRY
	MapView.requested_squad_size = 5
	var view := (load(MAP_SCENE) as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	return view


func _body(unit: SimUnit) -> Vector2:
	return UnitsView.feet_position(unit) + UnitsView.BODY


func test_selection_basics() -> void:
	var selection := Selection.new()
	var changes := [0]
	selection.changed.connect(func() -> void: changes[0] += 1)
	check(selection.is_empty(), "starts empty")
	selection.set_ids([3, 5, 3])
	check_eq(selection.ids, [3, 5] as Array[int], "duplicates are dropped")
	selection.add_ids([7, 5])
	check_eq(selection.ids, [3, 5, 7] as Array[int], "adding keeps what was there")
	selection.toggle(5)
	check_eq(selection.ids, [3, 7] as Array[int], "toggling a selected unit removes it")
	selection.toggle(9)
	check(selection.has(9), "toggling an unselected unit adds it")
	check_eq(changes[0], 4, "one change signal per change")
	selection.set_ids([3, 7, 9])
	check_eq(changes[0], 4, "no signal when nothing changes")
	selection.clear()
	check(selection.is_empty(), "clear empties it")


func test_control_groups() -> void:
	var selection := Selection.new()
	selection.set_ids([1, 2])
	selection.assign_group(1)
	selection.set_ids([3])
	selection.assign_group(2)
	check(selection.recall_group(1), "group 1 can be recalled")
	check_eq(selection.ids, [1, 2] as Array[int], "group 1")
	check(selection.recall_group(2), "group 2 can be recalled")
	check_eq(selection.ids, [3] as Array[int], "group 2")
	check(not selection.recall_group(5), "an unset group cannot be recalled")
	check_eq(selection.ids, [3] as Array[int], "and leaves the selection alone")
	selection.ids.append(99)     # changing the selection later must not change the stored group
	selection.recall_group(2)
	check_eq(selection.ids, [3] as Array[int], "a stored group is a copy")


func test_prune_forgets_missing_units() -> void:
	var world := _world()
	var unit := world.add_unit(_type(), 0, Vector2i(2, 2))
	var selection := Selection.new()
	selection.set_ids([unit.id, 12345])
	selection.assign_group(1)
	selection.prune(world)
	check_eq(selection.ids, [unit.id] as Array[int], "selection keeps only real units")
	check_eq(selection.groups[1], [unit.id], "so do the groups")


func test_picking_a_unit() -> void:
	var world := _world()
	var a := world.add_unit(_type(), 0, Vector2i(2, 2))
	var b := world.add_unit(_type(), 0, Vector2i(3, 2))
	var enemy := world.add_unit(_type(), 1, Vector2i(6, 6))
	check_eq(UnitsView.feet_position(a), Vector2(80, 83), "feet of the unit in cell (2,2)")
	check(UnitsView.unit_at_point(world, _body(a), 0) == a, "clicking a unit's body picks it")
	check(UnitsView.unit_at_point(world, _body(a) + Vector2(6, 0), 0) == a, "a little off still picks it")
	check(UnitsView.unit_at_point(world, _body(a) + Vector2(24, 0), 0) == b, "nearer to the neighbour picks the neighbour")
	check(UnitsView.unit_at_point(world, _body(a) + Vector2(16, 0), 0) == null, "half-way between two units picks neither")
	check(UnitsView.unit_at_point(world, Vector2(200, 40), 0) == null, "empty ground picks nothing")
	check(UnitsView.unit_at_point(world, _body(enemy), 0) == null, "another team's unit is not picked")


func test_box_selection() -> void:
	var world := _world()
	var a := world.add_unit(_type(), 0, Vector2i(2, 2))
	var b := world.add_unit(_type(), 0, Vector2i(4, 3))
	var c := world.add_unit(_type(), 0, Vector2i(9, 8))
	world.add_unit(_type(), 1, Vector2i(3, 3))
	check_eq(UnitsView.units_in_rect(world, Rect2(40, 40, 140, 100), 0), [a.id, b.id] as Array[int], "two of ours in the box")
	check_eq(UnitsView.units_in_rect(world, Rect2(180, 140, -140, -100), 0), [a.id, b.id] as Array[int],
			"dragging up and to the left works the same")
	check_eq(UnitsView.units_in_rect(world, Rect2(0, 0, 400, 400), 0).size(), 3, "a big box takes all three")
	check_eq(UnitsView.units_in_rect(world, Rect2(250, 0, 30, 30), 0), [] as Array[int], "an empty box takes none")
	check(c != null, "third unit exists")


func test_walking_animation_frames() -> void:
	var world := _world()
	var unit := world.add_unit(_type(), 0, Vector2i(2, 2))
	check_eq(UnitsView.sprite_frame(unit, 0), Vector2i(0, 0), "standing: pose 0, facing south")
	world.order_move([unit.id], Vector2i(8, 2))
	world.tick()
	var poses := {}
	for tick in 16:
		var frame := UnitsView.sprite_frame(unit, tick)
		check_eq(frame.x, 6, "facing east while walking east")
		poses[frame.y] = true
	check_eq(poses.keys().size(), 2, "walking alternates between two poses")
	check(not poses.has(0), "and never shows the standing pose")


func test_shroud_tiles() -> void:
	var shroud := Shroud.new(Vector2i(8, 8))
	check_eq(ShroudView.corner_mask(shroud, 3, 3), 15, "all four cells unexplored")
	shroud.reveal_circle(Vector2i(3, 3), 0)
	check_eq(ShroudView.corner_mask(shroud, 3, 3), 15 - TerrainView.BOTTOM_RIGHT, "the explored cell is below-right of its own corner")
	check_eq(ShroudView.corner_mask(shroud, 4, 4), 15 - TerrainView.TOP_LEFT, "and above-left of the opposite corner")
	shroud.reveal_circle(Vector2i(3, 3), 1)
	check_eq(ShroudView.corner_mask(shroud, 4, 4), 0, "a corner with all four cells explored has no shroud tile")

	var view := ShroudView.new()
	tree.root.add_child(view)
	var fresh := Shroud.new(Vector2i(8, 8))
	view.setup(fresh)
	check_eq(view.get_used_cells().size(), 9 * 9, "a fully hidden 8x8 map is covered by 9x9 tiles")
	check_eq(view.position, Vector2(-16, -16), "shifted by half a cell like the terrain borders")
	fresh.reveal_circle(Vector2i(4, 4), 2)
	view.refresh()
	check(view.get_cell_source_id(Vector2i(5, 5)) == -1, "tiles inside the revealed area are removed")
	check(view.get_cell_source_id(Vector2i(0, 0)) == 0, "tiles far away stay")
	var expected := 0
	for j in 9:
		for i in 9:
			if ShroudView.corner_mask(fresh, i, j) != 0:
				expected += 1
	check_eq(view.get_used_cells().size(), expected, "after a refresh the tiles match the shroud exactly")
	view.free()


func test_minimap_hides_unexplored_cells() -> void:
	var world := _world()
	world.add_unit(_type(), 0, Vector2i(2, 2))
	var image := Minimap.build_image(world.map, world.shroud_for(0))
	var grass := world.map.biome.terrains[0].minimap_color
	check(absf(image.get_pixel(2, 2).g - grass.g) < 0.01, "explored cells show their terrain")
	check(image.get_pixel(11, 9).g < 0.05, "unexplored cells are black")


func test_scene_starts_with_a_squad() -> void:
	var view := _view()
	check_eq(view.world.units.size(), 5, "five units")
	var start: Vector2i = view.map.starts[0]
	for unit in view.world.units:
		var gap := unit.cell - start
		check(maxi(absi(gap.x), absi(gap.y)) <= 2, "unit %d starts near the start position" % unit.id)
		check_eq(unit.team, SimWorld.PLAYER_TEAM, "it is the player's")
	check(view.world.shroud_for(0).is_explored(start), "the start is explored")
	check(not view.world.shroud_for(0).is_explored(Vector2i(32, 24)), "the middle of the map is not")
	check(view.camera.get_view_rect().has_point(MapData.cell_center(start)), "the camera shows the squad")
	check(view.shroud_view.get_used_cells().size() > 2000, "most of the map is under shroud tiles")
	view.free()


func test_click_and_box_select_in_the_scene() -> void:
	var view := _view()
	var first: SimUnit = view.world.units[0]
	view.click_select(_body(first))
	check_eq(view.selection.ids, [first.id] as Array[int], "a click selects the unit under it")
	var second: SimUnit = view.world.units[1]
	view.click_select(_body(second), true)
	check_eq(view.selection.ids.size(), 2, "a shift-click adds a second unit")
	view.click_select(_body(second), true)
	check_eq(view.selection.ids, [first.id] as Array[int], "a second shift-click removes it again")
	view.click_select(_body(first) + Vector2(300, -200))
	check(view.selection.is_empty(), "a click on empty ground clears the selection")
	var start := MapData.cell_center(view.map.starts[0])
	view.box_select(Rect2(start - Vector2(120, 120), Vector2(240, 240)))
	check_eq(view.selection.ids.size(), 5, "a box around the squad selects all five")
	check(MapView.describe_selection(view.world, view.selection).contains("5 units selected"), "the sidebar says so")
	view.selection.set_ids([first.id])
	check(MapView.describe_selection(view.world, view.selection).contains("Guardsman"), "one unit is described by name")
	view.free()


func test_right_click_orders_a_move() -> void:
	var view := _view()
	view.order_move_to(Vector2(600, 1100))
	for unit in view.world.units:
		check(not unit.has_goal, "nothing moves when nothing is selected")
	var ids: Array = []
	for unit in view.world.units:
		ids.append(unit.id)
	view.selection.set_ids(ids)
	var target := Vector2i(14, 34)
	view.order_move_to(MapData.cell_center(target))
	for i in 400:
		view.world.tick()
	for unit in view.world.units:
		var gap := unit.cell - target
		check(maxi(absi(gap.x), absi(gap.y)) <= 1, "unit %d walked to the clicked spot" % unit.id)
	view.free()


func test_mouse_events_reach_the_map() -> void:
	var view := _view()
	var first: SimUnit = view.world.units[0]
	var on_screen := _body(first) - view.camera.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = on_screen
	view._unhandled_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = on_screen + Vector2(1, 1)
	view._unhandled_input(release)
	check_eq(view.selection.ids, [first.id] as Array[int], "press and release on a unit selects it")

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = on_screen + Vector2(96, 0)
	view._unhandled_input(right)
	check(first.has_goal, "a right click gives the selected unit a goal")
	check_eq(first.goal, MapData.cell_at_pixel(view.screen_to_map(right.position)), "at the clicked cell")

	check(MapView.in_map_area(Vector2(100, 100)), "the left part of the screen is the map")
	check(not MapView.in_map_area(Vector2(800, 100)), "the sidebar is not")
	view.free()


func test_group_keys_in_the_scene() -> void:
	var view := _view()
	var a: SimUnit = view.world.units[0]
	var b: SimUnit = view.world.units[1]
	view.selection.set_ids([a.id, b.id])
	view.press_group_key(1, true)
	view.selection.clear()
	view.press_group_key(1, false)
	check_eq(view.selection.ids, [a.id, b.id] as Array[int], "1 recalls what Ctrl+1 stored")
	view.press_group_key(4, false)
	check_eq(view.selection.ids, [a.id, b.id] as Array[int], "an empty group changes nothing")
	view.camera.center_on(Vector2(1500, 300))
	var away := view.camera.position
	view.press_group_key(1, false)
	check(view.camera.position != away, "pressing the group number twice jumps the camera to the group")
	check(view.camera.get_view_rect().has_point(UnitsView.feet_position(a)), "and the group is on screen")
	view.free()
