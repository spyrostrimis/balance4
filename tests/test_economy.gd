extends TestCase
## Orichalcum: deposits, buildings, the harvester's round trip (the robot
## fills the trailer, the truck takes it to the refinery), the refinery and
## its storage limit, the harvest trial, and what the screen shows of it.
## Guarding and stealing are in test_trailer.gd.

const FOREST := "res://data/biomes/forest.tres"
const MAPS := ["res://data/maps/forest_01.tres", "res://data/maps/desert_01.tres"]
const HARVESTERS := ["res://data/units/blue_harvester.tres", "res://data/units/red_harvester.tres"]
const REFINERIES := ["res://data/buildings/blue_refinery.tres", "res://data/buildings/red_refinery.tres"]
const TRIALS := ["res://data/missions/harvest_trial_blue.tres", "res://data/missions/harvest_trial_red.tres"]
const MISSION_1 := "res://data/missions/first_claim_blue.tres"
const GUARD := "res://data/units/blue_infantry.tres"
const MAP_SCENE := "res://scenes/map_view.tscn"
const PLAYER := SimWorld.PLAYER_TEAM
const Job := SimUnit.Job
## A small field: stone to build on at the left, a rock of four cells (200
## Orichalcum) at the right.
const FIELD := [
	"....................",
	"....................",
	"....................",
	".sss............oo..",
	".sss............oo..",
	"....................",
	"....................",
	"....................",
]
const ROCK := Vector2i(16, 3)
const SITE := Vector2i(1, 3)


func _world(rows: Array = FIELD) -> SimWorld:
	var map := MapData.new()
	map.biome = load(FOREST)
	map.rows = PackedStringArray(rows)
	return SimWorld.new(map)


func _harvester_type() -> UnitType:
	return load(HARVESTERS[0]) as UnitType


## A refinery type like Blue's, with another storage limit if one is given.
func _refinery_type(storage := -1) -> BuildingType:
	var type := (load(REFINERIES[0]) as BuildingType).duplicate() as BuildingType
	if storage >= 0:
		type.storage = storage
	return type


func _run(world: SimWorld, seconds: float) -> void:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		world.tick()


## Tick until a harvester has a job, for at most `seconds`. Returns whether it got there.
func _run_until(world: SimWorld, unit: SimUnit, job: SimUnit.Job, seconds := 60.0) -> bool:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		if unit.job == job:
			return true
		world.tick()
	return unit.job == job


## Tick for as long as a harvester keeps a job. Returns how many ticks that was.
func _ticks_in(world: SimWorld, unit: SimUnit, job: SimUnit.Job) -> int:
	var ticks := 0
	while unit.job == job and ticks < 1000:
		world.tick()
		ticks += 1
	return ticks


# --- deposits ------------------------------------------------------------------------

func test_ore_rock_is_a_deposit_on_both_maps() -> void:
	for path in MAPS:
		var map := load(path) as MapData
		var world := SimWorld.new(map)
		check_eq(world.deposits.size(), 1, "%s has one deposit" % path)
		var deposit := world.deposits[0]
		var rock_cells := 0
		for y in map.get_size().y:
			for x in map.get_size().x:
				var cell := Vector2i(x, y)
				if map.terrain_at(cell).id == &"ore_rock":
					rock_cells += 1
					check(world.deposit_at(cell) == deposit, "rock cell %s belongs to the deposit" % cell)
		check(rock_cells >= 12, "the formation in %s has a fair number of cells (%d)" % [path, rock_cells])
		check_eq(deposit.cells.size(), rock_cells, "every rock cell of %s is in the deposit" % path)
		check_eq(deposit.capacity, rock_cells * 50, "each cell holds 50")
		check_eq(deposit.amount, deposit.capacity, "it starts full")
		check_eq(world.ore_left(), deposit.capacity, "and that is all the Orichalcum on the map")
		check(world.deposit_at(map.starts[0]) == null, "ordinary ground is not a deposit")
		check(world.deposit_at(Vector2i(-1, 0)) == null, "nor is anything outside the map")
		check(map.terrain_at(deposit.cells[0]).spent_tiles != null, "the rock has tiles for its mined-out look")


func test_separate_rocks_are_separate_deposits() -> void:
	var world := _world(["oo....o", "oo.....", "......."])
	check_eq(world.deposits.size(), 2, "two formations that do not touch")
	check_eq(world.deposits[0].capacity, 200, "four cells")
	check_eq(world.deposits[1].capacity, 50, "one cell")
	check(world.deposit_at(Vector2i(0, 0)) != world.deposit_at(Vector2i(6, 0)), "they are different deposits")
	var diagonal := _world(["o..", ".o.", "..."])
	check_eq(diagonal.deposits.size(), 1, "cells touching at a corner are one formation")


