extends TestCase
## The heroes of M7: the Prince's Restore (an area heal) and Encouragement
## (a haste aura), the rule that losing a hero loses the mission, repairing
## buildings, selecting a building, the ability keys and buttons, and the
## hero trial.

const FOREST := "res://data/biomes/forest.tres"
const PRINCE := "res://data/units/blue_leader.tres"
const COMMANDER := "res://data/units/blue_commander.tres"
const GUARD := "res://data/units/blue_infantry.tres"
const TANK := "res://data/units/blue_tank.tres"
const LEGIONARY := "res://data/units/red_infantry.tres"
const RED_COMMANDER := "res://data/units/red_commander.tres"
const BLUE_HQ := "res://data/buildings/blue_headquarters.tres"
const BLUE_REFINERY := "res://data/buildings/blue_refinery.tres"
const HERO_TRIAL := "res://data/missions/hero_trial_blue.tres"
const MAP_SCENE := "res://scenes/map_view.tscn"
const PLAYER := Mission.PLAYER_TEAM
const ENEMY := Mission.ENEMY_TEAM


## An open 30x20 map of grass with stone along the top four rows.
func _map() -> MapData:
	var map := MapData.new()
	map.biome = load(FOREST)
	var rows := []
	for y in 20:
		rows.append(("s" if y < 4 else ".").repeat(30))
	map.rows = PackedStringArray(rows)
	map.starts = [Vector2i(3, 10), Vector2i(26, 10)] as Array[Vector2i]
	return map


func _world() -> SimWorld:
	return SimWorld.new(_map())


## A mission on the open map with the given forces and no objectives.
func _mission(forces: Array) -> Mission:
	var def := MissionDef.new()
	def.id = &"test"
	def.map = _map()
	for name in ["Blue", "Red"]:
		var side := MissionSide.new()
		side.name = name
		side.start = 0 if name == "Blue" else 1
		def.sides.append(side)
	def.forces.assign(forces)
	return Mission.new(def)


func _put(team: int, path: String, cell: Vector2i, count := 1) -> Placement:
	var placement := Placement.new()
	placement.team = team
	placement.type = load(path)
	placement.count = count
	placement.at = Placement.At.CELL
	placement.cell = cell
	return placement


func _ticks(world: SimWorld, count: int) -> void:
	for i in count:
		world.tick()


# --- the abilities' data ---------------------------------------------------------------

func test_the_princes_abilities() -> void:
	var prince := load(PRINCE) as UnitType
	check(prince.is_hero, "the Prince is a hero")
	check(prince.ability != null and prince.ability.kind == Ability.Kind.HEAL_AREA, "his active ability is an area heal")
	check_eq(prince.ability.key, "E", "used with E")
	check(not prince.ability.needs_target(), "at once, without picking a unit")
	check(prince.passive != null and prince.passive.kind == Ability.Kind.HASTE_AURA, "his passive is a haste aura")
	check_eq([prince.passive.amount, prince.passive.cast_range], [5, 4], "5% faster within 4 cells, as decided")
	check(prince.passive.is_passive(), "and it is always on")
	var commander := load(COMMANDER) as UnitType
	check_eq(commander.ability.key, "Q", "Mend keeps Q")
	check(commander.ability.needs_target(), "and is used on a unit")


# --- Restore ---------------------------------------------------------------------------

func test_restore_heals_troops_and_repairs_vehicles_around_him() -> void:
	var world := _world()
	var prince := world.add_unit(load(PRINCE), PLAYER, Vector2i(10, 10))
	check(world.ability_problem(prince.id, prince.id).begins_with("Nobody near"), "with nobody hurt there is nothing to do")
	var near := world.add_unit(load(GUARD), PLAYER, Vector2i(12, 10))
	var tank := world.add_unit(load(TANK), PLAYER, Vector2i(10, 12))
	var far := world.add_unit(load(GUARD), PLAYER, Vector2i(17, 10))
	var harmless := (load(LEGIONARY) as UnitType).duplicate() as UnitType
	harmless.attack_damage = 0                  # so that it hurts nobody during the test
	var enemy := world.add_unit(harmless, ENEMY, Vector2i(10, 8))
	var hq := world.add_building(load(BLUE_HQ), PLAYER, Vector2i(8, 1))
	for unit in [prince, near, tank, far, enemy]:
		unit.health = 10
	hq.health = 100
	check_eq(world.ability_problem(prince.id, prince.id), "", "with wounded units around him he can")
	check(world.order_ability(prince.id, prince.id), "the order is taken")
	world.tick()
	check_eq(prince.health, 45, "he heals himself")
	check_eq(near.health, 45, "a soldier within 3 cells")
	check_eq(tank.health, 45, "and repairs a vehicle within 3 cells")
	check_eq(far.health, 10, "but not a soldier 7 cells away")
	check(enemy.health <= 10, "nor an enemy")
	check_eq(hq.health, 100, "nor a building")
	check(prince.ability_ticks_left > 0, "then it recharges")
	check(world.ability_problem(prince.id, prince.id).contains("not ready"), "and cannot be used again at once")
	var pulses := world.effects.filter(func(e: Dictionary) -> bool: return e["kind"] == &"pulse")
	check_eq(pulses.size(), 1, "a pulse is shown")


