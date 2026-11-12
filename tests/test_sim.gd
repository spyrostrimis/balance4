extends TestCase
## The simulation: units on the grid, ticks, move orders, pathfinding, shroud.

const FOREST := "res://data/biomes/forest.tres"
const INFANTRY := "res://data/units/blue_infantry.tres"
const UNITS := ["res://data/units/blue_infantry.tres", "res://data/units/red_infantry.tres"]


func _world(rows: Array) -> SimWorld:
	var map := MapData.new()
	map.biome = load(FOREST)
	map.rows = PackedStringArray(rows)
	return SimWorld.new(map)


func _open(width: int, height: int) -> SimWorld:
	var rows := []
	for y in height:
		rows.append(".".repeat(width))
	return _world(rows)


func _type() -> UnitType:
	return load(INFANTRY)


## Run the simulation until every unit has stopped. Returns the number of ticks it took, or -1 if it never settled.
## Along the way it checks that no two units ever occupy the same cell.
func _run(world: SimWorld, max_ticks := 2000) -> int:
	for tick in max_ticks:
		var settled := true
		var cells := {}
		for unit in world.units:
			check(not cells.has(unit.cell), "two units share cell %s at tick %d" % [unit.cell, world.tick_count])
			check(world.unit_at(unit.cell) == unit, "cell %s does not point back at its unit" % unit.cell)
			check(world.map.is_walkable(unit.cell), "a unit stands on impassable cell %s" % unit.cell)
			cells[unit.cell] = true
			if not unit.is_settled():
				settled = false
		if settled:
			return tick
		world.tick()
	return -1


func test_unit_types_load() -> void:
	for path in UNITS:
		var type := load(path) as UnitType
		check(type != null, "%s loads as a UnitType" % path)
		if type == null:
			continue
		check(type.display_name != "", "%s has a name" % path)
		check(type.max_health > 0 and type.speed > 0 and type.sight > 0, "%s has health, speed and sight" % path)
		check_eq(type.sprites.get_size(), Vector2(8 * type.sprite_size.x, 3 * type.sprite_size.y),
				"%s sprite sheet is 8 facings by 3 poses" % path)


func test_ticks_per_cell() -> void:
	var type := UnitType.new()
	type.speed = 2.5
	check_eq(type.ticks_per_cell(false), 8, "2.5 cells a second is 8 ticks a cell")
	check_eq(type.ticks_per_cell(true), 11, "and 11 ticks diagonally")
	type.speed = 1000.0
	check_eq(type.ticks_per_cell(false), 1, "never less than one tick")


func test_add_unit() -> void:
	var world := _world(["..w", "..."])
	var unit := world.add_unit(_type(), 0, Vector2i(1, 0))
	check(unit != null, "a unit can be added on grass")
	check_eq(unit.health, _type().max_health, "it starts at full health")
	check(world.unit_at(Vector2i(1, 0)) == unit, "it occupies its cell")
	check(world.get_unit(unit.id) == unit, "it can be found by id")
	check(not world.is_free(Vector2i(1, 0)), "its cell is no longer free")
	check(world.add_unit(_type(), 0, Vector2i(1, 0)) == null, "no second unit on the same cell")
	check(world.add_unit(_type(), 0, Vector2i(2, 0)) == null, "no unit on water")
	check(world.add_unit(_type(), 0, Vector2i(5, 5)) == null, "no unit outside the map")
	check_eq(world.units.size(), 1, "failed additions add nothing")


func test_walks_straight_at_the_right_speed() -> void:
	var world := _open(8, 3)
	var unit := world.add_unit(_type(), 0, Vector2i(0, 1))
	world.order_move([unit.id], Vector2i(5, 1))
	var ticks := _run(world)
	check_eq(unit.cell, Vector2i(5, 1), "arrives at the target")
	# One tick to start, then 8 ticks for each of the 5 cells.
	check_eq(ticks, 1 + 5 * 8, "ticks taken for 5 cells")
	check_eq(unit.facing, 6, "ends facing east")
	check(not unit.has_goal, "has no goal left")


func test_walks_diagonally() -> void:
	var world := _open(6, 6)
	var unit := world.add_unit(_type(), 0, Vector2i(0, 0))
	world.order_move([unit.id], Vector2i(4, 4))
	var ticks := _run(world)
	check_eq(unit.cell, Vector2i(4, 4), "arrives at the target")
	check_eq(ticks, 1 + 4 * 11, "ticks taken for 4 diagonal cells")
	check_eq(unit.facing, 7, "ends facing south-east")


func test_facing() -> void:
	check_eq(SimWorld.facing_for(Vector2i(0, 1)), 0, "south")
	check_eq(SimWorld.facing_for(Vector2i(-1, 0)), 2, "west")
	check_eq(SimWorld.facing_for(Vector2i(0, -1)), 4, "north")
	check_eq(SimWorld.facing_for(Vector2i(1, 0)), 6, "east")
	check_eq(SimWorld.facing_for(Vector2i(-3, -3)), 3, "north-west, any length")