func test_a_deposit_is_dug_from_where_the_harvester_stands() -> void:
	var world := _world()
	var deposit := world.deposit_at(ROCK)
	var from := Vector2i(15, 4)
	var dug: Array[Vector2i] = []
	check_eq(deposit.take(from, 30, dug), 30, "it gives what is asked for")
	check_eq(dug[0], Vector2i(16, 4), "from the cell nearest to the harvester")
	check_eq(deposit.left_at(Vector2i(16, 4)), 20, "which now holds less")
	check_eq(deposit.amount, 170, "and so does the deposit")
	check(not deposit.is_spent(Vector2i(16, 4)), "the cell is not empty yet")
	check_eq(deposit.take(from, 40, dug), 40, "a load can come from two cells")
	check(deposit.is_spent(Vector2i(16, 4)), "the first is now spent")
	check_eq(dug[0], Vector2i(16, 3), "and digging went on in the next nearest")
	check_eq(world.spent_log, [Vector2i(16, 4)] as Array[Vector2i], "the world lists the spent cell")
	check_eq(deposit.live_cells(), 3, "three cells still hold something")
	check_eq(deposit.take(from, 1000), 130, "it never gives more than it has")
	check(deposit.is_empty(), "then it has run out")
	check_eq(deposit.take(from, 10), 0, "and gives nothing")
	check_eq(world.spent_log.size(), 4, "all four cells are spent")
	check(not world.map.is_walkable(Vector2i(16, 4)), "spent rock is still rock")


# --- buildings -----------------------------------------------------------------------

func test_buildings_stand_only_on_ground_that_can_be_built_on() -> void:
	var world := _world()
	var type := _refinery_type()
	check_eq(type.footprint, Vector2i(3, 2), "the refinery covers three by two cells")
	check(world.can_build(type, SITE), "it fits on the stone")
	check(not world.can_build(type, SITE + Vector2i(1, 0)), "but not half on grass")
	check(not world.can_build(type, Vector2i(18, 7)), "and not across the edge of the map")
	check(world.add_building(type, PLAYER, Vector2i(8, 1)) == null, "so it cannot be put on grass")
	check_eq(world.nearest_build_site(type, Vector2i(10, 6)), SITE, "the nearest site is found")
	var guard := world.add_unit(load(GUARD), PLAYER, Vector2i(2, 4))
	check(not world.can_build(type, SITE), "a unit in the way blocks it")
	check_eq(world.nearest_build_site(type, Vector2i(10, 6)), SimWorld.NO_CELL, "and then there is no site at all")
	world.order_move([guard.id], Vector2i(6, 6))
	_run(world, 4.0)
	var refinery := world.add_building(type, PLAYER, SITE)
	check(refinery != null, "once the unit has left it can be built")
	check(not world.can_build(type, SITE), "but not twice in the same place")
	check(world.building_at(Vector2i(3, 4)) == refinery, "the building is found by any cell it covers")
	check(world.building_at(Vector2i(4, 4)) == null, "and not by the cell next to it")
	check(world.get_building(refinery.id) == refinery, "or by its id")
	check(refinery.is_beside(Vector2i(4, 5)), "a cell at its corner is beside it")
	check(not refinery.is_beside(Vector2i(2, 3)) and not refinery.is_beside(Vector2i(5, 4)), "a cell under it or further off is not")
	check_eq(world.storage_for(PLAYER), 800, "a refinery gives its side storage")
	check_eq(world.storage_for(1), 0, "and the other side none")


func test_units_walk_around_buildings() -> void:
	var world := _world()
	var refinery := world.add_building(_refinery_type(), PLAYER, SITE)
	for cell in refinery.cells():
		check(not world.is_free(cell), "cell %s under the building is not free" % cell)
		check_eq(world.region_at(cell), 0, "and cannot be walked on")
	check(world.add_unit(load(GUARD), PLAYER, Vector2i(2, 3)) == null, "a unit cannot be put on a building")
	var guard := world.add_unit(load(GUARD), PLAYER, Vector2i(0, 3))
	world.order_move([guard.id], Vector2i(5, 4))
	var crossed := false
	for i in 200:
		world.tick()
		if refinery.rect().has_point(guard.cell):
			crossed = true
	check_eq(guard.cell, Vector2i(5, 4), "the unit reaches the far side")
	check(not crossed, "without walking through the building")
	world.order_move([guard.id], Vector2i(2, 3))
	_run(world, 5.0)
	check(refinery.is_beside(guard.cell), "sent onto the building, it stops beside it")
	check(world.shroud_for(PLAYER).is_explored(Vector2i(5, 1)), "a building lifts the shroud around itself")


# --- the harvester -------------------------------------------------------------------