# --- Encouragement ---------------------------------------------------------------------

func test_encouragement_speeds_up_units_near_the_prince() -> void:
	var world := _world()
	var prince := world.add_unit(load(PRINCE), PLAYER, Vector2i(10, 10))
	var near := world.add_unit(load(GUARD), PLAYER, Vector2i(13, 10))
	var far := world.add_unit(load(GUARD), PLAYER, Vector2i(16, 10))
	var enemy := world.add_unit(load(LEGIONARY), ENEMY, Vector2i(10, 13))
	world.tick()
	check(is_equal_approx(world.haste_of(near), 1.05), "a unit within 4 cells is 5% faster")
	check_eq(world.haste_of(far), 1.0, "one 6 cells away is not")
	check_eq(world.haste_of(prince), 1.0, "nor is the Prince himself")
	check_eq(world.haste_of(enemy), 1.0, "nor an enemy")
	# Rounding to whole ticks is carried over, so the speed-up comes out right on average.
	var steps := 0
	var swings := 0
	for i in 100:
		steps += world._hasted_ticks(near, 8, true)
		swings += world._hasted_ticks(near, 20, false)
	check(absi(steps - 762) <= 1, "100 steps of 8 ticks take about 762 ticks (%d)" % steps)
	check(absi(swings - 1905) <= 1, "100 swings of 20 ticks take about 1905 ticks (%d)" % swings)
	check_eq(world._hasted_ticks(far, 8, true), 8, "a unit out of reach keeps its pace")
	prince.health = 0
	world._kill(prince)
	world.tick()
	check_eq(world.haste_of(near), 1.0, "a dead Prince encourages nobody")


func test_encouraged_units_walk_faster() -> void:
	var times := []
	for with_prince in [false, true]:
		var world := _world()
		var walker := world.add_unit(load(GUARD), PLAYER, Vector2i(5, 10))
		if with_prince:
			var prince := world.add_unit(load(PRINCE), PLAYER, Vector2i(5, 12))
			prince.type = (prince.type as UnitType).duplicate()
			prince.type.speed = 20.0           # keeps up with the walker
			world.order_move([prince.id], Vector2i(25, 12))
		world.order_move([walker.id], Vector2i(25, 10))
		var ticks := 0
		while ticks < 400 and not (walker.cell == Vector2i(25, 10) and walker.is_settled()):
			world.tick()
			ticks += 1
		times.append(ticks)
	check(times[1] < times[0], "an encouraged soldier walks 20 cells sooner (%d ticks against %d)" % [times[1], times[0]])


# --- losing a hero ---------------------------------------------------------------------

func test_losing_any_hero_loses_the_mission() -> void:
	for path in [PRINCE, COMMANDER]:
		var mission := _mission([_put(PLAYER, PRINCE, Vector2i(5, 10)), _put(PLAYER, COMMANDER, Vector2i(5, 13)),
				_put(ENEMY, RED_COMMANDER, Vector2i(25, 10))])
		check_eq(mission.player_heroes().size(), 2, "the player has two heroes")
		var enemy_hero: SimUnit = null
		for unit in mission.world.units:
			if unit.team == ENEMY:
				enemy_hero = unit
		enemy_hero.health = 0
		mission.world._kill(enemy_hero)
		mission.tick()
		check(not mission.is_over(), "losing an enemy hero ends nothing")
		var hero: SimUnit = null
		for unit in mission.player_heroes():
			if unit.type.resource_path == path:
				hero = unit
		hero.health = 0
		mission.world._kill(hero)
		mission.tick()
		check(mission.is_over() and not mission.player_won(), "losing %s loses the mission" % hero.type.display_name)
		check_eq(mission.win_reason, &"hero", "for that reason")
		check_eq(mission.fallen_hero, hero.type, "and the mission knows who fell")
		check(MissionHud.result_text(mission).contains("%s has fallen" % hero.type.display_name), "the result screen says so")


# --- repairing buildings ---------------------------------------------------------------

func test_repairing_a_building() -> void:
	var world := _world()
	var refinery := world.add_building(load(BLUE_REFINERY), PLAYER, Vector2i(2, 1))
	world.stored[PLAYER] = 3
	refinery.health = refinery.type.max_health - 100
	check_eq(SimWorld.repair_cost(refinery), 25, "100 health costs 25 Orichalcum")
	world.order_repair(refinery.id, true)
	check(refinery.repairing, "it is being repaired")
	_ticks(world, 20)
	check_eq(refinery.health, refinery.type.max_health - 88, "it gets back health until the store is empty (3 Orichalcum, 12 health)")
	check_eq(world.stored_for(PLAYER), 0, "paid for bit by bit")
	check(refinery.repairing, "and then waits")
	world.stored[PLAYER] = 500
	_ticks(world, 20)
	check_eq(refinery.health, refinery.type.max_health - 68, "with Orichalcum it goes on at 20 health a second")
	_ticks(world, 100)
	check_eq(refinery.health, refinery.type.max_health, "until it is whole")
	check(not refinery.repairing, "then it stops")
	check_eq(world.stored_for(PLAYER), 500 - 22, "the whole repair cost 25")
	world.order_repair(refinery.id, true)
	check(not refinery.repairing, "a whole building is not repaired")


