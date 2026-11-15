extends TestCase
## Mission 2, "Holding the Claim": its map, its data, and the whole mission
## played through by a simple player that does what the hints say.

const MISSION := "res://data/missions/holding_the_claim_blue.tres"
const MAP := "res://data/maps/forest_02.tres"
const PLAYER := Mission.PLAYER_TEAM
const ENEMY := Mission.ENEMY_TEAM
const BASE := Vector2i(14, 33)
const CAMP := Vector2i(56, 9)
const GENERATOR := "res://data/buildings/blue_generator.tres"
const BARRACKS := "res://data/buildings/blue_barracks.tres"
const GUARD := "res://data/units/blue_infantry.tres"


func test_the_map() -> void:
	var map := load(MAP) as MapData
	check(map != null and map.problems().is_empty(), "River Fords loads cleanly")
	check_eq(map.get_size(), Vector2i(64, 48), "64 by 48 cells")
	var world := SimWorld.new(map)
	check_eq(world.deposits.size(), 2, "two Orichalcum rocks: Blue's and a small one by Red's camp")
	check_eq(world.region_at(map.starts[0]), world.region_at(map.starts[1]), "Blue can walk to Red's camp")
	check(map.is_buildable(BASE) and map.is_buildable(CAMP + Vector2i(-3, 1)), "both sides have building ground")
	# The river runs from the north edge to the south edge; only the fords cross it.
	var water_rows := 0
	for y in map.get_size().y:
		for x in range(33, 42):
			if map.terrain_at(Vector2i(x, y)).id == &"water":
				water_rows += 1
				break
	check(water_rows >= 36, "the river crosses most rows (%d of 48)" % water_rows)
	for ford: Vector2i in [Vector2i(37, 13), Vector2i(36, 37)]:
		check(map.is_walkable(ford), "the ford at %s can be walked" % ford)


func test_the_mission_data() -> void:
	var def := load(MISSION) as MissionDef
	check(def != null and def.problems().is_empty(), "Mission 2 loads cleanly: %s" % (def.problems() if def != null else "missing"))
	check_eq([def.number, def.kind, def.player_side], [2, MissionDef.Kind.STORY, "Blue"], "it is Mission 2, played as Blue")
	var mission := Mission.new(def)
	mission.tick()
	check_eq(mission.player_heroes().size(), 2, "with both Blue heroes")
	check_eq(mission.tagged_left(&"camp"), 4, "Red's camp has four buildings")
	check(mission.computer != null and not mission.computer.attacks, "the camp defends itself but does not attack on its own")
	check_eq(mission.shown_objectives().size(), 2, "at first: keep the heroes alive, and bring the Prince to the base site")
	check(mission.world.shroud_for(PLAYER).is_explored(BASE), "the base site is shown on the map")
	check(not mission.world.shroud_for(PLAYER).is_explored(CAMP), "Red's camp is not")


## The player: take everyone to the base site, build a generator and a
## barracks, set the harvester to work, train soldiers, hold the base, and
## when told to, attack-move into Red's camp with the heroes a few cells
## behind the troops, using Restore and Mend when they help.
func _play(mission: Mission, max_minutes := 30) -> Dictionary:
	var world := mission.world
	var log := {}
	var production := world.production
	var sent_to_base := false
	var launched := {}          # fighters sent at the camp
	for tick in max_minutes * 60 * SimWorld.TICKS_PER_SECOND:
		if mission.is_over():
			break
		mission.tick()
		for id in [&"establish", &"dig_in", &"hold", &"strike"]:
			if not log.has(id) and mission.objective_state(id) == Mission.DONE:
				log[id] = roundi(mission.seconds())
		if world.tick_count % SimWorld.TICKS_PER_SECOND != 0:
			continue
		var heroes := mission.player_heroes()
		var fighters: Array[int] = []
		for unit in world.units:
			if unit.team == PLAYER and not unit.type.is_hero and unit.type.attack_damage > 0 and not unit.type.is_harvester():
				fighters.append(unit.id)
		if not sent_to_base:
			var everyone: Array = fighters.duplicate()
			for hero in heroes:
				everyone.append(hero.id)
			world.order_move(everyone, BASE)
			sent_to_base = true
		if mission.objective_state(&"establish") == Mission.DONE:
			_build(world, production)
			_harvest(world)
		# Hold the base; once told to strike, go at the camp in groups of at least eight.
		var striking := mission.objective_state(&"strike") == Mission.OPEN
		var front := Vector2.ZERO
		var out := 0
		var at_home: Array = []
		for id in fighters:
			var unit := world.get_unit(id)
			if launched.has(id):
				front += Vector2(unit.cell)
				out += 1
				if unit.order == SimUnit.Order.NONE and unit.target_id == 0:
					world.order_attack_move([id], CAMP)
			elif unit.order == SimUnit.Order.NONE and unit.target_id == 0:
				at_home.append(id)
				if SimWorld._cells_apart(unit.cell, BASE) > 6:
					world.order_attack_move([id], BASE)
		if striking and at_home.size() >= (8 if out == 0 else 4):
			world.order_attack_move(at_home, CAMP)
			for id in at_home:
				launched[id] = true
		# The heroes keep a few cells behind the troops that are out, and help.
		front = front / maxf(1.0, out)
		var behind := BASE + Vector2i(-2, 3)
		if out > 0:
			var back := (Vector2(BASE) - front).normalized() * 4.0
			behind = world.nearest_free_cell(Vector2i((front + back).round()), world.region_at(BASE))
		for hero in heroes:
			if hero.order == SimUnit.Order.NONE and SimWorld._cells_apart(hero.cell, behind) > 3:
				world.order_move([hero.id], behind)
			if hero.ability_ticks_left == 0:
				var ability := hero.type.ability
				if ability.kind == Ability.Kind.HEAL_AREA:
					var hurt := 0
					for other in world.units_in_reach(hero.cell, PLAYER, ability.cast_range):
						if other.health <= other.type.max_health - ability.amount:
							hurt += 1
					if hurt >= 2 or hero.health < hero.type.max_health / 2:
						world.order_ability(hero.id, hero.id)
				else:
					var worst: SimUnit = null
					for other in world.units_in_reach(hero.cell, PLAYER, ability.cast_range + 1):
						if other != hero and other.health <= other.type.max_health - ability.amount \
								and (worst == null or other.health < worst.health):
							worst = other
					if worst != null:
						world.order_ability(hero.id, worst.id)
	log["seconds"] = roundi(mission.seconds())
	log["won"] = mission.player_won()
	log["reason"] = mission.win_reason
	log["lost"] = int(world.losses.get(PLAYER, 0))
	return log