func test_harvester_data() -> void:
	for i in 2:
		var type := load(HARVESTERS[i]) as UnitType
		check(type != null and type.is_harvester(), "%s is a harvester" % HARVESTERS[i])
		check(type.cargo_capacity > 0 and type.harvest_rate > 0 and type.unload_rate > 0, "it carries, digs and unloads")
		check(type.pack_capacity > 0 and type.pack_capacity < type.cargo_capacity, "the robot's pack is smaller than the trailer")
		check(type.load_rate > 0 and type.robot_speed > 0.0, "the robot walks and fills the trailer")
		check(type.attack_damage > 0 and type.robot_armor >= 50, "the robot can hit back and is heavily armoured")
		check(type.attack_damage < (load(GUARD) as UnitType).attack_damage, "but hits less hard than a soldier")
		check_eq(type.transform_ticks(), 20, "changing shape takes a second")
		check_eq(type.sprites.get_size(), Vector2(8 * type.sprite_size.x, 6 * type.sprite_size.y), "its sheet has 8 facings and 6 rows")
		check_eq(type.trailer_sprites.get_size(), Vector2(8 * type.sprite_size.x, 2 * type.sprite_size.y), "the trailer's has 8 facings and 2 rows")
		var refinery := load(REFINERIES[i]) as BuildingType
		check(refinery != null and refinery.is_refinery and refinery.storage > 0, "%s is a refinery with storage" % REFINERIES[i])
		check_eq(refinery.sprite.get_size(), Vector2(refinery.footprint * 32 + refinery.sprite_origin * 2),
				"its picture covers its cells and a margin")
	check(not (load(GUARD) as UnitType).is_harvester(), "a soldier is not a harvester")


func test_harvester_round_trip() -> void:
	var world := _world()
	var refinery := world.add_building(_refinery_type(), PLAYER, SITE)
	var harvester := world.add_unit(_harvester_type(), PLAYER, Vector2i(5, 4))
	var deposit := world.deposit_at(ROCK)
	check(world.order_harvest([harvester.id], ROCK), "the order is accepted")
	check_eq(harvester.order, SimUnit.Order.HARVEST, "the harvester has a harvest order")
	var jobs: Array = []
	var trailer_cells := {}
	var truck_dug := false
	var filled_away_from_trailer := false
	for i in 20 * 40:
		var pack := harvester.pack
		var cargo := harvester.cargo
		var job := harvester.job
		world.tick()
		if jobs.is_empty() or jobs[-1] != harvester.job:
			jobs.append(harvester.job)
		var trailer := world.get_trailer(harvester.trailer_id)
		if trailer != null:
			trailer_cells[trailer.cell] = true
			if harvester.cargo > cargo and SimWorld._cells_apart(harvester.cell, trailer.cell) != 1:
				filled_away_from_trailer = true
		if harvester.pack > pack and job != Job.EXTRACT:
			truck_dug = true
		if world.stored_for(PLAYER) > 0 and harvester.job == Job.TO_DEPOSIT:
			break
	check_eq(jobs.slice(0, 6), [Job.TO_DEPOSIT, Job.DEPLOY, Job.TO_ROCK, Job.EXTRACT, Job.TO_TRAILER, Job.LOAD],
			"it drives out as a truck, unfolds, and the robot digs and tips its pack into the trailer")
	check_eq(jobs.count(Job.EXTRACT), 4, "four packs fill the trailer")
	check_eq(jobs.slice(jobs.find(Job.PACK)), [Job.PACK, Job.TO_REFINERY, Job.UNLOAD, Job.NONE, Job.TO_DEPOSIT],
			"then it folds up, drives back and unloads")
	check_eq(trailer_cells.size(), 1, "the trailer stays where the truck stopped")
	check(not truck_dug, "only the digging robot fills its pack")
	check(not filled_away_from_trailer, "and the trailer is filled from right beside it")
	check_eq(world.stored_for(PLAYER), 100, "one full load is in store")
	check_eq(harvester.cargo, 0, "the trailer is empty again")
	check_eq(deposit.amount, 100, "and the deposit is a load poorer")
	check_eq(world.spent_log.size(), 2, "two of its cells are spent")
	check_eq(harvester.order, SimUnit.Order.HARVEST, "it keeps its order")
	check_eq(harvester.job, Job.TO_DEPOSIT, "and sets off again on its own")
	check(refinery.is_beside(harvester.cell), "from beside the refinery")
	_run(world, 60.0)
	check_eq(world.stored_for(PLAYER), 200, "it fetches the rest without being told")
	check(deposit.is_empty(), "until the deposit has run out")
	check_eq(harvester.order, SimUnit.Order.NONE, "then it has nothing left to do")
	check_eq(harvester.job, Job.NONE, "and stands as a truck")
	check(not harvester.is_robot() and world.trailers.is_empty(), "with its trailer hitched")
	check(not world.order_harvest([harvester.id], Vector2i(8, 6)), "grass cannot be harvested")


