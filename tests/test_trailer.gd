extends TestCase
## The harvester as truck, robot and trailer under attack: the trailer itself,
## guarding it, the robot's armour and its fight, what happens to the trailer
## when the harvester is destroyed, and the raid trial.

const FOREST := "res://data/biomes/forest.tres"
const HARVESTER := "res://data/units/blue_harvester.tres"
const RED_HARVESTER := "res://data/units/red_harvester.tres"
const REFINERY := "res://data/buildings/red_refinery.tres"
const GUARD := "res://data/units/blue_infantry.tres"
const LEGIONARY := "res://data/units/red_infantry.tres"
const RAIDS := ["res://data/missions/raid_trial_blue.tres", "res://data/missions/raid_trial_red.tres"]
const HARVEST_TRIAL := "res://data/missions/harvest_trial_blue.tres"
const MAP_SCENE := "res://scenes/map_view.tscn"
const BLUE := 0
const RED := 1
const Job := SimUnit.Job
## Open grass with a rock of four cells (200 Orichalcum) at the right and
## stone to build on at the left.
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
## Where the harvester of _digging() parks its trailer.
const PARKED := Vector2i(15, 4)
const WORK_JOBS := [Job.TO_ROCK, Job.EXTRACT, Job.TO_TRAILER, Job.LOAD]


func _world() -> SimWorld:
	var map := MapData.new()
	map.biome = load(FOREST)
	map.rows = PackedStringArray(FIELD)
	return SimWorld.new(map)


func _run(world: SimWorld, seconds: float) -> void:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		world.tick()


## Run until `done` returns true. Returns false if it never did.
func _until(world: SimWorld, done: Callable, seconds := 100.0) -> bool:
	for i in roundi(seconds * SimWorld.TICKS_PER_SECOND):
		if done.call():
			return true
		world.tick()
	return done.call()


## A world with a Blue harvester that has unhitched beside the rock and is digging.
func _digging(world: SimWorld) -> SimUnit:
	var harvester := world.add_unit(load(HARVESTER), BLUE, PARKED)
	world.order_harvest([harvester.id], ROCK)
	_until(world, func() -> bool: return harvester.job == Job.EXTRACT)
	return harvester


## Red soldiers put down around a cell.
func _raiders(world: SimWorld, near: Vector2i, count: int) -> Array:
	var ids: Array = []
	for unit in world.add_group(load(LEGIONARY), RED, near, count):
		ids.append(unit.id)
	return ids


# --- the trailer ---------------------------------------------------------------------

func test_trailer_takes_its_cell_and_cannot_be_attacked() -> void:
	var world := _world()
	var harvester := _digging(world)
	var trailer := world.get_trailer(harvester.trailer_id)
	check(trailer != null and trailer.cell == PARKED, "the trailer stands where the truck stopped")
	check(not trailer.is_orphan(), "it belongs to its robot")
	check(world.unit_at(PARKED) == null, "it is not a unit: there is nothing on its cell to attack")
	check(not world.is_free(PARKED), "but the cell is taken")
	check(world.add_unit(load(GUARD), BLUE, PARKED) == null, "so no unit can be put there")
	harvester.cargo = 40
	check_eq(world.trailer_cargo(trailer), 40, "its cargo is the harvester's")
	var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(10, 6))
	check(world.nearest_enemy(soldier.cell, RED, 30) == harvester, "an enemy looking for a target finds the robot, never the trailer")
	world.order_move([soldier.id], PARKED)
	_run(world, 6.0)
	check(soldier.cell != PARKED, "a unit sent onto the trailer does not get onto it")
	check_eq(SimWorld._cells_apart(soldier.cell, PARKED), 1, "it stops beside it")
	check(world.get_trailer(trailer.id) == trailer and world.trailer_cargo(trailer) >= 40, "and the trailer is untouched")


func test_units_walk_around_a_trailer() -> void:
	var world := _world()
	var trailer := SimTrailer.new()
	trailer.id = 999
	trailer.team = BLUE
	trailer.type = load(HARVESTER)
	trailer.cell = Vector2i(10, 6)
	trailer.owner_id = 12345
	world._add_trailer(trailer)
	var walker := world.add_unit(load(GUARD), BLUE, Vector2i(6, 6))
	world.order_move([walker.id], Vector2i(14, 6))
	var crossed := false
	for i in 200:
		world.tick()
		if walker.cell == trailer.cell:
			crossed = true
	check_eq(walker.cell, Vector2i(14, 6), "the unit gets past the trailer")
	check(not crossed, "without walking through it")