func test_the_computer_repairs_its_buildings() -> void:
	var mission := Mission.new(load("res://data/missions/skirmish_blue.tres"))
	var world := mission.world
	var hq := world.get_building(mission.enemy_headquarters_id)
	hq.health = 300
	for i in 25:
		mission.tick()
	check(hq.repairing, "the computer repairs a badly damaged building")
	check(hq.health > 300, "and it gets better")


# --- selecting a building --------------------------------------------------------------

func test_selecting_a_building() -> void:
	var selection := Selection.new()
	selection.set_ids([1, 2])
	selection.set_building(7)
	check_eq(selection.building_id, 7, "a building is selected")
	check(selection.ids.is_empty(), "on its own")
	check(not selection.is_empty(), "the selection is not empty")
	selection.set_ids([3])
	check_eq(selection.building_id, 0, "selecting units lets go of it")
	selection.set_building(7)
	selection.clear()
	check(selection.is_empty(), "clearing lets go of it too")


# --- the hero trial in the game scene --------------------------------------------------

func _view() -> MapView:
	MapView.requested_mission = HERO_TRIAL
	var view := (load(MAP_SCENE) as PackedScene).instantiate() as MapView
	tree.root.add_child(view)
	MapView.requested_mission = ""
	return view


func _key(view: MapView, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	view._unhandled_input(event)


func _hero(view: MapView, path: String) -> SimUnit:
	for hero in view.mission.player_heroes():
		if hero.type.resource_path == path:
			return hero
	return null


func test_hero_trial_scene() -> void:
	var view := _view()
	var mission := view.mission
	check(mission != null and mission.def.problems().is_empty(), "the hero trial starts")
	check_eq(mission.player_heroes().size(), 2, "with both Blue heroes")
	check_eq(MissionHud.ability_keys(mission.def), ["E", "Q"] as Array[String], "the HUD has a button for each hero's ability")
	check_eq(view.hud._ability_buttons.size(), 2, "two ability buttons")
	check_eq((view.hud._ability_buttons["E"] as Button).text, "Restore", "named after the abilities")
	check((view.hud._ability_buttons["E"] as Button).tooltip_text.begins_with("Restore (E)"), "with their keys")
	var prince := _hero(view, PRINCE)
	var commander := _hero(view, COMMANDER)
	check(view.ability_unit("E") == prince and view.ability_unit("Q") == commander, "E is the Prince's, Q the Field Commander's")
	_key(view, KEY_E)
	check(view.hint_text().contains("Nobody near"), "E with nobody hurt says why nothing happens")
	prince.health = 50
	_key(view, KEY_E)
	view._process(0.06)
	check(prince.health > 50, "E heals at once")
	check_eq(view.mode, MapView.Mode.NORMAL, "without waiting for a click")
	_key(view, KEY_Q)
	check_eq(view.mode, MapView.Mode.ABILITY, "Q waits for a unit to heal")
	view.set_mode(MapView.Mode.NORMAL)
	# Select a building and repair it.
	var hq := view.world.get_building(mission.player_headquarters_id)
	hq.health = 600
	view.click_select(hq.center() * 32.0)
	check_eq(view.selection.building_id, hq.id, "a click on the player's building selects it")
	check(MapView.describe_selection(view.world, view.selection).contains("Repair (R)"), "the sidebar offers a repair")
	view._process(0.01)
	check(view.hud._repair.visible and not view.hud._attack.visible, "Repair takes the place of Attack and Stop")
	_key(view, KEY_R)
	check(hq.repairing, "R repairs it")
	view._process(0.01)
	check_eq(view.hud._repair.text, "Stop repair", "the button can stop it")
	_key(view, KEY_R)
	check(not hq.repairing, "R again stops")
	view.free()


func test_hero_trial_attacks_come() -> void:
	var mission := Mission.new(load(HERO_TRIAL))
	var world := mission.world
	check_eq(world.team_size(ENEMY), 0, "nobody attacks at first")
	for i in 31 * 20:
		mission.tick()
	check(not mission.messages.is_empty() and mission.messages[0]["speaker"] == "Scout", "a scout warns of the first attack")
	for i in 10 * 20:
		mission.tick()
	var wave := mission.tagged_units(&"wave1")
	check_eq(wave.size(), 4, "the first attack comes")
	check(wave.all(func(u: SimUnit) -> bool: return u.order == SimUnit.Order.ATTACK_MOVE), "at the player's base")
	check_eq(mission.objective_state(&"beat_off"), Mission.HIDDEN, "the last objective waits for the last attack")