func test_harvester_times() -> void:
	var world := _world()
	world.add_building(_refinery_type(), PLAYER, SITE)
	var harvester := world.add_unit(_harvester_type(), PLAYER, Vector2i(15, 4))
	var parked := Vector2i(15, 4)
	world.order_harvest([harvester.id], ROCK)
	world.tick()
	check_eq(harvester.job, Job.DEPLOY, "beside the rock it unfolds at once")
	check_eq(harvester.cell, parked, "where it stands")
	check_eq(harvester.facing, 6, "facing the rock (east)")
	check(world.trailers.is_empty(), "the trailer is still hitched")
	check_eq(_ticks_in(world, harvester, Job.DEPLOY), 20, "unfolding takes a second")
	var trailer := world.get_trailer(harvester.trailer_id)
	check(trailer != null and trailer.cell == parked, "then the trailer stands where the truck stood")
	check(world.trailer_at(parked) == trailer and trailer.owner_id == harvester.id, "and belongs to the robot")
	check_eq(trailer.facing, 6, "facing the way the truck did")
	check(not world.is_free(parked), "it takes up its cell")
	check_eq(SimWorld._cells_apart(harvester.cell, parked), 1, "and the robot has stepped off next to it")
	check(_run_until(world, harvester, Job.EXTRACT, 5.0), "the robot starts to dig")
	check_eq(_ticks_in(world, harvester, Job.EXTRACT), 25, "filling the pack of 25 takes 25 ticks at 20 a second")
	check_eq(harvester.pack, 25, "and fills it exactly")
	check_eq(harvester.cargo, 0, "nothing is in the trailer yet")
	check(_run_until(world, harvester, Job.LOAD, 5.0), "it turns to the trailer")
	check_eq(_ticks_in(world, harvester, Job.LOAD), 10, "tipping the pack out takes half a second at 50 a second")
	check_eq([harvester.pack, harvester.cargo], [0, 25], "then the load is in the trailer")
	check(_run_until(world, harvester, Job.PACK), "with the trailer full it goes back to it")
	check_eq(harvester.cargo, 100, "the trailer holds four packs")
	check(world.trailers.is_empty(), "the trailer is hitched again")
	var ticks := _ticks_in(world, harvester, Job.PACK)
	check(ticks >= 20 and ticks <= 35, "stepping onto the trailer and folding up takes a good second (%d ticks)" % ticks)
	check_eq(harvester.cell, parked, "the truck stands where the trailer stood")
	check_eq(harvester.facing, 6, "facing the way it did")
	check(_run_until(world, harvester, Job.UNLOAD), "it drives to the refinery")
	check_eq(_ticks_in(world, harvester, Job.UNLOAD), 40, "unloading takes two seconds at 50 a second")


func test_storage_has_a_limit() -> void:
	var world := _world()
	var refinery := world.add_building(_refinery_type(150), PLAYER, SITE)
	var harvester := world.add_unit(_harvester_type(), PLAYER, Vector2i(5, 4))
	check_eq(world.storage_for(PLAYER), 150, "the side can store 150")
	world.order_harvest([harvester.id], ROCK)
	_run(world, 100.0)
	check(world.deposits[0].is_empty(), "the whole deposit was fetched")
	check_eq(world.stored_for(PLAYER), 150, "but only what fits is in store")
	check_eq(harvester.cargo, 50, "the harvester keeps the rest")
	check(world.is_waiting_for_room(harvester), "and waits at the refinery")
	check(refinery.is_beside(harvester.cell) and harvester.is_settled(), "right beside it")
	check_eq(harvester.order, SimUnit.Order.HARVEST, "still on its harvest order")
	check_eq(MapView.job_text(harvester, world), "Waiting: the store is full", "the sidebar says why it waits")
	check_eq(MissionHud.store_text(world, PLAYER), "Orichalcum 150 / 150 (full)", "the HUD says the store is full")
	check_eq(MissionHud.rock_text(world), "The rock has run out", "and that the rock has run out")
	refinery.type.storage = 180
	_run(world, 3.0)
	check_eq([world.stored_for(PLAYER), harvester.cargo], [180, 20], "when there is room again it unloads as much as fits")
	refinery.type.storage = 800
	_run(world, 3.0)
	check_eq([world.stored_for(PLAYER), harvester.cargo], [200, 0], "and the rest once that fits too")
	check_eq(harvester.order, SimUnit.Order.NONE, "then it is done")


func test_two_refineries_store_twice_as_much() -> void:
	var world := _world([".sss.sss........oo..", ".sss.sss........oo..", "....................", "...................."])
	world.add_building(_refinery_type(60), PLAYER, Vector2i(1, 0))
	world.add_building(_refinery_type(60), PLAYER, Vector2i(5, 0))
	check_eq(world.storage_for(PLAYER), 120, "storage adds up")
	var harvester := world.add_unit(_harvester_type(), PLAYER, Vector2i(9, 2))
	world.order_harvest([harvester.id], Vector2i(16, 0))
	_run(world, 100.0)
	check_eq(world.stored_for(PLAYER), 120, "and fills up to the sum")
	check_eq(world.get_building(harvester.refinery_id).cell, Vector2i(5, 0), "the harvester uses the nearer refinery")