# --- guarding ------------------------------------------------------------------------

func test_robot_stops_work_to_guard_its_trailer() -> void:
	var world := _world()
	var harvester := _digging(world)
	var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(9, 4))
	world.order_move([soldier.id], Vector2i(9, 5))
	_run(world, 1.5)
	check(harvester.job in WORK_JOBS, "an enemy six cells away does not disturb it")
	world.order_move([soldier.id], Vector2i(12, 4))      # walks up without attacking: a move order ignores enemies
	check(_until(world, func() -> bool: return harvester.job == Job.GUARD, 5.0), "an enemy coming near makes it stand guard")
	_run(world, 2.0)
	check_eq(harvester.job, Job.GUARD, "it stays on guard while the enemy is there")
	check_eq(SimWorld._cells_apart(harvester.cell, PARKED), 1, "right beside its trailer")
	check((harvester.cell - soldier.cell).length_squared() <= (PARKED - soldier.cell).length_squared(),
			"on the side the enemy is on")
	check_eq(harvester.order, SimUnit.Order.HARVEST, "its order stays")
	check_eq(MapView.job_text(harvester), "Guarding its trailer", "the sidebar says what it is doing")
	var dug := world.ore_left()
	_run(world, 2.0)
	check_eq(world.ore_left(), dug, "and it does not dig meanwhile")
	world.order_move([soldier.id], Vector2i(3, 6))
	check(_until(world, func() -> bool: return harvester.job in WORK_JOBS, 12.0), "when the enemy has gone it goes back to work")
	check(world.get_trailer(harvester.trailer_id) != null, "without having folded up")
	check(_until(world, func() -> bool: return world.ore_left() < dug, 10.0), "and digs again")


func test_guarding_does_not_depend_on_the_cargo() -> void:
	for cargo in [0, 100]:
		var world := _world()
		var harvester := _digging(world)
		harvester.cargo = cargo
		var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(12, 4))
		world.order_stop([soldier.id])
		_run(world, 1.0)
		check_eq(harvester.job, Job.GUARD, "with a cargo of %d it guards its trailer" % cargo)


func test_enemy_harvesters_are_no_threat() -> void:
	var world := _world()
	var harvester := _digging(world)
	var other := world.add_unit(load(RED_HARVESTER), RED, Vector2i(13, 4))
	_run(world, 2.0)
	check(harvester.job in WORK_JOBS, "an enemy truck beside it does not stop the work")
	world.order_harvest([other.id], ROCK)
	check(_until(world, func() -> bool: return other.job == Job.EXTRACT, 20.0), "the enemy harvester works the same rock")
	_run(world, 3.0)
	check(harvester.job != Job.GUARD and other.job != Job.GUARD, "and neither minds the other")
	check_eq([harvester.health, other.health], [harvester.type.max_health, other.type.max_health], "nobody is hurt")


func test_truck_under_attack_unfolds_and_fights() -> void:
	var world := _world()
	var harvester := world.add_unit(load(HARVESTER), BLUE, Vector2i(10, 4))
	harvester.cargo = 40
	var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(6, 4))
	world.order_attack([soldier.id], harvester.id)
	check(_until(world, func() -> bool: return harvester.health < harvester.type.max_health, 10.0), "the soldier reaches the truck and hits it")
	check_eq(harvester.type.max_health - harvester.health, 12, "the truck has no armour: the hit takes 12")
	world.tick()
	check_eq(harvester.job, Job.DEPLOY, "the truck unfolds at once")
	check(_until(world, func() -> bool: return harvester.job == Job.GUARD, 3.0), "and the robot stands guard")
	var trailer := world.get_trailer(harvester.trailer_id)
	check(trailer != null and trailer.cell == Vector2i(10, 4), "its trailer stands where the truck was hit")
	check_eq(SimWorld._cells_apart(harvester.cell, trailer.cell), 1, "and the robot is next to it")
	var health := harvester.health
	check(_until(world, func() -> bool: return harvester.health < health, 5.0), "the soldier hits the robot too")
	check_eq(health - harvester.health, 4, "but its armour stops most of the blow: 4 instead of 12")
	check(_until(world, func() -> bool: return soldier.health < soldier.type.max_health, 5.0), "the robot hits back")
	check_eq(soldier.type.max_health - soldier.health, harvester.type.attack_damage, "with its own weak blow")
	check(_until(world, func() -> bool: return soldier.dead, 30.0), "one soldier alone loses the fight")
	check(harvester.health > harvester.type.max_health / 2, "and leaves the robot in good shape (%d)" % harvester.health)
	check(_until(world, func() -> bool: return not harvester.is_robot(), 10.0), "afterwards the robot hitches up again")
	check(world.trailers.is_empty(), "the trailer is hitched")
	check_eq(harvester.cell, Vector2i(10, 4), "the truck stands where it stood")
	check_eq([harvester.cargo, harvester.order, harvester.job], [40, SimUnit.Order.NONE, Job.NONE], "with its cargo, waiting for orders")