func test_position_between_ticks() -> void:
	var world := _open(4, 1)
	var unit := world.add_unit(_type(), 0, Vector2i(0, 0))
	check_eq(unit.visual_cell(0.5), Vector2(0, 0), "standing still")
	world.order_move([unit.id], Vector2i(2, 0))
	world.tick()
	check(unit.is_moving(), "moving after the first tick")
	check_eq(unit.cell, Vector2i(1, 0), "already occupies the cell it walks into")
	check_eq(unit.visual_cell(0.0), Vector2(0, 0), "but is still drawn where it started")
	world.tick()
	world.tick()
	check_eq(unit.visual_cell(0.0), Vector2(0.25, 0), "a quarter of the way after 2 of 8 ticks")
	check_eq(unit.visual_cell(0.5), Vector2(0.3125, 0), "and a little further half a tick later")


func test_path_goes_around_water() -> void:
	var world := _world([
		".....",
		".www.",
		".....",
	])
	var unit := world.add_unit(_type(), 0, Vector2i(2, 0))
	world.order_move([unit.id], Vector2i(2, 2))
	var visited := {}
	for tick in 400:
		world.tick()
		visited[unit.cell] = true
		check(world.map.is_walkable(unit.cell), "never steps on water (at %s)" % unit.cell)
	check_eq(unit.cell, Vector2i(2, 2), "arrives on the other side")
	check(visited.has(Vector2i(0, 1)) or visited.has(Vector2i(4, 1)), "went round one end of the water")


func test_no_cutting_corners() -> void:
	var world := _world([
		".w",
		"w.",
	])
	check_eq(world.terrain_path(Vector2i(0, 0), Vector2i(1, 1)), [] as Array[Vector2i], "no diagonal between two water cells")
	check(world.region_at(Vector2i(0, 0)) != world.region_at(Vector2i(1, 1)), "the two grass cells are separate areas")
	var unit := world.add_unit(_type(), 0, Vector2i(0, 0))
	world.order_move([unit.id], Vector2i(1, 1))
	_run(world)
	check_eq(unit.cell, Vector2i(0, 0), "the unit stays where it is")


func test_unreachable_target_gets_as_close_as_possible() -> void:
	var world := _world([
		"....w.",
		"....w.",
		"....w.",
	])
	var unit := world.add_unit(_type(), 0, Vector2i(0, 1))
	world.order_move([unit.id], Vector2i(5, 1))     # across the water
	var ticks := _run(world)
	check(ticks >= 0, "the unit comes to rest")
	check_eq(unit.cell, Vector2i(3, 1), "next to the water, on its own side")

	world.order_move([unit.id], Vector2i(4, 0))     # on the water itself
	_run(world)
	check_eq(unit.cell, Vector2i(3, 0), "nearest land to a water target")

	world.order_move([unit.id], Vector2i(-7, 40))   # outside the map
	_run(world)
	check_eq(unit.cell, Vector2i(0, 2), "a target outside the map is pulled to the nearest corner")


func test_group_gathers_around_the_target() -> void:
	var world := _open(16, 12)
	var ids := []
	for i in 5:
		ids.append(world.add_unit(_type(), 0, Vector2i(1, 1 + i)).id)
	var target := Vector2i(11, 6)
	world.order_move(ids, target)
	var ticks := _run(world)
	check(ticks >= 0, "everyone comes to rest")
	var cells := {}
	for id in ids:
		var unit := world.get_unit(id)
		cells[unit.cell] = true
		var gap := unit.cell - target
		check(maxi(absi(gap.x), absi(gap.y)) <= 1, "unit %d ends next to the target, at %s" % [id, unit.cell])
	check_eq(cells.size(), 5, "on five different cells")
	check(cells.has(target), "one of them on the target itself")


func test_walks_around_a_unit_standing_in_the_way() -> void:
	var world := _world([
		"ww...ww",
		".......",
		"ww...ww",
	])
	var blocker := world.add_unit(_type(), 0, Vector2i(3, 1))
	var walker := world.add_unit(_type(), 0, Vector2i(0, 1))
	world.order_move([walker.id], Vector2i(6, 1))
	check(_run(world) >= 0, "comes to rest")
	check_eq(walker.cell, Vector2i(6, 1), "the walker gets past")
	check_eq(blocker.cell, Vector2i(3, 1), "the standing unit has not moved")


func test_blocked_corridor_does_not_hang() -> void:
	var world := _world([
		"wwwwwww",
		".......",
		"wwwwwww",
	])
	world.add_unit(_type(), 0, Vector2i(3, 1))
	var walker := world.add_unit(_type(), 0, Vector2i(0, 1))
	world.order_move([walker.id], Vector2i(6, 1))
	check(_run(world) >= 0, "the walker gives up instead of trying for ever")
	check_eq(walker.cell, Vector2i(2, 1), "it stops right behind the unit in its way")