func test_two_harvesters_share_a_rock() -> void:
	var world := _world()
	world.add_building(_refinery_type(), PLAYER, SITE)
	var first := world.add_unit(_harvester_type(), PLAYER, Vector2i(5, 4))
	var second := world.add_unit(_harvester_type(), PLAYER, Vector2i(5, 5))
	world.order_harvest([first.id, second.id], ROCK)
	check(_run_until(world, first, Job.EXTRACT) and _run_until(world, second, Job.EXTRACT), "both get to dig")
	check(first.cell != second.cell, "each from its own cell")
	check_eq(world.trailers.size(), 2, "each with its own trailer")
	check(world.trailers[0].cell != world.trailers[1].cell, "on its own cell")
	_run(world, 90.0)
	check_eq(world.stored_for(PLAYER), 200, "together they bring in the whole deposit")
	check_eq(first.order, SimUnit.Order.NONE, "and then both stop")
	check_eq(second.order, SimUnit.Order.NONE, "and then both stop")
	check(world.trailers.is_empty(), "as trucks")


func test_new_orders_interrupt_the_work() -> void:
	var world := _world()
	var refinery := world.add_building(_refinery_type(), PLAYER, SITE)
	var harvester := world.add_unit(_harvester_type(), PLAYER, Vector2i(14, 4))
	world.order_harvest([harvester.id], ROCK)
	check(_run_until(world, harvester, Job.EXTRACT), "it starts digging")
	_run(world, 1.0)
	var pack := harvester.pack
	check(pack > 0 and pack < 25, "it has part of a pack")
	var parked := world.get_trailer(harvester.trailer_id).cell
	world.order_move([harvester.id], Vector2i(10, 6))
	check(harvester.leaving and harvester.is_robot(), "told to move, the robot first goes back to its trailer")
	check_eq(MapView.job_text(harvester), "Going back to its trailer", "and the sidebar says so")
	check(_run_until(world, harvester, Job.PACK, 5.0), "it steps onto it and folds up")
	check_eq(harvester.cell, parked, "where the trailer stands")
	check_eq(harvester.cargo, pack, "what was in its pack goes into the trailer")
	_run(world, 6.0)
	check_eq(harvester.cell, Vector2i(10, 6), "then it drives where it was sent")
	check_eq(harvester.job, Job.NONE, "as a truck")
	check(not harvester.is_robot() and world.trailers.is_empty(), "with its trailer")
	check_eq(harvester.order, SimUnit.Order.NONE, "and waits there")
	check_eq([harvester.cargo, harvester.pack], [pack, 0], "with what it had dug")
	# Sent to the refinery with a part load, it unloads and goes back to work.
	check(world.order_unload([harvester.id], refinery.id), "it can be sent to unload")
	check(_run_until(world, harvester, Job.UNLOAD), "it drives to the refinery")
	check(_run_until(world, harvester, Job.EXTRACT), "and afterwards back to the rock it was working")
	check_eq(world.stored_for(PLAYER), pack, "the part load is in store")
	# Sent to the rock it is already working, the robot just carries on.
	world.order_harvest([harvester.id], ROCK)
	check(not harvester.leaving and harvester.job == Job.EXTRACT, "a second order for the same rock changes nothing")
	world.order_stop([harvester.id])
	check(harvester.leaving, "stop sends it back to its trailer")
	_run(world, 4.0)
	check_eq(harvester.order, SimUnit.Order.NONE, "and it stays stopped")
	check_eq(harvester.job, Job.NONE, "as a truck")
	check(world.trailers.is_empty(), "with its trailer hitched")
	check(not world.order_unload([harvester.id], 12345), "there is no unloading at something that is not a refinery")


func test_an_unfolding_truck_can_be_called_off() -> void:
	var world := _world()
	var harvester := world.add_unit(_harvester_type(), PLAYER, Vector2i(15, 4))
	world.order_harvest([harvester.id], ROCK)
	_run(world, 0.5)
	check_eq(harvester.job, Job.DEPLOY, "it is unfolding")
	world.order_move([harvester.id], Vector2i(10, 4))
	check_eq(harvester.job, Job.PACK, "told to move, it folds up again at once")
	check(world.trailers.is_empty(), "the trailer was never unhitched")
	_run(world, 0.5)
	check_eq(harvester.cell, Vector2i(15, 4), "it stays put while it folds")
	_run(world, 4.0)
	check_eq(harvester.cell, Vector2i(10, 4), "then drives where it was sent")
	check_eq(harvester.order, SimUnit.Order.NONE, "and waits")