func test_armour_is_the_robots() -> void:
	var world := _world()
	var truck := world.add_unit(load(HARVESTER), BLUE, Vector2i(6, 6))
	check_eq(SimWorld.damage_to(truck, 12), 12, "a truck takes a hit in full")
	var robot := _digging(world)
	check_eq(SimWorld.damage_to(robot, 12), 4, "a robot takes less than half of it")
	check_eq(SimWorld.damage_to(robot, 1), 1, "but never nothing")
	var soldier := world.add_unit(load(GUARD), BLUE, Vector2i(6, 5))
	check_eq(SimWorld.damage_to(soldier, 12), 12, "soldiers have no armour")


func test_truck_told_to_move_drives_on_under_attack() -> void:
	var world := _world()
	var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(5, 4))      # first, so that it strikes before the truck pulls away
	var harvester := world.add_unit(load(HARVESTER), BLUE, Vector2i(6, 4))
	world.order_attack([soldier.id], harvester.id)
	world.order_move([harvester.id], Vector2i(18, 6))
	_run(world, 2.0)
	check(harvester.health < harvester.type.max_health, "it is hit as it sets off")
	check(not harvester.is_robot() and world.trailers.is_empty(), "but a truck with a move order does not unfold")
	world.order_move([soldier.id], Vector2i(2, 6))
	_run(world, 6.0)
	check_eq(harvester.cell, Vector2i(18, 6), "it drives where it was sent")
	check(not harvester.is_robot() and world.trailers.is_empty(), "and with the enemy left behind it stays a truck")


func test_harvesters_do_not_take_attack_orders() -> void:
	var world := _world()
	var harvester := world.add_unit(load(HARVESTER), BLUE, Vector2i(6, 4))
	var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(16, 6))
	world.order_stop([soldier.id])
	world.order_attack([harvester.id], soldier.id)
	check_eq(harvester.order, SimUnit.Order.NONE, "an attack order is ignored")
	world.order_attack_move([harvester.id], Vector2i(9, 4))
	check_eq(harvester.order, SimUnit.Order.MOVE, "attack-move is a plain move for a harvester")
	_run(world, 3.0)
	check_eq(harvester.cell, Vector2i(9, 4), "it drives there")
	check(not harvester.is_robot(), "as a truck")


func test_a_robot_is_worth_about_two_soldiers() -> void:
	var results := {}
	for count: int in [2, 3]:
		var world := _world()
		var harvester := _digging(world)
		var ids := _raiders(world, Vector2i(8, 4), count)
		world.order_attack_move(ids, Vector2i(14, 4))
		_until(world, func() -> bool: return harvester.dead or world.team_size(RED) == 0, 120.0)
		results[count] = [harvester.dead, count - world.team_size(RED)]
	check_eq(results[2], [false, 2], "two soldiers both die against a robot")
	check_eq(results[3], [true, 2], "three kill it, but it takes two of them with it")


# --- the trailer of a destroyed harvester --------------------------------------------