func test_units_meeting_in_a_corridor_change_places() -> void:
	var world := _world([
		"wwwwww",
		"......",
		"wwwwww",
	])
	var a := world.add_unit(_type(), 0, Vector2i(0, 1))
	var b := world.add_unit(_type(), 0, Vector2i(5, 1))
	world.order_move([a.id], Vector2i(4, 1))
	world.order_move([b.id], Vector2i(1, 1))
	check(_run(world) >= 0, "both come to rest")
	check_eq(a.cell, Vector2i(4, 1), "the first gets past the second")
	check_eq(b.cell, Vector2i(1, 1), "the second gets past the first")


func test_goal_taken_by_someone_else() -> void:
	var world := _open(8, 3)
	world.add_unit(_type(), 0, Vector2i(6, 1))
	var walker := world.add_unit(_type(), 0, Vector2i(0, 1))
	world.order_move([walker.id], Vector2i(6, 1))
	check(_run(world) >= 0, "comes to rest")
	var gap := walker.cell - Vector2i(6, 1)
	check_eq(maxi(absi(gap.x), absi(gap.y)), 1, "stops on a cell next to the taken one")


func test_new_order_replaces_the_old_one() -> void:
	var world := _open(10, 3)
	var unit := world.add_unit(_type(), 0, Vector2i(0, 1))
	world.order_move([unit.id], Vector2i(9, 1))
	for i in 20:
		world.tick()
	world.order_move([unit.id], Vector2i(0, 1))
	_run(world)
	check_eq(unit.cell, Vector2i(0, 1), "walks back to where the second order sent it")
	world.order_move([unit.id], Vector2i(9, 1))
	for i in 12:
		world.tick()
	world.order_stop([unit.id])
	_run(world)
	check_eq(unit.cell, Vector2i(2, 1), "a stop order ends the walk at the end of the current step")


func test_same_orders_same_result() -> void:
	var results := []
	for run in 2:
		var world := SimWorld.new(load("res://data/maps/forest_01.tres"))
		var ids := []
		for unit in MapView.spawn_squad(world, _type(), 0, world.map.starts[0], 5):
			ids.append(unit.id)
		world.order_move(ids, Vector2i(32, 24))
		for i in 300:
			world.tick()
		var cells := []
		for unit in world.units:
			cells.append(unit.cell)
		results.append(cells)
	check_eq(results[0], results[1], "two runs of the same orders")
	check(results[0][0] != Vector2i(10, 38), "and the squad did move")


func test_squad_crosses_the_real_map() -> void:
	var world := SimWorld.new(load("res://data/maps/forest_01.tres"))
	var ids := []
	for unit in MapView.spawn_squad(world, _type(), 0, world.map.starts[0], 5):
		ids.append(unit.id)
	check_eq(ids.size(), 5, "five units spawned")
	var target: Vector2i = world.map.starts[1]
	world.order_move(ids, target)
	var ticks := _run(world, 6000)
	check(ticks >= 0, "the squad arrives (took %d ticks)" % ticks)
	for id in ids:
		var gap := world.get_unit(id).cell - target
		check(maxi(absi(gap.x), absi(gap.y)) <= 2, "unit %d ends near the far start position" % id)


func test_shroud_starts_closed_and_opens_around_units() -> void:
	var world := _open(30, 30)
	var shroud := world.shroud_for(0)
	check_eq(shroud.explored_count(), 0, "nothing explored before any unit exists")
	var unit := world.add_unit(_type(), 0, Vector2i(15, 15))
	check(shroud.is_explored(Vector2i(15, 15)), "the unit's own cell")
	check(shroud.is_explored(Vector2i(19, 15)), "4 cells east (sight is 4)")
	check(not shroud.is_explored(Vector2i(20, 15)), "5 cells east is still hidden")
	check(shroud.is_explored(Vector2i(18, 18)), "3 cells diagonally")
	check(not shroud.is_explored(Vector2i(19, 19)), "the corner of the square is hidden: the area is round")
	check(not shroud.is_explored(Vector2i(-1, 15)), "outside the map counts as unexplored")
	check(not world.shroud_for(1).is_explored(Vector2i(15, 15)), "the other team has seen nothing")
	var before := shroud.explored_count()
	var version := shroud.version
	world.order_move([unit.id], Vector2i(25, 15))
	_run(world)
	check(shroud.is_explored(Vector2i(29, 15)), "walking east reveals more to the east")
	check(shroud.is_explored(Vector2i(11, 15)), "what was seen before stays visible")
	check(shroud.explored_count() > before, "the explored area grew")
	check(shroud.version > version, "the version went up")
	check_eq(shroud.revealed_log.size(), shroud.explored_count(), "every revealed cell is logged once")


func test_shroud_at_the_map_edge() -> void:
	var shroud := Shroud.new(Vector2i(6, 6))
	check_eq(shroud.reveal_circle(Vector2i(0, 0), 2), 8, "a circle at the corner reveals only cells inside the map")
	check_eq(shroud.reveal_circle(Vector2i(0, 0), 2), 0, "revealing the same area again adds nothing")
	check_eq(shroud.version, 1, "and does not bump the version")
	check(shroud.is_explored_clamped(Vector2i(-3, -3)), "outside cells take the state of the nearest inside cell")