func _build(world: SimWorld, production: Production) -> void:
	var ready := production.ready_building(PLAYER)
	if ready != null:
		var site := world.nearest_build_site(ready, BASE)
		if site != SimWorld.NO_CELL:
			production.place(PLAYER, site)
		return
	if not production.line(PLAYER, Production.BUILDINGS).is_empty():
		return
	for path in [GENERATOR, BARRACKS]:
		var type := load(path) as BuildingType
		var has := false
		for building in world.buildings:
			if building.team == PLAYER and building.type == type:
				has = true
		if not has and production.problem(PLAYER, Production.BUILDINGS, type) == "":
			production.queue(PLAYER, Production.BUILDINGS, type)
			return
	for key in production.keys(PLAYER):
		if key != Production.BUILDINGS and production.line(PLAYER, key).is_empty() and world.fighter_count(PLAYER) < 16:
			var guard := load(GUARD) as UnitType
			if guard in production.options(PLAYER, key) and production.problem(PLAYER, key, guard) == "":
				production.queue(PLAYER, key, guard)


func _harvest(world: SimWorld) -> void:
	for unit in world.units:
		if unit.team == PLAYER and unit.type.is_harvester() and unit.order == SimUnit.Order.NONE \
				and unit.job == SimUnit.Job.NONE and unit.cargo == 0:
			var rock := world.deposits[0]
			for deposit in world.deposits:
				if (Vector2(deposit.cells[0] - BASE)).length() < (Vector2(rock.cells[0] - BASE)).length():
					rock = deposit
			world.order_harvest([unit.id], rock.cells[0])


func test_mission_2_can_be_won() -> void:
	var mission := Mission.new(load(MISSION))
	var log := _play(mission)
	print("    Mission 2 played: %s" % log)
	check(log["won"], "playing as the hints teach wins Mission 2: %s" % log)
	for id in [&"establish", &"dig_in", &"hold", &"strike"]:
		check(log.has(id), "objective %s is done along the way" % id)
	check(log["seconds"] >= 8 * 60 and log["seconds"] <= 25 * 60, "in 8 to 25 minutes (%d s)" % log["seconds"])


func test_doing_nothing_loses() -> void:
	var mission := Mission.new(load(MISSION))
	for tick in 15 * 60 * SimWorld.TICKS_PER_SECOND:
		if mission.is_over():
			break
		mission.tick()
	check(mission.is_over() and not mission.player_won(), "a player who does nothing loses Mission 2")
	check_eq(mission.win_reason, &"hero", "Red's assault comes for the Prince")
	check(mission.seconds() > 8 * 60, "but not before the assault after eight minutes (%d s)" % mission.seconds())
	var speakers := mission.messages.map(func(m: Dictionary) -> String: return m["speaker"])
	check(speakers.has("Field Commander") and speakers.has("Scout"), "the mission talks to the player: %s" % [speakers])