func test_dead_robot_leaves_its_trailer_to_be_taken() -> void:
	var world := _world()
	var harvester := _digging(world)
	harvester.cargo = 60
	harvester.pack = 10
	var friend := world.add_unit(load(GUARD), BLUE, Vector2i(14, 3))
	world.order_move([friend.id], Vector2i(14, 3))        # a move order: it stands by and does not fight
	var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(12, 6))
	world.order_stop([soldier.id])
	world._kill(harvester)
	check(harvester.dead and world.get_unit(harvester.id) == null, "the robot is destroyed")
	check_eq(world.trailers.size(), 1, "its trailer stays")
	var trailer := world.trailers[0]
	check(trailer.is_orphan(), "with nobody to guard it")
	check_eq([trailer.cargo, world.trailer_cargo(trailer)], [60, 60], "holding its cargo; what was in the robot's pack is lost")
	check(not world.is_free(PARKED), "it still takes up its cell")
	_run(world, 2.0)
	check_eq(world.trailers.size(), 1, "a unit of its own side beside it changes nothing")
	check_eq(world.stored_for(BLUE), 0, "and gains nothing")
	world.order_move([soldier.id], PARKED)
	check(_until(world, func() -> bool: return world.trailers.is_empty(), 10.0), "an enemy unit that walks up to it takes it")
	check_eq(SimWorld._cells_apart(soldier.cell, PARKED), 1, "from the cell beside it")
	check_eq(world.stolen_for(RED), 60, "all of its cargo is stolen")
	check_eq(world.stored_for(RED), 0, "a side without storage keeps no store")
	check(world.is_free(PARKED), "and the cell is free again")
	check(world.effects.any(func(effect: Dictionary) -> bool: return effect["kind"] == &"steal"), "the screen is told about it")


func test_stolen_cargo_goes_into_the_thiefs_store() -> void:
	var world := _world()
	var refinery := (load(REFINERY) as BuildingType).duplicate() as BuildingType
	refinery.storage = 50
	world.add_building(refinery, RED, Vector2i(1, 3))
	var harvester := _digging(world)
	harvester.cargo = 60
	world._kill(harvester)
	var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(14, 5))
	world.order_stop([soldier.id])
	_run(world, 1.0)
	check_eq(world.stored_for(RED), 50, "a side with a refinery stores what it steals, as far as it fits")
	check_eq(world.trailers.size(), 1, "the trailer stays while there is something in it")
	check_eq(world.trailers[0].cargo, 10, "with the rest")
	refinery.storage = 800
	_run(world, 1.0)
	check_eq(world.stored_for(RED), 60, "which is taken once there is room")
	check(world.trailers.is_empty(), "then the trailer is gone")


func test_empty_trailer_goes_with_its_robot() -> void:
	var world := _world()
	var harvester := _digging(world)
	harvester.cargo = 0
	harvester.pack = 20
	world._kill(harvester)
	check(world.trailers.is_empty(), "an empty trailer disappears when its robot is destroyed")
	check(world.is_free(PARKED), "and frees its cell")


func test_dead_truck_leaves_its_trailer_too() -> void:
	var world := _world()
	var loaded := world.add_unit(load(HARVESTER), BLUE, Vector2i(6, 4))
	loaded.cargo = 30
	var empty := world.add_unit(load(HARVESTER), BLUE, Vector2i(6, 6))
	world._kill(loaded)
	world._kill(empty)
	check_eq(world.trailers.size(), 1, "only the truck that carried something leaves a trailer")
	check_eq([world.trailers[0].cell, world.trailers[0].cargo], [Vector2i(6, 4), 30], "where it stood, with its cargo")
	check(world.trailers[0].is_orphan(), "for anyone to take")


# --- the raid trial ------------------------------------------------------------------

## The player's harvesters in a mission, by id.
func _harvesters(world: SimWorld) -> Array:
	var ids: Array = []
	for unit in world.units:
		if unit.team == BLUE and unit.type.is_harvester():
			ids.append(unit.id)
	return ids


func test_raid_trial_start() -> void:
	for path in RAIDS:
		var def := load(path) as MissionDef
		check(def != null and def.practice and def.has_raid(), "%s is a practice mission with a raid" % path)
		var mission := Mission.new(def)
		var world := mission.world
		check(mission.raiders != null, "it has raiders")
		check(world.get_building(mission.player_refinery_id) != null, "the player has a refinery")
		check_eq(_harvesters(world).size(), 2, "two harvesters")
		check_eq(world.team_size(BLUE), 5, "and three soldiers")
		check_eq(world.team_size(RED), 3, "the raiders are three")
		for unit in world.units:
			if unit.team == RED:
				check(not unit.type.is_harvester() and unit.type.attack_damage > 0, "all of them soldiers")
		for tick in 20 * 30:
			mission.tick()
		for unit in world.units:
			if unit.team == RED:
				check_eq(unit.order, SimUnit.Order.NONE, "they wait before they set off")
		check(not mission.is_over(), "nothing is won or lost meanwhile")
	check(not (load(HARVEST_TRIAL) as MissionDef).has_raid(), "the harvest trial has no raid")
	check(Mission.new(load(HARVEST_TRIAL)).raiders == null, "and no raiders")


