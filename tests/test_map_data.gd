extends TestCase
## MapData: reading the grid, bounds, and what each cell allows.

const FOREST := "res://data/biomes/forest.tres"
const MAPS := ["res://data/maps/forest_01.tres", "res://data/maps/desert_01.tres"]


func _small_map() -> MapData:
	var map := MapData.new()
	map.biome = load(FOREST)
	map.rows = PackedStringArray([
		"..ww",
		".dsw",
		"ffs.",
	])
	return map


func test_size() -> void:
	var map := _small_map()
	check_eq(map.get_size(), Vector2i(4, 3), "size in cells")
	check_eq(map.get_pixel_size(), Vector2i(128, 96), "size in pixels")
	check_eq(Array(map.problems()), [], "problems")


func test_terrain_lookup() -> void:
	var map := _small_map()
	check_eq(map.terrain_at(Vector2i(0, 0)).id, &"grass", "(0,0)")
	check_eq(map.terrain_at(Vector2i(1, 1)).id, &"dirt", "(1,1)")
	check_eq(map.terrain_at(Vector2i(2, 1)).id, &"stone", "(2,1)")
	check_eq(map.terrain_at(Vector2i(3, 0)).id, &"water", "(3,0)")
	check_eq(map.terrain_at(Vector2i(0, 2)).id, &"forest", "(0,2)")
	check_eq(map.terrain_index(Vector2i(3, 2)), 0, "index at (3,2)")


func test_outside_the_map() -> void:
	var map := _small_map()
	check(map.in_bounds(Vector2i(3, 2)), "(3,2) is inside")
	check(not map.in_bounds(Vector2i(4, 2)), "(4,2) is outside")
	check(not map.in_bounds(Vector2i(0, -1)), "(0,-1) is outside")
	check_eq(map.terrain_index(Vector2i(-1, 0)), -1, "index outside")
	check(map.terrain_at(Vector2i(0, 3)) == null, "terrain outside is null")
	check(not map.is_walkable(Vector2i(-1, 0)), "outside is not walkable")
	check(not map.is_buildable(Vector2i(9, 9)), "outside is not buildable")
	check_eq(map.terrain_index_clamped(Vector2i(9, -5)), 3, "clamped to the top-right cell (water)")
	check_eq(map.terrain_index_clamped(Vector2i(-2, 7)), 4, "clamped to the bottom-left cell (forest)")


func test_walkable_and_buildable() -> void:
	var map := _small_map()
	check(map.is_walkable(Vector2i(0, 0)), "grass is walkable")
	check(not map.is_walkable(Vector2i(2, 0)), "water is not walkable")
	check(map.is_buildable(Vector2i(2, 2)), "stone is buildable")
	check(not map.is_buildable(Vector2i(1, 1)), "dirt is not buildable")
	check(not map.is_buildable(Vector2i(0, 2)), "forest is not buildable")
	check(not map.is_walkable(Vector2i(0, 2)), "forest is not walkable")
	check(map.is_walkable(Vector2i(2, 1)), "stone is walkable")
	check(map.is_walkable(Vector2i(1, 1)), "dirt is walkable")


func test_cell_and_pixel_conversion() -> void:
	check_eq(MapData.cell_at_pixel(Vector2(0, 0)), Vector2i(0, 0), "pixel (0,0)")
	check_eq(MapData.cell_at_pixel(Vector2(31.9, 32)), Vector2i(0, 1), "pixel (31.9,32)")
	check_eq(MapData.cell_at_pixel(Vector2(-1, 5)), Vector2i(-1, 0), "pixel (-1,5)")
	check_eq(MapData.cell_center(Vector2i(2, 1)), Vector2(80, 48), "centre of (2,1)")


func test_bad_maps_are_reported() -> void:
	var ragged := MapData.new()
	ragged.biome = load(FOREST)
	ragged.rows = PackedStringArray(["...", ".."])
	check(not ragged.problems().is_empty(), "a short row is reported")

	var unknown := MapData.new()
	unknown.biome = load(FOREST)
	unknown.rows = PackedStringArray(["..x"])
	check(not unknown.problems().is_empty(), "an unknown symbol is reported")
	check_eq(unknown.terrain_index(Vector2i(2, 0)), 0, "an unknown symbol falls back to ground")

	var no_biome := MapData.new()
	no_biome.rows = PackedStringArray(["..."])
	check(not no_biome.problems().is_empty(), "a missing biome is reported")
	check_eq(no_biome.get_size(), Vector2i.ZERO, "a map without a biome is empty")


func test_changing_rows_reparses() -> void:
	var map := _small_map()
	check_eq(map.get_size(), Vector2i(4, 3), "before")
	map.rows = PackedStringArray(["ss"])
	check_eq(map.get_size(), Vector2i(2, 1), "after")
	check(map.is_buildable(Vector2i(1, 0)), "new rows are used")


func test_shipped_maps() -> void:
	for path in MAPS:
		var map := load(path) as MapData
		check(map != null, "%s loads as MapData" % path)
		if map == null:
			continue
		check_eq(Array(map.problems()), [], "problems in %s" % path)
		check_eq(map.get_size(), Vector2i(64, 48), "size of %s" % path)
		check(map.display_name != "", "%s has a name" % path)
		var used := {}
		var size := map.get_size()
		for y in size.y:
			for x in size.x:
				used[map.terrain_index(Vector2i(x, y))] = true
		check_eq(used.size(), map.biome.terrains.size(), "%s uses every terrain of its biome" % path)
		check(map.has_control_point(), "%s has a control point" % path)
		check_eq(map.control_point, Vector2(size) / 2.0, "the control point of %s is the map centre" % path)
		check_eq(map.terrain_at(size / 2).id, &"ore_rock", "the Orichalcum rock stands on the centre of %s" % path)
		check(not map.is_walkable(size / 2), "the rock on %s cannot be crossed" % path)
		check_eq(map.starts.size(), 2, "%s has two start positions" % path)


func test_shipped_maps_are_connected() -> void:
	# Trees, water and the rock block the way: both sides must still be able to
	# walk to the rock and to each other.
	for path in MAPS:
		var map := load(path) as MapData
		var world := SimWorld.new(map)
		var region := world.region_at(map.starts[0])
		check(region != 0, "the first start of %s is walkable" % path)
		check_eq(world.region_at(map.starts[1]), region, "the starts of %s are joined by walkable ground" % path)
		check(not world.terrain_path(map.starts[0], map.starts[1]).is_empty(), "there is a path between the starts of %s" % path)
		var beside_rock := world.nearest_free_cell(Vector2i(map.control_point), region)
		var gap := Vector2(beside_rock) + Vector2(0.5, 0.5) - map.control_point
		check(gap.length() < 5.0, "ground next to the rock on %s can be reached from the starts" % path)