func test_without_a_refinery_the_harvester_waits_with_its_load() -> void:
	var world := _world()
	var harvester := world.add_unit(_harvester_type(), PLAYER, Vector2i(14, 4))
	world.order_harvest([harvester.id], ROCK)
	_run(world, 20.0)
	check_eq(harvester.cargo, 100, "it fills its hold")
	check_eq(harvester.job, Job.TO_REFINERY, "and wants to unload")
	check(harvester.is_settled(), "but waits, as there is no refinery")
	check_eq(world.stored_for(PLAYER), 0, "nothing is stored")
	check_eq(MissionHud.store_text(world, PLAYER), "", "and the HUD shows no store")
	world.add_building(_refinery_type(), PLAYER, SITE)
	_run(world, 20.0)
	check(world.stored_for(PLAYER) >= 100, "once a refinery stands, it delivers")


func test_only_harvesters_harvest() -> void:
	var world := _world()
	var refinery := world.add_building(_refinery_type(), PLAYER, SITE)
	var guard := world.add_unit(load(GUARD), PLAYER, Vector2i(5, 4))
	check(not world.order_harvest([guard.id], ROCK), "a soldier does not take a harvest order")
	check_eq(guard.order, SimUnit.Order.NONE, "and keeps standing")
	check(not world.order_unload([guard.id], refinery.id), "nor an order to unload")
	var foreign := world.add_unit(_harvester_type(), 1, Vector2i(6, 4))
	check(not world.order_unload([foreign.id], refinery.id), "a harvester does not unload at another side's refinery")
	foreign.cargo = 100
	world.order_harvest([foreign.id], ROCK)
	_run(world, 10.0)
	check_eq(world.stored_for(PLAYER), 0, "and never delivers to it")
	check_eq(world.stored_for(1), 0, "its own side has no store")


func test_harvester_moves_on_to_another_rock() -> void:
	var world := _world([
		"o.............o.",
		"................",
		".sss............",
		".sss............",
	])
	world.add_building(_refinery_type(), PLAYER, Vector2i(1, 2))
	var harvester := world.add_unit(_harvester_type(), PLAYER, Vector2i(5, 1))
	world.order_harvest([harvester.id], Vector2i(0, 0))
	_run(world, 90.0)
	check_eq(world.ore_left(), 0, "when its rock runs out it goes on to the next")
	check_eq(world.stored_for(PLAYER), 100, "and brings that in too")
	check_eq(harvester.order, SimUnit.Order.NONE, "then it is done")


# --- the harvest trial ---------------------------------------------------------------

func test_trial_start() -> void:
	for i in 2:
		var def := load(TRIALS[i]) as MissionDef
		check(def != null and def.practice, "%s is a practice mission" % TRIALS[i])
		var mission := Mission.new(def)
		var world := mission.world
		var refinery := world.get_building(mission.player_refinery_id)
		check(refinery != null and refinery.type.is_refinery and refinery.type in def.placed_types(PLAYER), "the player has a refinery")
		if refinery == null:
			continue
		for cell in refinery.cells():
			check(def.map.is_buildable(cell), "it stands on ground that can be built on (%s)" % cell)
		check(refinery.center().distance_to(Vector2(def.map.starts[0])) < 8.0, "near the player's start")
		check_eq(world.units.size(), 2, "two harvesters and nobody else")
		for unit in world.units:
			check(unit.type.is_harvester() and unit.team == PLAYER, "unit %d is the player's harvester" % unit.id)
			check((Vector2(unit.cell) - refinery.center()).length() < 4.0, "and starts by the refinery")
		check_eq(world.stored_for(PLAYER), 0, "the store starts empty")
		check_eq(world.storage_for(PLAYER), 800, "and holds 800")
		check(world.shroud_for(PLAYER).is_explored(world.deposits[0].cells[0]), "the rock is marked on the player's map")
		for tick in 20 * 30:
			mission.tick()
		check(not mission.is_over(), "doing nothing neither wins nor loses a practice mission")
		check_eq(mission.world.tick_count, 600, "but time passes")