func test_raid_left_alone_costs_a_harvester_and_its_cargo() -> void:
	for path in RAIDS:
		var mission := Mission.new(load(path) as MissionDef)
		var world := mission.world
		var ids := _harvesters(world)
		world.order_harvest(ids, world.deposits[0].cells[0])
		var guarded := false
		for tick in 20 * 240:
			mission.tick()
			for id in ids:
				var harvester := world.get_unit(id)
				if harvester != null and harvester.job == Job.GUARD:
					guarded = true
		check(guarded, "attacked, a harvester guards its trailer in %s" % path)
		check_eq(int(world.losses.get(BLUE, 0)), 1, "three raiders destroy one harvester")
		check(int(world.losses.get(RED, 0)) >= 2, "which takes two of them with it")
		check(world.stolen_for(RED) > 0, "and they take what was in its trailer (%d)" % world.stolen_for(RED))
		check(world.trailers.all(func(trailer: SimTrailer) -> bool: return not trailer.is_orphan()), "no orphaned trailer is left standing")
		check(not mission.is_over(), "a practice mission is not lost")


func test_raid_beaten_off_by_the_players_soldiers() -> void:
	for path in RAIDS:
		var mission := Mission.new(load(path) as MissionDef)
		var world := mission.world
		var ids := _harvesters(world)
		var soldiers: Array = []
		for unit in world.units:
			if unit.team == BLUE and not unit.type.is_harvester():
				soldiers.append(unit.id)
		world.order_harvest(ids, world.deposits[0].cells[0])
		var sent := false
		for tick in 20 * 240:
			mission.tick()
			for id in ids:
				var harvester := world.get_unit(id)
				if not sent and harvester != null and harvester.health < harvester.type.max_health:
					world.order_attack_move(soldiers, harvester.cell)     # the player sends help at the first blow
					sent = true
		check(sent, "the raiders reach a harvester in %s" % path)
		check_eq(int(world.losses.get(BLUE, 0)), 0, "with help on the way nobody is lost")
		check_eq(world.team_size(RED), 0, "the raiders are all destroyed")
		check_eq(world.stolen_for(RED), 0, "and nothing is stolen")
		check(world.stored_for(BLUE) > 0, "the harvesters went back to work afterwards (%d in store)" % world.stored_for(BLUE))


# --- on screen -----------------------------------------------------------------------