func test_trial_earns_on_its_own_and_fills_the_store() -> void:
	for i in 2:
		var mission := Mission.new(load(TRIALS[i]) as MissionDef)
		var world := mission.world
		var deposit := world.deposits[0]
		var ids: Array = []
		for unit in world.units:
			ids.append(unit.id)
		check(world.order_harvest(ids, deposit.cells[0]), "the harvesters are sent to the rock once")
		for tick in 20 * 60:
			mission.tick()
		check(world.stored_for(PLAYER) >= 100, "a minute later Orichalcum is in store in %s (%d)" % [TRIALS[i], world.stored_for(PLAYER)])
		var full_tick := -1
		for tick in 20 * 600:
			if world.stored_for(PLAYER) >= 800 and full_tick < 0:
				full_tick = world.tick_count
			if full_tick >= 0 and world.tick_count - full_tick > 20 * 60:
				break
			mission.tick()
		check(full_tick > 0 and full_tick < 20 * 240, "the store is full within four minutes in %s (%d s)" % [TRIALS[i], full_tick / 20])
		check_eq(world.stored_for(PLAYER), 800, "and never holds more than fits")
		var on_board := 0
		for unit in world.units:
			on_board += unit.cargo + unit.pack
			check(world.is_waiting_for_room(unit), "harvester %d waits at the refinery with its load" % unit.id)
			check_eq(unit.cargo, 100, "a full one")
		check_eq(world.stored_for(PLAYER) + on_board + deposit.amount, deposit.capacity, "nothing was lost on the way")
		check(world.trailers.is_empty(), "no trailer is left standing")


func test_mission_1_has_no_economy() -> void:
	var mission := Mission.new(load(MISSION_1) as MissionDef)
	check(mission.world.buildings.is_empty(), "no buildings")
	check_eq(mission.world.units.size(), 10, "and the same ten units as before")
	check_eq(MissionHud.store_text(mission.world, PLAYER), "", "so the HUD shows no store")


# --- on screen -----------------------------------------------------------------------

## The map scene running the harvest trial. The caller frees it.
func _view(index := 0) -> MapView:
	MapView.requested_mission = TRIALS[index]
	var view := (load(MAP_SCENE) as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	MapView.requested_mission = ""
	return view


func _click(view: MapView, map_point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = view.map_to_screen(map_point)
	view._unhandled_input(event)
	if button == MOUSE_BUTTON_LEFT:
		var release := InputEventMouseButton.new()
		release.button_index = button
		release.pressed = false
		release.position = event.position
		view._unhandled_input(release)


func test_title_screen_offers_the_trial() -> void:
	var title := load("res://scripts/ui/title_screen.gd")
	check_eq(title.map_from_args(PackedStringArray(["--map=harvest-forest"])), "harvest-forest", "--map=harvest-forest")
	check_eq(title.map_from_args(PackedStringArray(["--map=harvest-desert"])), "harvest-desert", "--map=harvest-desert")
	check((load(title.MISSIONS["harvest-forest"]) as MissionDef).practice, "it starts the practice mission")
	var node := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(node)
	check(node.get_node_or_null("Center/Box/Trials/HarvestForest") != null, "there is a button for the forest trial")
	check(node.get_node_or_null("Center/Box/Trials/HarvestDesert") != null, "and one for the desert trial")
	node.free()


func test_trial_hints() -> void:
	var def := load(TRIALS[0]) as MissionDef
	var hints := MissionHints.new(Mission.new(def))
	check_eq(hints.current(), &"select", "first: select a harvester")
	check(hints.text().contains("harvesters"), "the first hint says where they are")
	hints.note(&"select")
	check_eq(hints.current(), &"harvest", "then: send it to the rock")
	check(hints.text().contains("Right-click the Orichalcum rock"), "the second hint says how")
	hints.note(&"harvest")
	check_eq(hints.current(), &"watch", "last: what happens on its own")
	check(hints.text().contains("800"), "the last hint gives the storage limit from the data")
	var hasty := MissionHints.new(Mission.new(def))
	hasty.note(&"harvest")
	check_eq(hasty.current(), &"watch", "a player who sends the harvesters at once skips the first hint")


func test_scene_runs_the_trial() -> void:
	for index in 2:
		var view := _view(index)
		var world := view.world
		var harvester: SimUnit = world.units[0]
		var deposit := world.deposits[0]
		var refinery := world.buildings[0]
		check(view.mission != null and view.mission.def.practice, "the scene runs the practice mission")
		check(view.hud.visible, "with the mission HUD")
		check(not view.control_view.visible, "and no control ring")
		check(view.camera.get_view_rect().has_point(refinery.center() * 32.0), "the camera shows the refinery")
		check_eq(view.hint_text(), view.hints.text(), "the first hint is shown")
		check(view.hud.top_bar_text().begins_with("Orichalcum 0 / 800"), "the top bar shows the store: '%s'" % view.hud.top_bar_text())
		check_eq(view.hud._forces.text, "Harvesters: 2", "and the sidebar counts the harvesters")
		check(view.hud._status.text.begins_with("Left in the rock"), "and the sidebar what is left in the rock")
		check(BuildingsView.building_at_point(world, refinery.center() * 32.0, PLAYER) == refinery, "the refinery can be found under the mouse")
		check(MapView.describe_spot(world, refinery.cell).contains("Stores up to 800"), "and described")
		check(MapView.describe_spot(world, deposit.cells[0]).contains("Orichalcum here: 50"), "a rock cell shows its Orichalcum")

		# Select a harvester with a click, send it to the rock with a right click.
		_click(view, UnitsView.feet_position(harvester) + UnitsView.BODY)
		check_eq(view.selection.ids, [harvester.id] as Array[int], "a click selects the harvester")
		check_eq(view.hints.current(), &"harvest", "and the hints move on")
		check(MapView.describe_selection(world, view.selection).contains("Cargo 0 / 100"), "the sidebar shows its cargo")
		view.camera.center_on(MapData.cell_center(deposit.cells[0]))
		_click(view, MapData.cell_center(deposit.cells[0]), MOUSE_BUTTON_RIGHT)
		check_eq(harvester.order, SimUnit.Order.HARVEST, "a right click on the rock is a harvest order")
		check_eq(world.units[1].order, SimUnit.Order.NONE, "for the selected harvester only")
		check_eq(view.hints.current(), &"watch", "the hints move on again")
		check(MapView.describe_selection(world, view.selection).contains("Driving to the rock"), "the sidebar says what it is doing")
		check_eq(UnitsView.sprite_frame(harvester, 0).y, 0, "on the way out it is drawn as an empty truck")
		for i in 20 * 60:
			if harvester.job == Job.EXTRACT:
				break
			view._process(0.05)
		check_eq(harvester.job, Job.EXTRACT, "it gets there and digs")
		check(UnitsView.sprite_frame(harvester, 0).y >= 3, "drawn as a robot")
		check(MapView.describe_selection(world, view.selection).contains("Digging"), "and described as digging")
		check(MapView.describe_selection(world, view.selection).contains("Pack "), "with what is in its pack")
		var trailer := world.get_trailer(harvester.trailer_id)
		check(trailer != null and world.is_trailer_visible_to(trailer, PLAYER), "its trailer stands beside it")
		check_eq(UnitsView.trailer_frame(world, trailer), Vector2i(trailer.facing, 0), "drawn empty")
		check(MapView.describe_spot(world, trailer.cell).begins_with("Trailer"), "and described when the mouse is on it")
		harvester.cargo = 60
		check_eq(UnitsView.trailer_frame(world, trailer).y, 1, "half full, it is drawn loaded")
		harvester.cargo = 0
		for i in 20 * 60:
			if world.stored_for(PLAYER) >= 100:
				break
			if harvester.job == Job.TO_REFINERY:
				check_eq(UnitsView.sprite_frame(harvester, 0).y, 1, "on the way back it is drawn as a loaded truck")
			view._process(0.05)
		check_eq(world.stored_for(PLAYER), 100, "the first load reaches the store")
		view._process(0.05)
		check(view.hud.top_bar_text().begins_with("Orichalcum 100 / 800"), "and the top bar shows it: '%s'" % view.hud.top_bar_text())
		check_eq(view.deposit_view.spent.size(), world.spent_log.size(), "the mined-out cells are drawn")
		check(view.deposit_view.spent.size() >= 2, "there are some by now")
		check(view.deposit_view.get_used_cells().size() >= 4, "as tiles over the rock")
		var image := Minimap.build_image(view.map, null, world)
		var spent: Vector2i = world.spent_log[0]
		var shown := image.get_pixelv(spent)
		check(absf(shown.r - Minimap.SPENT.r) < 0.01 and absf(shown.g - Minimap.SPENT.g) < 0.01, "and grey on the minimap")

		# A right click on the refinery sends it to unload; one on the ground moves it.
		harvester.cargo = 30
		view.camera.center_on(refinery.center() * 32.0)
		_click(view, refinery.center() * 32.0, MOUSE_BUTTON_RIGHT)
		check(harvester.job == Job.TO_REFINERY or harvester.next_job == Job.TO_REFINERY, "a right click on the refinery sends it to unload")
		check(harvester.unload_first, "with whatever it carries")
		_click(view, Vector2(refinery.cell * 32) + Vector2(16, 4 * 32), MOUSE_BUTTON_RIGHT)
		check_eq(harvester.order, SimUnit.Order.MOVE, "a right click on open ground is a move order")
		view.free()


func test_spent_rock_cannot_be_harvested_from_the_screen() -> void:
	var view := _view()
	var world := view.world
	var deposit := world.deposits[0]
	var harvester: SimUnit = world.units[0]
	deposit.take(deposit.cells[0], 100000)
	view.selection.set_ids([harvester.id])
	check(not view.order_harvest_at(MapData.cell_center(deposit.cells[0])), "an empty rock takes no harvesters")
	check(view.hint_text().contains("no Orichalcum left"), "and the hint box says why")
	check_eq(harvester.order, SimUnit.Order.NONE, "the harvester stays")
	view._process(0.05)
	check(view.hud._status.text == "The rock has run out", "the sidebar says the rock has run out")
	view.free()