func _view(path: String) -> MapView:
	MapView.requested_mission = path
	var view := (load(MAP_SCENE) as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	MapView.requested_mission = ""
	return view


func test_title_screen_offers_the_raid_trial() -> void:
	var title := load("res://scripts/ui/title_screen.gd")
	check_eq(title.map_from_args(PackedStringArray(["--map=raid-forest"])), "raid-forest", "--map=raid-forest")
	check_eq(title.map_from_args(PackedStringArray(["--map=raid-desert"])), "raid-desert", "--map=raid-desert")
	check((load(title.MISSIONS["raid-forest"]) as MissionDef).has_raid(), "it starts the raid trial")
	var node := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(node)
	check(node.mission_button("raid-forest") != null, "there is a button for the forest raid")
	check(node.mission_button("raid-desert") != null, "and one for the desert raid")
	node.free()


func test_robot_and_trailer_sprites() -> void:
	var world := _world()
	var harvester := world.add_unit(load(HARVESTER), BLUE, PARKED)
	check_eq(UnitsView.sprite_frame(harvester, 0).y, 0, "an empty truck")
	harvester.cargo = 50
	check_eq(UnitsView.sprite_frame(harvester, 0).y, 1, "a truck with a trailer half full")
	harvester.cargo = 0
	world.order_harvest([harvester.id], ROCK)
	world.tick()
	check_eq(UnitsView.sprite_frame(harvester, 0), Vector2i(harvester.facing, 2), "halfway while it unfolds")
	_until(world, func() -> bool: return harvester.job == Job.TO_ROCK)
	check_eq(UnitsView.sprite_frame(harvester, 0).y, 5, "a robot that walks is drawn standing")
	_until(world, func() -> bool: return harvester.job == Job.EXTRACT)
	check(UnitsView.sprite_frame(harvester, 0).y in [3, 4], "digging, it swings")
	_until(world, func() -> bool: return harvester.job == Job.LOAD)
	check_eq(UnitsView.sprite_frame(harvester, 0).y, 5, "filling the trailer, it stands")
	var soldier := world.add_unit(load(LEGIONARY), RED, Vector2i(12, 4))
	world.order_attack([soldier.id], harvester.id)
	_until(world, func() -> bool: return world.tick_count - harvester.last_attack_tick < 3, 20.0)
	check_eq(harvester.job, Job.GUARD, "on guard")
	check(UnitsView.sprite_frame(harvester, world.tick_count).y in [3, 4], "it swings at the enemy")
	check_eq(UnitsView.cab_offset(0), Vector2(0, 9), "the cab of a truck facing south is drawn south of its middle")
	check_eq(UnitsView.cab_offset(6).y, 0.0, "and of one facing east, east")


func test_scene_shows_the_raid() -> void:
	var view := _view(RAIDS[0])
	var world := view.world
	check(view.mission.def.has_raid(), "the scene runs the raid trial")
	check_eq(view.hud._forces.text, "Harvesters: 2    Raiders: 3", "the sidebar counts harvesters and raiders")
	view.hints.note(&"harvest")
	check(view.hints.text().contains("Raiders are coming"), "the last hint warns of the raid")
	var ids := _harvesters(world)
	var harvester := world.get_unit(ids[0])
	world.order_harvest(ids, world.deposits[0].cells[0])
	for i in 20 * 40:
		if harvester.job == Job.EXTRACT:
			break
		view._process(0.05)
	check_eq(harvester.job, Job.EXTRACT, "the harvester gets to work")
	var trailer := world.get_trailer(harvester.trailer_id)
	var parked := trailer.cell
	check(MapView.describe_spot(world, parked).contains("Cannot be attacked"), "its trailer is described as safe")
	check(MapView.describe_unit(harvester, world).contains("Robot: attack 10, armour 70%"), "and the harvester with its robot's values")
	harvester.cargo = 60
	world._kill(harvester)
	view._process(0.05)
	check(view.selection.is_empty() or not view.selection.has(harvester.id), "a destroyed harvester is not selected")
	check(MapView.describe_spot(world, parked).contains("Its harvester is destroyed"), "the orphaned trailer says what it is")
	check(MapView.describe_spot(world, parked).contains("An enemy that reaches it"), "and what will happen to it")
	check_eq(view.hud._forces.text, "Harvesters: 1    Raiders: 3", "the sidebar counts one harvester less")
	var thief: SimUnit = null
	for unit in world.units:
		if unit.team == RED:
			thief = unit
	world.order_move([thief.id], parked)
	for i in 20 * 90:
		if world.trailers.all(func(left: SimTrailer) -> bool: return not left.is_orphan()):
			break
		view._process(0.05)
	check_eq(world.stolen_for(RED), 60, "a raider that reaches it takes the cargo")
	view._process(0.05)
	check(view.hud._forces.text.ends_with("Taken: 60"), "and the sidebar shows the loss: '%s'" % view.hud._forces.text)
	view.free()


func test_player_takes_an_enemy_trailer_with_a_right_click() -> void:
	var view := _view(RAIDS[0])
	var world := view.world
	var soldier: SimUnit = null
	for unit in world.units:
		if unit.team == BLUE and not unit.type.is_harvester():
			soldier = unit
	var spot := world.nearest_free_cell(soldier.cell + Vector2i(4, 0), world.region_at(soldier.cell))
	var foreign := world.add_unit(load(RED_HARVESTER), RED, spot)
	foreign.cargo = 80
	world._kill(foreign)
	var trailer := world.trailer_at(spot)
	check(trailer != null and trailer.is_orphan() and trailer.team == RED, "an enemy harvester destroyed with cargo leaves its trailer")
	check(MapView.describe_spot(world, spot).contains("Send a unit up to it"), "the sidebar says it can be taken")
	view.selection.set_ids([soldier.id])
	view.order_at(MapData.cell_center(spot))
	check_eq(soldier.order, SimUnit.Order.MOVE, "a right click on it sends the soldier there")
	for i in 20 * 20:
		if world.trailers.is_empty():
			break
		view._process(0.05)
	check(world.trailers.is_empty(), "the soldier takes it")
	check_eq(world.stored_for(BLUE), 80, "and its Orichalcum goes into the player's store")
	check_eq(world.stolen_for(BLUE), 80, "counted as taken")
	view.free()
